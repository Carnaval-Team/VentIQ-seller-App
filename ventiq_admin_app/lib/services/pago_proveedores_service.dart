import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pago_proveedores.dart';
import '../utils/storage_key_sanitizer.dart';
import 'user_preferences_service.dart';

class PagoProveedoresService {
  static final PagoProveedoresService _instance =
      PagoProveedoresService._internal();
  factory PagoProveedoresService() => _instance;
  PagoProveedoresService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  // ==================== ESTADOS DE FACTURA (NOMENCLADOR) ====================

  Future<List<EstadoFacturaProveedor>> getEstados() async {
    try {
      final response = await _supabase
          .from('prv_nom_estado_factura')
          .select()
          .order('orden');
      return response
          .map<EstadoFacturaProveedor>(
            (j) => EstadoFacturaProveedor.fromJson(j),
          )
          .toList();
    } catch (e) {
      print('❌ Error obteniendo estados de factura proveedor: $e');
      rethrow;
    }
  }

  Future<EstadoFacturaProveedor> createEstado(
    EstadoFacturaProveedor estado,
  ) async {
    try {
      final response = await _supabase
          .from('prv_nom_estado_factura')
          .insert(estado.toJson())
          .select()
          .single();
      return EstadoFacturaProveedor.fromJson(response);
    } catch (e) {
      print('❌ Error creando estado proveedor: $e');
      rethrow;
    }
  }

  Future<EstadoFacturaProveedor> updateEstado(
    int id,
    EstadoFacturaProveedor estado,
  ) async {
    try {
      final response = await _supabase
          .from('prv_nom_estado_factura')
          .update(estado.toJson())
          .eq('id', id)
          .select()
          .single();
      return EstadoFacturaProveedor.fromJson(response);
    } catch (e) {
      print('❌ Error actualizando estado proveedor: $e');
      rethrow;
    }
  }

  Future<void> deleteEstado(int id) async {
    try {
      await _supabase.from('prv_nom_estado_factura').delete().eq('id', id);
    } catch (e) {
      print('❌ Error eliminando estado proveedor: $e');
      rethrow;
    }
  }

  Future<EstadoFacturaProveedor?> getEstadoInicial() async {
    try {
      final response = await _supabase
          .from('prv_nom_estado_factura')
          .select()
          .eq('activo', true)
          .order('orden', ascending: true)
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return EstadoFacturaProveedor.fromJson(response);
    } catch (e) {
      print('❌ Error obteniendo estado inicial proveedor: $e');
      return null;
    }
  }

  // ==================== MONEDAS ====================

  Future<List<MonedaPago>> getMonedas({bool soloActivas = false}) async {
    try {
      final response = soloActivas
          ? await _supabase
                .from('prv_nom_moneda')
                .select()
                .eq('activo', true)
                .order('codigo')
          : await _supabase.from('prv_nom_moneda').select().order('codigo');
      return response.map<MonedaPago>((j) => MonedaPago.fromJson(j)).toList();
    } catch (e) {
      print('❌ Error obteniendo monedas: $e');
      rethrow;
    }
  }

  Future<MonedaPago> createMoneda(MonedaPago moneda) async {
    try {
      final response = await _supabase
          .from('prv_nom_moneda')
          .insert(moneda.toJson())
          .select()
          .single();
      return MonedaPago.fromJson(response);
    } catch (e) {
      print('❌ Error creando moneda: $e');
      rethrow;
    }
  }

  Future<MonedaPago> updateMoneda(int id, MonedaPago moneda) async {
    try {
      final response = await _supabase
          .from('prv_nom_moneda')
          .update(moneda.toJson())
          .eq('id', id)
          .select()
          .single();
      return MonedaPago.fromJson(response);
    } catch (e) {
      print('❌ Error actualizando moneda: $e');
      rethrow;
    }
  }

  Future<void> setMonedaActiva(int id, bool activo) async {
    try {
      await _supabase
          .from('prv_nom_moneda')
          .update({'activo': activo})
          .eq('id', id);
    } catch (e) {
      print('❌ Error cambiando activo moneda: $e');
      rethrow;
    }
  }

  // ==================== CONFIG PROVEEDOR (MONEDA) ====================

  Future<ProveedorConfig?> getProveedorConfig(int idProveedor) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('prv_dat_proveedor_config')
          .select('*, moneda:id_moneda(codigo, simbolo, denominacion)')
          .eq('idtienda', storeId)
          .eq('id_proveedor', idProveedor)
          .maybeSingle();

      if (response == null) return null;
      return ProveedorConfig.fromJson(response);
    } catch (e) {
      print('❌ Error obteniendo config proveedor: $e');
      return null;
    }
  }

  Future<ProveedorConfig> setProveedorConfig({
    required int idProveedor,
    required int idMoneda,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('prv_dat_proveedor_config')
          .upsert({
            'idtienda': storeId,
            'id_proveedor': idProveedor,
            'id_moneda': idMoneda,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'idtienda,id_proveedor')
          .select('*, moneda:id_moneda(codigo, simbolo, denominacion)')
          .single();

      return ProveedorConfig.fromJson(response);
    } catch (e) {
      print('❌ Error guardando config proveedor: $e');
      rethrow;
    }
  }

  // ==================== SALDO DISPONIBLE ====================

  Future<double> getSaldoDisponible(int idProveedor) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('prv_dat_saldo')
          .select('saldo_disponible')
          .eq('idtienda', storeId)
          .eq('id_proveedor', idProveedor)
          .maybeSingle();

      if (response == null) return 0.0;
      return (response['saldo_disponible'] ?? 0.0).toDouble();
    } catch (e) {
      print('❌ Error obteniendo saldo proveedor: $e');
      return 0.0;
    }
  }

  Future<void> _upsertSaldo(
    int storeId,
    int idProveedor,
    double nuevoSaldo,
    double saldoAnterior,
    String tipoOperacion,
    String referencia, {
    int? idRecarga,
  }) async {
    if (nuevoSaldo < 0) {
      throw Exception('El saldo no puede ser negativo');
    }

    await _supabase.from('prv_dat_saldo').upsert({
      'idtienda': storeId,
      'id_proveedor': idProveedor,
      'saldo_disponible': nuevoSaldo,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'idtienda,id_proveedor');

    final histRow = <String, dynamic>{
      'idtienda': storeId,
      'id_proveedor': idProveedor,
      'monto_anterior': saldoAnterior,
      'monto_nuevo': nuevoSaldo,
      'diferencia': nuevoSaldo - saldoAnterior,
      'tipo_operacion': tipoOperacion,
      'referencia': referencia,
      'created_at': DateTime.now().toIso8601String(),
    };
    if (idRecarga != null) histRow['id_recarga'] = idRecarga;

    await _supabase.from('prv_hist_saldo').insert(histRow);
  }

  // ==================== RECARGAS DE SALDO ====================

  Future<List<RecargaSaldoProveedor>> getRecargas(int idProveedor) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('prv_dat_recarga_saldo')
          .select()
          .eq('idtienda', storeId)
          .eq('id_proveedor', idProveedor)
          .order('created_at', ascending: false);

      return response
          .map<RecargaSaldoProveedor>((j) => RecargaSaldoProveedor.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo recargas proveedor: $e');
      rethrow;
    }
  }

  Future<void> agregarRecarga({
    required int idProveedor,
    required double monto,
    required DateTime fechaPago,
    String? observacion,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final saldoActual = await getSaldoDisponible(idProveedor);
      final nuevoSaldo = saldoActual + monto;

      final recargaRow = await _supabase
          .from('prv_dat_recarga_saldo')
          .insert({
            'idtienda': storeId,
            'id_proveedor': idProveedor,
            'monto': monto,
            'fecha_pago': fechaPago.toIso8601String().split('T').first,
            'observacion': observacion,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();
      final recargaId = recargaRow['id'] as int;

      final refRecarga = observacion != null && observacion.isNotEmpty
          ? 'Recarga de saldo: \$${monto.toStringAsFixed(2)} — $observacion'
          : 'Recarga de saldo: \$${monto.toStringAsFixed(2)}';
      await _upsertSaldo(
        storeId,
        idProveedor,
        nuevoSaldo,
        saldoActual,
        'recarga',
        refRecarga,
        idRecarga: recargaId,
      );

      print(
        '✅ Recarga proveedor $idProveedor de \$${monto.toStringAsFixed(2)} registrada. Nuevo saldo: \$${nuevoSaldo.toStringAsFixed(2)}',
      );
    } catch (e) {
      print('❌ Error agregando recarga proveedor: $e');
      rethrow;
    }
  }

  /// Cancela un pago (recarga): resta el monto del saldo y elimina recarga + historial.
  Future<void> cancelarPagoRecarga({
    required int idProveedor,
    required int idRecarga,
    int? idHistorial,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final recargaRow = await _supabase
          .from('prv_dat_recarga_saldo')
          .select('id, monto')
          .eq('id', idRecarga)
          .eq('idtienda', storeId)
          .eq('id_proveedor', idProveedor)
          .maybeSingle();
      if (recargaRow == null) {
        throw Exception('No se encontró el pago a cancelar');
      }

      final monto = (recargaRow['monto'] as num).toDouble();
      final saldoActual = await getSaldoDisponible(idProveedor);
      if (saldoActual < monto) {
        throw Exception(
          'Saldo insuficiente para cancelar este pago. '
          'Saldo actual: \$${saldoActual.toStringAsFixed(2)}, '
          'monto del pago: \$${monto.toStringAsFixed(2)}',
        );
      }

      if (idHistorial != null) {
        await _supabase
            .from('prv_hist_saldo')
            .delete()
            .eq('id', idHistorial)
            .eq('idtienda', storeId)
            .eq('id_proveedor', idProveedor);
      } else {
        await _supabase
            .from('prv_hist_saldo')
            .delete()
            .eq('id_recarga', idRecarga)
            .eq('idtienda', storeId)
            .eq('id_proveedor', idProveedor);
      }

      await _supabase
          .from('prv_dat_recarga_saldo')
          .delete()
          .eq('id', idRecarga)
          .eq('idtienda', storeId)
          .eq('id_proveedor', idProveedor);

      await _supabase.from('prv_dat_saldo').upsert({
        'idtienda': storeId,
        'id_proveedor': idProveedor,
        'saldo_disponible': saldoActual - monto,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'idtienda,id_proveedor');

      print(
        '✅ Pago recarga #$idRecarga cancelado (proveedor $idProveedor). Monto descontado: \$${monto.toStringAsFixed(2)}',
      );
    } catch (e) {
      print('❌ Error cancelando pago proveedor: $e');
      rethrow;
    }
  }

  /// Resuelve el id de recarga asociado a un movimiento del historial.
  int? resolverRecargaId(
    HistorialSaldoProveedor historial,
    List<RecargaSaldoProveedor> recargas,
  ) {
    if (historial.idRecarga != null) return historial.idRecarga;

    RecargaSaldoProveedor? mejor;
    var mejorDiff = const Duration(days: 9999);

    for (final r in recargas) {
      if (r.id == null || r.monto != historial.diferencia) continue;
      final diff = r.createdAt.difference(historial.createdAt).abs();
      if (diff < mejorDiff) {
        mejorDiff = diff;
        mejor = r;
      }
    }

    if (mejor != null && mejorDiff.inHours <= 24) return mejor.id;

    final candidatos = recargas
        .where((r) => r.id != null && r.monto == historial.diferencia)
        .toList();
    if (candidatos.length == 1) return candidatos.first.id;

    return null;
  }

  // ==================== HISTORIAL DE SALDO ====================

  Future<List<HistorialSaldoProveedor>> getHistorialSaldo(
    int idProveedor,
  ) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      List<dynamic> response;
      try {
        response = await _supabase
            .from('prv_hist_saldo')
            .select('*, recarga:prv_dat_recarga_saldo(observacion)')
            .eq('idtienda', storeId)
            .eq('id_proveedor', idProveedor)
            .order('created_at', ascending: false)
            .limit(100);
      } catch (_) {
        response = await _supabase
            .from('prv_hist_saldo')
            .select(
              'id, idtienda, id_proveedor, monto_anterior, monto_nuevo, diferencia, tipo_operacion, referencia, id_recarga, created_at',
            )
            .eq('idtienda', storeId)
            .eq('id_proveedor', idProveedor)
            .order('created_at', ascending: false)
            .limit(100);
      }

      return response
          .map<HistorialSaldoProveedor>(
            (j) => HistorialSaldoProveedor.fromJson(j),
          )
          .toList();
    } catch (e) {
      print('❌ Error obteniendo historial de saldo proveedor: $e');
      rethrow;
    }
  }

  // ==================== FACTURAS ====================

  Future<List<ProveedorFactura>> getFacturas(int idProveedor) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('prv_dat_factura')
          .select(
            '*, estado:id_estado(denominacion, color), fotos:prv_dat_factura_foto(id, id_factura, foto_url, numero_pagina, created_at)',
          )
          .eq('idtienda', storeId)
          .eq('id_proveedor', idProveedor)
          .order('created_at', ascending: false);

      return response
          .map<ProveedorFactura>((j) => ProveedorFactura.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo facturas proveedor: $e');
      rethrow;
    }
  }

  Future<List<FacturaFotoProveedor>> getFotosFactura(int idFactura) async {
    try {
      final response = await _supabase
          .from('prv_dat_factura_foto')
          .select()
          .eq('id_factura', idFactura)
          .order('numero_pagina', ascending: true);
      return response
          .map<FacturaFotoProveedor>((j) => FacturaFotoProveedor.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo fotos de factura proveedor: $e');
      rethrow;
    }
  }

  Future<FacturaFotoProveedor> agregarFotoFactura({
    required int idFactura,
    required Uint8List bytes,
    required String fileName,
    required int numeroPagina,
    String mimeType = 'image/jpeg',
    String? nombreArchivo,
  }) async {
    try {
      final url = await uploadFacturaFoto(
        bytes,
        fileName,
        contentType: mimeType,
      );
      if (url == null) throw Exception('No se pudo subir el archivo');

      final response = await _supabase
          .from('prv_dat_factura_foto')
          .insert({
            'id_factura': idFactura,
            'foto_url': url,
            'numero_pagina': numeroPagina,
            'mime_type': mimeType,
            'nombre_archivo': nombreArchivo ?? fileName,
          })
          .select()
          .single();

      print(
        '✅ Archivo p.$numeroPagina añadido a factura proveedor $idFactura ($mimeType)',
      );
      return FacturaFotoProveedor.fromJson(response);
    } catch (e) {
      print('❌ Error añadiendo archivo proveedor: $e');
      rethrow;
    }
  }

  Future<void> eliminarFotoFactura(int idFoto) async {
    try {
      await _supabase.from('prv_dat_factura_foto').delete().eq('id', idFoto);
      print('✅ Foto $idFoto eliminada');
    } catch (e) {
      print('❌ Error eliminando foto proveedor: $e');
      rethrow;
    }
  }

  Future<ProveedorFactura> crearFactura({
    required int idProveedor,
    required String numeroFactura,
    required double valor,
    required DateTime fechaProcesamiento,
    List<({Uint8List bytes, String nombre, String mimeType})> fotosEntradas =
        const [],
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final saldoActual = await getSaldoDisponible(idProveedor);
      if (saldoActual < valor) {
        throw Exception(
          'Saldo insuficiente. Saldo disponible: \$${saldoActual.toStringAsFixed(2)}, valor de factura: \$${valor.toStringAsFixed(2)}',
        );
      }

      final estadoInicial = await getEstadoInicial();
      if (estadoInicial == null) {
        throw Exception(
          'No hay estados configurados. Configure al menos un estado en el nomenclador.',
        );
      }

      print(
        '🔍 Estado inicial resuelto: id=${estadoInicial.id} denominacion=${estadoInicial.denominacion} orden=${estadoInicial.orden}',
      );

      final insertData = {
        'idtienda': storeId,
        'id_proveedor': idProveedor,
        'numero_factura': numeroFactura,
        'valor': valor,
        'fecha_procesamiento': fechaProcesamiento
            .toIso8601String()
            .split('T')
            .first,
        'id_estado': estadoInicial.id,
        'created_at': DateTime.now().toIso8601String(),
      };
      print(
        '🔍 Insertando factura proveedor con id_estado=${insertData['id_estado']}',
      );

      final response = await _supabase
          .from('prv_dat_factura')
          .insert(insertData)
          .select('*, estado:id_estado(denominacion, color)')
          .single();

      print(
        '🔍 Respuesta insert factura: id_estado=${response['id_estado']} estado=${response['estado']}',
      );

      final factura = ProveedorFactura.fromJson(response);

      for (int i = 0; i < fotosEntradas.length; i++) {
        final entrada = fotosEntradas[i];
        await agregarFotoFactura(
          idFactura: factura.id!,
          bytes: entrada.bytes,
          fileName: entrada.nombre,
          numeroPagina: i + 1,
          mimeType: entrada.mimeType,
          nombreArchivo: entrada.nombre,
        );
      }

      await _upsertSaldo(
        storeId,
        idProveedor,
        saldoActual - valor,
        saldoActual,
        'descuento_factura',
        'Factura #$numeroFactura: -\$${valor.toStringAsFixed(2)}',
      );

      await _supabase.from('prv_hist_estado_factura').insert({
        'id_factura': factura.id,
        'id_estado_anterior': estadoInicial.id,
        'id_estado_nuevo': estadoInicial.id,
        'observacion': 'Factura creada',
        'created_at': DateTime.now().toIso8601String(),
      });

      print(
        '✅ Factura #$numeroFactura creada (proveedor $idProveedor) con ${fotosEntradas.length} foto(s). Saldo descontado: \$${valor.toStringAsFixed(2)}',
      );
      return factura;
    } catch (e) {
      print('❌ Error creando factura proveedor: $e');
      rethrow;
    }
  }

  Future<void> cambiarEstadoFactura({
    required int idFactura,
    required int idEstadoAnterior,
    required int idEstadoNuevo,
    String? observacion,
  }) async {
    try {
      await _supabase
          .from('prv_dat_factura')
          .update({'id_estado': idEstadoNuevo})
          .eq('id', idFactura);

      await _supabase.from('prv_hist_estado_factura').insert({
        'id_factura': idFactura,
        'id_estado_anterior': idEstadoAnterior,
        'id_estado_nuevo': idEstadoNuevo,
        'observacion': observacion,
        'created_at': DateTime.now().toIso8601String(),
      });

      print(
        '✅ Estado de factura proveedor $idFactura cambiado de $idEstadoAnterior a $idEstadoNuevo',
      );
    } catch (e) {
      print('❌ Error cambiando estado de factura proveedor: $e');
      rethrow;
    }
  }

  Future<List<HistorialEstadoFacturaProveedor>> getHistorialEstadoFactura(
    int idFactura,
  ) async {
    try {
      final response = await _supabase
          .from('prv_hist_estado_factura')
          .select(
            '*, estado_anterior:id_estado_anterior(denominacion), estado_nuevo:id_estado_nuevo(denominacion)',
          )
          .eq('id_factura', idFactura)
          .order('created_at', ascending: false);

      return response
          .map<HistorialEstadoFacturaProveedor>(
            (j) => HistorialEstadoFacturaProveedor.fromJson(j),
          )
          .toList();
    } catch (e) {
      print('❌ Error obteniendo historial de estados proveedor: $e');
      rethrow;
    }
  }

  // ==================== FOTO DE FACTURA ====================

  Future<String?> uploadFacturaFoto(
    Uint8List imageBytes,
    String fileName, {
    String contentType = 'image/jpeg',
  }) async {
    try {
      final uniqueFileName =
          'pago_proveedor_${DateTime.now().millisecondsSinceEpoch}_${sanitizeStorageKey(fileName)}';
      final response = await _supabase.storage
          .from('images_back')
          .uploadBinary(
            uniqueFileName,
            imageBytes,
            fileOptions: FileOptions(
              contentType: contentType,
              cacheControl: '3600',
              upsert: true,
            ),
          );
      if (response.isEmpty) throw Exception('Error al subir foto de factura');
      final url = _supabase.storage
          .from('images_back')
          .getPublicUrl(uniqueFileName);
      print('✅ Foto de factura proveedor subida: $url');
      return url;
    } catch (e) {
      print('❌ Error subiendo foto de factura proveedor: $e');
      return null;
    }
  }

  Future<void> actualizarDetallesFactura({
    required int idProveedor,
    required int idFactura,
    required String numeroFacturaAnterior,
    required String nuevoNumeroFactura,
    required double valorAnterior,
    required double nuevoValor,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final diferencia = nuevoValor - valorAnterior;

      if (diferencia > 0) {
        final saldoActual = await getSaldoDisponible(idProveedor);
        if (saldoActual < diferencia) {
          throw Exception(
            'Saldo insuficiente para aumentar el valor. Diferencia: \$${diferencia.toStringAsFixed(2)}, saldo disponible: \$${saldoActual.toStringAsFixed(2)}',
          );
        }
      }

      await _supabase
          .from('prv_dat_factura')
          .update({'numero_factura': nuevoNumeroFactura, 'valor': nuevoValor})
          .eq('id', idFactura)
          .eq('id_proveedor', idProveedor);

      if (diferencia != 0) {
        final saldoActual = await getSaldoDisponible(idProveedor);
        final nuevoSaldo = saldoActual - diferencia;
        await _upsertSaldo(
          storeId,
          idProveedor,
          nuevoSaldo,
          saldoActual,
          'ajuste_factura',
          'Ajuste Factura #$nuevoNumeroFactura: ${diferencia > 0 ? '-' : '+'}\$${diferencia.abs().toStringAsFixed(2)}',
        );
      }

      print(
        '✅ Factura #$nuevoNumeroFactura actualizada (proveedor $idProveedor). Diferencia de saldo: \$${diferencia.toStringAsFixed(2)}',
      );
    } catch (e) {
      print('❌ Error actualizando detalles de factura proveedor: $e');
      rethrow;
    }
  }

  Future<void> actualizarFotoFactura(int idFactura, String fotoUrl) async {
    try {
      await _supabase
          .from('prv_dat_factura')
          .update({'foto_url': fotoUrl})
          .eq('id', idFactura);
      print('✅ foto_url actualizada en factura proveedor $idFactura');
    } catch (e) {
      print('❌ Error actualizando foto de factura proveedor: $e');
      rethrow;
    }
  }

  Future<void> inicializarEstadosEstandar() async {
    final estadosEstandar = [
      {
        'denominacion': 'Procesando por Proveedor',
        'descripcion': 'La factura está siendo procesada por el proveedor',
        'color': '#FF9800',
        'orden': 1,
        'activo': true,
      },
      {
        'denominacion': 'Pagado a Proveedor',
        'descripcion': 'El pago ha sido realizado al proveedor',
        'color': '#2196F3',
        'orden': 2,
        'activo': true,
      },
      {
        'denominacion': 'En Recogida',
        'descripcion': 'La mercancía está en proceso de recogida',
        'color': '#9C27B0',
        'orden': 3,
        'activo': true,
      },
      {
        'denominacion': 'Finalizado',
        'descripcion': 'El proceso ha finalizado exitosamente',
        'color': '#4CAF50',
        'orden': 4,
        'activo': true,
      },
    ];

    for (final estado in estadosEstandar) {
      try {
        await _supabase.from('prv_nom_estado_factura').insert(estado);
      } catch (e) {
        if (!e.toString().contains('duplicate') &&
            !e.toString().contains('unique')) {
          print('❌ Error insertando estado estándar proveedor: $e');
        }
      }
    }
    print('✅ Estados estándar proveedor inicializados');
  }
}
