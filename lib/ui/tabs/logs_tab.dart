import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../engine/vpn_engine.dart';

class LogsTab extends StatefulWidget {
  const LogsTab({Key? key}) : super(key: key);

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnEngine>(
      builder: (ctx, engine, _) {
        final logs = engine.logs;
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text('ENGINE DIAGNOSTICS', 
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 13, color: Colors.white70)),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: logs.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard')));
                },
              ),
            ],
          ),
          body: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: logs.length,
              itemBuilder: (ctx, i) {
                final line = logs[i];
                final isErr = line.contains('ERROR') || line.contains('WARNING');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: GoogleFonts.firaCode(
                      color: isErr ? Colors.redAccent.withOpacity(0.8) : Colors.greenAccent.withOpacity(0.7),
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
