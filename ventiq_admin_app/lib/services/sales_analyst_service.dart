import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/gemini_config.dart';
import '../models/sales.dart';
import '../models/sales_analyst_models.dart';
import 'sales_service.dart';

class SalesAnalystService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  String get initialMessage => 'What do you want to know about your sales?';

  String? validateQuestion(String question) {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return 'Escribe una pregunta sobre tus ventas.';
    }
    if (trimmed.length < 4) {
      return 'La pregunta es muy corta. Agrega más detalle.';
    }

    final lower = trimmed.toLowerCase();
    final keywords = [
      'venta',
      'ventas',
      'ingreso',
      'ingresos',
      'ganancia',
      'margen',
      'utilidad',
      'producto',
      'tpv',
      'tiempo real',
      'real time',
      'vendedor',
      'proveedor',
      'cliente',
      'ticket',
      'orden',
      'pedido',
      'factura',
      'tendencia',
      'proyeccion',
      'proyección',
      'proyecciones',
      'ranking',
      'top',
      'grafico',
      'gráfico',
      'tabla',
      'comparar',
      'crecimiento',
    ];

    final matches = keywords.any(lower.contains);
    if (!matches) {
      return 'Solo puedes preguntar cosas relacionadas con tus ventas.';
    }

    return null;
  }

  Map<String, dynamic> buildContext({
    required DateTime startDate,
    required DateTime endDate,
    required double totalSales,
    required int totalProductsSold,
    required List<ProductSalesReport> productSalesReports,
    required List<SalesVendorReport> vendorReports,
    required List<SupplierSalesReport> supplierReports,
    required String selectedTpv,
    int? selectedWarehouseId,
    String? selectedWarehouseName,
    List<ProductAnalysis> productAnalysis = const [],
  }) {
    final productReportsSorted = [...productSalesReports]
      ..sort((a, b) => b.ingresosTotales.compareTo(a.ingresosTotales));

    final topProducts =
        productReportsSorted.take(8).map(_mapProductReport).toList();

    final vendorTotals = _aggregateVendorTotals(vendorReports);
    final supplierTotals = _aggregateSupplierTotals(supplierReports);

    return {
      'meta': {
        'generated_at': DateTime.now().toIso8601String(),
        'periodo': {
          'fecha_inicio': startDate.toIso8601String(),
          'fecha_fin': endDate.toIso8601String(),
        },
        'tpv_seleccionado': selectedTpv,
        'almacen': {
          'id': selectedWarehouseId,
          'nombre': selectedWarehouseName ?? '',
        },
        'moneda': 'CUP',
      },
      'tiempo_real': {
        'total_ventas': totalSales,
        'total_productos_vendidos': totalProductsSold,
        'top_productos': topProducts,
        'productos': productSalesReports.map(_mapProductReport).toList(),
      },
      'tpvs': {
        'resumen': vendorTotals,
        'vendedores': vendorReports.map(_mapVendorReport).toList(),
      },
      'proveedores': {
        'resumen': supplierTotals,
        'proveedores': supplierReports.map(_mapSupplierReport).toList(),
      },
      'analisis_productos': productAnalysis.map(_mapProductAnalysis).toList(),
    };
  }

  Future<SalesAnalystResponse> analyze({
    required String question,
    required Map<String, dynamic> context,
  }) async {
    final validation = validateQuestion(question);
    if (validation != null) {
      throw Exception(validation);
    }

    if (GeminiConfig.apiKey.isEmpty) {
      throw Exception(
        'Configura GEMINI_API_KEY con --dart-define para usar la IA.',
      );
    }

    final prompt = _buildPrompt(question, context);

    final requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.35,
        'maxOutputTokens': 1400,
        'response_mime_type': 'application/json',
      },
    };

    final response = await http
        .post(
          Uri.parse(
            '$_baseUrl/${GeminiConfig.model}:generateContent?key=${GeminiConfig.apiKey}',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 40));

    if (response.statusCode != 200) {
      throw Exception(
        'Error en Gemini (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    final text = _extractResponseText(data);
    final jsonText = _extractJson(text);
    final parsed = jsonDecode(jsonText);

    if (parsed is Map<String, dynamic>) {
      if (parsed['error'] != null) {
        throw Exception(parsed['error'].toString());
      }
      return SalesAnalystResponse.fromJson(parsed);
    }

    throw Exception('Respuesta de IA inválida.');
  }

  String _buildPrompt(String question, Map<String, dynamic> context) {
    final contextJson = const JsonEncoder.withIndent('  ').convert(context);

    return '''Eres un analista experto en ventas para un negocio minorista.
Responde SOLO con JSON válido, sin markdown ni texto adicional.

Tu misión:
- Responder únicamente preguntas sobre ventas.
- Usar el contexto adjunto y hacer proyecciones aproximadas cuando se solicite.
- Si la pregunta no está relacionada con ventas, responde con:
  {"summary":"Solo puedo responder preguntas sobre ventas.","insights":[],"projections":[],"recommendations":[],"tables":[],"charts":[],"cards":[]}

Formato requerido:
{
  "title": "Título corto",
  "summary": "Respuesta principal en texto",
  "insights": ["Insight 1"],
  "formulas": ["Formula o cálculo"],
  "projections": ["Proyección o aproximación"],
  "recommendations": ["Recomendación"],
  "tables": [
    {
      "title": "Tabla",
      "columns": ["Col 1", "Col 2"],
      "rows": [["Dato", "Valor"]]
    }
  ],
  "charts": [
    {
      "type": "bar|line|pie",
      "title": "Título del gráfico",
      "labels": ["Etiqueta"],
      "series": [{"name": "Serie", "values": [1,2,3]}]
    }
  ],
  "cards": [
    {"title": "Métrica", "value": "123", "subtitle": "Detalle", "tone": "success|warning|danger|neutral"}
  ]
}

Contexto de ventas (JSON):
$contextJson

Pregunta del usuario:
$question''';
  }

  String _extractResponseText(dynamic data) {
    if (data is Map<String, dynamic>) {
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

  Map<String, dynamic> _mapProductReport(ProductSalesReport report) {
    return {
      'id_producto': report.idProducto,
      'producto': report.nombreProducto,
      'total_vendido': report.totalVendido,
      'ingresos_totales': report.ingresosTotales,
      'costo_total': report.costoTotalVendido,
      'ganancia_total': report.gananciaTotal,
    };
  }

  Map<String, dynamic> _mapVendorReport(SalesVendorReport report) {
    return {
      'uuid_usuario': report.uuidUsuario,
      'nombre': report.nombreCompleto,
      'total_ventas': report.totalVentas,
      'productos_vendidos': report.totalProductosVendidos,
      'dinero_general': report.totalDineroGeneral,
      'dinero_efectivo': report.totalDineroEfectivo,
      'dinero_transferencia': report.totalDineroTransferencia,
      'importe_ventas': report.totalImporteVentas,
      'egresos': report.totalEgresos,
      'primera_venta': report.primeraVenta.toIso8601String(),
      'ultima_venta': report.ultimaVenta.toIso8601String(),
      'status': report.status,
    };
  }

  Map<String, dynamic> _mapSupplierReport(SupplierSalesReport report) {
    return {
      'id_proveedor': report.idProveedor,
      'proveedor': report.nombreProveedor,
      'total_ventas': report.totalVentas,
      'total_costo': report.totalCosto,
      'total_ganancia': report.totalGanancia,
      'cantidad_productos': report.cantidadProductos,
      'margen_porcentaje': report.margenPorcentaje,
    };
  }

  Map<String, dynamic> _mapProductAnalysis(ProductAnalysis analysis) {
    return {
      'id_producto': analysis.idProducto,
      'producto': analysis.nombreProducto,
      'precio_venta_cup': analysis.precioVentaCup,
      'precio_costo_cup': analysis.precioCostoCup,
      'ganancia_cup': analysis.gananciaCup,
      'porcentaje_ganancia_cup': analysis.porcGananciaCup,
    };
  }

  Map<String, dynamic> _aggregateVendorTotals(List<SalesVendorReport> reports) {
    double totalDinero = 0;
    double totalProductos = 0;
    double totalEgresos = 0;

    for (final report in reports) {
      totalDinero += report.totalDineroGeneral;
      totalProductos += report.totalProductosVendidos;
      totalEgresos += report.totalEgresos;
    }

    return {
      'total_vendedores': reports.length,
      'total_dinero': totalDinero,
      'total_productos_vendidos': totalProductos,
      'total_egresos': totalEgresos,
    };
  }

  Map<String, dynamic> _aggregateSupplierTotals(
    List<SupplierSalesReport> reports,
  ) {
    double totalVentas = 0;
    double totalCosto = 0;
    double totalGanancia = 0;

    for (final report in reports) {
      totalVentas += report.totalVentas;
      totalCosto += report.totalCosto;
      totalGanancia += report.totalGanancia;
    }

    return {
      'total_proveedores': reports.length,
      'total_ventas': totalVentas,
      'total_costo': totalCosto,
      'total_ganancia': totalGanancia,
    };
  }
}
