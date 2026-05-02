import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/gemini_config.dart';

class StrategicRecommendation {
  final String titulo;
  final String descripcion;
  final String prioridad; // 'alta' | 'media' | 'baja'
  final String categoria; // 'inventario' | 'ventas' | 'precios' | 'mix' | 'operaciones' | 'crecimiento'
  final String impacto; // 'alto' | 'medio' | 'bajo'
  final List<String> acciones;
  final List<String> productosRelacionados;
  final String? metricaClave;

  const StrategicRecommendation({
    required this.titulo,
    required this.descripcion,
    required this.prioridad,
    required this.categoria,
    required this.impacto,
    required this.acciones,
    required this.productosRelacionados,
    this.metricaClave,
  });

  factory StrategicRecommendation.fromJson(Map<String, dynamic> json) {
    return StrategicRecommendation(
      titulo: (json['titulo'] ?? '').toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      prioridad: _normalize(json['prioridad'], const ['alta', 'media', 'baja'], 'media'),
      categoria: _normalize(
        json['categoria'],
        const ['inventario', 'ventas', 'precios', 'mix', 'operaciones', 'crecimiento'],
        'operaciones',
      ),
      impacto: _normalize(json['impacto'], const ['alto', 'medio', 'bajo'], 'medio'),
      acciones: (json['acciones'] is List)
          ? List<String>.from((json['acciones'] as List).map((e) => e.toString()))
          : <String>[],
      productosRelacionados: (json['productos_relacionados'] is List)
          ? List<String>.from(
              (json['productos_relacionados'] as List).map((e) => e.toString()),
            )
          : <String>[],
      metricaClave: json['metrica_clave']?.toString(),
    );
  }

  static String _normalize(dynamic value, List<String> allowed, String fallback) {
    final v = (value ?? '').toString().trim().toLowerCase();
    return allowed.contains(v) ? v : fallback;
  }
}

class StrategicAnalysisResult {
  final String resumenEjecutivo;
  final List<StrategicRecommendation> recomendaciones;
  final List<String> insights;
  final DateTime generatedAt;

  const StrategicAnalysisResult({
    required this.resumenEjecutivo,
    required this.recomendaciones,
    required this.insights,
    required this.generatedAt,
  });
}

class AiStrategicRecommendationsService {
  Future<StrategicAnalysisResult> analyze({
    required Map<String, dynamic> kpis,
    required List<Map<String, dynamic>> categoryDistribution,
    required Map<String, dynamic> abcAnalysis,
    required List<Map<String, dynamic>> topProducts,
    required List<Map<String, dynamic>> alerts,
    required Map<String, dynamic> bcgAnalysis,
  }) async {
    final config = await GeminiConfig.load();
    if (!config.hasApiKey) {
      throw Exception(
        'Configura api_key en la tabla config_asistant_model para usar la IA.',
      );
    }

    final prompt = _buildPrompt(
      kpis: kpis,
      categoryDistribution: categoryDistribution,
      abcAnalysis: abcAnalysis,
      topProducts: topProducts,
      alerts: alerts,
      bcgAnalysis: bcgAnalysis,
    );

    final requestBody = config.applyAuthToBody(
      config.isMuleRouter
          ? {
              'model': config.model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Eres un analista estratégico de retail. Devuelves solo JSON válido con recomendaciones accionables basadas en los datos del dashboard.',
                },
                {'role': 'user', 'content': prompt},
              ],
            }
          : {
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.3,
                'maxOutputTokens': 2000,
                'response_mime_type': 'application/json',
              },
            },
    );

    final uri = config.buildUri(endpoint: 'generateContent');
    final headers = config.buildHeaders();

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(requestBody))
        .timeout(const Duration(seconds: 120));

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

    final recsRaw = parsed['recomendaciones'];
    final recs = <StrategicRecommendation>[];
    if (recsRaw is List) {
      for (final r in recsRaw) {
        if (r is Map<String, dynamic>) {
          recs.add(StrategicRecommendation.fromJson(r));
        }
      }
    }

    final insightsRaw = parsed['insights'];
    final insights = <String>[];
    if (insightsRaw is List) {
      for (final i in insightsRaw) {
        final s = i.toString().trim();
        if (s.isNotEmpty) insights.add(s);
      }
    }

    return StrategicAnalysisResult(
      resumenEjecutivo: (parsed['resumen_ejecutivo'] ?? '').toString(),
      recomendaciones: recs,
      insights: insights,
      generatedAt: DateTime.now(),
    );
  }

  String _buildPrompt({
    required Map<String, dynamic> kpis,
    required List<Map<String, dynamic>> categoryDistribution,
    required Map<String, dynamic> abcAnalysis,
    required List<Map<String, dynamic>> topProducts,
    required List<Map<String, dynamic>> alerts,
    required Map<String, dynamic> bcgAnalysis,
  }) {
    final compactTop = topProducts
        .take(10)
        .map((p) => {
              'denominacion': p['denominacion'],
              'sku': p['sku'],
              'movimientos': p['movimientos'],
              'stockActual': p['stockActual'],
            })
        .toList();

    final compactAlerts = alerts
        .take(15)
        .map((a) => {
              'denominacion': a['denominacion'],
              'tipo': a['tipoAlerta'],
              'prioridad': a['prioridad'],
              'descripcion': a['descripcionAlerta'],
            })
        .toList();

    final compactBcgResumen = bcgAnalysis['resumen'] ?? {};
    final compactBcgProductos = (bcgAnalysis['productos'] is List)
        ? (bcgAnalysis['productos'] as List)
            .take(15)
            .map((p) => p is Map
                ? {
                    'denominacion': p['denominacion'],
                    'categoria_bcg': p['categoria_bcg'] ?? p['cuadrante'],
                    'cuota_mercado': p['cuota_mercado'],
                    'crecimiento': p['crecimiento'],
                  }
                : {})
            .toList()
        : <Map>[];

    final dataset = {
      'kpis': kpis,
      'distribucion_categorias': categoryDistribution,
      'analisis_abc': abcAnalysis,
      'top_productos': compactTop,
      'alertas': compactAlerts,
      'bcg': {
        'resumen': compactBcgResumen,
        'productos': compactBcgProductos,
      },
    };

    final datasetJson = jsonEncode(dataset);

    return '''
Eres un analista estratégico de retail experto en gestión de inventario, mix de productos, precios y operaciones.

Analiza los datos reales del dashboard de productos de la tienda (en JSON) y genera recomendaciones estratégicas accionables que ayuden al cliente a tomar mejores decisiones.

DATOS DEL DASHBOARD:
$datasetJson

INSTRUCCIONES:
1. Identifica patrones, riesgos y oportunidades a partir de los datos.
2. Devuelve entre 4 y 8 recomendaciones priorizadas (alta/media/baja).
3. Cada recomendación debe tener: título corto, descripción específica con números/porcentajes/nombres reales del dataset, categoría, impacto, acciones concretas (verbos en imperativo) y productos relacionados si aplica.
4. Genera además un resumen ejecutivo (2-3 frases) y 3-5 insights clave (frases cortas con datos).
5. NO inventes productos ni métricas que no estén en los datos. Si un dato falta, omítelo en lugar de inventarlo.
6. Idioma: español.

Devuelve SOLO un JSON válido con esta estructura exacta (sin texto adicional, sin markdown):
{
  "resumen_ejecutivo": "string",
  "insights": ["string", "string", ...],
  "recomendaciones": [
    {
      "titulo": "string",
      "descripcion": "string",
      "prioridad": "alta|media|baja",
      "categoria": "inventario|ventas|precios|mix|operaciones|crecimiento",
      "impacto": "alto|medio|bajo",
      "acciones": ["string", "string"],
      "productos_relacionados": ["string"],
      "metrica_clave": "string"
    }
  ]
}
''';
  }

  String _extractResponseText(dynamic data) {
    if (data is! Map<String, dynamic>) return '';

    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final first = candidates.first;
      if (first is Map<String, dynamic>) {
        final content = first['content'];
        if (content is Map<String, dynamic>) {
          final parts = content['parts'];
          if (parts is List && parts.isNotEmpty) {
            final part = parts.first;
            if (part is Map<String, dynamic>) {
              final text = part['text'];
              if (text is String) return text;
            }
          }
        }
      }
    }

    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content is String) return content;
        }
        final text = first['text'];
        if (text is String) return text;
      }
    }

    return '';
  }

  String _extractJson(String text) {
    if (text.isEmpty) {
      throw Exception('La IA no devolvió contenido.');
    }
    final trimmed = text.trim();

    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final match = fence.firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return trimmed.substring(start, end + 1);
    }
    return trimmed;
  }
}
