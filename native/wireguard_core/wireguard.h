/**
 * wireguard.h - Proprietary WireGuard Native C-API
 *
 * This header defines the complete C-ABI surface that our Go (CGO) shared
 * library exposes. Dart FFI and platform-specific native callers bind to
 * exactly these symbols.
 *
 * All strings are NUL-terminated UTF-8. Return values:
 *   >= 0  : success / tunnel handle
 *   -1    : error – call wg_get_last_error() for a description
 */

#ifndef WIREGUARD_ENGINE_H
#define WIREGUARD_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* ------------------------------------------------------------------ *
 * Opaque tunnel handle returned by wg_tunnel_start().                *
 * Treat as an integer token – never dereference it from the          *
 * Dart / platform layer.                                              *
 * ------------------------------------------------------------------ */
typedef int32_t WgTunnelHandle;
#define WG_INVALID_HANDLE ((WgTunnelHandle)-1)

/* ------------------------------------------------------------------ *
 * Metrics snapshot polled by Dart every second.                       *
 * ------------------------------------------------------------------ */
typedef struct {
    uint64_t rx_bytes;           /* Total bytes received (download)  */
    uint64_t tx_bytes;           /* Total bytes sent     (upload)    */
    uint64_t last_handshake_sec; /* Unix timestamp of last handshake */
    uint32_t rx_packets;         /* Total packets received           */
    uint32_t tx_packets;         /* Total packets sent               */
} WgMetrics;

/* ------------------------------------------------------------------ *
 * Connection state values returned by wg_tunnel_state().             *
 * ------------------------------------------------------------------ */
typedef enum {
    WG_STATE_DISCONNECTED  = 0,
    WG_STATE_CONNECTING    = 1,
    WG_STATE_CONNECTED     = 2,
    WG_STATE_DISCONNECTING = 3,
    WG_STATE_ERROR         = 4,
} WgTunnelState;

/* ------------------------------------------------------------------ *
 * Core lifecycle API                                                   *
 * ------------------------------------------------------------------ */

/**
 * wg_tunnel_start
 *
 * Initialise and bring up a WireGuard tunnel.
 *
 * @param wg_quick_config  Full wg-quick-style config block as UTF-8 string.
 * @param tunnel_name      Logical name for the TUN interface (e.g. "wg0").
 * @param fd               On Android only: the file descriptor of the VPN
 *                         socket obtained from VpnService.Builder.establish().
 *                         Pass -1 on all other platforms.
 *
 * @return  A valid WgTunnelHandle (>= 0) on success, WG_INVALID_HANDLE (-1)
 *          on failure. Call wg_get_last_error() for a description.
 */
WgTunnelHandle wg_tunnel_start(const char* wg_quick_config,
                                const char* tunnel_name,
                                int32_t     fd);

/**
 * wg_tunnel_stop
 *
 * Gracefully tears down the tunnel identified by @handle.
 * After this call returns, the handle is no longer valid.
 */
void wg_tunnel_stop(WgTunnelHandle handle);

/* ------------------------------------------------------------------ *
 * Telemetry API                                                        *
 * ------------------------------------------------------------------ */

/**
 * wg_get_metrics
 *
 * Fills @out with the latest Rx/Tx counters for @handle.
 * Returns 0 on success, -1 if the handle is invalid or the tunnel is down.
 */
int32_t wg_get_metrics(WgTunnelHandle handle, WgMetrics* out);

/**
 * wg_tunnel_state
 *
 * Returns the current WgTunnelState for @handle.
 */
WgTunnelState wg_tunnel_state(WgTunnelHandle handle);

/* ------------------------------------------------------------------ *
 * Error reporting                                                       *
 * ------------------------------------------------------------------ */

/**
 * wg_get_last_error
 *
 * Returns a pointer to a static thread-local string describing the last
 * error. The caller must NOT free this string. Valid until the next API
 * call on the same OS thread.
 */
const char* wg_get_last_error(void);

/* ------------------------------------------------------------------ *
 * Key utilities (Curve25519)                                           *
 * ------------------------------------------------------------------ */

/**
 * wg_generate_private_key
 *
 * Generates a Curve25519 private key and writes the base-64 representation
 * into @out_base64 (caller allocates at least 45 bytes).
 * Returns 0 on success, -1 on failure.
 */
int32_t wg_generate_private_key(char* out_base64, int32_t buf_len);

/**
 * wg_derive_public_key
 *
 * Derives the corresponding Curve25519 public key from @private_key_b64
 * and writes it (base-64) into @out_base64 (caller allocates at least 45 bytes).
 * Returns 0 on success, -1 on failure.
 */
int32_t wg_derive_public_key(const char* private_key_b64,
                              char*       out_base64,
                              int32_t     buf_len);

/**
 * wg_generate_preshared_key
 *
 * Generates a 32-byte random preshared key and writes the base-64
 * representation into @out_base64 (caller allocates at least 45 bytes).
 */
int32_t wg_generate_preshared_key(char* out_base64, int32_t buf_len);

#ifdef __cplusplus
}
#endif

#endif /* WIREGUARD_ENGINE_H */
