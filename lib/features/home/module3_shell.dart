import 'package:flutter/material.dart';

import 'home_page.dart';
import '../parking/parking_page.dart';
import 'settings_page.dart';

class Module3Shell extends StatefulWidget {
  const Module3Shell({super.key});

  @override
  State<Module3Shell> createState() => _Module3ShellState();
}

class _Module3ShellState extends State<Module3Shell> {
  int _index = 0;

  Widget _page() => switch (_index) {
    0 => const HomePage(),
    1 => const HomePage(initialFilter: PlaceFilter.lifts),
    2 => const HomePage(initialFilter: PlaceFilter.cafeteria),
    3 => const ParkingPage(),
    _ => const SettingsPage(),
  };

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.elevator_outlined),
      selectedIcon: Icon(Icons.elevator_rounded),
      label: 'Lifts',
    ),
    NavigationDestination(
      icon: Icon(Icons.restaurant_outlined),
      selectedIcon: Icon(Icons.restaurant_rounded),
      label: 'Cafeteria',
    ),
    NavigationDestination(
      icon: Icon(Icons.local_parking_outlined),
      selectedIcon: Icon(Icons.local_parking_rounded),
      label: 'Parking',
    ),
    NavigationDestination(
      icon: Icon(Icons.account_circle_outlined),
      selectedIcon: Icon(Icons.account_circle_rounded),
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.025, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_index), child: _page()),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: _destinations,
    ),
  );
}

