import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/client.dart';

/// Ensures there is an authenticated session for [email].
///
/// Registration is a two-step flow (signUp + RPC): if the RPC failed or the
/// app was closed in between, the auth user already exists but has no
/// profile. A plain retry of signUp would fail with "User already registered"
/// leaving that email permanently unusable. This helper falls back to
/// signing in with the provided credentials so the second step can be
/// retried. Throws [AuthException] if the email exists with a different
/// password.
Future<void> signUpOrSignIn(String email, String password) async {
  try {
    await supabase.auth.signUp(email: email, password: password);
  } on AuthException {
    // Likely "User already registered" — try to sign in below.
  }
  if (supabase.auth.currentSession == null) {
    await supabase.auth.signInWithPassword(email: email, password: password);
  }
}

/// Suggested display name from the OAuth provider (Google), if any.
/// Google populates `full_name` and `name` in user_metadata; password
/// sign-ups have neither.
String? providerDisplayName() {
  final meta = supabase.auth.currentUser?.userMetadata;
  final name = (meta?['full_name'] ?? meta?['name']) as String?;
  final trimmed = name?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Whether the current auth user already has a profile (i.e. finished
/// registration and belongs to a company).
Future<bool> currentUserHasProfile() async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return false;
  final row = await supabase
      .from('profiles')
      .select('id')
      .eq('id', uid)
      .maybeSingle();
  return row != null;
}
