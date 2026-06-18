import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_company_screen.dart';
import '../../features/auth/screens/invite_screen.dart';
import '../../features/shell/screens/main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuth = session != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation.startsWith('/invite');

      if (!isAuth && !isAuthRoute) return '/login';
      if (isAuth && isAuthRoute && !state.matchedLocation.startsWith('/invite')) return '/';
      return null;
    },
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
          GoRoute(path: '/', builder: (ctx, st) => const SizedBox.shrink()),
          GoRoute(path: '/dashboard', builder: (ctx, st) => const SizedBox.shrink()),
          GoRoute(path: '/teams', builder: (ctx, st) => const SizedBox.shrink()),
          GoRoute(path: '/challenges', builder: (ctx, st) => const SizedBox.shrink()),
          GoRoute(path: '/steps', builder: (ctx, st) => const SizedBox.shrink()),
        ],
      ),
    ],
  );
});
