import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/client.dart';
import '../models/profile.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final session = authState.valueOrNull?.session;
  if (session == null) return null;

  final data = await supabase
      .from('profiles')
      .select()
      .eq('id', session.user.id)
      .maybeSingle();

  return data == null ? null : Profile.fromMap(data);
});
