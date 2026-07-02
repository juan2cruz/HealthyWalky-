import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@visibleForTesting
SupabaseClient? mockSupabaseClient;

SupabaseClient get supabase => mockSupabaseClient ?? Supabase.instance.client;
