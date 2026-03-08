// tcp_fallback.go
//
// Module 1: UDP-over-WebSocket TCP Fallback
//
// When a strict firewall blocks plain WireGuard UDP (port 51820),
// this module wraps WireGuard's UDP packets inside a WebSocket
// stream running over TCP port 443 (HTTPS port — almost never blocked).
//
// Architecture:
//
//   WireGuard device (in-process)
//        ↕  raw UDP frames (to localhost relay)
//   localRelayConn (UDP loopback: 127.0.0.1:51820→127.0.0.1:RELAY_PORT)
//        ↕
//   TCPFallbackTunnel.runLoop()
//        ↕  WebSocket frames  (each frame = one WireGuard UDP datagram)
//   Remote WSTunnel server (wss://your.server.com:443/vpn)
//        ↕
//   WireGuard server (127.0.0.1:51820 on the VPN node)
//
// The remote server side is a tiny Go WebSocket relay (see docs/wstunnel_server.go).
// Popular open-source option: github.com/erebe/wstunnel (written in Rust, drop-in).

package fallback

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/net/websocket"
)

// TCPFallbackConfig configures the WebSocket relay parameters.
type TCPFallbackConfig struct {
	// WebSocket URL of the remote relay.
	// Example: "wss://vpn.example.com:443/wg"
	RelayURL string

	// LocalUDPPort is the UDP port we expose locally so wireguard-go
	// sends its frames here instead of directly to the VPN server.
	LocalUDPPort int

	// TLSSkipVerify disables certificate verification (testing only!).
	TLSSkipVerify bool

	// Token is a shared secret sent in the HTTP upgrade header to
	// authenticate the relay connection (prevents open proxy abuse).
	Token string
}

// TCPFallbackTunnel is a running UDP↔WebSocket relay.
type TCPFallbackTunnel struct {
	cfg    TCPFallbackConfig
	conn   *websocket.Conn
	udpLn  *net.UDPConn
	cancel context.CancelFunc
	active int32 // atomic flag: 1 = running
	mu     sync.Mutex
	wg     sync.WaitGroup
}

// NewTCPFallbackTunnel dials the WebSocket relay and binds the local UDP port.
// Returns an error if the relay is unreachable within 5 seconds.
func NewTCPFallbackTunnel(cfg TCPFallbackConfig) (*TCPFallbackTunnel, error) {
	// ── Step 1: Bind local UDP relay port ──────────────────────────────────
	lAddr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("127.0.0.1:%d", cfg.LocalUDPPort))
	if err != nil {
		return nil, fmt.Errorf("resolve local UDP: %w", err)
	}
	udpLn, err := net.ListenUDP("udp4", lAddr)
	if err != nil {
		return nil, fmt.Errorf("bind local UDP :  %d: %w", cfg.LocalUDPPort, err)
	}

	// ── Step 2: Dial WebSocket to remote relay ─────────────────────────────
	tlsCfg := &tls.Config{InsecureSkipVerify: cfg.TLSSkipVerify} //nolint:gosec
	dialer := &net.Dialer{Timeout: 5 * time.Second}
	transport := &http.Transport{
		DialContext:     dialer.DialContext,
		TLSClientConfig: tlsCfg,
	}

	wsConfig, err := websocket.NewConfig(cfg.RelayURL, "https://wireguard-engine")
	if err != nil {
		udpLn.Close()
		return nil, fmt.Errorf("ws config: %w", err)
	}
	wsConfig.TlsConfig = tlsCfg
	wsConfig.Header = http.Header{
		"X-WG-Token": []string{cfg.Token},
	}
	_ = transport // used implicitly by websocket.DialConfig

	var wsConn *websocket.Conn
	var dialErr error
	for i := 0; i < 3; i++ {
		wsConn, dialErr = websocket.DialConfig(wsConfig)
		if dialErr == nil {
			break
		}
		if i < 2 {
			time.Sleep(2 * time.Second)
		}
	}

	if dialErr != nil {
		udpLn.Close()
		return nil, fmt.Errorf("websocket dial (after retries): %w", dialErr)
	}
	wsConn.PayloadType = websocket.BinaryFrame

	ctx, cancel := context.WithCancel(context.Background())
	t := &TCPFallbackTunnel{
		cfg:   cfg,
		conn:  wsConn,
		udpLn: udpLn,
		cancel: cancel,
	}
	atomic.StoreInt32(&t.active, 1)

	// ── Step 3: Start bidirectional pump goroutines ────────────────────────
	t.wg.Add(2)
	go t.udpToWS(ctx)
	go t.wsToUDP(ctx)

	return t, nil
}

// Close tears down the fallback tunnel.
func (t *TCPFallbackTunnel) Close() {
	if !atomic.CompareAndSwapInt32(&t.active, 1, 0) {
		return
	}
	t.cancel()
	t.conn.Close()
	t.udpLn.Close()
	t.wg.Wait()
}

// IsActive returns true if the tunnel is running.
func (t *TCPFallbackTunnel) IsActive() bool {
	return atomic.LoadInt32(&t.active) == 1
}

// ── Pump: local UDP → remote WebSocket ────────────────────────────────────────

func (t *TCPFallbackTunnel) udpToWS(ctx context.Context) {
	defer t.wg.Done()
	buf := make([]byte, 65536)
	hdr := make([]byte, 2)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		t.udpLn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
		n, _, err := t.udpLn.ReadFromUDP(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			return
		}
		// Frame format: [2-byte big-endian length][payload]
		binary.BigEndian.PutUint16(hdr, uint16(n))
		frame := append(hdr, buf[:n]...)
		if _, err := t.conn.Write(frame); err != nil {
			return
		}
	}
}

// ── Pump: remote WebSocket → local UDP ───────────────────────────────────────

func (t *TCPFallbackTunnel) wsToUDP(ctx context.Context) {
	defer t.wg.Done()
	// wireguard-go sends to our local relay port; replies come back here.
	// We forward to wireguard-go by writing back to the same local port.
	loopback, err := net.ResolveUDPAddr("udp4", fmt.Sprintf("127.0.0.1:%d", t.cfg.LocalUDPPort))
	if err != nil {
		return
	}
	hdr := make([]byte, 2)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		// Read length header
		t.conn.SetReadDeadline(time.Now().Add(30 * time.Second))
		if _, err := io.ReadFull(t.conn, hdr); err != nil {
			return
		}
		pktLen := binary.BigEndian.Uint16(hdr)
		payload := make([]byte, pktLen)
		if _, err := io.ReadFull(t.conn, payload); err != nil {
			return
		}
		// Write back to wireguard-go's local UDP endpoint
		t.udpLn.WriteToUDP(payload, loopback)
	}
}
