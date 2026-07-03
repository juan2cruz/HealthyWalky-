import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/client.dart';
import '../auth_helpers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // OAuth vuelve por deep link (healthywalky://login-callback), así que la
    // navegación no puede vivir en el onPressed: se dispara cuando GoTrue
    // emite signedIn. También cubre el login con contraseña.
    _authSub = supabase.auth.onAuthStateChange.listen((state) async {
      if (state.event != AuthChangeEvent.signedIn) return;
      final hasProfile = await currentUserHasProfile();
      if (!mounted) return;
      context.go(hasProfile ? '/dashboard' : '/onboarding');
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'healthywalky://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await supabase.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      // La navegación la hace el listener de onAuthStateChange.
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text(
                    'HealthyWalky',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Compite. Camina. Gana.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    onSubmitted: (_) => _signIn(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Iniciar sesión'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('o', style: TextStyle(color: Colors.grey[600])),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _signInWithGoogle,
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Continuar con Google'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Registrar empresa'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _showInviteDialog(context),
                    child: const Text('Tengo una invitación'),
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
