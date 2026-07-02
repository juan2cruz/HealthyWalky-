import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/client.dart';
import '../auth_helpers.dart';

class RegisterCompanyScreen extends StatefulWidget {
  const RegisterCompanyScreen({super.key});

  @override
  State<RegisterCompanyScreen> createState() => _RegisterCompanyScreenState();
}

class _RegisterCompanyScreenState extends State<RegisterCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyNameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _slugCtrl.dispose();
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _toSlug(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      // 1. Create auth user (or recover the session of a previous
      //    half-finished registration with the same credentials)
      await signUpOrSignIn(_emailCtrl.text.trim(), _passCtrl.text);

      // Already fully registered? Go straight in.
      if (await currentUserHasProfile()) {
        await supabase.auth.refreshSession();
        if (mounted) context.go('/dashboard');
        return;
      }

      // 2. Create company + admin profile atomically
      await supabase.rpc('register_company', params: {
        'p_company_name': _companyNameCtrl.text.trim(),
        'p_company_slug': _slugCtrl.text.trim(),
        'p_display_name': _displayNameCtrl.text.trim(),
      });

      // signUp() fires authStateProvider before the profile exists, so
      // currentProfileProvider caches null. refreshSession() emits
      // tokenRefreshed AFTER the profile is created, forcing a re-read
      // (same workaround as InviteScreen).
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
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar empresa')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _companyNameCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre de la empresa'),
                      validator: (v) => (v?.isEmpty ?? true) ? 'Obligatorio' : null,
                      onChanged: (v) => _slugCtrl.text = _toSlug(v),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _slugCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Slug (URL identifier)',
                        hintText: 'mi-empresa',
                      ),
                      validator: (v) {
                        if (v?.isEmpty ?? true) return 'Obligatorio';
                        if (!RegExp(r'^[a-z0-9-]+$').hasMatch(v!)) {
                          return 'Solo letras minúsculas, números y guiones';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _displayNameCtrl,
                      decoration: const InputDecoration(labelText: 'Tu nombre completo'),
                      validator: (v) => (v?.isEmpty ?? true) ? 'Obligatorio' : null,
                    ),
                    const Divider(height: 32),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email de administrador'),
                      validator: (v) =>
                          (v?.contains('@') ?? false) ? null : 'Email inválido',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Contraseña (min. 6 caracteres)'),
                      validator: (v) =>
                          (v?.length ?? 0) >= 6 ? null : 'Mínimo 6 caracteres',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _register,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Crear empresa'),
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
