import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/steps_provider.dart';
import '../models/team_leaderboard_entry.dart';

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengeAsync = ref.watch(activeChallengeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          challengeAsync.valueOrNull?.title ?? 'Leaderboard',
        ),
      ),
      body: challengeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (challenge) {
          if (challenge == null) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No hay ningún desafío activo',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          if (!challenge.isTeam) {
            return const Center(
              child: Text(
                'El leaderboard de equipos no está disponible\npara desafíos individuales.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          final leaderboardAsync =
              ref.watch(teamLeaderboardProvider(challenge.id));

          return leaderboardAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) => RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(teamLeaderboardProvider(challenge.id)),
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                          'Aún no hay equipos inscritos con pasos registrados',
                          style: TextStyle(color: Colors.grey)),
                    )
                  : _LeaderboardList(entries: entries, ref: ref),
            ),
          );
        },
      ),
    );
  }
}

class _LeaderboardList extends ConsumerWidget {
  final List<TeamLeaderboardEntry> entries;
  final WidgetRef ref;
  const _LeaderboardList({required this.entries, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (ctx, i) => _LeaderboardTile(entry: entries[i], rank: i),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final TeamLeaderboardEntry entry;
  final int rank;
  const _LeaderboardTile({required this.entry, required this.rank});

  Color get _medalColor => switch (entry.ranking) {
        1 => const Color(0xFFFFD700), // gold
        2 => const Color(0xFFC0C0C0), // silver
        3 => const Color(0xFFCD7F32), // bronze
        _ => Colors.grey.shade300,
      };

  @override
  Widget build(BuildContext context) {
    final isTop3 = entry.ranking <= 3;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isTop3 ? 2 : 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _medalColor.withValues(alpha: isTop3 ? 1 : 0.4),
          child: Text(
            '${entry.ranking}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isTop3 ? Colors.white : Colors.black54,
            ),
          ),
        ),
        title: Text(
          entry.teamName,
          style: TextStyle(
              fontWeight: isTop3 ? FontWeight.bold : FontWeight.normal),
        ),
        subtitle: Text('${entry.memberCount} miembros'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatNumber(entry.avgSteps),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text('media / miembro',
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
