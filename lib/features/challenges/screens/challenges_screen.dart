import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/challenge.dart';
import '../providers/challenge_provider.dart';

class ChallengesScreen extends ConsumerWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(challengesProvider);
    final isAdmin = ref.watch(currentProfileProvider).valueOrNull?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Desafíos')),
      body: challengesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (challenges) {
          if (challenges.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No hay desafíos todavía',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                  if (isAdmin) ...[
                    const SizedBox(height: 8),
                    const Text('Crea el primero con el botón +',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(challengesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: challenges.length,
              itemBuilder: (ctx, i) => _ChallengeCard(challenge: challenges[i]),
            ),
          );
        },
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => context.push('/challenges/new'),
              tooltip: 'Crear desafío',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  const _ChallengeCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _statusColor(challenge.status).withValues(alpha: 0.15),
          child: Icon(
            challenge.isIndividual ? Icons.person_outlined : Icons.groups_outlined,
            color: _statusColor(challenge.status),
          ),
        ),
        title: Text(challenge.title),
        subtitle: Row(
          children: [
            _Chip(
                label: _statusLabel(challenge.status),
                color: _statusColor(challenge.status)),
            const SizedBox(width: 6),
            _Chip(
                label: challenge.isIndividual ? 'Individual' : 'Equipos',
                color: Colors.purple),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/challenges/${challenge.id}'),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

Color _statusColor(String status) => switch (status) {
      'draft' => Colors.grey,
      'active' => Colors.green,
      'completed' => Colors.grey.shade700,
      _ => Colors.grey,
    };

String _statusLabel(String status) => switch (status) {
      'draft' => 'Borrador',
      'active' => 'Activo',
      'completed' => 'Completado',
      _ => status,
    };
