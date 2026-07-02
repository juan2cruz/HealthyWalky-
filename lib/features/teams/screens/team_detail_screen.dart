import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../../auth/models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/models.dart';
import '../providers/team_provider.dart';
import '../providers/team_detail_providers.dart';

class TeamDetailScreen extends ConsumerStatefulWidget {
  final String teamId;
  const TeamDetailScreen({super.key, required this.teamId});

  @override
  ConsumerState<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends ConsumerState<TeamDetailScreen> {
  void _invalidate() {
    ref.invalidate(teamByIdProvider(widget.teamId));
    ref.invalidate(teamMembersWithNamesProvider(widget.teamId));
    ref.invalidate(invitableMembersProvider(widget.teamId));
    ref.invalidate(teamsProvider);
  }

  Future<void> _approve() async {
    try {
      await supabase
          .rpc('approve_team', params: {'p_team_id': widget.teamId});
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _disqualify() async {
    final reason = await _reasonDialog('Motivo de descalificación');
    if (reason == null) return;
    try {
      await supabase.rpc('disqualify_team',
          params: {'p_team_id': widget.teamId, 'p_reason': reason});
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _abort() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abortar equipo'),
        content: const Text(
            'El equipo quedará archivado y sus miembros activos quedarán libres para unirse a otros equipos.\n\n¿Confirmas?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, abortar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase
          .rpc('abort_team', params: {'p_team_id': widget.teamId});
      _invalidate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Equipo archivado')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _expel(String teamMemberId) async {
    final reason = await _reasonDialog('Motivo de expulsión');
    if (reason == null) return;
    try {
      await supabase.rpc('expel_team_member', params: {
        'p_team_member_id': teamMemberId,
        'p_reason': reason,
      });
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _respondRequest(String teamMemberId, bool accept) async {
    try {
      await supabase.rpc('respond_join_request', params: {
        'p_team_member_id': teamMemberId,
        'p_accept': accept,
      });
      _invalidate();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<String?> _reasonDialog(String title) => showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration:
                  const InputDecoration(hintText: 'Escribe el motivo...'),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: () {
                  final t = ctrl.text.trim();
                  if (t.isNotEmpty) Navigator.pop(ctx, t);
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      );

  Future<void> _showInviteSheet(List<Profile> available) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _InviteSheet(
          teamId: widget.teamId,
          available: available,
          onDone: _invalidate,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final teamAsync = ref.watch(teamByIdProvider(widget.teamId));
    final membersAsync = ref.watch(teamMembersWithNamesProvider(widget.teamId));
    final profileAsync = ref.watch(currentProfileProvider);

    final profile = profileAsync.valueOrNull;
    final isAdmin = profile?.isAdmin ?? false;
    final currentUserId = supabase.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(teamAsync.valueOrNull?.name ?? 'Equipo'),
      ),
      body: teamAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (team) {
          if (team == null) {
            return const Center(child: Text('Equipo no encontrado'));
          }
          final isCreator = team.isUserCreator(currentUserId);

          return RefreshIndicator(
            onRefresh: () async => _invalidate(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Header ─────────────────────────────────────────────
                _TeamHeader(team: team),
                const SizedBox(height: 16),

                // ── Admin actions ───────────────────────────────────────
                if (isAdmin && team.isDraft) ...[
                  FilledButton.icon(
                    onPressed: _approve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Aprobar equipo'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (isAdmin &&
                    (team.isEnrolled || team.isActive) &&
                    !team.isDisqualified) ...[
                  OutlinedButton.icon(
                    onPressed: _disqualify,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                    icon: const Icon(Icons.gavel),
                    label: const Text('Descalificar equipo'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (isAdmin && !team.isArchived && !team.isCompleted) ...[
                  OutlinedButton.icon(
                    onPressed: _abort,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                    icon: const Icon(Icons.block_outlined),
                    label: const Text('Abortar equipo'),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Creator invite action ───────────────────────────────
                if (isCreator && team.canAddMembers) ...[
                  Consumer(builder: (ctx, r, _) {
                    final av = r.watch(invitableMembersProvider(widget.teamId));
                    return OutlinedButton.icon(
                      onPressed: av.valueOrNull?.isNotEmpty == true
                          ? () => _showInviteSheet(av.value!)
                          : null,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Invitar miembro'),
                    );
                  }),
                  const SizedBox(height: 8),
                ],

                // ── Members ─────────────────────────────────────────────
                const SizedBox(height: 8),
                Text('Miembros',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                membersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Sin miembros todavía',
                            style: TextStyle(color: Colors.grey)),
                      );
                    }
                    return Column(
                      children: entries
                          .map((entry) => _MemberTile(
                                member: entry.$1,
                                displayName: entry.$2,
                                isCreator: isCreator,
                                isAdmin: isAdmin,
                                teamIsActive: team.isActive,
                                onExpel: () => _expel(entry.$1.id),
                                onRespond: (accept) =>
                                    _respondRequest(entry.$1.id, accept),
                              ))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _TeamHeader extends StatelessWidget {
  final Team team;
  const _TeamHeader({required this.team});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(team.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(team.name,
                        style: Theme.of(context).textTheme.headlineSmall)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_statusLabel(team.status),
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
              ],
            ),
            if (team.isDisqualified &&
                team.disqualificationReason != null) ...[
              const SizedBox(height: 8),
              Text('Motivo: ${team.disqualificationReason}',
                  style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final TeamMember member;
  final String? displayName;
  final bool isCreator;
  final bool isAdmin;
  final bool teamIsActive;
  final VoidCallback onExpel;
  final void Function(bool) onRespond;

  const _MemberTile({
    required this.member,
    required this.displayName,
    required this.isCreator,
    required this.isAdmin,
    required this.teamIsActive,
    required this.onExpel,
    required this.onRespond,
  });

  Color _memberStatusColor() => switch (member.status) {
        'active' => Colors.green,
        'invited' => Colors.blue,
        'request_pending' => Colors.orange,
        'expelled' => Colors.red,
        _ => Colors.grey,
      };

  String _memberStatusLabel() => switch (member.status) {
        'active' => 'Activo',
        'invited' => 'Invitado',
        'request_pending' => 'Solicitud pendiente',
        'rejected' => 'Rechazado',
        'expelled' => 'Expulsado',
        _ => member.status,
      };

  @override
  Widget build(BuildContext context) {
    final name = displayName ?? member.userId;
    return ListTile(
      leading: CircleAvatar(
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
      ),
      title: Text(name),
      subtitle: Text(_memberStatusLabel(),
          style: TextStyle(color: _memberStatusColor(), fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCreator && member.isRequestPending) ...[
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              tooltip: 'Aceptar',
              onPressed: () => onRespond(true),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              tooltip: 'Rechazar',
              onPressed: () => onRespond(false),
            ),
          ],
          if (isAdmin && member.isActive && teamIsActive)
            IconButton(
              icon:
                  const Icon(Icons.person_remove_outlined, color: Colors.red),
              tooltip: 'Expulsar',
              onPressed: onExpel,
            ),
        ],
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  final String teamId;
  final List<Profile> available;
  final VoidCallback onDone;

  const _InviteSheet({
    required this.teamId,
    required this.available,
    required this.onDone,
  });

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final Set<String> _sending = {};

  Future<void> _invite(Profile p) async {
    setState(() => _sending.add(p.id));
    try {
      await supabase.rpc('invite_to_team',
          params: {'p_team_id': widget.teamId, 'p_user_id': p.id});
      widget.onDone();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invitación enviada a ${p.displayName}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Invitar miembro',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: widget.available.length,
              itemBuilder: (ctx, i) {
                final p = widget.available[i];
                final sending = _sending.contains(p.id);
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(p.displayName.isNotEmpty
                        ? p.displayName[0].toUpperCase()
                        : '?'),
                  ),
                  title: Text(p.displayName),
                  trailing: sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.send_outlined),
                          onPressed: () => _invite(p),
                        ),
                );
              },
            ),
          ),
        ],
      ),
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
