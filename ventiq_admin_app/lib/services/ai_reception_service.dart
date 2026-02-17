import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import '../models/ai_reception_models.dart';
import '../services/user_preferences_service.dart';

class AiReceptionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, List<dynamic>>> loadFullContext() async {
    final userPrefs = UserPreferencesService();
    final idTienda = await userPrefs.getIdTienda();
    if (idTienda == null)
      return {'products': [], 'motives': [], 'locations': []};

    // 1. Products
    final prodResponse = await _supabase
        .from('app_dat_producto')
        .select('id, denominacion, sku')
        .eq('id_tienda', idTienda)
        .eq('es_vendible', true)
        .limit(1000);

    final products =
        (prodResponse as List)
            .map(
              (e) => ProductAiContext(
                id: e['id'],
                denominacion: e['denominacion'],
                sku: e['sku'],
              ),
            )
            .toList();

    // 2. Motives (Reasons)
    final motResponse = await _supabase
        .from('app_nom_motivo_recepcion')
        .select('id, denominacion');
    final motives =
        (motResponse as List)
            .map(
              (e) =>
                  MotivoAiContext(id: e['id'], denominacion: e['denominacion']),
            )
            .toList();

    // 3. Locations
    final locResponse = await _supabase
        .from('app_dat_layout_almacen')
        .select('id, denominacion, app_dat_almacen(id_tienda)')
        .eq('app_dat_almacen.id_tienda', idTienda);
    final locations =
        (locResponse as List)
            .map(
              (e) => UbicacionAiContext(
                id: e['id'],
                denominacion: e['denominacion'],
              ),
            )
            .toList();

    return {'products': products, 'motives': motives, 'locations': locations};
  }

  Future<AiReceptionResult> parseReceptionText({
    required String prompt,
    required List<ProductAiContext> contextProducts,
    required List<MotivoAiContext> contextMotives,
    required List<UbicacionAiContext> contextLocations,
  }) async {
    final config = await GeminiConfig.load();
    if (!config.hasApiKey) {
      throw Exception('API Key no configurada.');
    }

    final prodJson = jsonEncode(
      contextProducts.map((e) => e.toJson()).toList(),
    );
    final motJson = jsonEncode(contextMotives.map((e) => e.toJson()).toList());
    final locJson = jsonEncode(
      contextLocations.map((e) => e.toJson()).toList(),
    );

    // Construct prompt
    final fullPrompt = _buildFullPrompt(prompt, prodJson, motJson, locJson);

    final requestBody = config.applyAuthToBody(
      config.isMuleRouter
          ? {
            'model': config.model,
            'messages': [
              {
                'role': 'system',
                'content': 'You are a smart inventory assistant.',
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
              'temperature': 0.0,
              'maxOutputTokens': 2500,
              'response_mime_type': 'application/json',
            },
          },
    );

    final uri = config.buildUri(endpoint: 'generateContent');
    final headers = config.buildHeaders();

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(requestBody))
        .timeout(const Duration(seconds: 50));

    if (response.statusCode != 200) {
      throw Exception('Error en IA (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body);
    final text = _extractResponseText(data);
    final jsonText = _extractJson(text);
    final parsed = jsonDecode(jsonText);

    return _parseResult(parsed, contextProducts);
  }

  String _buildFullPrompt(
    String userText,
    String prodJson,
    String motJson,
    String locJson,
  ) {
    return '''
Act as an inventory reception assistant.
Context:
- Products: $prodJson
- Reasons: $motJson
- Locations: $locJson

User Input: "$userText"

Task:
1. Infer the reception details: reason, location, currency (USD, CUP, MLC, EUR), observations, received_by, delivered_by.
2. Extract product items (match with Products list by fuzzy name).

Instructions:
- "reason": Match "denominacion" from Reasons list. If ambiguous, pick best fit.
- "location": Match "denominacion" from Locations list.
- "currency": Infer from text (e.g. "\$", "USD" -> "USD"; "CUP", "pesos" -> "CUP"). Default "USD".
- "received_by": Name of the person receiving (if mentioned).
- "delivered_by": Name of the person delivering (if mentioned).
- "items": List of products.
   - "qty": Quantity.
   - "price": Unit price.
   - "id": ID from Products list. If not found, null.
   - "term": Original text.

Output JSON:
{
  "reason": "Name of reason",
  "location": "Name of location",
  "currency": "USD",
  "observations": "Any extra notes...",
  "received_by": "John Doe",
  "delivered_by": "Supplier X",
  "items": [
    {"term": "50 cocas", "id": 123, "qty": 50, "price": 10},
    ...
  ]
}
''';
  }

  AiReceptionResult _parseResult(
    Map<String, dynamic> parsed,
    List<ProductAiContext> context,
  ) {
    // Parse items
    final itemsList = parsed['items'] as List? ?? [];
    final drafts =
        itemsList.map<AiReceptionDraft>((item) {
          final id = item['id'] as int?;
          final matched = context.firstWhere(
            (c) => c.id == id,
            orElse: () => ProductAiContext(id: -1, denominacion: 'Unknown'),
          );
          final isFound = id != null && matched.id != -1;

          return AiReceptionDraft(
            localId:
                DateTime.now().microsecondsSinceEpoch.toString() +
                (item['term'] ?? ''),
            originalTerm: item['term'],
            productId: isFound ? id : null,
            productName:
                isFound
                    ? matched.denominacion
                    : (item['term'] ?? 'Item desconocido'),
            productSku: isFound ? matched.sku : null,
            quantity: (item['qty'] as num?)?.toDouble() ?? 1.0,
            price: (item['price'] as num?)?.toDouble(),
            isMatched: isFound,
            unit: item['unit'],
          );
        }).toList();

    return AiReceptionResult(
      items: drafts,
      reason: parsed['reason'],
      location: parsed['location'],
      currency: parsed['currency'],
      observations: parsed['observations'],
      receivedBy: parsed['received_by'],
      deliveredBy: parsed['delivered_by'],
    );
  }

  String _extractResponseText(dynamic data) {
    if (data is Map<String, dynamic>) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty)
        return choices.first['message']['content'].toString();
      final candidates = data['candidates'];
      if (candidates is List && candidates.isNotEmpty)
        return candidates.first['content']['parts'].first['text'].toString();
    }
    throw Exception('Formato de respuesta IA desconocido');
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1) throw Exception('No JSON found');
    return text.substring(start, end + 1);
  }
}
