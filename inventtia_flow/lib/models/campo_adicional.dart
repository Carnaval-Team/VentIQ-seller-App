enum TipoCampo { texto, numero, select }

extension TipoCampoX on TipoCampo {
  String get valor => switch (this) {
        TipoCampo.texto => 'texto',
        TipoCampo.numero => 'numero',
        TipoCampo.select => 'select',
      };

  String get etiqueta => switch (this) {
        TipoCampo.texto => 'Texto',
        TipoCampo.numero => 'Número',
        TipoCampo.select => 'Seleccionable',
      };

  static TipoCampo fromValor(String? v) => switch (v) {
        'numero' => TipoCampo.numero,
        'select' => TipoCampo.select,
        _ => TipoCampo.texto,
      };
}

/// Un campo de datos adicionales que el admin configura por servicio y que el
/// cliente debe llenar al reservar. Refleja un item de
/// app_dat_servicios.campos_adicionales (jsonb).
class CampoAdicional {
  final String clave;
  final String etiqueta;
  final TipoCampo tipo;
  final bool requerido;
  final List<String> opciones; // solo select
  final int? min; // numero: valor mínimo; texto: longitud mínima
  final int? max;

  CampoAdicional({
    required this.clave,
    required this.etiqueta,
    this.tipo = TipoCampo.texto,
    this.requerido = false,
    List<String>? opciones,
    this.min,
    this.max,
  }) : opciones = opciones ?? [];

  factory CampoAdicional.fromJson(Map<String, dynamic> json) => CampoAdicional(
        clave: json['clave'] as String,
        etiqueta: json['etiqueta'] as String? ?? json['clave'] as String,
        tipo: TipoCampoX.fromValor(json['tipo'] as String?),
        requerido: (json['requerido'] as bool?) ?? false,
        opciones: (json['opciones'] as List?)?.map((e) => e.toString()).toList() ?? [],
        min: (json['min'] as num?)?.toInt(),
        max: (json['max'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'clave': clave,
        'etiqueta': etiqueta,
        'tipo': tipo.valor,
        'requerido': requerido,
        'opciones': opciones,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };

  CampoAdicional copyWith({
    String? clave,
    String? etiqueta,
    TipoCampo? tipo,
    bool? requerido,
    List<String>? opciones,
    int? min,
    int? max,
  }) =>
      CampoAdicional(
        clave: clave ?? this.clave,
        etiqueta: etiqueta ?? this.etiqueta,
        tipo: tipo ?? this.tipo,
        requerido: requerido ?? this.requerido,
        opciones: opciones ?? this.opciones,
        min: min ?? this.min,
        max: max ?? this.max,
      );

  /// Genera un slug a partir de una etiqueta (para la clave).
  static String slug(String texto) {
    var s = texto.trim().toLowerCase();
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'campo' : s;
  }
}
