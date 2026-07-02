import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/company_provider.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final usersAsync = ref.watch(companyUsersProvider);
    final isAdmin = profileAsync.valueOrNull?.isAdmin ?? false;
    final currentUserId = supabase.auth.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Miembros')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showInviteDialog(context, ref),
              icon: const Icon(Icons.person_add),
              label: const Text('Invitar'),
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
            )
          : null,
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (users) {
          if (users.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.group_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No hay miembros aún', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(companyUsersProvider),
            child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final user = users[i];
              final canKick = isAdmin && !user.isAdmin && user.id != currentUserId;
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    child: Text(
                      user.displayName[0].toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(user.displayName),
                  subtitle: Text(
                    user.isAdmin ? 'Administrador' : 'Miembro',
                    style: TextStyle(
                      color: user.isAdmin ? const Color(0xFF4CAF50) : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  trailing: canKick
                      ? IconButton(
                          icon: const Icon(Icons.person_remove_outlined,
                              color: Colors.red),
                          tooltip: 'Echar',
                          onPressed: () => _confirmKick(context, ref, user.id,
                              user.displayName),
                        )
                      : Text(
                          _formatDate(user.createdAt),
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 11),
                        ),
                ),
              );
            },
          ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _confirmKick(BuildContext context, WidgetRef ref,
      String userId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Echar a $displayName'),
        content: const Text(
            'Se eliminarán todos sus datos (pasos, membresías de equipo e inscripciones en desafíos). Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Echar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await supabase.rpc('kick_user', params: {'p_user_id': userId});
      ref.invalidate(companyUsersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$displayName ha sido eliminado')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _GenerateInviteDialog(),
    ).then((_) => ref.invalidate(companyUsersProvider));
  }
}

class _GenerateInviteDialog extends ConsumerStatefulWidget {
  const _GenerateInviteDialog();

  @override
  ConsumerState<_GenerateInviteDialog> createState() => _GenerateInviteDialogState();
}

class _GenerateInviteDialogState extends ConsumerState<_GenerateInviteDialog> {
  String? _inviteUrl;
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final token = await supabase.rpc('create_invite') as String;
      final baseUrl = Uri.base.origin;
      setState(() => _inviteUrl = '$baseUrl/invite?token=$token');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generar invitación'),
      content: _inviteUrl == null
          ? const Text('Genera un enlace de un solo uso para invitar a un miembro.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enlace generado. Compártelo con tu compañero:',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _inviteUrl!,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _inviteUrl!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enlace copiado')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        if (_inviteUrl == null)
          FilledButton(
            onPressed: _loading ? null : _generate,
            child: _loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Generar enlace'),
          ),
      ],
    );
  }
}
