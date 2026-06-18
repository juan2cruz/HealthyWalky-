import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/client.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/company.dart';
import '../../auth/models/profile.dart';

final companyProvider = FutureProvider<Company?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return null;

  final data = await supabase
      .from('companies')
      .select()
      .eq('id', profile.companyId)
      .single();

  return Company.fromMap(data);
});

final companyUsersProvider = FutureProvider<List<Profile>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return [];

  final data = await supabase
      .from('profiles')
      .select()
      .eq('company_id', profile.companyId)
      .order('created_at');

  return (data as List).map((e) => Profile.fromMap(e as Map<String, dynamic>)).toList();
});
