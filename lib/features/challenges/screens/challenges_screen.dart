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
            onRefresh: () async {
              ref.invalidate(challengesProvider);
              ref.invalidate(myEnrollmentsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: challenges.length,
              itemBuilder: (ctx, i) =>
                  _ChallengeCard(challenge: challenges[i]),
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

class _ChallengeCard extends ConsumerWidget {
  final Challenge challenge;
  const _ChallengeCard({required this.challenge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollments = ref.watch(myEnrollmentsProvider).valueOrNull ?? {};
    final isEnrolled = enrollments.contains(challenge.id);
    final canEnroll = challenge.isDraft && !isEnrolled;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/challenges/${challenge.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        _statusColor(challenge.status).withValues(alpha: 0.15),
                    child: Icon(
                      challenge.isIndividual
                          ? Icons.person_outlined
                          : Icons.groups_outlined,
                      size: 18,
                      color: _statusColor(challenge.status),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(challenge.title,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Chip(
                      label: _statusLabel(challenge.status),
                      color: _statusColor(challenge.status)),
                  const SizedBox(width: 6),
                  _Chip(
                      label: challenge.isIndividual ? 'Individual' : 'Equipos',
                      color: Colors.purple),
                  const Spacer(),
                  if (isEnrolled)
                    _Chip(label: '✓ Inscrito', color: Colors.green)
                  else if (canEnroll)
                    _Chip(label: 'Inscríbete →', color: Colors.blue),
                ],
              ),
            ],
          ),
        ),
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
      'draft' => Colors.orange,
      'active' => Colors.green,
      'completed' => Colors.grey.shade600,
      _ => Colors.grey,
    };

String _statusLabel(String status) => switch (status) {
      'draft' => 'Inscripción abierta',
      'active' => 'Activo',
      'completed' => 'Completado',
      _ => status,
    };
