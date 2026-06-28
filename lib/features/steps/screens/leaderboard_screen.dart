import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../models/team_leaderboard_entry.dart';
import '../providers/steps_provider.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Trigger snapshot generation as soon as the screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final challenge = ref.read(activeChallengeProvider).valueOrNull;
    if (challenge == null || !challenge.isTeam) return;

    setState(() => _refreshing = true);
    try {
      await supabase
          .rpc('refresh_leaderboard', params: {'p_challenge_id': challenge.id});
    } catch (e) {
      // Non-fatal: stream may already have data from a previous refresh
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final challengeAsync = ref.watch(activeChallengeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(challengeAsync.valueOrNull?.title ?? 'Ranking'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar ranking',
              onPressed: _refresh,
            ),
        ],
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
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'El ranking de equipos no está disponible para desafíos individuales.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          final snapshotAsync =
              ref.watch(leaderboardSnapshotStreamProvider(challenge.id));

          return snapshotAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) {
              if (entries.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hourglass_empty_outlined,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('Generando ranking…',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      if (_refreshing)
                        const CircularProgressIndicator()
                      else
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Reintentar'),
                        ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) => _LeaderboardTile(entry: entries[i]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final TeamLeaderboardEntry entry;
  const _LeaderboardTile({required this.entry});

  Color get _medalColor => switch (entry.ranking) {
        1 => const Color(0xFFFFD700),
        2 => const Color(0xFFC0C0C0),
        3 => const Color(0xFFCD7F32),
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
          backgroundColor: _medalColor.withValues(alpha: isTop3 ? 1 : 0.5),
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
              _fmt(entry.avgSteps),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text('media/miembro',
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
}
