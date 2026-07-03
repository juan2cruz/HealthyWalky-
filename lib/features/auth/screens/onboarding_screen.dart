import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/supabase/client.dart';

/// Landing para usuarios autenticados sin perfil (recién llegados por OAuth,
/// registros a medias o kickeados de una empresa).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _showInviteDialog(BuildContext ctx) {
    final tokenCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Código de invitación'),
        content: TextField(
          controller: tokenCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Pega aquí tu código',
            hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final token = tokenCtrl.text.trim();
              if (token.isEmpty) return;
              Navigator.pop(dialogCtx);
              ctx.push('/invite?token=$token');
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.directions_walk, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    '¡Ya casi estás!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Has iniciado sesión como $email, pero aún no perteneces '
                    'a ninguna empresa.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Registrar mi empresa'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _showInviteDialog(context),
                    child: const Text('Tengo un código de invitación'),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () async {
                      await supabase.auth.signOut();
                      if (context.mounted) context.go('/login');
                    },
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
