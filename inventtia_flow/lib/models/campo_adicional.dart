enum TipoCampo { texto, numero, select, booleano }

extension TipoCampoX on TipoCampo {
  String get valor => switch (this) {
        TipoCampo.texto => 'texto',
        TipoCampo.numero => 'numero',
        TipoCampo.select => 'select',
        TipoCampo.booleano => 'booleano',
      };

  String get etiqueta => switch (this) {
        TipoCampo.texto => 'Texto',
        TipoCampo.numero => 'Número',
        TipoCampo.select => 'Seleccionable',
        TipoCampo.booleano => 'Sí / No',
      };

  static TipoCampo fromValor(String? v) => switch (v) {
        'numero' => TipoCampo.numero,
        'select' => TipoCampo.select,
        'booleano' => TipoCampo.booleano,
        _ => TipoCampo.texto,
      };
}

/// Regla de valor por defecto condicional: "si [siClave] es igual a [igual],
/// entonces el valor por defecto del campo es [valor]". Refleja un item de
/// CampoAdicional.reglas (jsonb).
class ReglaDefault {
  final String siClave; // clave de OTRO campo del que depende
  final String igual; // valor (como texto) que debe tener ese campo
  final Object valor; // default a aplicar si la condición se cumple

  ReglaDefault({required this.siClave, required this.igual, required this.valor});

  factory ReglaDefault.fromJson(Map<String, dynamic> json) => ReglaDefault(
        siClave: json['si_clave']?.toString() ?? '',
        igual: json['igual']?.toString() ?? '',
        valor: json['valor'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'si_clave': siClave,
        'igual': igual,
        'valor': valor,
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

  /// Valor por defecto fijo (clave json "default"). Para booleano es bool,
  /// para número/texto/select es el valor como texto.
  final Object? valorDefault;

  /// Si true, este campo se totaliza en el listado de reservas.
  final bool contabilizar;

  /// Reglas de default condicional (dependen de otro campo).
  final List<ReglaDefault> reglas;

  CampoAdicional({
    required this.clave,
    required this.etiqueta,
    this.tipo = TipoCampo.texto,
    this.requerido = false,
    List<String>? opciones,
    this.min,
    this.max,
    this.valorDefault,
    this.contabilizar = false,
    List<ReglaDefault>? reglas,
  })  : opciones = opciones ?? [],
        reglas = reglas ?? [];

  factory CampoAdicional.fromJson(Map<String, dynamic> json) => CampoAdicional(
        clave: json['clave'] as String,
        etiqueta: json['etiqueta'] as String? ?? json['clave'] as String,
        tipo: TipoCampoX.fromValor(json['tipo'] as String?),
        requerido: (json['requerido'] as bool?) ?? false,
        opciones: (json['opciones'] as List?)?.map((e) => e.toString()).toList() ?? [],
        min: (json['min'] as num?)?.toInt(),
        max: (json['max'] as num?)?.toInt(),
        valorDefault: json['default'],
        contabilizar: (json['contabilizar'] as bool?) ?? false,
        reglas: (json['reglas'] as List?)
                ?.map((e) => ReglaDefault.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'clave': clave,
        'etiqueta': etiqueta,
        'tipo': tipo.valor,
        'requerido': requerido,
        'opciones': opciones,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (valorDefault != null) 'default': valorDefault,
        if (contabilizar) 'contabilizar': true,
        if (reglas.isNotEmpty) 'reglas': reglas.map((r) => r.toJson()).toList(),
      };

  CampoAdicional copyWith({
    String? clave,
    String? etiqueta,
    TipoCampo? tipo,
    bool? requerido,
    List<String>? opciones,
    int? min,
    int? max,
    Object? valorDefault,
    bool? contabilizar,
    List<ReglaDefault>? reglas,
  }) =>
      CampoAdicional(
        clave: clave ?? this.clave,
        etiqueta: etiqueta ?? this.etiqueta,
        tipo: tipo ?? this.tipo,
        requerido: requerido ?? this.requerido,
        opciones: opciones ?? this.opciones,
        min: min ?? this.min,
        max: max ?? this.max,
        valorDefault: valorDefault ?? this.valorDefault,
        contabilizar: contabilizar ?? this.contabilizar,
        reglas: reglas ?? this.reglas,
      );

  /// Resuelve el valor por defecto de este campo dado el estado actual de los
  /// demás valores. Recorre las reglas en orden: la primera cuyo campo
  /// [ReglaDefault.siClave] tenga el valor [ReglaDefault.igual] gana. Si ninguna
  /// coincide, devuelve el default fijo ([valorDefault]).
  Object? defaultPara(Map<String, dynamic> valoresActuales) {
    for (final r in reglas) {
      final actual = valoresActuales[r.siClave];
      if (actual != null && actual.toString() == r.igual) {
        return r.valor;
      }
    }
    return valorDefault;
  }

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
