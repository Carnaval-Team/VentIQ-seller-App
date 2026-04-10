import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import '../models/carnaval_dashboard_data.dart';

class CarnavalAiSummaryService {
  static Future<String> generateSummary(
    CarnavalDashboardData data, {
    DateTime? from,
    DateTime? to,
  }) async {
    final config = await GeminiConfig.load();
    if (!config.hasApiKey) {
      return 'No se ha configurado la API de IA. Agrega una configuración en config_asistant_model.';
    }

    final prompt = _buildPrompt(data, from: from, to: to);

    try {
      final uri = config.buildUri(endpoint: 'generateContent');
      final headers = config.buildHeaders();

      Map<String, dynamic> body;
      if (config.isMuleRouter ||
          config.url.toLowerCase().contains('chat/completions')) {
        body = config.applyAuthToBody({
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.5,
          'max_tokens': 2000,
        });
      } else {
        body = config.applyAuthToBody({
          'contents': [
            {
              'parts': [
                {'text': '$_systemPrompt\n\n$prompt'}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.5,
            'maxOutputTokens': 2000,
          },
        });
      }

      final response = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 40));

      if (response.statusCode != 200) {
        return 'Error al obtener resumen IA (${response.statusCode}). Intenta de nuevo.';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _extractText(json, config);
    } catch (e) {
      return 'Error al generar resumen IA: $e';
    }
  }

  static String _extractText(
      Map<String, dynamic> json, AssistantModelConfig config) {
    // Mule Router / OpenAI format
    if (json.containsKey('choices')) {
      final choices = json['choices'] as List;
      if (choices.isNotEmpty) {
        final msg = choices[0]['message'] as Map<String, dynamic>?;
        return (msg?['content'] ?? '').toString().trim();
      }
    }
    // Gemini format
    if (json.containsKey('candidates')) {
      final candidates = json['candidates'] as List;
      if (candidates.isNotEmpty) {
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return (parts[0]['text'] ?? '').toString().trim();
        }
      }
    }
    return 'No se pudo interpretar la respuesta del modelo.';
  }

  static const String _systemPrompt = '''
Eres un analista de negocios experto en e-commerce y apps de delivery/marketplace.
Tu tarea es analizar los datos de un dashboard de una aplicación llamada "Carnaval App"
y dar un resumen ejecutivo en español, con formato Markdown.

El resumen debe incluir las siguientes secciones con headers ##:

## Estado General
Breve resumen del estado del negocio (2-3 líneas).

## Puntos Fuertes
Qué va bien, con datos concretos.

## Áreas de Mejora
Qué se debe reforzar, con datos concretos.

## Proyecciones
Calcula y muestra proyecciones numéricas basadas en los datos:
- **Proyección mensual de ingresos**: extrapola los ingresos diarios promedio a 30 días.
- **Proyección de crecimiento de usuarios**: basada en la tasa de registro diaria promedio, proyecta a 30 y 90 días.
- **Ticket promedio proyectado**: basado en tendencia actual.
- **Tasa de conversión estimada**: ratio ordenes/usuarios y tendencia.
Si hay suficientes datos, incluye fórmulas simples (ej: "Ingreso proyectado = promedio diario × 30 = ...").

## Recomendaciones
Acciones específicas y concretas para mejorar.

## Alertas
Alertas importantes si las hay (tasas de cancelación altas, caída de usuarios, etc). Si no hay alertas, omite esta sección.

Usa formato Markdown: ## para títulos, **negritas**, - para listas, > para citas destacadas.
Sé directo, usa datos concretos del reporte. No inventes datos que no estén en el reporte.
''';

  static String _buildPrompt(CarnavalDashboardData data,
      {DateTime? from, DateTime? to}) {
    final buf = StringBuffer();
    buf.writeln('DATOS DEL DASHBOARD CARNAVAL APP:');
    buf.writeln('');
    if (from != null && to != null) {
      final days = to.difference(from).inDays + 1;
      buf.writeln(
          'PERÍODO: ${from.toIso8601String().substring(0, 10)} al ${to.toIso8601String().substring(0, 10)} ($days días)');
      buf.writeln('');
    }
    buf.writeln('USUARIOS:');
    buf.writeln('- Total registrados: ${data.totalUsuarios}');
    if (data.usuariosPorDia.isNotEmpty) {
      buf.writeln(
          '- Pico de registros: ${data.usuariosPorDia.reduce((a, b) => a.count > b.count ? a : b).count} en un día');
      buf.writeln('- Días con registros: ${data.usuariosPorDia.length}');
    }
    buf.writeln('');
    buf.writeln('ORDENES:');
    buf.writeln('- Total ordenes: ${data.totalOrdenes}');
    buf.writeln('- Completadas: ${data.ordenesCompletadas}');
    buf.writeln('- Canceladas: ${data.ordenesCanceladas}');
    if (data.totalOrdenes > 0) {
      buf.writeln(
          '- Tasa de completación: ${(data.ordenesCompletadas / data.totalOrdenes * 100).toStringAsFixed(1)}%');
      buf.writeln(
          '- Tasa de cancelación: ${(data.ordenesCanceladas / data.totalOrdenes * 100).toStringAsFixed(1)}%');
    }
    buf.writeln(
        '- Dinero recaudado (completadas): ${data.dineroRecaudado.toStringAsFixed(2)}');
    buf.writeln('');
    buf.writeln('MÉTODOS DE PAGO (por cantidad de ordenes):');
    for (final entry in data.ordenesPorMetodoPago.entries) {
      final total = entry.value.fold(0, (sum, e) => sum + e.count);
      buf.writeln('- ${entry.key}: $total ordenes');
    }
    buf.writeln('');
    buf.writeln('DINERO POR MONEDA:');
    for (final entry in data.dineroPorMoneda.entries) {
      buf.writeln('- ${entry.key}: ${entry.value.toStringAsFixed(2)}');
    }
    buf.writeln('');
    buf.writeln('PROVEEDORES:');
    buf.writeln('- Total proveedores: ${data.totalProveedores}');
    if (data.productosPorProveedor.isNotEmpty) {
      buf.writeln('- Productos por proveedor (top):');
      for (final p in data.productosPorProveedor.take(5)) {
        buf.writeln('  - ${p.name}: ${p.count} productos');
      }
    }
    buf.writeln('');
    buf.writeln('TOP 5 PRODUCTOS MÁS VENDIDOS:');
    for (final p in data.top5Productos) {
      buf.writeln('- ${p.name}: ${p.count} unidades');
    }
    buf.writeln('');
    buf.writeln('TOP 5 COMPRADORES:');
    for (final c in data.top5Compradores) {
      buf.writeln('- ${c.name}: ${c.value.toStringAsFixed(2)} gastado');
    }
    buf.writeln('');
    buf.writeln('TOP 5 PROVEEDORES QUE MÁS VENDEN:');
    for (final p in data.top5Proveedores) {
      buf.writeln('- ${p.name}: ${p.count} unidades vendidas');
    }
    return buf.toString();
  }
}
