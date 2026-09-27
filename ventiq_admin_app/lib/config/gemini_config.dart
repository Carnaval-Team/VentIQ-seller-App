import 'dart:convert';

import 'package:http/http.dart' as http;
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
    // Anthropic (/v1/messages) y OpenAI (chat/completions) usan la URL tal cual.
    // Solo Gemini necesita el sufijo /model:endpoint.
    final resolvedUrl =
        (_shouldIncludeModelInBody || isMuleRouter || isAnthropic)
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

  /// Proveedor con formato Anthropic Messages API (system aparte + content[]).
  /// Ej: https://api.justwoker.icu/v1/messages
  bool get isAnthropic => url.toLowerCase().contains('/v1/messages');

  /// Proveedor OpenAI-compatible (chat/completions), incluye MuleRouter.
  bool get isChatCompletions => _shouldIncludeModelInBody || isMuleRouter;

  /// Construye el cuerpo del request adaptado al proveedor configurado.
  ///
  /// Unifica la lógica que antes estaba duplicada (y hardcodeada a MuleRouter/
  /// Gemini) en cada servicio de IA. Recibe el [systemPrompt] y el
  /// [userPrompt] y arma el JSON correcto para Anthropic, OpenAI o Gemini.
  Map<String, dynamic> buildChatBody({
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.3,
    int maxTokens = 1400,
    bool jsonResponse = true,
    List<Map<String, String>> history = const [],
  }) {
    if (isAnthropic) {
      final messages = <Map<String, dynamic>>[
        for (final h in history)
          {'role': h['role'], 'content': h['content'] ?? ''},
        {'role': 'user', 'content': userPrompt},
      ];
      return applyAuthToBody({
        'model': model,
        'max_tokens': maxTokens,
        'system': systemPrompt,
        'messages': messages,
      });
    }

    if (isChatCompletions) {
      return applyAuthToBody({
        'model': model,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          for (final h in history)
            {'role': h['role'], 'content': h['content'] ?? ''},
          {'role': 'user', 'content': userPrompt},
        ],
      });
    }

    // Gemini generateContent.
    return applyAuthToBody({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': '$systemPrompt\n\n$userPrompt'},
          ],
        },
      ],
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
        if (jsonResponse) 'response_mime_type': 'application/json',
      },
    });
  }

  /// Extrae el texto de la respuesta del LLM, soportando los tres formatos:
  /// Anthropic (content[] con posibles bloques 'thinking'), OpenAI (choices[])
  /// y Gemini (candidates[]).
  static String extractResponseText(dynamic data) {
    if (data is! Map) return '';

    // Anthropic: { content: [{type:'text', text:'...'}, {type:'thinking',...}] }
    final content = data['content'];
    if (content is List && content.isNotEmpty) {
      final textos = <String>[];
      for (final b in content) {
        if (b is Map && b['type'] == 'text' && b['text'] is String) {
          textos.add(b['text'] as String);
        }
      }
      if (textos.isNotEmpty) return textos.join('\n');
    }

    // OpenAI / chat.completions: { choices: [{ message: { content } }] }
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = choices.first['message'];
      if (message is Map && message['content'] != null) {
        return message['content'].toString();
      }
    }

    // Gemini: { candidates: [{ content: { parts: [{ text }] } }] }
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final cont = candidates.first['content'];
      if (cont is Map) {
        final parts = cont['parts'];
        if (parts is List && parts.isNotEmpty && parts.first['text'] != null) {
          return parts.first['text'].toString();
        }
      }
    }

    return '';
  }

  /// Realiza el POST al LLM con reintentos automáticos ante fallos transitorios
  /// (timeouts, 429, 5xx). Devuelve el body decodificado (Map).
  ///
  /// Lanza excepción si tras [maxRetries] intentos sigue fallando.
  Future<Map<String, dynamic>> sendChatRequest({
    required Map<String, dynamic> requestBody,
    Duration timeout = const Duration(seconds: 45),
    int maxRetries = 2,
  }) async {
    final uri = buildUri(endpoint: 'generateContent');
    final headers = buildHeaders();
    final payload = jsonEncode(requestBody);

    Object? lastError;
    for (var intento = 0; intento <= maxRetries; intento++) {
      try {
        final response = await http
            .post(uri, headers: headers, body: payload)
            .timeout(timeout);

        // Reintentar en errores transitorios del servidor / rate limit.
        if (response.statusCode == 429 ||
            (response.statusCode >= 500 && response.statusCode < 600)) {
          lastError = Exception(
            'IA status ${response.statusCode}: ${response.body}',
          );
          if (intento < maxRetries) {
            await Future.delayed(Duration(milliseconds: 600 * (intento + 1)));
            continue;
          }
          throw lastError;
        }

        if (response.statusCode != 200) {
          throw Exception(
            'Error en IA (${response.statusCode}): ${response.body}',
          );
        }

        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'raw': decoded};
      } catch (e) {
        lastError = e;
        // Reintentar solo ante timeouts / errores de red.
        final msg = e.toString().toLowerCase();
        final transitorio = msg.contains('timeout') ||
            msg.contains('timed out') ||
            msg.contains('socket') ||
            msg.contains('connection') ||
            msg.contains('status 5') ||
            msg.contains('status 429');
        if (intento < maxRetries && transitorio) {
          await Future.delayed(Duration(milliseconds: 600 * (intento + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw lastError ?? Exception('Error desconocido al contactar la IA.');
  }

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
