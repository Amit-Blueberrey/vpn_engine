// lib/models/traffic_stats.dart
// ─────────────────────────────────────────────────────────────────────────────
// Models for traffic statistics, per-packet/connection log entries,
// and DNS query log. All fed from native EventChannel streams.
// ─────────────────────────────────────────────────────────────────────────────

/// Aggregate bandwidth/packet stats for the active tunnel
class TrafficStats {
  final int rxBytes;      // bytes received through tunnel
  final int txBytes;      // bytes sent through tunnel
  final int rxPackets;
  final int txPackets;
  final double rxRateBps; // current receive rate bytes/sec
  final double txRateBps; // current transmit rate bytes/sec
  final DateTime timestamp;

  const TrafficStats({
    required this.rxBytes,
    required this.txBytes,
    required this.rxPackets,
    required this.txPackets,
    required this.rxRateBps,
    required this.txRateBps,
    required this.timestamp,
  });

  factory TrafficStats.empty() => TrafficStats(
        rxBytes: 0,
        txBytes: 0,
        rxPackets: 0,
        txPackets: 0,
        rxRateBps: 0,
        txRateBps: 0,
        timestamp: DateTime.now(),
      );

  factory TrafficStats.fromMap(Map<String, dynamic> map) => TrafficStats(
        rxBytes: map['rxBytes'] as int? ?? 0,
        txBytes: map['txBytes'] as int? ?? 0,
        rxPackets: map['rxPackets'] as int? ?? 0,
        txPackets: map['txPackets'] as int? ?? 0,
        rxRateBps: (map['rxRateBps'] as num?)?.toDouble() ?? 0,
        txRateBps: (map['txRateBps'] as num?)?.toDouble() ?? 0,
        timestamp: map['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
            : DateTime.now(),
      );

  String get formattedRx => formatBytes(rxBytes);
  String get formattedTx => formatBytes(txBytes);
  String get formattedRxRate => '${formatBytes(rxRateBps.toInt())}/s';
  String get formattedTxRate => '${formatBytes(txRateBps.toInt())}/s';

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

/// Live traffic log entry – fired per TCP/UDP connection by the native layer
class TrafficLogEntry {
  final DateTime timestamp;
  final String protocol;        // TCP | UDP | ICMP
  final String srcIp;
  final int srcPort;
  final String dstIp;
  final int dstPort;
  final int bytes;
  final String? hostname;       // resolved hostname if available
  final String direction;       // 'out' | 'in'

  const TrafficLogEntry({
    required this.timestamp,
    required this.protocol,
    required this.srcIp,
    required this.srcPort,
    required this.dstIp,
    required this.dstPort,
    required this.bytes,
    this.hostname,
    required this.direction,
  });

  factory TrafficLogEntry.fromMap(Map<String, dynamic> map) => TrafficLogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        protocol: map['protocol'] as String? ?? 'TCP',
        srcIp: map['srcIp'] as String? ?? '0.0.0.0',
        srcPort: map['srcPort'] as int? ?? 0,
        dstIp: map['dstIp'] as String? ?? '0.0.0.0',
        dstPort: map['dstPort'] as int? ?? 0,
        bytes: map['bytes'] as int? ?? 0,
        hostname: map['hostname'] as String?,
        direction: map['direction'] as String? ?? 'out',
      );

  @override
  String toString() =>
      '[${timestamp.toIso8601String()}] $direction $protocol '
      '${hostname ?? dstIp}:$dstPort  ${TrafficStats.formatBytes(bytes)}';
}

/// DNS query log entry – from the VPN layer DNS interceptor
class DnsLogEntry {
  final DateTime timestamp;
  final String queryType;       // A, AAAA, CNAME, MX, TXT, etc.
  final String hostname;        // queried hostname
  final List<String> answers;   // resolved IPs or CNAME targets
  final int responseMs;         // DNS response time
  final bool blocked;           // if DNS-level blocking is active

  const DnsLogEntry({
    required this.timestamp,
    required this.queryType,
    required this.hostname,
    required this.answers,
    required this.responseMs,
    required this.blocked,
  });

  factory DnsLogEntry.fromMap(Map<String, dynamic> map) => DnsLogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        queryType: map['queryType'] as String? ?? 'A',
        hostname: map['hostname'] as String? ?? '',
        answers: List<String>.from(map['answers'] as List? ?? []),
        responseMs: map['responseMs'] as int? ?? 0,
        blocked: map['blocked'] as bool? ?? false,
      );
}

/// Browsing log entry combining DNS + page visit data (when available)
class BrowsingLogEntry {
  final DateTime timestamp;
  final String url;             // full URL or "hostname" if partial
  final String hostname;
  final String? title;          // page title if captured
  final int? statusCode;        // HTTP status if captured
  final String protocol;        // https | http | dns-only
  final int bytesTransferred;

  const BrowsingLogEntry({
    required this.timestamp,
    required this.url,
    required this.hostname,
    this.title,
    this.statusCode,
    required this.protocol,
    required this.bytesTransferred,
  });

  factory BrowsingLogEntry.fromMap(Map<String, dynamic> map) => BrowsingLogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        url: map['url'] as String? ?? '',
        hostname: map['hostname'] as String? ?? '',
        title: map['title'] as String?,
        statusCode: map['statusCode'] as int?,
        protocol: map['protocol'] as String? ?? 'https',
        bytesTransferred: map['bytesTransferred'] as int? ?? 0,
      );
}
