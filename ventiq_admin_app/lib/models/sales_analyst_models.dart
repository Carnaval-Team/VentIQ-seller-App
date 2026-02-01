enum SalesAnalystRole { user, assistant }

class SalesAnalystMessage {
  final SalesAnalystRole role;
  final String text;
  final SalesAnalystResponse? response;
  final DateTime timestamp;
  final bool isError;

  const SalesAnalystMessage({
    required this.role,
    required this.text,
    required this.timestamp,
    this.response,
    this.isError = false,
  });

  factory SalesAnalystMessage.user(String text) {
    return SalesAnalystMessage(
      role: SalesAnalystRole.user,
      text: text,
      timestamp: DateTime.now(),
    );
  }

  factory SalesAnalystMessage.assistant({
    required String text,
    SalesAnalystResponse? response,
    bool isError = false,
  }) {
    return SalesAnalystMessage(
      role: SalesAnalystRole.assistant,
      text: text,
      response: response,
      isError: isError,
      timestamp: DateTime.now(),
    );
  }

  factory SalesAnalystMessage.error(String text) {
    return SalesAnalystMessage.assistant(text: text, isError: true);
  }

  bool get isUser => role == SalesAnalystRole.user;
}

class SalesAnalystResponse {
  final String summary;
  final String title;
  final List<String> insights;
  final List<String> formulas;
  final List<String> projections;
  final List<String> recommendations;
  final List<SalesAnalystTable> tables;
  final List<SalesAnalystChart> charts;
  final List<SalesAnalystCard> cards;
  final Map<String, dynamic> raw;

  const SalesAnalystResponse({
    required this.summary,
    required this.title,
    required this.insights,
    required this.formulas,
    required this.projections,
    required this.recommendations,
    required this.tables,
    required this.charts,
    required this.cards,
    required this.raw,
  });

  factory SalesAnalystResponse.fromJson(Map<String, dynamic> json) {
    final insights = _parseStringList(json['insights'] ?? json['hallazgos']);
    final formulas = _parseStringList(json['formulas'] ?? json['fórmulas']);
    final projections = _parseStringList(
      json['projections'] ?? json['proyecciones'],
    );
    final recommendations = _parseStringList(
      json['recommendations'] ?? json['recomendaciones'],
    );

    final tables = _parseTables(json['tables']);
    final charts = _parseCharts(json['charts']);
    final cards = _parseCards(json['cards']);

    final summary =
        (json['summary'] ?? json['resumen'] ?? json['respuesta'] ?? '')
            .toString();
    final title =
        (json['title'] ?? json['titulo'] ?? 'Analista de Ventas').toString();

    return SalesAnalystResponse(
      summary: summary,
      title: title,
      insights: insights,
      formulas: formulas,
      projections: projections,
      recommendations: recommendations,
      tables: tables,
      charts: charts,
      cards: cards,
      raw: json,
    );
  }

  bool get hasStructuredContent =>
      insights.isNotEmpty ||
      formulas.isNotEmpty ||
      projections.isNotEmpty ||
      recommendations.isNotEmpty ||
      tables.isNotEmpty ||
      charts.isNotEmpty ||
      cards.isNotEmpty;

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }

  static List<SalesAnalystTable> _parseTables(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map(SalesAnalystTable.fromJson)
          .toList();
    }
    return const [];
  }

  static List<SalesAnalystChart> _parseCharts(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map(SalesAnalystChart.fromJson)
          .toList();
    }
    return const [];
  }

  static List<SalesAnalystCard> _parseCards(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map(SalesAnalystCard.fromJson)
          .toList();
    }
    return const [];
  }
}

class SalesAnalystTable {
  final String title;
  final List<String> columns;
  final List<List<String>> rows;

  const SalesAnalystTable({
    required this.title,
    required this.columns,
    required this.rows,
  });

  factory SalesAnalystTable.fromJson(Map<String, dynamic> json) {
    final columns =
        (json['columns'] as List?)?.map((item) => item.toString()).toList() ??
        const [];
    final rows =
        (json['rows'] as List?)
            ?.map(
              (row) =>
                  (row as List?)?.map((cell) => cell.toString()).toList() ??
                  const <String>[],
            )
            .toList() ??
        const [];

    return SalesAnalystTable(
      title: json['title']?.toString() ?? 'Tabla',
      columns: columns,
      rows: rows,
    );
  }
}

class SalesAnalystChart {
  final String type;
  final String title;
  final List<String> labels;
  final List<SalesAnalystSeries> series;

  const SalesAnalystChart({
    required this.type,
    required this.title,
    required this.labels,
    required this.series,
  });

  factory SalesAnalystChart.fromJson(Map<String, dynamic> json) {
    final labels =
        (json['labels'] as List?)?.map((item) => item.toString()).toList() ??
        const [];
    final series =
        (json['series'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(SalesAnalystSeries.fromJson)
            .toList() ??
        const [];

    return SalesAnalystChart(
      type: json['type']?.toString() ?? 'bar',
      title: json['title']?.toString() ?? 'Gráfico',
      labels: labels,
      series: series,
    );
  }
}

class SalesAnalystSeries {
  final String name;
  final List<double> values;

  const SalesAnalystSeries({required this.name, required this.values});

  factory SalesAnalystSeries.fromJson(Map<String, dynamic> json) {
    final values =
        (json['values'] as List?)
            ?.map((value) => double.tryParse(value.toString()) ?? 0)
            .toList() ??
        const [];

    return SalesAnalystSeries(
      name: json['name']?.toString() ?? 'Serie',
      values: values,
    );
  }
}

class SalesAnalystCard {
  final String title;
  final String value;
  final String subtitle;
  final String tone;

  const SalesAnalystCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.tone,
  });

  factory SalesAnalystCard.fromJson(Map<String, dynamic> json) {
    return SalesAnalystCard(
      title: json['title']?.toString() ?? 'Métrica',
      value: json['value']?.toString() ?? '-',
      subtitle: json['subtitle']?.toString() ?? '',
      tone: json['tone']?.toString() ?? 'neutral',
    );
  }
}
