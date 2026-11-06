import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Edge Function que resuelve la URL y la autenticación del proveedor de IA.
///
/// Contrato congelado: `POST /functions/v1/ai-proxy` con
/// `{ "body": <cuerpo del proveedor>, "endpoint": "generateContent" }`,
/// `Authorization: Bearer <JWT del usuario>` y `apikey: <publishable key>`.
/// Devuelve el status y el JSON del proveedor *verbatim*.
const String _aiProxyPath = '/functions/v1/ai-proxy';
const String _aiProxyEndpoint = 'generateContent';

/// Configuración del modelo de IA del asistente.
///
/// POR QUÉ CAMBIÓ: este fichero llamaba directamente al proveedor desde el
/// cliente, lo que (1) rompía en web por CORS —el proveedor no permite el
/// origen de la app— y (2) obligaba a leer la `api_key` de
/// `config_asistant_model`, tabla que estaba sin RLS y filtraba la credencial.
///
/// Ahora el cliente solo describe *qué* proveedor/modelo usar, leyendo la vista
/// pública `config_asistant_model_publico` (sin `api_key`), y toda la resolución
/// de URL/auth ocurre en la Edge Function `ai-proxy`, donde vive la clave. La
/// credencial nunca vuelve al navegador ni se escribe en el cliente.
class AssistantModelConfig {
  static const String defaultModel = 'gemini-flash-lite-latest';
  static const String defaultUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String model;
  final String url;
  final String paramType;
  final String paramKey;

  const AssistantModelConfig({
    required this.model,
    required this.url,
    required this.paramType,
    required this.paramKey,
  });

  factory AssistantModelConfig.fromMap(Map<String, dynamic> map) {
    return AssistantModelConfig(
      model: (map['model'] ?? defaultModel).toString(),
      url: (map['url'] ?? defaultUrl).toString(),
      paramType: _normalizeParamType(map['param_type']),
      paramKey: _normalizeParamKey(map['param_key']),
    );
  }

  /// `true` cuando hay configuración de IA cargada.
  ///
  /// Antes significaba "hay `api_key` en el cliente"; hoy la clave es del proxy,
  /// así que basta con que exista la fila pública. Se conserva el nombre para no
  /// romper a los consumidores actuales (resumen IA del dashboard Carnaval).
  bool get hasApiKey => model.trim().isNotEmpty;

  /// `true` cuando el proveedor espera la credencial dentro del cuerpo
  /// (`param_type = body`).
  ///
  /// El cliente NUNCA escribe ese hueco: el proxy sobrescribe el valor con la
  /// clave real que solo él conoce.
  bool get serverInjectsKeyInBody => _normalizedParamType == 'body';

  /// URI del proxy de IA.
  ///
  /// La resolución de la URL del proveedor (sufijo `/<model>:<endpoint>`, query
  /// `?key=…`, cabeceras `Authorization`/`x-goog-api-key`) se movió al servidor
  /// junto con la clave, así que aquí ya no se compone ninguna URL de proveedor:
  /// este método devuelve siempre el endpoint del proxy.
  ///
  /// Se conservan nombre y firma; el parámetro [endpoint] se ignora porque el
  /// proxy decide el endpoint real. Ver [applyAuthToBody] para el consumidor
  /// que todavía arma su propio POST.
  Uri buildUri({required String endpoint}) {
    return Uri.parse('${SupabaseConfig.supabaseUrl}$_aiProxyPath');
  }

  /// Cabeceras del proxy: JWT del usuario + `apikey` pública.
  ///
  /// Sustituyen a las antiguas cabeceras del proveedor (que llevaban la
  /// `api_key`). Son necesarias porque `ai-proxy` se despliega con
  /// `verify_jwt = true` y además comprueba que haya un usuario real detrás del
  /// token; sin sesión no hay forma de autenticarse contra la IA.
  Map<String, String> buildHeaders({Map<String, String>? baseHeaders}) {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Sesión no iniciada: ai-proxy requiere el JWT del usuario.',
      );
    }

    return <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'apikey': SupabaseConfig.supabaseAnonKey,
      ...?baseHeaders,
    };
  }

  /// Prepara el sobre que viaja al proxy.
  ///
  /// Se conserva el nombre `applyAuthToBody` por compatibilidad: antes era el
  /// método que inyectaba la clave en el cuerpo cuando `param_type = 'body'`;
  /// ahora ese hueco lo rellena el servidor y el método solo construye el sobre.
  ///
  /// Devuelve el sobre congelado `{ body, endpoint }` con el cuerpo del
  /// proveedor **tal cual** (solo se completa `model` cuando el proveedor lo
  /// espera dentro del body, p. ej. `chat/completions`). El hueco de la clave
  /// para `param_type = 'body'` lo rellena el servidor: enviarlo desde aquí
  /// sería filtrar la credencial, que es justo lo que se está cerrando.
  ///
  /// POR QUÉ ENVUELVE EN VEZ DE DEVOLVER EL CUERPO CRUDO: el único consumidor
  /// que queda (`CarnavalAiSummaryService`) compone su propio POST con estos
  /// tres métodos y no forma parte de este cambio; devolviendo el sobre, esa
  /// ruta habla el contrato del proxy sin tocarla. Si en el futuro ese servicio
  /// pasa a usar [sendChatRequest], este método puede volver a devolver el
  /// cuerpo crudo.
  Map<String, dynamic> applyAuthToBody(Map<String, dynamic> body) {
    final providerBody = Map<String, dynamic>.from(body);
    if (_shouldIncludeModelInBody && !providerBody.containsKey('model')) {
      providerBody['model'] = model;
    }
    return buildProxyEnvelope(providerBody);
  }

  /// Sobre que espera la Edge Function: cuerpo del proveedor + endpoint.
  ///
  /// Es el primitivo explícito; [applyAuthToBody] delega aquí para no duplicar
  /// el contrato.
  Map<String, dynamic> buildProxyEnvelope(Map<String, dynamic> providerBody) {
    return <String, dynamic>{
      'body': providerBody,
      'endpoint': _aiProxyEndpoint,
    };
  }

  String get _normalizedParamType => paramType.trim().toLowerCase();
  bool get _shouldIncludeModelInBody =>
      url.toLowerCase().contains('chat/completions');
  bool get isGemini =>
      url.toLowerCase().contains('generativelanguage.googleapis.com');
  bool get isMuleRouter => url.toLowerCase().contains('mulerouter.ai');

  /// Realiza el POST al proxy con reintentos automáticos ante fallos
  /// transitorios (timeouts, 429, 5xx). Devuelve el body decodificado (Map).
  ///
  /// El proxy devuelve el status y el JSON del proveedor *verbatim*, por lo que
  /// la política de reintentos y de errores se conserva igual que cuando se
  /// llamaba al proveedor directamente: si el proveedor responde 429/5xx, el
  /// cliente lo ve y reintenta.
  ///
  /// Lanza excepción si tras [maxRetries] intentos sigue fallando.
  Future<Map<String, dynamic>> sendChatRequest({
    required Map<String, dynamic> requestBody,
    Duration timeout = const Duration(seconds: 45),
    int maxRetries = 2,
  }) async {
    final uri = buildUri(endpoint: _aiProxyEndpoint);
    final headers = buildHeaders();
    // Acepta tanto el cuerpo crudo del proveedor como un sobre ya construido
    // (p. ej. el que devuelve [applyAuthToBody]) para no envolverlo dos veces.
    final payload = jsonEncode(_ensureProxyEnvelope(requestBody));

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

  /// Envuelve [requestBody] solo si todavía no es un sobre del proxy.
  Map<String, dynamic> _ensureProxyEnvelope(Map<String, dynamic> requestBody) {
    final yaEnvuelto =
        requestBody['body'] is Map && requestBody['endpoint'] is String;
    return yaEnvuelto ? requestBody : buildProxyEnvelope(requestBody);
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

  /// Vista pública de la configuración: mismas columnas que la tabla, sin
  /// `api_key`. La tabla original quedó cerrada por RLS (solo `service_role`,
  /// que es el cliente que usa `ai-proxy`): leerla desde aquí devolvería 0
  /// filas y la IA se quedaría sin modelo.
  static const String _publicView = 'config_asistant_model_publico';

  static AssistantModelConfig? _cachedConfig;
  static DateTime? _lastFetchAt;

  static Future<AssistantModelConfig> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedConfig != null && _lastFetchAt != null) {
      final elapsed = DateTime.now().difference(_lastFetchAt!);
      if (elapsed < _cacheTtl) return _cachedConfig!;
    }

    final response = await _supabase
        .from(_publicView)
        .select('id, model, url, param_type, param_key, updated_at')
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      throw Exception(
        'No hay configuración en $_publicView. Agrega una fila activa.',
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
