import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _locationIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/teams')) return 1;
    if (location.startsWith('/challenges')) return 2;
    if (location.startsWith('/steps')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _locationIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/dashboard');
            case 1: context.go('/teams');
            case 2: context.go('/challenges');
            case 3: context.go('/steps');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Equipos'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Desafíos'),
          NavigationDestination(icon: Icon(Icons.directions_walk_outlined), selectedIcon: Icon(Icons.directions_walk), label: 'Pasos'),
        ],
      ),
    );
  }
}
