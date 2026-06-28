import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../../challenges/models/challenge.dart';
import '../../challenges/providers/challenge_provider.dart';
import '../models/step_entry.dart';
import '../models/team_leaderboard_entry.dart';

// Active challenge for the company (null if none active)
final activeChallengeProvider = FutureProvider<Challenge?>((ref) async {
  final challenges = await ref.watch(challengesProvider.future);
  try {
    return challenges.firstWhere((c) => c.isActive);
  } catch (_) {
    return null;
  }
});

// Canonical step entries for the current user in a given challenge
final myStepsProvider =
    FutureProvider.family<List<StepEntry>, String>((ref, challengeId) async {
  final data = await supabase.rpc(
    'get_my_steps_in_challenge',
    params: {'p_challenge_id': challengeId},
  );
  return (data as List)
      .map((e) => StepEntry.fromMap(e as Map<String, dynamic>))
      .toList();
});

// Unresolved step conflicts for the current user, grouped by date
final myConflictsProvider =
    FutureProvider<List<StepConflict>>((ref) async {
  final data = await supabase.rpc('get_my_conflicts');

  // Group rows by step_date
  final Map<String, List<Map<String, dynamic>>> byDate = {};
  for (final row in data as List) {
    final date = row['step_date'] as String;
    byDate.putIfAbsent(date, () => []).add(row as Map<String, dynamic>);
  }

  return byDate.entries
      .map((e) => StepConflict.fromRows(e.key, e.value))
      .toList()
    ..sort((a, b) => b.stepDate.compareTo(a.stepDate));
});

// Team leaderboard for a given challenge
final teamLeaderboardProvider =
    FutureProvider.family<List<TeamLeaderboardEntry>, String>(
        (ref, challengeId) async {
  final data = await supabase.rpc(
    'get_team_leaderboard',
    params: {'p_challenge_id': challengeId},
  );
  return (data as List)
      .map((e) => TeamLeaderboardEntry.fromMap(e as Map<String, dynamic>))
      .toList();
});

// Realtime stream of leaderboard snapshots for a challenge
final leaderboardSnapshotStreamProvider =
    StreamProvider.family<List<TeamLeaderboardEntry>, String>(
        (ref, challengeId) {
  return supabase
      .from('leaderboard_snapshots')
      .stream(primaryKey: ['id'])
      .eq('challenge_id', challengeId)
      .order('rank')
      .map((rows) => rows
          .map((r) => TeamLeaderboardEntry.fromSnapshot(r))
          .toList());
});

// Total accumulated steps for the current user in a challenge
final myTotalStepsProvider =
    FutureProvider.family<int, String>((ref, challengeId) async {
  final steps = await ref.watch(myStepsProvider(challengeId).future);
  return steps.fold<int>(0, (sum, e) => sum + e.stepCount);
});
