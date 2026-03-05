// lib/ui/widgets/connect_button.dart
import 'package:flutter/material.dart';
import '../../models/vpn_status.dart';

class ConnectButton extends StatefulWidget {
  final VpnStatus status;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const ConnectButton({
    super.key,
    required this.status,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _buttonColor {
    switch (widget.status.state) {
      case VpnState.connected:
        return const Color(0xFF00C896);
      case VpnState.connecting:
      case VpnState.reconnecting:
        return const Color(0xFFFFB300);
      case VpnState.error:
        return const Color(0xFFFF5252);
      default:
        return const Color(0xFF6C63FF);
    }
  }

  String get _label {
    switch (widget.status.state) {
      case VpnState.connected:
        return 'Connected';
      case VpnState.connecting:
        return 'Connecting...';
      case VpnState.reconnecting:
        return 'Reconnecting...';
      case VpnState.disconnecting:
        return 'Disconnecting...';
      case VpnState.error:
        return 'Error – Tap to retry';
      default:
        return 'Tap to Connect';
    }
  }

  IconData get _icon {
    switch (widget.status.state) {
      case VpnState.connected:
        return Icons.lock;
      case VpnState.connecting:
      case VpnState.reconnecting:
        return Icons.sync;
      case VpnState.error:
        return Icons.error_outline;
      default:
        return Icons.lock_open;
    }
  }

  bool get _isLoading =>
      widget.status.state == VpnState.connecting ||
      widget.status.state == VpnState.disconnecting ||
      widget.status.state == VpnState.reconnecting;

  @override
  Widget build(BuildContext context) {
    final color = _buttonColor;

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (ctx, child) {
        final scale = widget.status.isConnected ? _pulseAnim.value : 1.0;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: _isLoading
            ? null
            : (widget.status.isConnected ? widget.onDisconnect : widget.onConnect),
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withOpacity(0.3), color.withOpacity(0.05)],
            ),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                )
              else
                Icon(_icon, color: color, size: 44),
              const SizedBox(height: 8),
              Text(
                _label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
