import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../../auth/models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/models.dart';

// Team members joined with their profile display name.
// Used by TeamDetailScreen to show names alongside status.
final teamMembersWithNamesProvider =
    FutureProvider.family<List<(TeamMember, String?)>, String>(
        (ref, teamId) async {
  final data = await supabase
      .from('team_members')
      .select('*, profiles(display_name)')
      .eq('team_id', teamId)
      .order('joined_at');

  return (data as List).map((e) {
    final map = e as Map<String, dynamic>;
    final member = TeamMember.fromMap(map);
    final name =
        (map['profiles'] as Map<String, dynamic>?)?['display_name'] as String?;
    return (member, name);
  }).toList();
});

// Company members invitable to a given team (for invite bottom sheet).
// Only memberships that still block an invite exclude a user; people whose
// invitation/request was rejected or who were expelled can be re-invited.
final invitableMembersProvider =
    FutureProvider.family<List<Profile>, String>((ref, teamId) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return [];

  final existing = await supabase
      .from('team_members')
      .select('user_id')
      .eq('team_id', teamId)
      .inFilter('status', ['invited', 'request_pending', 'active']);

  final existingIds =
      (existing as List).map((e) => e['user_id'] as String).toSet();

  final all = await supabase
      .from('profiles')
      .select()
      .eq('company_id', profile.companyId)
      .order('display_name');

  return (all as List)
      .map((e) => Profile.fromMap(e as Map<String, dynamic>))
      .where((p) => !existingIds.contains(p.id))
      .toList();
});
