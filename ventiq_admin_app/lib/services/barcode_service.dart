import 'package:supabase_flutter/supabase_flutter.dart';

class BarcodeService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Busca un código de barras en la BD local (app_dat_codigos_barras)
  /// y retorna info del producto asociado si existe.
  static Future<Map<String, dynamic>?> lookupBarcode(String codigo) async {
    try {
      final response = await _supabase
          .from('app_dat_codigos_barras')
          .select('id, codigo_barras, es_principal, id_producto, app_dat_producto(id, denominacion, nombre_comercial)')
          .eq('codigo_barras', codigo)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      // Extraer datos del producto del join
      final producto = response['app_dat_producto'] as Map<String, dynamic>?;
      return {
        'id_codigo_barras': response['id'],
        'codigo_barras': response['codigo_barras'],
        'es_principal': response['es_principal'],
        'id_producto': response['id_producto'],
        'denominacion': producto?['denominacion'],
        'nombre_comercial': producto?['nombre_comercial'],
      };
    } catch (e) {
      print('Error buscando código de barras en BD: $e');
      return null;
    }
  }

  /// Inserta un registro en app_dat_codigos_barras.
  /// Maneja conflictos UNIQUE silenciosamente.
  static Future<void> insertCodigoBarras({
    required int idProducto,
    required String codigoBarras,
    bool esPrincipal = true,
  }) async {
    try {
      await _supabase.from('app_dat_codigos_barras').insert({
        'id_producto': idProducto,
        'codigo_barras': codigoBarras,
        'es_principal': esPrincipal,
      });
      print('✅ Código de barras insertado en app_dat_codigos_barras');
    } catch (e) {
      // Si falla por UNIQUE constraint, no bloquear
      if (e.toString().contains('duplicate') || e.toString().contains('unique')) {
        print('⚠️ Código de barras ya existe en app_dat_codigos_barras, omitiendo insert');
      } else {
        print('❌ Error insertando código de barras: $e');
      }
    }
  }

  /// Inserta un registro en codigo_producto con dígitos desglosados.
  static Future<void> insertCodigoProducto({
    required int idProducto,
    required String codigoBarras,
    required String tipoCodigo,
    String? fabricante,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final parsed = parseBarcode(codigoBarras, tipoCodigo);

      await _supabase.from('codigo_producto').insert({
        'id_producto': idProducto,
        'codigo_barras': codigoBarras,
        'tipo_codigo': tipoCodigo,
        // Dígitos desglosados
        if (parsed['prefijo_pais'] != null) 'prefijo_pais': parsed['prefijo_pais'],
        if (parsed['codigo_fabricante'] != null) 'codigo_fabricante': parsed['codigo_fabricante'],
        if (parsed['codigo_producto'] != null) 'codigo_producto': parsed['codigo_producto'],
        if (parsed['digito_control'] != null) 'digito_control': parsed['digito_control'],
        if (parsed['numero_sistema'] != null) 'numero_sistema': parsed['numero_sistema'],
        // Datos interpretados
        if (parsed['pais_origen'] != null) 'pais_origen': parsed['pais_origen'],
        if (fabricante != null) 'fabricante': fabricante,
        if (userId != null) 'created_by': userId,
      });
      print('✅ Código producto insertado en codigo_producto');
      print('📊 Desglose: $parsed');
    } catch (e) {
      print('❌ Error insertando en codigo_producto: $e');
    }
  }

  /// Wrapper que inserta en ambas tablas.
  static Future<void> saveBarcodeData({
    required int idProducto,
    required String codigoBarras,
    required String tipoCodigoBarras,
    String? fabricante,
  }) async {
    await insertCodigoBarras(
      idProducto: idProducto,
      codigoBarras: codigoBarras,
    );

    final tipoHuman = formatToHumanReadable(tipoCodigoBarras);
    await insertCodigoProducto(
      idProducto: idProducto,
      codigoBarras: codigoBarras,
      tipoCodigo: tipoHuman,
      fabricante: fabricante,
    );
  }

  // ─── PARSING DE CÓDIGOS DE BARRAS ───────────────────────────

  /// Desglosa un código de barras en sus componentes según el tipo.
  ///
  /// EAN-13 (13 dígitos): PPP-MMMM-IIIII-C
  ///   - PPP (3): Prefijo país/región GS1
  ///   - MMMM (4): Código de fabricante
  ///   - IIIII (5): Código de producto
  ///   - C (1): Dígito de control
  ///
  /// EAN-8 (8 dígitos): PPP-IIII-C
  ///   - PPP (3): Prefijo país/región GS1
  ///   - IIII (4): Código de producto
  ///   - C (1): Dígito de control
  ///
  /// UPC-A (12 dígitos): S-MMMMM-IIIII-C
  ///   - S (1): Número de sistema
  ///   - MMMMM (5): Código de fabricante
  ///   - IIIII (5): Código de producto
  ///   - C (1): Dígito de control
  ///
  /// UPC-E (8 dígitos): S-MMMMMM-C (comprimido)
  ///   - S (1): Número de sistema (siempre 0)
  ///   - MMMMMM (6): Código comprimido fabricante+producto
  ///   - C (1): Dígito de control
  static Map<String, String?> parseBarcode(String barcode, String tipo) {
    final digits = barcode.replaceAll(RegExp(r'[^0-9]'), '');
    final tipoLower = tipo.toLowerCase().replaceAll('-', '').replaceAll(' ', '');

    switch (tipoLower) {
      case 'ean13':
        return _parseEAN13(digits);
      case 'ean8':
        return _parseEAN8(digits);
      case 'upca':
        return _parseUPCA(digits);
      case 'upce':
        return _parseUPCE(digits);
      default:
        // Para otros formatos (Code-128, QR, etc.) no hay estructura fija
        return {
          'prefijo_pais': null,
          'codigo_fabricante': null,
          'codigo_producto': null,
          'digito_control': null,
          'numero_sistema': null,
          'pais_origen': null,
        };
    }
  }

  static Map<String, String?> _parseEAN13(String digits) {
    if (digits.length != 13) {
      return {
        'prefijo_pais': null,
        'codigo_fabricante': null,
        'codigo_producto': null,
        'digito_control': null,
        'numero_sistema': null,
        'pais_origen': null,
      };
    }
    final prefijo = digits.substring(0, 3);
    return {
      'prefijo_pais': prefijo,
      'codigo_fabricante': digits.substring(3, 7),
      'codigo_producto': digits.substring(7, 12),
      'digito_control': digits.substring(12, 13),
      'numero_sistema': null,
      'pais_origen': getCountryFromPrefix(prefijo),
    };
  }

  static Map<String, String?> _parseEAN8(String digits) {
    if (digits.length != 8) {
      return {
        'prefijo_pais': null,
        'codigo_fabricante': null,
        'codigo_producto': null,
        'digito_control': null,
        'numero_sistema': null,
        'pais_origen': null,
      };
    }
    final prefijo = digits.substring(0, 3);
    return {
      'prefijo_pais': prefijo,
      'codigo_fabricante': null,
      'codigo_producto': digits.substring(3, 7),
      'digito_control': digits.substring(7, 8),
      'numero_sistema': null,
      'pais_origen': getCountryFromPrefix(prefijo),
    };
  }

  static Map<String, String?> _parseUPCA(String digits) {
    if (digits.length != 12) {
      return {
        'prefijo_pais': null,
        'codigo_fabricante': null,
        'codigo_producto': null,
        'digito_control': null,
        'numero_sistema': null,
        'pais_origen': null,
      };
    }
    // UPC-A es subconjunto de EAN-13 (prefijo '000'-'019' = USA/Canadá)
    return {
      'prefijo_pais': '000',
      'codigo_fabricante': digits.substring(1, 6),
      'codigo_producto': digits.substring(6, 11),
      'digito_control': digits.substring(11, 12),
      'numero_sistema': digits.substring(0, 1),
      'pais_origen': 'Estados Unidos / Canadá',
    };
  }

  static Map<String, String?> _parseUPCE(String digits) {
    if (digits.length != 8) {
      return {
        'prefijo_pais': null,
        'codigo_fabricante': null,
        'codigo_producto': null,
        'digito_control': null,
        'numero_sistema': null,
        'pais_origen': null,
      };
    }
    return {
      'prefijo_pais': '000',
      'codigo_fabricante': digits.substring(1, 7),
      'codigo_producto': null,
      'digito_control': digits.substring(7, 8),
      'numero_sistema': digits.substring(0, 1),
      'pais_origen': 'Estados Unidos / Canadá',
    };
  }

  // ─── MAPA DE PREFIJOS GS1 → PAÍS ────────────────────────────

  /// Retorna el nombre del país/región según el prefijo GS1 del código de barras.
  static String? getCountryFromPrefix(String prefix) {
    final num = int.tryParse(prefix);
    if (num == null) return null;

    // Rangos GS1 principales
    if (num >= 0 && num <= 19) return 'Estados Unidos / Canadá';
    if (num >= 20 && num <= 29) return 'Uso interno';
    if (num >= 30 && num <= 39) return 'Francia / Mónaco';
    if (num >= 40 && num <= 44) return 'Alemania';
    if (num == 45 || num == 49) return 'Japón';
    if (num >= 46 && num <= 48) return 'Rusia';
    if (num == 50) return 'Reino Unido';
    if (num == 51) return 'Reservado';
    if (num == 52) return 'Grecia';
    if (num == 53) return 'Irlanda';
    if (num == 54) return 'Bélgica / Luxemburgo';
    if (num == 55) return 'Portugal';
    if (num == 56) return 'Brasil';
    if (num == 57) return 'Dinamarca';
    if (num == 58) return 'Polonia';
    if (num == 59) return 'Cuba';
    if (num == 60 || num == 61) return 'Sudáfrica';
    if (num == 64) return 'Finlandia';
    if (num == 69) return 'China';
    if (num == 70) return 'Noruega';
    if (num == 71) return 'Israel';
    if (num == 73) return 'Suecia';
    if (num == 74) return 'Guatemala';
    if (num == 75) return 'México';
    if (num == 76) return 'Suiza';
    if (num == 77) return 'Colombia';
    if (num == 78) return 'Argentina';
    if (num == 79) return 'Brasil';
    if (num == 80) return 'Italia';
    if (num == 84) return 'España';
    if (num == 85) return 'Brasil';
    if (num == 86) return 'China';
    if (num == 87) return 'Países Bajos';
    if (num == 88) return 'Corea del Sur';
    if (num == 89) return 'Turquía';
    if (num == 90 || num == 91) return 'Austria';
    if (num == 93) return 'Australia';
    if (num == 94) return 'Nueva Zelanda';

    // Rangos de 3 dígitos específicos
    if (num >= 100 && num <= 139) return 'Estados Unidos';
    if (num >= 200 && num <= 299) return 'Uso interno';
    if (num >= 300 && num <= 379) return 'Francia / Mónaco';
    if (num >= 380 && num <= 380) return 'Bulgaria';
    if (num == 383) return 'Eslovenia';
    if (num == 385) return 'Croacia';
    if (num == 387) return 'Bosnia';
    if (num == 389) return 'Montenegro';
    if (num >= 400 && num <= 440) return 'Alemania';
    if (num >= 450 && num <= 459) return 'Japón';
    if (num >= 460 && num <= 469) return 'Rusia';
    if (num == 470) return 'Kirguistán';
    if (num == 471) return 'Taiwán';
    if (num == 474) return 'Estonia';
    if (num == 475) return 'Letonia';
    if (num == 476) return 'Azerbaiyán';
    if (num == 477) return 'Lituania';
    if (num == 478) return 'Uzbekistán';
    if (num == 479) return 'Sri Lanka';
    if (num == 480) return 'Filipinas';
    if (num == 481) return 'Bielorrusia';
    if (num == 482) return 'Ucrania';
    if (num == 484) return 'Moldavia';
    if (num == 485) return 'Armenia';
    if (num == 486) return 'Georgia';
    if (num == 487) return 'Kazajistán';
    if (num == 489) return 'Hong Kong';
    if (num >= 490 && num <= 499) return 'Japón';
    if (num >= 500 && num <= 509) return 'Reino Unido';
    if (num >= 520 && num <= 521) return 'Grecia';
    if (num == 528) return 'Líbano';
    if (num == 529) return 'Chipre';
    if (num == 530) return 'Albania';
    if (num == 531) return 'Macedonia';
    if (num == 535) return 'Malta';
    if (num >= 539 && num <= 539) return 'Irlanda';
    if (num >= 540 && num <= 549) return 'Bélgica / Luxemburgo';
    if (num >= 560 && num <= 569) return 'Portugal';
    if (num >= 570 && num <= 579) return 'Dinamarca';
    if (num >= 590 && num <= 590) return 'Polonia';
    if (num == 594) return 'Rumanía';
    if (num == 599) return 'Hungría';
    if (num >= 600 && num <= 601) return 'Sudáfrica';
    if (num == 603) return 'Ghana';
    if (num == 604) return 'Senegal';
    if (num == 608) return 'Bahréin';
    if (num == 609) return 'Mauricio';
    if (num == 611) return 'Marruecos';
    if (num == 613) return 'Argelia';
    if (num == 615) return 'Nigeria';
    if (num == 616) return 'Kenia';
    if (num == 618) return 'Costa de Marfil';
    if (num == 619) return 'Túnez';
    if (num == 620) return 'Tanzania';
    if (num == 621) return 'Siria';
    if (num == 622) return 'Egipto';
    if (num == 624) return 'Libia';
    if (num == 625) return 'Jordania';
    if (num == 626) return 'Irán';
    if (num == 627) return 'Kuwait';
    if (num == 628) return 'Arabia Saudita';
    if (num == 629) return 'Emiratos Árabes';
    if (num >= 640 && num <= 649) return 'Finlandia';
    if (num >= 690 && num <= 699) return 'China';
    if (num >= 700 && num <= 709) return 'Noruega';
    if (num == 729) return 'Israel';
    if (num >= 730 && num <= 739) return 'Suecia';
    if (num == 740) return 'Guatemala';
    if (num == 741) return 'El Salvador';
    if (num == 742) return 'Honduras';
    if (num == 743) return 'Nicaragua';
    if (num == 744) return 'Costa Rica';
    if (num == 745) return 'Panamá';
    if (num == 746) return 'República Dominicana';
    if (num >= 750 && num <= 750) return 'México';
    if (num >= 754 && num <= 755) return 'Canadá';
    if (num == 759) return 'Venezuela';
    if (num >= 760 && num <= 769) return 'Suiza';
    if (num >= 770 && num <= 771) return 'Colombia';
    if (num == 773) return 'Uruguay';
    if (num == 775) return 'Perú';
    if (num == 777) return 'Bolivia';
    if (num >= 778 && num <= 779) return 'Argentina';
    if (num == 780) return 'Chile';
    if (num == 784) return 'Paraguay';
    if (num == 786) return 'Ecuador';
    if (num >= 789 && num <= 790) return 'Brasil';
    if (num >= 800 && num <= 839) return 'Italia';
    if (num >= 840 && num <= 849) return 'España';
    if (num == 850) return 'Cuba';
    if (num == 858) return 'Eslovaquia';
    if (num == 859) return 'República Checa';
    if (num == 860) return 'Serbia';
    if (num == 865) return 'Mongolia';
    if (num == 867) return 'Corea del Norte';
    if (num >= 868 && num <= 869) return 'Turquía';
    if (num >= 870 && num <= 879) return 'Países Bajos';
    if (num >= 880 && num <= 880) return 'Corea del Sur';
    if (num == 884) return 'Camboya';
    if (num == 885) return 'Tailandia';
    if (num == 888) return 'Singapur';
    if (num == 890) return 'India';
    if (num == 893) return 'Vietnam';
    if (num == 896) return 'Pakistán';
    if (num == 899) return 'Indonesia';
    if (num >= 900 && num <= 919) return 'Austria';
    if (num >= 930 && num <= 939) return 'Australia';
    if (num >= 940 && num <= 949) return 'Nueva Zelanda';
    if (num == 955) return 'Malasia';
    if (num == 958) return 'Macao';

    return null;
  }

  // ─── UTILIDADES ──────────────────────────────────────────────

  /// Convierte el nombre del formato del scanner a formato legible.
  static String formatToHumanReadable(String format) {
    switch (format.toLowerCase()) {
      case 'ean13':
        return 'EAN-13';
      case 'ean8':
        return 'EAN-8';
      case 'upca':
        return 'UPC-A';
      case 'upce':
        return 'UPC-E';
      case 'code128':
        return 'Code-128';
      case 'code39':
        return 'Code-39';
      case 'code93':
        return 'Code-93';
      case 'codabar':
        return 'Codabar';
      case 'itf':
        return 'ITF';
      case 'qrcode':
      case 'qr':
        return 'QR Code';
      case 'datamatrix':
        return 'Data Matrix';
      case 'pdf417':
        return 'PDF-417';
      case 'aztec':
        return 'Aztec';
      default:
        return format.toUpperCase();
    }
  }
}
