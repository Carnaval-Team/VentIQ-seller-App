import 'package:flutter/foundation.dart';

class SupabaseConfig {
  // IMPORTANTE: usar la anon key (rol "anon"), NUNCA la service_role key.
  // La service_role key expone acceso total a la base de datos y Supabase
  // la bloquea en el cliente web (CORS), causando "permiso denegado para flow".

  // Rama de debug (newa) -> se usa con `flutter run` / `flutter build apk --debug`
  static const String _debugUrl = 'https://qhprswhhfasrikhawjoz.supabase.co';
  static const String _debugAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFocHJzd2hoZmFzcmlraGF3am96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzNTg0NjksImV4cCI6MjEwNTkzNDQ2OX0.2CsGM_HCmBXNmPs7I8qTmQ9_-ouNsJquamKA593R82s';

  // Rama principal (main) -> se usa con `flutter run --release` / `flutter build apk --release`
  static const String _releaseUrl = 'https://vsieeihstajlrdvpuooh.supabase.co';
  static const String _releaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ1MzIyMDYsImV4cCI6MjA3MDEwODIwNn0.ZQmME9zoNTd77WwblxosRv5nnyMTWN8pKkDA6UMKcO4';

  static const String supabaseUrl = kReleaseMode ? _releaseUrl : _debugUrl;
  static const String supabaseAnonKey =
      kReleaseMode ? _releaseAnonKey : _debugAnonKey;
}
