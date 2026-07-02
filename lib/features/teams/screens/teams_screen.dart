import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/team_provider.dart';
import '../models/models.dart';

class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Equipos')),
      body: teamsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (teams) {
          if (teams.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.groups_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No hay equipos todavía',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Crea el primero con el botón +',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(teamsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: teams.length,
              itemBuilder: (ctx, i) => _TeamCard(team: teams[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/teams/new'),
        tooltip: 'Crear equipo',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final Team team;
  const _TeamCard({required this.team});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(team.status);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            team.name.isNotEmpty ? team.name[0].toUpperCase() : '?',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(team.name),
        subtitle: _StatusChip(status: team.status),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/teams/${team.id}'),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _statusLabel(status),
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

Color _statusColor(String status) => switch (status) {
      'draft' => Colors.grey,
      'approved' => Colors.blue,
      'enrolled' => Colors.orange,
      'active' => Colors.green,
      'completed' => Colors.grey.shade700,
      'disqualified' => Colors.red,
      'archived' => Colors.brown,
      _ => Colors.grey,
    };

String _statusLabel(String status) => switch (status) {
      'draft' => 'Borrador',
      'approved' => 'Aprobado',
      'enrolled' => 'Inscrito',
      'active' => 'En competición',
      'completed' => 'Completado',
      'disqualified' => 'Descalificado',
      'archived' => 'Archivado',
      _ => status,
    };
