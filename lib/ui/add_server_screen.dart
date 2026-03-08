import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../models/vpn_models.dart';
import '../services/server_repository.dart';
import '../engine/vpn_engine.dart';
import '../utils/config_parser.dart';
import 'package:provider/provider.dart';

class AddServerScreen extends StatefulWidget {
  const AddServerScreen({Key? key}) : super(key: key);

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  bool _isPasteMode = true;
  final _configController = TextEditingController();
  
  // Manual fields
  final _nameController = TextEditingController(text: 'My Custom Server');
  final _keyController = TextEditingController();
  final _addressController = TextEditingController(text: '10.0.0.2/32');
  final _pubKeyController = TextEditingController();
  final _endpointController = TextEditingController();
  final _dnsController = TextEditingController(text: '1.1.1.1');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('ADD NEW SERVER', style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 13)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildModeSwitch(),
            const SizedBox(height: 30),
            _isPasteMode ? _buildPasteSection() : _buildManualForm(),
            const SizedBox(height: 40),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _modeButton('PASTE CONFIG', _isPasteMode, () => setState(() => _isPasteMode = true))),
          Expanded(child: _modeButton('MANUAL ENTRY', !_isPasteMode, () => setState(() => _isPasteMode = false))),
        ],
      ),
    );
  }

  Widget _modeButton(String title, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.white38)),
      ),
    );
  }

  Widget _buildPasteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WIRE GUARD CONFIG (.conf)', style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 12),
        TextField(
          controller: _configController,
          maxLines: 12,
          style: GoogleFonts.firaCode(fontSize: 12, color: Colors.greenAccent),
          decoration: InputDecoration(
            hintText: '[Interface]\nPrivateKey = ...\nAddress = ...\n\n[Peer]\nPublicKey = ...\nEndpoint = ...',
            hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
            filled: true,
            fillColor: Colors.black.withOpacity(0.3),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildManualForm() {
    return Column(
      children: [
        _field('SERVER NAME', _nameController, 'e.g. London Fast'),
        _field('PRIVATE KEY', _keyController, 'Client Private Key'),
        _field('CLIENT ADDRESS', _addressController, 'e.g. 10.0.0.2/32'),
        _field('SERVER PUBLIC KEY', _pubKeyController, 'Remote Peer Public Key'),
        _field('ENDPOINT', _endpointController, 'e.g. 1.2.3.4:51820'),
        _field('DNS', _dnsController, 'e.g. 1.1.1.1'),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true, fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        onPressed: _saveAndConnect,
        child: Text('SAVE AND CONNECT', style: GoogleFonts.inter(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      ),
    );
  }

  void _saveAndConnect() async {
    final engine = Provider.of<VpnEngine>(context, listen: false);
    VpnConfig? config;
    String name = _nameController.text;

    if (_isPasteMode) {
      config = ConfigParser.parse(_configController.text);
      if (config == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid configuration format. Make sure [Interface] and [Peer] sections are present.')));
        return;
      }
    } else {
      config = VpnConfig(
        privateKey: _keyController.text,
        address: _addressController.text,
        serverPublicKey: _pubKeyController.text,
        endpoint: _endpointController.text,
        allowedIPs: '0.0.0.0/0',
        dns: _dnsController.text,
      );
    }

    final server = SavedServer(
      id: const Uuid().v4(),
      name: name,
      country: 'Custom',
      flagEmoji: '🌍',
      config: config,
    );

    // Instead of saving immediately, we trigger a connection.
    // VpnEngine will save it to the database ONLY if it successfully connects.
    Navigator.pop(context);
    await engine.connect(config, serverMetadata: server);
  }
}
