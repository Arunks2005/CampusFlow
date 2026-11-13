import 'package:flutter/material.dart';

import 'alerts_page.dart';
import 'home_page.dart';
import 'planner_page.dart';
import 'settings_page.dart';

class Module3Shell extends StatefulWidget {
  const Module3Shell({super.key});
  @override
  State<Module3Shell> createState() => _Module3ShellState();
}

class _Module3ShellState extends State<Module3Shell> {
  int _index = 0;
  static const _pages = [
    HomePage(),
    PlannerPage(),
    AlertsPage(),
    SettingsPage(),
  ];
  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.event_available_outlined),
      selectedIcon: Icon(Icons.event_available_rounded),
      label: 'Planner',
    ),
    NavigationDestination(
      icon: Icon(Icons.notifications_none_rounded),
      selectedIcon: Icon(Icons.notifications_active_rounded),
      label: 'Alerts',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: _destinations,
    ),
  );
}
