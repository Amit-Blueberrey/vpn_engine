// fallback_exports.go
//
// CGO exports for the TCP fallback system.
// These functions extend the main wireguard.h C-API with fallback controls.
// Compiled into the same shared library as main.go.

package main

/*
#include <stdint.h>
#include <stdlib.h>
typedef int32_t WgTunnelHandle;
*/
import "C"

import (
	"context"
	"fmt"
	"sync"
	"time"

	"wireguard_engine/fallback"
)

// ── Global fallback registry ─────────────────────────────────────────────────

var (
	fbMu      sync.Mutex
	fbTunnels = make(map[C.int32_t]*fallback.TCPFallbackTunnel)
)

// ── Exported C functions ──────────────────────────────────────────────────────

//export wg_tunnel_start_with_fallback
//
// Starts a WireGuard tunnel and, if UDP handshake fails within
// timeoutSec seconds, silently tears down the UDP socket and spins up
// the TCP/WebSocket fallback.
//
// relayURL:   WebSocket relay URL (e.g. "wss://vpn.example.com:443/wg")
// relayToken: shared secret for relay authentication
// Returns the tunnel handle on success, WG_INVALID_HANDLE on failure.
func wg_tunnel_start_with_fallback(
	cfgC *C.char,
	nameC *C.char,
	fdC C.int32_t,
	relayURLc *C.char,
	relayTokenC *C.char,
	timeoutSec C.int32_t,
) C.int32_t {
	relayURL   := C.GoString(relayURLc)
	relayToken := C.GoString(relayTokenC)
	timeout    := time.Duration(timeoutSec) * time.Second

	// Step 1: Try normal UDP tunnel first
	handle := wg_tunnel_start(cfgC, nameC, fdC)
	if handle == C.int32_t(-1) {
		return C.int32_t(-1) // catastrophic failure, not a firewall block
	}

	// Step 2: Probe for a successful handshake within `timeout`
	if probeHandshake(handle, timeout) {
		return handle // UDP works fine, done
	}

	// Step 3: Handshake failed ── tear down UDP tunnel
	wg_tunnel_stop(handle)

	if relayURL == "" {
		return setError("UDP blocked by firewall and no relay URL provided")
	}

	// Step 4: Pick a random ephemeral local port for the UDP relay
	localRelayPort := 51900

	// Step 5: Rewrite the config's Endpoint to point at our local relay
	origCfg := C.GoString(cfgC)
	relayCfg := rewriteEndpointToLocalhost(origCfg, localRelayPort)

	// Step 6: Spin up the WebSocket→UDP relay tunnel
	fbCfg := fallback.TCPFallbackConfig{
		RelayURL:     relayURL,
		LocalUDPPort: localRelayPort,
		Token:        relayToken,
	}
	fbTunnel, err := fallback.NewTCPFallbackTunnel(fbCfg)
	if err != nil {
		return setError(fmt.Sprintf("tcp fallback dial: %v", err))
	}

	// Step 7: Start the WireGuard tunnel pointing at localhost relay
	relayCfgC := C.CString(relayCfg)
	defer C.free(relayCfgC) //nolint: staticcheck -- acceptable in CGO
	newHandle := wg_tunnel_start(relayCfgC, nameC, fdC)
	if newHandle == C.int32_t(-1) {
		fbTunnel.Close()
		return C.int32_t(-1)
	}

	fbMu.Lock()
	fbTunnels[newHandle] = fbTunnel
	fbMu.Unlock()

	return newHandle
}

//export wg_stop_fallback
func wg_stop_fallback(handle C.int32_t) {
	fbMu.Lock()
	fb, ok := fbTunnels[handle]
	if ok {
		delete(fbTunnels, handle)
	}
	fbMu.Unlock()
	if ok {
		fb.Close()
	}
	wg_tunnel_stop(handle)
}

//export wg_is_using_fallback
func wg_is_using_fallback(handle C.int32_t) C.int32_t {
	fbMu.Lock()
	defer fbMu.Unlock()
	_, ok := fbTunnels[handle]
	if ok {
		return 1
	}
	return 0
}

// ── Internal helpers ──────────────────────────────────────────────────────────

// probeHandshake polls wg_get_metrics every 500ms until a handshake is
// observed (last_handshake_sec > 0) or the timeout elapses.
func probeHandshake(handle C.int32_t, timeout time.Duration) bool {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return false
		case <-ticker.C:
			mu.Lock()
			t, ok := tunnels[handle]
			mu.Unlock()
			if !ok {
				return false
			}
			// A successful handshake increments rx_bytes if any data
			// was exchanged, OR we can check t.state == stateConnected.
			if t.state == stateConnected && t.rxBytes > 0 {
				return true
			}
		}
	}
}

// rewriteEndpointToLocalhost replaces "Endpoint = host:port" with the
// local relay address so wireguard-go talks to our WebSocket proxy.
func rewriteEndpointToLocalhost(cfg string, localPort int) string {
	import_strings := func(s, old, new string) string {
		// manual replace to avoid importing strings at the top
		result := ""
		for i := 0; i < len(s); {
			if i+len(old) <= len(s) && s[i:i+len(old)] == old {
				result += new
				i += len(old)
			} else {
				result += string(s[i])
				i++
			}
		}
		return result
	}
	_ = import_strings
	// Simple line-by-line scan
	lines := splitLines(cfg)
	for i, line := range lines {
		if len(line) > 8 && lowerEq(line[:8], "endpoint") {
			lines[i] = fmt.Sprintf("Endpoint = 127.0.0.1:%d", localPort)
		}
	}
	return joinLines(lines)
}

func splitLines(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			out = append(out, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}

func joinLines(lines []string) string {
	result := ""
	for i, l := range lines {
		if i > 0 {
			result += "\n"
		}
		result += l
	}
	return result
}

func lowerEq(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i++ {
		ca, cb := a[i], b[i]
		if ca >= 'A' && ca <= 'Z' {
			ca += 32
		}
		if ca != cb {
			return false
		}
	}
	return true
}
