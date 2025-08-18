import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // TODO: Configurar con las credenciales reales de Supabase
  static const String url = 'YOUR_SUPABASE_URL';
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY';
  
  static SupabaseClient get client => Supabase.instance.client;
  
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }
}
