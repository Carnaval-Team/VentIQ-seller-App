import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/gemini_config.dart';
import '../models/store_ai_models.dart';

class StoreAiAssistantResponse {
  final String assistantMessage;
  final StoreAiPlan plan;
  final bool isComplete;
  final List<String> missing;

  const StoreAiAssistantResponse({
    required this.assistantMessage,
    required this.plan,
    required this.isComplete,
    required this.missing,
  });
}

class StoreAiAssistantService {
  String? validatePrompt(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return 'Escribe un mensaje para iniciar el asistente.';
    }
    if (trimmed.length < 4) {
      return 'El mensaje es muy corto. Describe un poco más.';
    }
    return null;
  }

  StoreAiPlan normalizePlan(StoreAiPlan plan) {
    final user = StoreAiUserDraft(
      fullName: plan.user.fullName,
      phone: plan.user.phone,
      email: plan.user.email,
      password:
          (plan.user.password ?? '').trim().isEmpty
              ? _generatePasswordSuggestion(plan.user.fullName)
              : plan.user.password,
    );

    final warehouses =
        plan.warehouses.isEmpty
            ? [const StoreAiWarehouseDraft(name: 'Almacén Principal')]
            : plan.warehouses;

    final primaryWarehouseName =
        (warehouses.first.name ?? 'Almacén Principal').trim().isEmpty
            ? 'Almacén Principal'
            : (warehouses.first.name ?? 'Almacén Principal').trim();

    final normalizedLayouts = <StoreAiLayoutDraft>[];
    final existingCodes = <String>{};
    for (final l in plan.layouts) {
      final warehouseName =
          (l.warehouseName ?? '').trim().isEmpty
              ? primaryWarehouseName
              : (l.warehouseName ?? '').trim();
      final code =
          (l.code ?? '').trim().isEmpty
              ? _generateLayoutCode(existingCodes)
              : (l.code ?? '').trim().toUpperCase();
      existingCodes.add(code);
      normalizedLayouts.add(
        StoreAiLayoutDraft(
          name: l.name,
          code: code,
          warehouseName: warehouseName,
          tipoLayoutId: l.tipoLayoutId ?? 1,
        ),
      );
    }

    if (normalizedLayouts.isEmpty) {
      normalizedLayouts.add(
        StoreAiLayoutDraft(
          name: 'Zona Principal',
          code: _generateLayoutCode(existingCodes),
          warehouseName: primaryWarehouseName,
          tipoLayoutId: 1,
        ),
      );
    }

    final normalizedTpvs = <StoreAiTpvDraft>[];
    for (final t in plan.tpvs) {
      final warehouseName =
          (t.warehouseName ?? '').trim().isEmpty
              ? primaryWarehouseName
              : (t.warehouseName ?? '').trim();
      normalizedTpvs.add(
        StoreAiTpvDraft(
          name: (t.name ?? '').trim().isEmpty ? 'Caja 1' : t.name,
          warehouseName: warehouseName,
        ),
      );
    }

    if (normalizedTpvs.isEmpty) {
      normalizedTpvs.add(
        StoreAiTpvDraft(name: 'Caja 1', warehouseName: primaryWarehouseName),
      );
    }

    final normalizedWarehouses =
        warehouses
            .map(
              (w) => StoreAiWarehouseDraft(
                name:
                    (w.name ?? '').trim().isEmpty
                        ? 'Almacén Principal'
                        : w.name,
                address: w.address,
                location: w.location,
              ),
            )
            .toList();

    return StoreAiPlan(
      user: user,
      storeName: plan.storeName,
      storeAddress: plan.storeAddress,
      location: plan.location,
      warehouses: normalizedWarehouses,
      layouts: normalizedLayouts,
      tpvs: normalizedTpvs,
    );
  }

  List<String> validatePlanCompleteness(StoreAiPlan plan) {
    final missing = <String>[];

    // Usuario
    if ((plan.user.fullName ?? '').trim().isEmpty)
      missing.add('user.full_name');
    if ((plan.user.phone ?? '').trim().isEmpty) missing.add('user.phone');
    if ((plan.user.email ?? '').trim().isEmpty) missing.add('user.email');
    if ((plan.user.password ?? '').trim().isEmpty) missing.add('user.password');

    // Tienda
    if ((plan.storeName ?? '').trim().isEmpty) missing.add('store.store_name');
    if ((plan.storeAddress ?? '').trim().isEmpty) {
      missing.add('store.store_address');
    }

    // Ubicación mínima
    if ((plan.location.countryCode ?? '').trim().isEmpty) {
      missing.add('location.country_code');
    }
    if ((plan.location.stateCode ?? '').trim().isEmpty) {
      missing.add('location.state_code');
    }
    if ((plan.location.stateName ?? '').trim().isEmpty) {
      missing.add('location.state_name');
    }
    if ((plan.location.city ?? '').trim().isEmpty) missing.add('location.city');

    // Config obligatoria del stepper
    if (plan.warehouses.isEmpty) missing.add('config.warehouses[>=1]');
    if (plan.layouts.isEmpty) missing.add('config.layouts[>=1]');
    if (plan.tpvs.isEmpty) missing.add('config.tpvs[>=1]');

    // Cada almacén debe tener al menos un layout
    if (plan.warehouses.isNotEmpty) {
      for (final w in plan.warehouses) {
        final warehouseName = (w.name ?? '').trim();
        if (warehouseName.isEmpty) continue;
        final hasLayout = plan.layouts.any(
          (l) => (l.warehouseName ?? '').trim() == warehouseName,
        );
        if (!hasLayout) {
          missing.add('config.layouts[warehouse=${warehouseName}]');
        }
      }
    }

    // Campos mínimos en warehouses/layouts/tpvs
    for (final w in plan.warehouses) {
      if ((w.name ?? '').trim().isEmpty) missing.add('warehouse.name');
    }
    for (final l in plan.layouts) {
      if ((l.name ?? '').trim().isEmpty) missing.add('layout.name');
      if ((l.code ?? '').trim().isEmpty) missing.add('layout.code');
      if ((l.warehouseName ?? '').trim().isEmpty) {
        missing.add('layout.warehouse_name');
      }
      if (l.tipoLayoutId == null) missing.add('layout.tipo_layout_id');
    }
    for (final t in plan.tpvs) {
      if ((t.name ?? '').trim().isEmpty) missing.add('tpv.name');
      if ((t.warehouseName ?? '').trim().isEmpty)
        missing.add('tpv.warehouse_name');
    }

    return missing.toSet().toList();
  }

  Future<StoreAiAssistantResponse> sendMessage({
    required List<Map<String, String>> conversation,
    required String userMessage,
    StoreAiPlan? currentPlan,
    required List<Map<String, dynamic>> layoutTypes,
  }) async {
    final validationError = validatePrompt(userMessage);
    if (validationError != null) {
      throw Exception(validationError);
    }

    final config = await GeminiConfig.load();
    if (!config.hasApiKey) {
      throw Exception(
        'Configura api_key en la tabla config_asistant_model para usar la IA.',
      );
    }

    final safePlan = currentPlan ?? StoreAiPlan.empty();
    final missingBefore = validatePlanCompleteness(safePlan);

    final fullPrompt = _buildAssistantPrompt(
      conversation: conversation,
      userMessage: userMessage,
      currentPlan: safePlan,
      missingKeys: missingBefore,
      layoutTypes: layoutTypes,
    );

    final requestBody = config.applyAuthToBody(
      config.isMuleRouter
          ? {
            'model': config.model,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are a store setup assistant. Only discuss data required to create a store.',
              },
              {'role': 'user', 'content': fullPrompt},
            ],
          }
          : {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': fullPrompt},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.2,
              'maxOutputTokens': 1600,
              'response_mime_type': 'application/json',
            },
          },
    );

    final uri = config.buildUri(endpoint: 'generateContent');
    final headers = config.buildHeaders();

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(requestBody))
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception('Error en IA (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body);
    final text = _extractResponseText(data);
    final jsonText = _extractJson(text);
    final parsed = jsonDecode(jsonText);

    if (parsed is Map<String, dynamic> && parsed['error'] != null) {
      throw Exception(parsed['error'].toString());
    }

    if (parsed is! Map<String, dynamic>) {
      throw Exception('Respuesta de IA inválida.');
    }

    final assistantMessage = (parsed['assistant_message'] ?? '').toString();
    final planRaw = parsed['plan'];
    final nextPlan =
        planRaw is Map<String, dynamic>
            ? StoreAiPlan.fromJson(planRaw)
            : safePlan;

    final normalizedPlan = normalizePlan(nextPlan);

    final missingAfter = validatePlanCompleteness(normalizedPlan);

    return StoreAiAssistantResponse(
      assistantMessage:
          assistantMessage.isEmpty
              ? 'Necesito algunos datos para continuar.'
              : assistantMessage,
      plan: normalizedPlan,
      isComplete: missingAfter.isEmpty,
      missing: missingAfter,
    );
  }

  String _buildAssistantPrompt({
    required List<Map<String, String>> conversation,
    required String userMessage,
    required StoreAiPlan currentPlan,
    required List<String> missingKeys,
    required List<Map<String, dynamic>> layoutTypes,
  }) {
    final convoJson = const JsonEncoder.withIndent('  ').convert(conversation);
    final planJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(currentPlan.toJson());
    final missingJson = const JsonEncoder.withIndent('  ').convert(missingKeys);
    final layoutTypesJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(layoutTypes);

    return '''Eres un asistente de configuración para crear una tienda en VentIQ Admin.
Tu objetivo es completar un plan con TODOS los datos necesarios para crear una tienda y su estructura inicial.

RESTRICCIÓN:
- Solo habla de datos necesarios para crear la tienda: usuario, tienda, ubicación, almacenes, zonas/layouts, tpvs.
- Si el usuario pregunta algo fuera de esto, redirige: "Para crear la tienda necesito...".

AUTOCOMPLETADO:
- Si faltan campos que se pueden generar, genéralos sin preguntarle al usuario.
- Genera automáticamente:
  - "layouts[].code" (código/sku de zona) con un formato corto y único.
  - Nombres por defecto cuando falten: almacén "Almacén Principal", zona "Zona Principal", tpv "Caja 1".
  - Asigna "warehouse_name" en layouts/tpvs al primer almacén si el usuario no lo indicó.
  - Sugiere una contraseña si el usuario no la definió.
- NO le preguntes al usuario por códigos internos (layout.code, state_code, country_code) si puede inferirse.

DATOS REQUERIDOS (debes conseguirlos todos):
- user.full_name, user.phone, user.email, user.password
- store.store_name, store.store_address
- location.country_code (ISO2), location.country_name (nombre), location.state_code (adminCode1), location.state_name, location.city
- config.warehouses (>=1)
- config.layouts (>=1)
- config.tpvs (>=1)
- Regla: cada almacén debe tener al menos una zona/layout asociada.

Tipos de layout disponibles (usa SOLO estos ids):
$layoutTypesJson

Estado actual del plan (JSON):
$planJson

Campos faltantes según validación:
$missingJson

Historial de conversación (JSON):
$convoJson

Mensaje actual del usuario:
"$userMessage"

Tarea:
1) Actualiza el plan agregando/ajustando datos si el usuario los dio.
2) Si faltan datos, haz UNA pregunta clara a la vez (o máximo 2 si están muy relacionadas).
3) Si ya está completo, indica que ya se puede generar la vista previa.

SALIDA: responde SOLO con JSON válido (sin markdown, sin texto adicional) con este formato exacto:
{
  "assistant_message": "texto corto en español",
  "plan": {
    "user": {"full_name": "", "phone": "", "email": "", "password": ""},
    "store_name": "",
    "store_address": "",
    "location": {"country_code": "", "country_name": "", "state_code": "", "state_name": "", "city": "", "latitude": null, "longitude": null},
    "warehouses": [{"name": "", "address": "", "location": ""}],
    "layouts": [{"name": "", "code": "ZON-001", "warehouse_name": "", "tipo_layout_id": 1}],
    "tpvs": [{"name": "", "warehouse_name": ""}]
  }
}
''';
  }

  String _generateLayoutCode(Set<String> existing) {
    var i = 1;
    while (true) {
      final code = 'ZON-${i.toString().padLeft(3, '0')}';
      if (!existing.contains(code)) return code;
      i++;
    }
  }

  String _generatePasswordSuggestion(String? fullName) {
    final base = (fullName ?? '').trim().split(' ').where((e) => e.isNotEmpty);
    final first = base.isNotEmpty ? base.first.toLowerCase() : 'admin';
    final year = DateTime.now().year.toString();
    return '${first}#${year}!';
  }

  String _extractResponseText(dynamic data) {
    if (data is Map<String, dynamic>) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = choices.first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content != null) {
            return content.toString();
          }
        }
      }

      final candidates = data['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final content = candidates.first['content'];
        if (content is Map<String, dynamic>) {
          final parts = content['parts'];
          if (parts is List && parts.isNotEmpty) {
            final text = parts.first['text'];
            if (text != null) {
              return text.toString();
            }
          }
        }
      }
    }

    throw Exception('Respuesta de IA vacía o inválida.');
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');

    if (start == -1 || end == -1 || end <= start) {
      throw Exception('La IA no devolvió JSON válido.');
    }

    return text.substring(start, end + 1);
  }
}
