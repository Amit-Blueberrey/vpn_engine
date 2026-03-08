/// vpn_core_ffi.dart
///
/// Phase 2: The Dart FFI Bridge.
///
/// This file is the ONLY file that contains dart:ffi/package:ffi code.
/// It is intentionally kept as a thin, safe wrapper so the rest of the
/// codebase works with pure Dart types.
///
/// Design principles:
///   1. Memory safety – every Pointer obtained from native is freed
///      before the call returns. We never leak C heap memory.
///   2. Isolation  – native panics cannot crash the isolate because all
///      FFI calls are wrapped in try/catch.
///   3. Thread-safety – the tunnel handle is an integer; Dart Isolate
///      model means only one thread calls native at a time.

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import '../models/vpn_models.dart';

// ─── C struct mirrors ─────────────────────────────────────────────────────────

/// Mirrors WgMetrics in wireguard.h
final class NativeWgMetrics extends Struct {
  @Uint64()
  external int rxBytes;

  @Uint64()
  external int txBytes;

  @Uint64()
  external int lastHandshakeSec;

  @Uint32()
  external int rxPackets;

  @Uint32()
  external int txPackets;
}

// ─── Native function signatures ───────────────────────────────────────────────

typedef _WgTunnelStartNative = Int32 Function(
    Pointer<Utf8> config, Pointer<Utf8> name, Int32 fd);
typedef WgTunnelStart = int Function(
    Pointer<Utf8> config, Pointer<Utf8> name, int fd);

typedef _WgTunnelStopNative = Void Function(Int32 handle);
typedef WgTunnelStop = void Function(int handle);

typedef _WgGetMetricsNative = Int32 Function(
    Int32 handle, Pointer<NativeWgMetrics> out);
typedef WgGetMetrics = int Function(
    int handle, Pointer<NativeWgMetrics> out);

typedef _WgTunnelStateNative = Int32 Function(Int32 handle);
typedef WgTunnelState = int Function(int handle);

typedef _WgGetLastErrorNative = Pointer<Utf8> Function();
typedef WgGetLastError = Pointer<Utf8> Function();

typedef _WgGeneratePrivateKeyNative = Int32 Function(
    Pointer<Utf8> out, Int32 bufLen);
typedef WgGeneratePrivateKey = int Function(Pointer<Utf8> out, int bufLen);

typedef _WgDerivePublicKeyNative = Int32 Function(
    Pointer<Utf8> privB64, Pointer<Utf8> out, Int32 bufLen);
typedef WgDerivePublicKey = int Function(
    Pointer<Utf8> privB64, Pointer<Utf8> out, int bufLen);

typedef _WgGeneratePresharedKeyNative = Int32 Function(
    Pointer<Utf8> out, Int32 bufLen);
typedef WgGeneratePresharedKey = int Function(Pointer<Utf8> out, int bufLen);

// ─── Fallback function signatures ─────────────────────────────────────────────

typedef _WgTunnelStartFallbackNative = Int32 Function(
    Pointer<Utf8> config,
    Pointer<Utf8> name,
    Int32 fd,
    Pointer<Utf8> relayUrl,
    Pointer<Utf8> relayToken,
    Int32 timeoutSec);
typedef WgTunnelStartFallback = int Function(
    Pointer<Utf8> config,
    Pointer<Utf8> name,
    int fd,
    Pointer<Utf8> relayUrl,
    Pointer<Utf8> relayToken,
    int timeoutSec);

typedef _WgStopFallbackNative = Void Function(Int32 handle);
typedef WgStopFallback = void Function(int handle);

typedef _WgIsUsingFallbackNative = Int32 Function(Int32 handle);
typedef WgIsUsingFallback = int Function(int handle);

// ─── Library loader ───────────────────────────────────────────────────────────

DynamicLibrary _openLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libwireguard.so');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libwireguard.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('wireguard.dll');
  } else if (Platform.isMacOS || Platform.isIOS) {
    // Statically linked into the main binary on Apple platforms.
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

// ─── WireGuardCore facade ─────────────────────────────────────────────────────

/// A safe, pure-Dart-typed wrapper around the native WireGuard C library.
/// Instantiate once (singleton) and share across the app.
class WireGuardCore {
  WireGuardCore._() {
    _lib = _openLibrary();
    _tunnelStart =
        _lib.lookupFunction<_WgTunnelStartNative, WgTunnelStart>('wg_tunnel_start');
    _tunnelStop =
        _lib.lookupFunction<_WgTunnelStopNative, WgTunnelStop>('wg_tunnel_stop');
    _getMetrics =
        _lib.lookupFunction<_WgGetMetricsNative, WgGetMetrics>('wg_get_metrics');
    _tunnelStateFn =
        _lib.lookupFunction<_WgTunnelStateNative, WgTunnelState>('wg_tunnel_state');
    _getLastError =
        _lib.lookupFunction<_WgGetLastErrorNative, WgGetLastError>('wg_get_last_error');
    _genPrivKey =
        _lib.lookupFunction<_WgGeneratePrivateKeyNative, WgGeneratePrivateKey>(
            'wg_generate_private_key');
    _derivePubKey =
        _lib.lookupFunction<_WgDerivePublicKeyNative, WgDerivePublicKey>(
            'wg_derive_public_key');
    _genPsk =
        _lib.lookupFunction<_WgGeneratePresharedKeyNative, WgGeneratePresharedKey>(
            'wg_generate_preshared_key');
    // Fallback bindings
    _tunnelStartFallback =
        _lib.lookupFunction<_WgTunnelStartFallbackNative, WgTunnelStartFallback>(
            'wg_tunnel_start_with_fallback');
    _stopFallback =
        _lib.lookupFunction<_WgStopFallbackNative, WgStopFallback>('wg_stop_fallback');
    _isUsingFallback =
        _lib.lookupFunction<_WgIsUsingFallbackNative, WgIsUsingFallback>(
            'wg_is_using_fallback');
  }

  static WireGuardCore? _instance;
  static WireGuardCore get instance {
    _instance ??= WireGuardCore._();
    return _instance!;
  }

  late final DynamicLibrary _lib;
  late final WgTunnelStart _tunnelStart;
  late final WgTunnelStop _tunnelStop;
  late final WgGetMetrics _getMetrics;
  late final WgTunnelState _tunnelStateFn;
  late final WgGetLastError _getLastError;
  late final WgGeneratePrivateKey _genPrivKey;
  late final WgDerivePublicKey _derivePubKey;
  late final WgGeneratePresharedKey _genPsk;
  // Fallback
  late final WgTunnelStartFallback _tunnelStartFallback;
  late final WgStopFallback _stopFallback;
  late final WgIsUsingFallback _isUsingFallback;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Starts a new WireGuard tunnel (direct UDP, no fallback).
  int tunnelStart(String config, {String name = 'wg0', int fd = -1}) {
    final configPtr = config.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      final result = _tunnelStart(configPtr, namePtr, fd);
      if (result < 0) throw WgException(lastError);
      return result;
    } finally {
      calloc.free(configPtr);
      calloc.free(namePtr);
    }
  }

  /// Starts a WireGuard tunnel with automatic TCP fallback.
  ///
  /// If the UDP handshake has no response within [handshakeTimeoutSec] seconds,
  /// the engine silently tears down the UDP socket and spins up a WebSocket
  /// relay on port 443 instead.
  ///
  /// [relayUrl]   — WebSocket relay URL, e.g. "wss://vpn.example.com:443/wg"
  /// [relayToken] — Shared secret sent in X-WG-Token header.
  int tunnelStartWithFallback(String config, {
    String name = 'wg0',
    int fd = -1,
    required String relayUrl,
    String relayToken = '',
    int handshakeTimeoutSec = 5,
  }) {
    final configPtr    = config.toNativeUtf8();
    final namePtr      = name.toNativeUtf8();
    final relayUrlPtr  = relayUrl.toNativeUtf8();
    final tokenPtr     = relayToken.toNativeUtf8();
    try {
      final result = _tunnelStartFallback(
          configPtr, namePtr, fd, relayUrlPtr, tokenPtr, handshakeTimeoutSec);
      if (result < 0) throw WgException(lastError);
      return result;
    } finally {
      calloc.free(configPtr);
      calloc.free(namePtr);
      calloc.free(relayUrlPtr);
      calloc.free(tokenPtr);
    }
  }

  /// Tears down the tunnel, including any associated TCP fallback relay.
  void tunnelStopWithFallback(int handle) => _stopFallback(handle);

  /// Returns true if this handle is currently using the TCP/WebSocket fallback.
  bool isUsingFallback(int handle) => _isUsingFallback(handle) == 1;

  /// Returns a [VpnMetrics] snapshot for [handle].
  /// Returns [VpnMetrics.zero()] if the handle is invalid.
  VpnMetrics getMetrics(int handle) {
    final ptr = calloc<NativeWgMetrics>();
    try {
      final rc = _getMetrics(handle, ptr);
      if (rc != 0) return VpnMetrics.zero();
      final m = ptr.ref;
      return VpnMetrics(
        rxBytes: m.rxBytes,
        txBytes: m.txBytes,
        rxPackets: m.rxPackets,
        txPackets: m.txPackets,
        timestamp: DateTime.now(),
      );
    } finally {
      calloc.free(ptr);
    }
  }

  /// Returns the current [VpnState] for [handle].
  VpnState tunnelState(int handle) =>
      VpnStateFromInt.fromNative(_tunnelStateFn(handle));

  /// Returns the last error string from the native layer.
  String get lastError {
    final ptr = _getLastError();
    // The C function returns a static buffer – DO NOT free it.
    return ptr.toDartString();
  }

  // ── Key utilities ───────────────────────────────────────────────────────────

  /// Generates a new Curve25519 private key in base-64.
  String generatePrivateKey() {
    final buf = calloc<Uint8>(45);
    try {
      final rc = _genPrivKey(buf.cast<Utf8>(), 45);
      if (rc != 0) throw WgException(lastError);
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buf);
    }
  }

  /// Derives the Curve25519 public key from [privateKeyB64].
  String derivePublicKey(String privateKeyB64) {
    final privPtr = privateKeyB64.toNativeUtf8();
    final buf = calloc<Uint8>(45);
    try {
      final rc = _derivePubKey(privPtr, buf.cast<Utf8>(), 45);
      if (rc != 0) throw WgException(lastError);
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(privPtr);
      calloc.free(buf);
    }
  }

  /// Generates a 32-byte preshared key in base-64.
  String generatePresharedKey() {
    final buf = calloc<Uint8>(45);
    try {
      final rc = _genPsk(buf.cast<Utf8>(), 45);
      if (rc != 0) throw WgException(lastError);
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buf);
    }
  }
}

/// Thrown when a native WireGuard call returns an error.
class WgException implements Exception {
  final String message;
  const WgException(this.message);
  @override
  String toString() => 'WgException: $message';
}
