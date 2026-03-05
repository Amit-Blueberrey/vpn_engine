// lib/utils/vpn_logger.dart
// ─────────────────────────────────────────────────────────────────────────────
// Central logger for the VPN engine.
// All log lines are stored in memory and available for in-app display.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:collection';

enum LogLevel { debug, info, warn, error }

class LogLine {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  const LogLine({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  @override
  String toString() {
    final ts = timestamp.toIso8601String().substring(11, 23);
    final lvl = level.name.toUpperCase().padRight(5);
    return '[$ts][$lvl][$tag] $message';
  }
}

class VpnLogger {
  static const int _maxLines = 2000;
  static final Queue<LogLine> _lines = Queue();
  static final List<void Function(LogLine)> _listeners = [];

  static List<LogLine> get lines => List.unmodifiable(_lines);

  static void addListener(void Function(LogLine) cb) => _listeners.add(cb);
  static void removeListener(void Function(LogLine) cb) =>
      _listeners.remove(cb);

  static void _log(LogLevel level, String message, [String tag = 'VPN']) {
    final line = LogLine(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );
    if (_lines.length >= _maxLines) _lines.removeFirst();
    _lines.addLast(line);
    // ignore: avoid_print
    print(line.toString());
    for (final cb in _listeners) {
      cb(line);
    }
  }

  static void debug(String msg, [String tag = 'VPN']) =>
      _log(LogLevel.debug, msg, tag);
  static void info(String msg, [String tag = 'VPN']) =>
      _log(LogLevel.info, msg, tag);
  static void warn(String msg, [String tag = 'VPN']) =>
      _log(LogLevel.warn, msg, tag);
  static void error(String msg, [String tag = 'VPN']) =>
      _log(LogLevel.error, msg, tag);

  static void clear() => _lines.clear();

  static String exportAsText() => _lines.map((l) => l.toString()).join('\n');
}
