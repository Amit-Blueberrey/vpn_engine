import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/servers_tab.dart';
import 'tabs/logs_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const DashboardTab(),
    const ServersTab(),
    const LogsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E1A),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF151525).withOpacity(0.8),
          border: const Border(top: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.white38,
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'DASHBOARD',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.public_outlined),
              activeIcon: Icon(Icons.public),
              label: 'SERVERS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.terminal_outlined),
              activeIcon: Icon(Icons.terminal),
              label: 'LOGS',
            ),
          ],
        ),
      ),
    );
  }
}
