import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/challenge_provider.dart';

// Teams created by the current user that can be enrolled (approved or enrolled status)
final _myEnrollableTeamsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return [];

  final data = await supabase
      .from('teams')
      .select('id, name, status, challenge_id')
      .eq('created_by', profile.id)
      .inFilter('status', ['approved', 'enrolled']);

  return (data as List).cast<Map<String, dynamic>>();
});

class ChallengeDetailScreen extends ConsumerStatefulWidget {
  final String challengeId;
  const ChallengeDetailScreen({super.key, required this.challengeId});

  @override
  ConsumerState<ChallengeDetailScreen> createState() =>
      _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState
    extends ConsumerState<ChallengeDetailScreen> {
  void _invalidate() {
    ref.invalidate(challengeByIdProvider(widget.challengeId));
    ref.invalidate(challengesProvider);
    ref.invalidate(myEnrollmentsProvider);
    ref.invalidate(_myEnrollableTeamsProvider);
  }

  Future<void> _activate() async {
    try {
      await supabase.rpc('activate_challenge',
          params: {'p_challenge_id': widget.challengeId});
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _enrollIndividual() async {
    try {
      await supabase.rpc('enroll_individual',
          params: {'p_challenge_id': widget.challengeId});
      _invalidate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Inscripción completada!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _enrollTeam(String teamId) async {
    try {
      await supabase
          .rpc('enroll_team', params: {'p_team_id': teamId});
      _invalidate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Equipo inscrito!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showTeamPicker(List<Map<String, dynamic>> teams) async {
    if (teams.length == 1) {
      await _enrollTeam(teams.first['id'] as String);
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Selecciona un equipo'),
        children: teams
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, t['id'] as String),
                  child: Text(t['name'] as String),
                ))
            .toList(),
      ),
    );
    if (picked != null) await _enrollTeam(picked);
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final challengeAsync = ref.watch(challengeByIdProvider(widget.challengeId));
    final enrollmentsAsync = ref.watch(myEnrollmentsProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isAdmin = profile?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(challengeAsync.valueOrNull?.title ?? 'Desafío'),
      ),
      body: challengeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (challenge) {
          if (challenge == null) {
            return const Center(child: Text('Desafío no encontrado'));
          }

          final isEnrolled =
              enrollmentsAsync.valueOrNull?.contains(challenge.id) ?? false;

          return RefreshIndicator(
            onRefresh: () async => _invalidate(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Info card ────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(challenge.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                            ),
                            _StatusChip(status: challenge.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.category_outlined,
                                size: 16, color: Colors.purple),
                            const SizedBox(width: 4),
                            Text(
                              challenge.isIndividual ? 'Individual' : 'Equipos',
                              style: const TextStyle(color: Colors.purple),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${_formatDate(challenge.startDate)} → ${_formatDate(challenge.endDate)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        if (challenge.description?.isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Text(challenge.description!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Admin: activate ──────────────────────────────────
                if (isAdmin && challenge.isDraft) ...[
                  FilledButton.icon(
                    onPressed: _activate,
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: const Text('Activar desafío'),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Individual enrollment ────────────────────────────
                if (challenge.isIndividual && challenge.isDraft) ...[
                  if (isEnrolled)
                    _EnrolledBadge()
                  else
                    FilledButton.icon(
                      onPressed: _enrollIndividual,
                      icon: const Icon(Icons.how_to_reg_outlined),
                      label: const Text('Inscribirse'),
                    ),
                  const SizedBox(height: 8),
                ],

                // ── Team enrollment (creator only) ───────────────────
                if (challenge.isTeam && challenge.isDraft) ...[
                  Consumer(builder: (ctx, r, _) {
                    final teamsAsync =
                        r.watch(_myEnrollableTeamsProvider);
                    return teamsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => const SizedBox.shrink(),
                      data: (teams) {
                        if (teams.isEmpty) return const SizedBox.shrink();
                        // Filter out teams already enrolled in this challenge
                        final available = teams
                            .where((t) =>
                                t['challenge_id'] == null ||
                                t['challenge_id'] != widget.challengeId)
                            .toList();
                        if (available.isEmpty) return _EnrolledBadge();
                        return FilledButton.icon(
                          onPressed: () => _showTeamPicker(available),
                          icon: const Icon(Icons.groups_outlined),
                          label: const Text('Inscribir mi equipo'),
                        );
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color get color => switch (status) {
        'draft' => Colors.grey,
        'active' => Colors.green,
        'completed' => Colors.grey.shade700,
        _ => Colors.grey,
      };

  String get label => switch (status) {
        'draft' => 'Borrador',
        'active' => 'Activo',
        'completed' => 'Completado',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class _EnrolledBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('Ya estás inscrito',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
