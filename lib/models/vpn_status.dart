// lib/models/vpn_status.dart

enum VpnState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  reconnecting,
  error,
}

class VpnStatus {
  final VpnState state;
  final String? tunnelIp;
  final String? serverEndpoint;
  final String? serverPublicKey;
  final int? uplinkMs;          // latency to server
  final DateTime? connectedAt;
  final String? errorMessage;
  final String? interfaceName;  // e.g. wg0

  const VpnStatus({
    required this.state,
    this.tunnelIp,
    this.serverEndpoint,
    this.serverPublicKey,
    this.uplinkMs,
    this.connectedAt,
    this.errorMessage,
    this.interfaceName,
  });

  factory VpnStatus.disconnected() => const VpnStatus(state: VpnState.disconnected);

  factory VpnStatus.fromMap(Map<String, dynamic> map) {
    final stateStr = map['state'] as String? ?? 'disconnected';
    final state = VpnState.values.firstWhere(
      (e) => e.name == stateStr,
      orElse: () => VpnState.disconnected,
    );
    return VpnStatus(
      state: state,
      tunnelIp: map['tunnelIp'] as String?,
      serverEndpoint: map['serverEndpoint'] as String?,
      serverPublicKey: map['serverPublicKey'] as String?,
      uplinkMs: map['uplinkMs'] as int?,
      connectedAt: map['connectedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['connectedAt'] as int)
          : null,
      errorMessage: map['errorMessage'] as String?,
      interfaceName: map['interfaceName'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'state': state.name,
        'tunnelIp': tunnelIp,
        'serverEndpoint': serverEndpoint,
        'serverPublicKey': serverPublicKey,
        'uplinkMs': uplinkMs,
        'connectedAt': connectedAt?.millisecondsSinceEpoch,
        'errorMessage': errorMessage,
        'interfaceName': interfaceName,
      };

  bool get isConnected => state == VpnState.connected;
  bool get isConnecting =>
      state == VpnState.connecting || state == VpnState.reconnecting;
  bool get isDisconnected =>
      state == VpnState.disconnected || state == VpnState.error;

  Duration? get uptime {
    if (connectedAt == null) return null;
    return DateTime.now().difference(connectedAt!);
  }

  @override
  String toString() =>
      'VpnStatus(state: $state, ip: $tunnelIp, uptime: $uptime)';
}

class VpnConnectResult {
  final bool success;
  final String message;
  final String? assignedTunnelIp;

  const VpnConnectResult({
    required this.success,
    required this.message,
    this.assignedTunnelIp,
  });

  factory VpnConnectResult.fromMap(Map<String, dynamic> map) => VpnConnectResult(
        success: map['success'] as bool? ?? false,
        message: map['message'] as String? ?? '',
        assignedTunnelIp: map['assignedTunnelIp'] as String?,
      );
}
