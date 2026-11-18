import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/db_service.dart';
import 'alerts_screen.dart';
import 'control_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'monitor_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.db, this.auth});

  /// Injectable for tests; each tab falls back to its own service when null.
  final DbService? db;

  /// Injectable for tests; only the sign-out action uses it, and `late` keeps
  /// it unbuilt until then.
  final AuthService? auth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // one tab = one entry in each of the three lists below
  static const _titles = ['Dashboard', 'Monitor', 'Control', 'History', 'Alerts'];

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
    NavigationDestination(icon: Icon(Icons.sensors_outlined), label: 'Monitor'),
    NavigationDestination(icon: Icon(Icons.tune_outlined), label: 'Control'),
    NavigationDestination(icon: Icon(Icons.history_outlined), label: 'History'),
    NavigationDestination(icon: Icon(Icons.notifications_outlined), label: 'Alerts'),
  ];

  // built once: IndexedStack children must keep identity or tab state resets
  late final List<Widget> _pages = [
    DashboardScreen(db: widget.db),
    MonitorScreen(db: widget.db),
    ControlScreen(db: widget.db),
    HistoryScreen(db: widget.db),
    AlertsScreen(db: widget.db),
  ];

  late final AuthService _auth = widget.auth ?? AuthService();

  /// The AuthGate swaps this shell for the login screen once the user is gone.
  Future<void> _signOut() async {
    try {
      await _auth.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not sign out.\n$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      // IndexedStack keeps every tab alive, so their state survives switching
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}
