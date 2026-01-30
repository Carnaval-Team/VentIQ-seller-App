class GeminiConfig {
  static const String apiKey = "AIzaSyBLPu0IjL1C8eeh3ZPAE_924Se_atooX8o";
  static const String model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-flash-lite-latest',
  );
}
