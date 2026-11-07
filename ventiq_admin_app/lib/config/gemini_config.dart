import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class AssistantModelConfig {
  static const String defaultModel = 'gemini-flash-lite-latest';
  static const String defaultUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Nombre de la Edge Function que actúa de proxy hacia el proveedor de IA.
  static const String proxyFunctionName = 'ai-proxy';

  /// Endpoint del proveedor que el proxy debe invocar.
  static const String proxyEndpoint = 'generateContent';

  /// Se conserva **vacía a propósito**: el secreto ya no viaja al cliente.
  ///
  /// La clave vive únicamente en el servidor (Edge Function `ai-proxy`), que la
  /// inyecta al reenviar la petición. El campo permanece porque
  /// [buildHeaders] y [applyAuthToBody] siguen documentando el contrato del
  /// proveedor y necesitan un valor (vacío) donde antes iba la clave.
  final String apiKey;
  final String model;
  final String url;
  final String paramType;
  final String paramKey;

  const AssistantModelConfig({
    this.apiKey = '',
    required this.model,
    required this.url,
    required this.paramType,
    required this.paramKey,
  });

  factory AssistantModelConfig.fromMap(Map<String, dynamic> map) {
    // `api_key` ya no existe en el origen de datos (vista pública sin secreto),
    // así que el valor se resuelve al default vacío.
    return AssistantModelConfig(
      model: (map['model'] ?? defaultModel).toString(),
      url: (map['url'] ?? defaultUrl).toString(),
      paramType: _normalizeParamType(map['param_type']),
      paramKey: _normalizeParamKey(map['param_key']),
    );
  }

  /// Indica si la configuración del asistente está lista para usarse.
  ///
  /// Históricamente significaba "hay una api_key local". Con el proxy esa clave
  /// es server-side y el cliente no puede verla, por lo que el único
  /// requisito verificable aquí es que [GeminiConfig.load] haya traído un
  /// modelo y una URL. Se mantiene el nombre (y el `true`) para no romper a los
  /// servicios que lo usan como guarda previa al llamado de IA.
  bool get hasApiKey => model.trim().isNotEmpty && url.trim().isNotEmpty;

  /// Resuelve la URL directa del proveedor (sin proxy).
  ///
  /// Ya **no se usa** en [sendChatRequest]: el cliente dejó de hablar con el
  /// proveedor para evitar el bloqueo de CORS en web. Se conserva porque
  /// documenta exactamente el contrato que la Edge Function `ai-proxy` replica
  /// en el servidor (sufijo `/model:endpoint` solo para Gemini, query param
  /// según `param_type`). Si algún día el proxy cambia, esta es la referencia.
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

  /// Construye las cabeceras de autenticación del proveedor.
  ///
  /// Tampoco la usa [sendChatRequest] (ver [buildUri]): el proxy es quien
  /// aplica `query`/`header`/`body` en el servidor. Se mantiene como
  /// documentación del contrato y por compatibilidad con otros llamadores.
  /// Con [apiKey] vacía, el valor inyectado queda vacío.
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

  /// Añade al cuerpo los campos que algunos proveedores esperan en el propio
  /// JSON (`model` para OpenAI-compatible y la credencial cuando
  /// `param_type = 'body'`).
  ///
  /// NOTA IMPORTANTE: con `param_type = 'body'` el hueco de la credencial se
  /// envía **vacío** porque el cliente ya no tiene la clave. Eso es correcto:
  /// la Edge Function `ai-proxy` la sobrescribe con la del servidor antes de
  /// reenviar. No "arregles" ese valor vacío intentando leer la clave en el
  /// cliente; volvería a exponer el secreto y a romper el contrato del proxy.
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

  /// Realiza el POST al LLM **a través de la Edge Function `ai-proxy`**, con
  /// reintentos automáticos ante fallos transitorios (timeouts, 429, 5xx).
  /// Devuelve el body decodificado (Map).
  ///
  /// Por qué existe el proxy: el navegador ya no puede llamar al proveedor
  /// (CORS lo bloquea) y la clave no debe viajar al cliente. El proxy reenvía
  /// la petición y devuelve el status y el JSON del proveedor *verbatim*, así
  /// que la semántica de reintentos y de respuesta es la misma que tenía la
  /// llamada directa: solo cambian el destino y la autenticación.
  ///
  /// Lanza excepción si tras [maxRetries] intentos sigue fallando.
  Future<Map<String, dynamic>> sendChatRequest({
    required Map<String, dynamic> requestBody,
    Duration timeout = const Duration(seconds: 45),
    int maxRetries = 2,
  }) async {
    final uri = Uri.parse(
      '${SupabaseConfig.supabaseUrl}/functions/v1/$proxyFunctionName',
    );
    final headers = <String, String>{
      'Content-Type': 'application/json',
      // El proxy se autentica con el JWT del usuario: sin sesión no hay IA.
      'Authorization': 'Bearer ${_requireAccessToken()}',
      // `apikey` es la clave pública del proyecto (no la del proveedor): así la
      // Edge Function sabe a qué proyecto pertenece la invocación.
      'apikey': SupabaseConfig.supabaseAnonKey,
    };
    // Contrato congelado del proxy: el cuerpo específico del proveedor viaja
    // anidado y sin tocar, y `endpoint` indica la operación a invocar.
    final payload = jsonEncode({
      'body': requestBody,
      'endpoint': proxyEndpoint,
    });

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
            'IA status ${response.statusCode}: ${_describeError(response)}',
          );
          if (intento < maxRetries) {
            await Future.delayed(Duration(milliseconds: 600 * (intento + 1)));
            continue;
          }
          throw lastError;
        }

        if (response.statusCode != 200) {
          throw Exception(
            'Error en IA (${response.statusCode}): '
            '${_describeError(response)}',
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

  /// Token del usuario autenticado. Es la credencial que el proxy valida
  /// (`verify_jwt`) para autorizar la llamada en nombre del usuario, por eso se
  /// exige sesión antes de intentar nada (fallar aquí evita reintentos inútiles
  /// con un 401 garantizado).
  static String _requireAccessToken() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception(
        'No hay una sesión activa. Inicia sesión para usar el asistente de IA.',
      );
    }
    return token;
  }

  /// Normaliza el cuerpo de error para los mensajes de excepción.
  ///
  /// El proxy responde `{ "error": "..." }` en sus propios fallos (400/500/502)
  /// y, cuando el fallo viene del proveedor, deja pasar su JSON tal cual. Aquí
  /// solo se prefiere el campo `error` si existe y, en cualquier otro caso, se
  /// devuelve el texto crudo: nunca se pierde información de diagnóstico.
  static String _describeError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } on FormatException {
      // El cuerpo no era JSON: se usa el texto crudo de abajo.
    }
    return response.body;
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

    // Se lee la vista pública: la tabla `config_asistant_model` ya no es
    // legible por `anon`/`authenticated` (contenía la api_key). La vista expone
    // el mismo contrato de configuración sin el secreto.
    final response =
        await _supabase
            .from('config_asistant_model_publico')
            .select('model, url, param_type, param_key, updated_at')
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle();

    if (response == null) {
      throw Exception(
        'No hay configuración en config_asistant_model_publico. '
        'Agrega una fila activa.',
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
