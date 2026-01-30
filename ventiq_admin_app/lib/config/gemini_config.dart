import 'package:supabase_flutter/supabase_flutter.dart';

class AssistantModelConfig {
  static const String defaultModel = 'gemini-flash-lite-latest';
  static const String defaultUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String apiKey;
  final String model;
  final String url;
  final String paramType;
  final String paramKey;

  const AssistantModelConfig({
    required this.apiKey,
    required this.model,
    required this.url,
    required this.paramType,
    required this.paramKey,
  });

  factory AssistantModelConfig.fromMap(Map<String, dynamic> map) {
    return AssistantModelConfig(
      apiKey: (map['api_key'] ?? '').toString(),
      model: (map['model'] ?? defaultModel).toString(),
      url: (map['url'] ?? defaultUrl).toString(),
      paramType: _normalizeParamType(map['param_type']),
      paramKey: _normalizeParamKey(map['param_key']),
    );
  }

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  Uri buildUri({required String endpoint}) {
    final cleanedUrl =
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final resolvedUrl =
        (_shouldIncludeModelInBody || isMuleRouter)
            ? cleanedUrl
            : '$cleanedUrl/$model:$endpoint';
    final baseUri = Uri.parse(resolvedUrl);

    if (_normalizedParamType == 'query') {
      final paramName = _resolveParamName();
      final paramValue = _resolveParamValue();
      return baseUri.replace(
        queryParameters: {...baseUri.queryParameters, paramName: paramValue},
      );
    }

    return baseUri;
  }

  Map<String, String> buildHeaders({Map<String, String>? baseHeaders}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...?baseHeaders,
    };

    if (_normalizedParamType == 'header') {
      if (_normalizedParamKey == 'key') {
        headers[_resolveParamName()] = apiKey;
      } else {
        headers['Authorization'] = _resolveParamValue();
      }
    }

    return headers;
  }

  Map<String, dynamic> applyAuthToBody(Map<String, dynamic> body) {
    final normalizedBody = Map<String, dynamic>.from(body);

    if (_shouldIncludeModelInBody && !normalizedBody.containsKey('model')) {
      normalizedBody['model'] = model;
    }

    if (_normalizedParamType != 'body') {
      return normalizedBody;
    }

    final paramName = _resolveParamName();
    final paramValue = _resolveParamValue();
    return {...normalizedBody, paramName: paramValue};
  }

  String get _normalizedParamType => paramType.trim().toLowerCase();
  String get _normalizedParamKey => paramKey.trim().toLowerCase();
  bool get _shouldIncludeModelInBody =>
      url.toLowerCase().contains('chat/completions');
  bool get isGemini =>
      url.toLowerCase().contains('generativelanguage.googleapis.com');
  bool get isMuleRouter => url.toLowerCase().contains('mulerouter.ai');

  String _resolveParamName() {
    if (_normalizedParamKey == 'key') {
      return 'key';
    }
    return 'Authorization';
  }

  String _resolveParamValue() {
    if (_normalizedParamKey == 'bearer') {
      return 'Bearer $apiKey';
    }
    if (_normalizedParamKey == 'basic') {
      return 'Basic $apiKey';
    }
    return apiKey;
  }

  static String _normalizeParamType(dynamic value) {
    final normalized = (value ?? 'query').toString().trim().toLowerCase();
    if (!['query', 'body', 'header'].contains(normalized)) {
      throw Exception('param_type inválido: $value');
    }
    return normalized;
  }

  static String _normalizeParamKey(dynamic value) {
    final normalized = (value ?? 'key').toString().trim().toLowerCase();
    if (!['key', 'bearer', 'basic'].contains(normalized)) {
      throw Exception('param_key inválido: $value');
    }
    return normalized;
  }
}

class GeminiConfig {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const Duration _cacheTtl = Duration(minutes: 10);
  static AssistantModelConfig? _cachedConfig;
  static DateTime? _lastFetchAt;

  static Future<AssistantModelConfig> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedConfig != null && _lastFetchAt != null) {
      final elapsed = DateTime.now().difference(_lastFetchAt!);
      if (elapsed < _cacheTtl) {
        return _cachedConfig!;
      }
    }

    final response =
        await _supabase
            .from('config_asistant_model')
            .select('api_key, model, url, param_type, param_key, updated_at')
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();

    if (response == null) {
      throw Exception(
        'No hay configuración en config_asistant_model. Agrega una fila activa.',
      );
    }

    final config = AssistantModelConfig.fromMap(response);
    _cachedConfig = config;
    _lastFetchAt = DateTime.now();
    return config;
  }

  static void clearCache() {
    _cachedConfig = null;
    _lastFetchAt = null;
  }
}
