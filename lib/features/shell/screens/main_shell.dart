import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _locationIndex(String location) {
    if (location.startsWith('/teams')) return 2;
    if (location.startsWith('/challenges')) return 3;
    if (location.startsWith('/steps')) return 4;
    if (location.startsWith('/users')) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _locationIndex(location);
    final profileAsync = ref.watch(currentProfileProvider);
    final isAdmin = profileAsync.valueOrNull?.isAdmin ?? false;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/dashboard');
            case 1: context.go(isAdmin ? '/users' : '/steps');
            case 2: context.go('/teams');
            case 3: context.go('/challenges');
            case 4: context.go('/steps');
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: isAdmin
                ? const Icon(Icons.group_outlined)
                : const Icon(Icons.directions_walk_outlined),
            selectedIcon: isAdmin
                ? const Icon(Icons.group)
                : const Icon(Icons.directions_walk),
            label: isAdmin ? 'Usuarios' : 'Pasos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Equipos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Desafíos',
          ),
        ],
      ),
    );
  }
}
