import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_company_screen.dart';
import '../../features/auth/screens/invite_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/companies/screens/dashboard_screen.dart';
import '../../features/companies/screens/users_screen.dart';
import '../../features/shell/screens/main_shell.dart';
import '../../features/teams/screens/teams_screen.dart';
import '../../features/teams/screens/create_team_screen.dart';
import '../../features/teams/screens/team_detail_screen.dart';
import '../../features/challenges/screens/challenges_screen.dart';
import '../../features/challenges/screens/create_challenge_screen.dart';
import '../../features/challenges/screens/challenge_detail_screen.dart';
import '../../features/steps/screens/steps_screen.dart';
import '../../features/steps/screens/leaderboard_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isAuth = Supabase.instance.client.auth.currentSession != null;
      // Use uri.path — more reliable than matchedLocation during Flutter Web init
      final path = state.uri.path;
      final isPublic = path == '/login' ||
          path == '/register' ||
          path.startsWith('/invite');

      // Deep links sin path (p. ej. el callback OAuth
      // healthywalky://login-callback) llegan como '' o '/': no hay ruta que
      // los sirva, así que se reconducen. La sesión del OAuth aún puede estar
      // procesándose; el listener de LoginScreen hace la navegación final.
      if (path.isEmpty || path == '/') return isAuth ? '/dashboard' : '/login';

      if (!isAuth && !isPublic) return '/login';
      if (isAuth && path == '/login') return '/dashboard';
      return null;
    },
    // No refreshListenable: auth-driven navigation is handled explicitly
    // in each screen (context.go) to avoid race conditions on Flutter Web.
    routes: [
      GoRoute(path: '/login', builder: (ctx, st) => const LoginScreen()),
      GoRoute(path: '/onboarding', builder: (ctx, st) => const OnboardingScreen()),
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
          GoRoute(
            path: '/teams',
            builder: (ctx, st) => const TeamsScreen(),
            routes: [
              GoRoute(path: 'new', builder: (ctx, st) => const CreateTeamScreen()),
              GoRoute(
                path: ':id',
                builder: (ctx, st) =>
                    TeamDetailScreen(teamId: st.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/challenges',
            builder: (ctx, st) => const ChallengesScreen(),
            routes: [
              GoRoute(
                  path: 'new',
                  builder: (ctx, st) => const CreateChallengeScreen()),
              GoRoute(
                path: ':id',
                builder: (ctx, st) => ChallengeDetailScreen(
                    challengeId: st.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/steps', builder: (ctx, st) => const StepsScreen()),
          GoRoute(path: '/leaderboard', builder: (ctx, st) => const LeaderboardScreen()),
        ],
      ),
    ],
  );
});
