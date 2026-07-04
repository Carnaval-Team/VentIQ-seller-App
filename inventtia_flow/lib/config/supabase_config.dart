class SupabaseConfig {
  // IMPORTANTE: usar la anon key (rol "anon"), NUNCA la service_role key.
  // La service_role key expone acceso total a la base de datos y Supabase
  // la bloquea en el cliente web (CORS), causando "permiso denegado para flow".
  // La anon key se encuentra en Supabase Dashboard > Project Settings > API.
  static const String supabaseUrl = 'https://vsieeihstajlrdvpuooh.supabase.co';

  // TODO: reemplazar por la anon key real antes de compilar release/web.
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ1MzIyMDYsImV4cCI6MjA3MDEwODIwNn0.ZQmME9zoNTd77WwblxosRv5nnyMTWN8pKkDA6UMKcO4';
}
