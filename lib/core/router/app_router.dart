import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_company_screen.dart';
import '../../features/auth/screens/invite_screen.dart';
import '../../features/companies/screens/dashboard_screen.dart';
import '../../features/companies/screens/users_screen.dart';
import '../../features/shell/screens/main_shell.dart';

final _routerKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _routerKey,
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuth = session != null;
      final loc = state.matchedLocation;
      final isPublic = loc == '/login' || loc == '/register' || loc.startsWith('/invite');

      if (!isAuth && !isPublic) return '/login';
      if (isAuth && loc == '/login') return '/dashboard';
      return null;
    },
    refreshListenable: _SupabaseAuthListenable(),
    routes: [
      GoRoute(path: '/login', builder: (ctx, st) => const LoginScreen()),
      GoRoute(path: '/register', builder: (ctx, st) => const RegisterCompanyScreen()),
      GoRoute(
        path: '/invite',
        builder: (ctx, st) => InviteScreen(token: st.uri.queryParameters['token'] ?? ''),
      ),
      ShellRoute(
        builder: (ctx, st, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (ctx, st) => const DashboardScreen()),
          GoRoute(path: '/users', builder: (ctx, st) => const UsersScreen()),
          GoRoute(path: '/teams', builder: (ctx, st) => const SizedBox.shrink()),
          GoRoute(path: '/challenges', builder: (ctx, st) => const SizedBox.shrink()),
          GoRoute(path: '/steps', builder: (ctx, st) => const SizedBox.shrink()),
        ],
      ),
    ],
  );
});

// Makes go_router re-evaluate redirect() on auth state changes
class _SupabaseAuthListenable extends ChangeNotifier {
  _SupabaseAuthListenable() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
}
