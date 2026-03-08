// Package main is the CGO entry point that compiles into a C shared library.
// It wraps wireguard-go's internal device/tun stack and exposes the C-ABI
// defined in wireguard.h so that Dart FFI can call it directly.
//
// Build commands (see scripts/build_*.sh for platform-specific flags):
//
//   Linux:   CGO_ENABLED=1 go build -buildmode=c-shared -o libwireguard.so .
//   Windows: CGO_ENABLED=1 GOARCH=amd64 GOOS=windows go build -buildmode=c-shared -o wireguard.dll .
//   Android: see scripts/build_android.sh   (cross-compile per ABI)
//   iOS/mac: see scripts/build_apple.sh     (XCFramework via gomobile or CGO)

package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef int32_t WgTunnelHandle;

typedef struct {
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    uint64_t last_handshake_sec;
    uint32_t rx_packets;
    uint32_t tx_packets;
} WgMetrics;

typedef void (*LogCallback)(const char* msg);

static inline void call_log_callback(LogCallback cb, const char* msg) {
    if (cb != NULL) {
        cb(msg);
    }
}
*/
import "C"

import (
	"encoding/base64"
	"fmt"
	"math/rand"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/crypto/curve25519"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

// ─── State constants (must mirror WgTunnelState in wireguard.h) ─────────────

const (
	stateDisconnected  = 0
	stateConnecting    = 1
	stateConnected     = 2
	stateDisconnecting = 3
	stateError         = 4
)

// ─── Per-tunnel bookkeeping ──────────────────────────────────────────────────

type tunnel struct {
	dev      *device.Device
	tunDev   tun.Device
	uapi     net.Listener
	state    int32
	rxBytes  uint64
	txBytes  uint64
	rxPkts   uint32
	txPkts   uint32
	lastHandshakeSec uint64
	ticker   *time.Ticker
	quit     chan struct{}
	// Windows-only: stored so we can clean up routes on disconnect
	tunName     string
	tunEndpoint string // the server's public IP, needed for exclusion route cleanup
}

var (
	mu       sync.Mutex
	tunnels  = make(map[C.int32_t]*tunnel)
	nextHdl  C.int32_t = 1
	lastErr  string
	
	logMu        sync.Mutex
	logCallback  C.LogCallback
)

func setError(msg string) C.int32_t {
	lastErr = msg
	return -1
}

// ─── Exported Logging Functions ──────────────────────────────────────────────

//export wg_set_log_callback
func wg_set_log_callback(cb C.LogCallback) {
	logMu.Lock()
	logCallback = cb
	logMu.Unlock()
}

// nativeLog prints locally (fmt) and dispatches to Dart if cb is set
func nativeLog(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	// Print to native stdout for local C debugging
	fmt.Printf("[wg-native] %s\n", msg)

	logMu.Lock()
	cb := logCallback
	logMu.Unlock()

	if cb != nil {
		cMsg := C.CString(msg)
		C.call_log_callback(cb, cMsg)
		C.free(unsafe.Pointer(cMsg))
	}
}

// Intercept Logger
func createCustomLogger() *device.Logger {
	return &device.Logger{
		Verbosef: func(format string, args ...interface{}) {
			nativeLog(format, args...)
		},
		Errorf: func(format string, args ...interface{}) {
			nativeLog("ERROR: "+format, args...)
		},
	}
}

// ─── Exported C functions ────────────────────────────────────────────────────

//export wg_tunnel_start
func wg_tunnel_start(cfgC *C.char, nameC *C.char, fdC C.int32_t) C.int32_t {
	cfg := C.GoString(cfgC)
	name := C.GoString(nameC)
	platformFd := int(fdC)

	mu.Lock()
	defer mu.Unlock()

	// ── Create the TUN interface ───────────────────────────────────────────
	var tunDev tun.Device
	var mtu int = 1420
	var err error

	tunDev, err = createTunDevice(name, mtu, platformFd)
	if err != nil {
		return setError(fmt.Sprintf("create TUN failed: %v", err))
	}

	// ── Bring up the WireGuard device ────────────────────────────────────
	logger := createCustomLogger()
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), logger)

	// ── Apply wg-quick style config via UAPI SetDevice ────────────────────
	if err := applyConfig(dev, cfg); err != nil {
		dev.Close()
		tunDev.Close()
		return setError(fmt.Sprintf("apply config failed: %v", err))
	}

	// ── Create UAPI socket listener (for stats) ───────────────────────────
	uapiLn := setupUAPI(name, dev)

	dev.Up()

	// ── Windows: configure adapter IP, DNS, and routing ─────────────────
	// This makes traffic actually flow through the tunnel.
	meta := parseConfigMeta(cfg)
	if meta.address != "" {
		if err := configureWindowsInterface(name, meta.address, meta.dns, meta.endpoint); err != nil {
			nativeLog("WARNING: Windows interface config failed: %v", err)
		}
	} else {
		nativeLog("WARNING: No Address found in config ─ traffic routing skipped")
	}

	t := &tunnel{
		dev:         dev,
		tunDev:      tunDev,
		uapi:        uapiLn,
		state:       stateConnected,
		quit:        make(chan struct{}),
		tunName:     name,
		tunEndpoint: meta.endpoint,
	}

	// ── Start the stats-polling goroutine ─────────────────────────────────
	t.ticker = time.NewTicker(1 * time.Second)
	go func() {
		for {
			select {
			case <-t.quit:
				return
			case <-t.ticker.C:
				pollStats(dev, t)
			}
		}
	}()

	hdl := nextHdl
	nextHdl++
	tunnels[hdl] = t
	return hdl
}

//export wg_tunnel_stop
func wg_tunnel_stop(handle C.int32_t) {
	mu.Lock()
	t, ok := tunnels[handle]
	if !ok {
		mu.Unlock()
		return
	}
	t.state = stateDisconnecting
	delete(tunnels, handle)
	mu.Unlock()

	t.ticker.Stop()
	close(t.quit)

	// Cleanup Windows routing rules before tearing down
	if t.tunName != "" {
		removeWindowsRoutes(t.tunName, t.tunEndpoint)
	}

	t.dev.Down()
	if t.uapi != nil {
		t.uapi.Close()
	}
	t.dev.Close()
	t.tunDev.Close()
}

// ─── Config metadata parser ───────────────────────────────────────────────

type configMeta struct {
	address  string
	dns      string
	endpoint string // server public IP, without port
}

// parseConfigMeta extracts the VPN client IP address, DNS and endpoint from a wg-quick block.
func parseConfigMeta(cfg string) configMeta {
	var m configMeta
	for _, rawLine := range strings.Split(cfg, "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "[") {
			continue
		}
		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			continue
		}
		switch strings.ToLower(strings.TrimSpace(kv[0])) {
		case "address":
			m.address = strings.TrimSpace(kv[1])
		case "dns":
			// Use only the first DNS entry
			m.dns = strings.TrimSpace(strings.SplitN(kv[1], ",", 2)[0])
		case "endpoint":
			// Strip port: "1.2.3.4:51820" → "1.2.3.4"
			ep := strings.TrimSpace(kv[1])
			if host, _, err := net.SplitHostPort(ep); err == nil {
				m.endpoint = host
			} else {
				m.endpoint = ep
			}
		}
	}
	return m
}

//export wg_get_metrics
func wg_get_metrics(handle C.int32_t, out *C.WgMetrics) C.int32_t {
	mu.Lock()
	t, ok := tunnels[handle]
	mu.Unlock()
	if !ok {
		return -1
	}
	out.rx_bytes = C.uint64_t(t.rxBytes)
	out.tx_bytes = C.uint64_t(t.txBytes)
	out.rx_packets = C.uint32_t(t.rxPkts)
	out.tx_packets = C.uint32_t(t.txPkts)
	out.last_handshake_sec = C.uint64_t(t.lastHandshakeSec)
	return 0
}

//export wg_tunnel_state
func wg_tunnel_state(handle C.int32_t) C.int32_t {
	mu.Lock()
	t, ok := tunnels[handle]
	mu.Unlock()
	if !ok {
		return stateDisconnected
	}
	return C.int32_t(t.state)
}

//export wg_get_last_error
func wg_get_last_error() *C.char {
	return C.CString(lastErr)
}

//export wg_generate_private_key
func wg_generate_private_key(out *C.char, bufLen C.int32_t) C.int32_t {
	var key [32]byte
	if _, err := rand.Read(key[:]); err != nil {
		return setError(err.Error())
	}
	key[0] &= 248
	key[31] &= 127
	key[31] |= 64
	encoded := base64.StdEncoding.EncodeToString(key[:])
	if len(encoded)+1 > int(bufLen) {
		return setError("buffer too small")
	}
	copy((*[45]byte)(unsafe.Pointer(out))[:], encoded+"\x00")
	return 0
}

//export wg_derive_public_key
func wg_derive_public_key(privB64 *C.char, out *C.char, bufLen C.int32_t) C.int32_t {
	privBytes, err := base64.StdEncoding.DecodeString(C.GoString(privB64))
	if err != nil || len(privBytes) != 32 {
		return setError("invalid private key")
	}
	var priv, pub [32]byte
	copy(priv[:], privBytes)
	curve25519.ScalarBaseMult(&pub, &priv)
	encoded := base64.StdEncoding.EncodeToString(pub[:])
	if len(encoded)+1 > int(bufLen) {
		return setError("buffer too small")
	}
	copy((*[45]byte)(unsafe.Pointer(out))[:], encoded+"\x00")
	return 0
}

//export wg_generate_preshared_key
func wg_generate_preshared_key(out *C.char, bufLen C.int32_t) C.int32_t {
	var key [32]byte
	if _, err := rand.Read(key[:]); err != nil {
		return setError(err.Error())
	}
	encoded := base64.StdEncoding.EncodeToString(key[:])
	if len(encoded)+1 > int(bufLen) {
		return setError("buffer too small")
	}
	copy((*[45]byte)(unsafe.Pointer(out))[:], encoded+"\x00")
	return 0
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

// applyConfig translates a wg-quick config block into UAPI SetDevice commands.
// This is the same approach used internally by wireguard-go's own tools.
func applyConfig(dev *device.Device, cfg string) error {
	ipcCmds := wgQuickToIPC(cfg)
	return dev.IpcSetOperation(strings.NewReader(ipcCmds))
}

// wgQuickToIPC converts a minimal wg-quick config to UAPI line-protocol.
// Handles [Interface] PrivateKey, ListenPort and [Peer] sections.
func wgQuickToIPC(cfg string) string {
	var b strings.Builder
	inPeer := false

	for _, rawLine := range strings.Split(cfg, "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		lower := strings.ToLower(line)

		switch lower {
		case "[interface]":
			inPeer = false
			continue
		case "[peer]":
			inPeer = true
			continue
		}

		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			continue
		}
		k := strings.TrimSpace(kv[0])
		v := strings.TrimSpace(kv[1])

		if !inPeer {
			switch strings.ToLower(k) {
			case "privatekey":
				raw, err := base64.StdEncoding.DecodeString(v)
				if err == nil && len(raw) == 32 {
					b.WriteString("private_key=" + hex(raw) + "\n")
				} else {
					nativeLog("ERROR: Skip invalid private key (len=%d)", len(raw))
				}
			case "listenport":
				b.WriteString("listen_port=" + v + "\n")
			}
		} else {
			switch strings.ToLower(k) {
			case "publickey":
				raw, err := base64.StdEncoding.DecodeString(v)
				if err == nil && len(raw) == 32 {
					b.WriteString("public_key=" + hex(raw) + "\n")
				} else {
					nativeLog("ERROR: Skip invalid public key (len=%d)", len(raw))
				}
			case "presharedkey":
				raw, err := base64.StdEncoding.DecodeString(v)
				if err == nil && len(raw) == 32 {
					b.WriteString("preshared_key=" + hex(raw) + "\n")
				} else {
					nativeLog("ERROR: Skip invalid preshared key (len=%d)", len(raw))
				}
			case "endpoint":
				b.WriteString("endpoint=" + v + "\n")
			case "allowedips":
				for _, cidr := range strings.Split(v, ",") {
					b.WriteString("allowed_ip=" + strings.TrimSpace(cidr) + "\n")
				}
			case "persistentkeepalive":
				b.WriteString("persistent_keepalive_interval=" + v + "\n")
			}
		}
	}
	return b.String()
}

func hex(b []byte) string {
	const hx = "0123456789abcdef"
	dst := make([]byte, len(b)*2)
	for i, v := range b {
		dst[i*2] = hx[v>>4]
		dst[i*2+1] = hx[v&0xf]
	}
	return string(dst)
}

// pollStats queries the UAPI for current Rx/Tx via IpcGetOperation.
func pollStats(dev *device.Device, t *tunnel) {
	var sb strings.Builder
	if err := dev.IpcGetOperation(&sb); err != nil {
		return
	}
	for _, line := range strings.Split(sb.String(), "\n") {
		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			continue
		}
		switch kv[0] {
		case "rx_bytes":
			v, _ := strconv.ParseUint(kv[1], 10, 64)
			t.rxBytes = v
		case "tx_bytes":
			v, _ := strconv.ParseUint(kv[1], 10, 64)
			t.txBytes = v
		case "last_handshake_time_sec":
			v, _ := strconv.ParseUint(kv[1], 10, 64)
			t.lastHandshakeSec = v
		}
	}
}

// main is required by CGO; it must exist but is never called at runtime.
func main() {}
