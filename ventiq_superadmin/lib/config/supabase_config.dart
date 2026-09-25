import 'package:flutter/foundation.dart';

class SupabaseConfig {
  // Rama de debug (newa) -> se usa con `flutter run` / `flutter build apk --debug`
  static const String _debugUrl = 'https://qhprswhhfasrikhawjoz.supabase.co';
  static const String _debugAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFocHJzd2hoZmFzcmlraGF3am96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzNTg0NjksImV4cCI6MjEwNTkzNDQ2OX0.2CsGM_HCmBXNmPs7I8qTmQ9_-ouNsJquamKA593R82s';

  // Rama principal (main) -> se usa con `flutter run --release` / `flutter build apk --release`
  static const String _releaseUrl = 'https://vsieeihstajlrdvpuooh.supabase.co';
  static const String _releaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NDUzMjIwNiwiZXhwIjoyMDcwMTA4MjA2fQ.d9fKCcunP_J0tdlZF8eg0vAD-bsK3XfemavnZWT3Ro8';

  static const String supabaseUrl = kReleaseMode ? _releaseUrl : _debugUrl;
  static const String supabaseAnonKey =
      kReleaseMode ? _releaseAnonKey : _debugAnonKey;
}
