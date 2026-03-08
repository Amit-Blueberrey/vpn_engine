import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../engine/vpn_engine.dart';
import '../../models/vpn_models.dart';
import '../../services/server_repository.dart';
import '../add_server_screen.dart';

class ServersTab extends StatefulWidget {
  const ServersTab({Key? key}) : super(key: key);

  @override
  State<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends State<ServersTab> {
  @override
  Widget build(BuildContext context) {
    final repository = ServerRepository.instance;
    final engine = Provider.of<VpnEngine>(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('LOCATIONS', 
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 14, color: Colors.white70)),
      ),
      body: Consumer<ServerRepository>(
        builder: (ctx, repository, _) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            itemCount: repository.servers.length,
            itemBuilder: (ctx, index) {
              final server = repository.servers[index];
              final isSelected = engine.metrics.rxBytes > 0 && // Simple logic for 'active'
                  engine.state == VpnState.connected; 

              return _buildServerCard(server, isSelected, engine);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddServerScreen())),
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildServerCard(SavedServer server, bool isSelected, VpnEngine engine) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151525),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? Colors.blueAccent.withOpacity(0.5) : Colors.white.withOpacity(0.05),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Text(server.flagEmoji, style: const TextStyle(fontSize: 32)),
        title: Text(server.name, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(server.country, style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
        trailing: IconButton(
          icon: Icon(
            engine.state == VpnState.connected ? Icons.swap_horiz : Icons.play_arrow_rounded, 
            color: Colors.blueAccent
          ),
          onPressed: () async {
             if (engine.state == VpnState.connected) {
               await engine.disconnect();
             }
             await engine.connect(server.config);
          },
        ),
      ),
    );
  }
}
