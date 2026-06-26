import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/challenge.dart';

// All challenges for the company (all statuses)
final challengesProvider = FutureProvider<List<Challenge>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return [];

  final data = await supabase
      .from('challenges')
      .select()
      .eq('company_id', profile.companyId)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => Challenge.fromMap(e as Map<String, dynamic>))
      .toList();
});

// Single challenge by ID
final challengeByIdProvider =
    FutureProvider.family<Challenge?, String>((ref, challengeId) async {
  final data = await supabase
      .from('challenges')
      .select()
      .eq('id', challengeId)
      .maybeSingle();

  return data == null ? null : Challenge.fromMap(data);
});

// Enrolled individuals for a given challenge (individual type)
final enrolledIndividualsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, challengeId) async {
  final data = await supabase
      .from('challenge_enrollments')
      .select('user_id, profiles(display_name)')
      .eq('challenge_id', challengeId)
      .not('user_id', 'is', null);

  return (data as List).cast<Map<String, dynamic>>();
});

// Enrolled teams for a given challenge (team type)
final enrolledTeamsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, challengeId) async {
  final data = await supabase
      .from('challenge_enrollments')
      .select('team_id, teams(name, status)')
      .eq('challenge_id', challengeId)
      .not('team_id', 'is', null);

  return (data as List).cast<Map<String, dynamic>>();
});

// IDs of challenges the current user is enrolled in
final myEnrollmentsProvider = FutureProvider<Set<String>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return {};

  final data = await supabase
      .from('challenge_enrollments')
      .select('challenge_id')
      .eq('user_id', profile.id);

  return (data as List).map((e) => e['challenge_id'] as String).toSet();
});
