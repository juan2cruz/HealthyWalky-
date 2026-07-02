import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/models.dart';

// -- Fetch: List all teams in the company --------------------------------
final teamsProvider = FutureProvider<List<Team>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return [];

  final data = await supabase
      .from('teams')
      .select()
      .eq('company_id', profile.companyId)
      .order('created_at', ascending: false);

  return (data as List)
      .map((e) => Team.fromMap(e as Map<String, dynamic>))
      .toList();
});

// -- Fetch: Single team by ID --------------------------------------------
final teamByIdProvider = FutureProvider.family<Team?, String>((ref, teamId) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return null;

  final data = await supabase
      .from('teams')
      .select()
      .eq('id', teamId)
      .eq('company_id', profile.companyId)
      .maybeSingle();

  if (data == null) return null;
  return Team.fromMap(data);
});

// -- Fetch: Team members -------------------------------------------------
final teamMembersProvider = FutureProvider.family<List<TeamMember>, String>((ref, teamId) async {
  final data = await supabase
      .from('team_members')
      .select()
      .eq('team_id', teamId)
      .order('joined_at');

  return (data as List)
      .map((e) => TeamMember.fromMap(e as Map<String, dynamic>))
      .toList();
});

// -- Action: Create team -------------------------------------------------
final createTeamProvider = FutureProvider.family<Team?, String>((ref, teamName) async {
  final result = await supabase.rpc('create_team', params: {'p_name': teamName});
  if (result == null) return null;
  return Team.fromMap(result as Map<String, dynamic>);
});

// -- Action: Invite to team ----------------------------------------------
final inviteToTeamProvider = FutureProvider.family<bool, (String, String)>((ref, params) async {
  final (teamId, userId) = params;
  await supabase.rpc('invite_to_team', params: {
    'p_team_id': teamId,
    'p_user_id': userId,
  });
  return true;
});

// -- Action: Request join team -------------------------------------------
final requestJoinTeamProvider = FutureProvider.family<bool, String>((ref, teamId) async {
  await supabase.rpc('request_join_team', params: {'p_team_id': teamId});
  return true;
});

// -- Action: Respond to invitation ---------------------------------------
final respondInvitationProvider = FutureProvider.family<bool, (String, bool)>((ref, params) async {
  final (teamMemberId, accept) = params;
  await supabase.rpc('respond_invitation', params: {
    'p_team_member_id': teamMemberId,
    'p_accept': accept,
  });
  return true;
});

// -- Action: Respond to join request (creator only) ---------------------
final respondJoinRequestProvider = FutureProvider.family<bool, (String, bool)>((ref, params) async {
  final (teamMemberId, accept) = params;
  await supabase.rpc('respond_join_request', params: {
    'p_team_member_id': teamMemberId,
    'p_accept': accept,
  });
  return true;
});

// -- Action: Expel team member (admin only) ------------------------------
final expelTeamMemberProvider = FutureProvider.family<bool, (String, String)>((ref, params) async {
  final (teamMemberId, reason) = params;
  await supabase.rpc('expel_team_member', params: {
    'p_team_member_id': teamMemberId,
    'p_reason': reason,
  });
  return true;
});

// -- Action: Disqualify team (admin only) --------------------------------
final disqualifyTeamProvider = FutureProvider.family<bool, (String, String)>((ref, params) async {
  final (teamId, reason) = params;
  await supabase.rpc('disqualify_team', params: {
    'p_team_id': teamId,
    'p_reason': reason,
  });
  return true;
});
