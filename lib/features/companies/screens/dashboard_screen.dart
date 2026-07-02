import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/supabase/client.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/company_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final companyAsync = ref.watch(companyProvider);

    return Scaffold(
      appBar: AppBar(
        title: companyAsync.when(
          data: (c) => Text(c?.name ?? 'HealthyWalky'),
          loading: () => const Text('HealthyWalky'),
          error: (e, st) => const Text('HealthyWalky'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          if (profile == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _WelcomeCard(displayName: profile.displayName, isAdmin: profile.isAdmin),
              const SizedBox(height: 20),
              if (profile.isAdmin) ...[
                _QuickActionCard(
                  icon: Icons.group_add,
                  title: 'Gestionar usuarios',
                  subtitle: 'Invitar y ver miembros de la empresa',
                  onTap: () => context.go('/users'),
                ),
                const SizedBox(height: 12),
                _QuickActionCard(
                  icon: Icons.group_outlined,
                  title: 'Gestionar equipos',
                  subtitle: 'Crear equipos y asignar miembros',
                  onTap: () => context.go('/teams'),
                ),
                const SizedBox(height: 12),
                _QuickActionCard(
                  icon: Icons.emoji_events_outlined,
                  title: 'Gestionar desafíos',
                  subtitle: 'Crear y activar competiciones',
                  onTap: () => context.go('/challenges'),
                ),
                const SizedBox(height: 12),
                _QuickActionCard(
                  icon: Icons.directions_walk,
                  title: 'Mis pasos',
                  subtitle: 'Registra y consulta tus pasos',
                  onTap: () => context.go('/steps'),
                ),
              ] else ...[
                _QuickActionCard(
                  icon: Icons.emoji_events_outlined,
                  title: 'Ver desafíos activos',
                  subtitle: 'Únete a una competición',
                  onTap: () => context.go('/challenges'),
                ),
                const SizedBox(height: 12),
                _QuickActionCard(
                  icon: Icons.directions_walk,
                  title: 'Registrar pasos',
                  subtitle: 'Añade tus pasos de hoy',
                  onTap: () => context.go('/steps'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final String displayName;
  final bool isAdmin;

  const _WelcomeCard({required this.displayName, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hola, $displayName',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isAdmin ? 'Panel de administrador' : 'Miembro del equipo',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF4CAF50)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
