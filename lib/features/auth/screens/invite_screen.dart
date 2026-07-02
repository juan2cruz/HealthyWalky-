import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/client.dart';
import '../auth_helpers.dart';

class InviteScreen extends StatefulWidget {
  final String token;
  const InviteScreen({super.key, required this.token});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.token.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Token de invitación inválido')));
      return;
    }
    setState(() => _loading = true);

    try {
      // Create the auth user, or recover the session of a previous
      // half-finished join attempt with the same credentials.
      await signUpOrSignIn(_emailCtrl.text.trim(), _passCtrl.text);

      if (await currentUserHasProfile()) {
        // Already joined a company — the token is not needed.
        if (mounted) context.go('/dashboard');
        return;
      }

      await supabase.rpc('accept_invite', params: {
        'p_token': widget.token,
        'p_display_name': _displayNameCtrl.text.trim(),
      });

      // signUp() fires authStateProvider before the profile exists.
      // refreshSession() emits tokenRefreshed AFTER the profile is created,
      // so currentProfileProvider re-evaluates and finds the new profile.
      await supabase.auth.refreshSession();

      if (mounted) context.go('/dashboard');
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al unirse: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unirse a la empresa')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Has sido invitado a HealthyWalky',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _displayNameCtrl,
                      decoration: const InputDecoration(labelText: 'Tu nombre'),
                      validator: (v) => (v?.isEmpty ?? true) ? 'Obligatorio' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) =>
                          (v?.contains('@') ?? false) ? null : 'Email inválido',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Contraseña'),
                      validator: (v) =>
                          (v?.length ?? 0) >= 6 ? null : 'Mínimo 6 caracteres',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _join,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Unirme al equipo'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
