import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/depositos_bancarios.dart';
import '../utils/storage_key_sanitizer.dart';
import 'user_preferences_service.dart';

class DepositosBancariosService {
  static final DepositosBancariosService _instance =
      DepositosBancariosService._internal();
  factory DepositosBancariosService() => _instance;
  DepositosBancariosService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  // ==================== MONEDAS ====================

  Future<List<MonedaDeposito>> getMonedas({bool soloActivas = false}) async {
    try {
      var query = _supabase.from('dep_nom_moneda').select();
      if (soloActivas) {
        query = query.eq('activo', true);
      }
      final response = await query.order('codigo');
      return response
          .map<MonedaDeposito>((j) => MonedaDeposito.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo monedas: $e');
      rethrow;
    }
  }

  Future<MonedaDeposito> createMoneda(MonedaDeposito moneda) async {
    try {
      final response = await _supabase
          .from('dep_nom_moneda')
          .insert(moneda.toJson())
          .select()
          .single();
      return MonedaDeposito.fromJson(response);
    } catch (e) {
      print('❌ Error creando moneda: $e');
      rethrow;
    }
  }

  Future<MonedaDeposito> updateMoneda(int id, MonedaDeposito moneda) async {
    try {
      final response = await _supabase
          .from('dep_nom_moneda')
          .update(moneda.toJson())
          .eq('id', id)
          .select()
          .single();
      return MonedaDeposito.fromJson(response);
    } catch (e) {
      print('❌ Error actualizando moneda: $e');
      rethrow;
    }
  }

  Future<void> deactivateMoneda(int id) async {
    try {
      await _supabase
          .from('dep_nom_moneda')
          .update({'activo': false})
          .eq('id', id);
    } catch (e) {
      print('❌ Error desactivando moneda: $e');
      rethrow;
    }
  }

  Future<void> setMonedaActiva(int id, bool activo) async {
    try {
      await _supabase
          .from('dep_nom_moneda')
          .update({'activo': activo})
          .eq('id', id);
    } catch (e) {
      print('❌ Error cambiando activo moneda: $e');
      rethrow;
    }
  }

  // ==================== BANCOS ====================

  Future<List<BancoDeposito>> getBancos({bool soloActivos = false}) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      var query = _supabase
          .from('dep_dat_banco')
          .select('*, moneda:id_moneda(codigo, denominacion, simbolo)')
          .eq('idtienda', storeId);
      if (soloActivos) {
        query = query.eq('activo', true);
      }
      final response = await query.order('denominacion');
      return response
          .map<BancoDeposito>((j) => BancoDeposito.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo bancos: $e');
      rethrow;
    }
  }

  Future<BancoDeposito> createBanco({
    required String denominacion,
    required int idMoneda,
    String? observacion,
    bool activo = true,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('dep_dat_banco')
          .insert({
            'idtienda': storeId,
            'denominacion': denominacion,
            'id_moneda': idMoneda,
            'activo': activo,
            'observacion': observacion,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select('*, moneda:id_moneda(codigo, denominacion, simbolo)')
          .single();
      return BancoDeposito.fromJson(response);
    } catch (e) {
      print('❌ Error creando banco: $e');
      rethrow;
    }
  }

  Future<BancoDeposito> updateBanco({
    required int id,
    required String denominacion,
    required int idMoneda,
    String? observacion,
    required bool activo,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('dep_dat_banco')
          .update({
            'denominacion': denominacion,
            'id_moneda': idMoneda,
            'activo': activo,
            'observacion': observacion,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('idtienda', storeId)
          .select('*, moneda:id_moneda(codigo, denominacion, simbolo)')
          .single();
      return BancoDeposito.fromJson(response);
    } catch (e) {
      print('❌ Error actualizando banco: $e');
      rethrow;
    }
  }

  Future<void> deactivateBanco(int id) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      await _supabase
          .from('dep_dat_banco')
          .update({
            'activo': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .eq('idtienda', storeId);
    } catch (e) {
      print('❌ Error desactivando banco: $e');
      rethrow;
    }
  }

  // ==================== ESTADOS DE DEPÓSITO ====================

  Future<List<EstadoDeposito>> getEstados() async {
    try {
      final response = await _supabase
          .from('dep_nom_estado_deposito')
          .select()
          .order('orden');
      return response
          .map<EstadoDeposito>((j) => EstadoDeposito.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo estados de depósito: $e');
      rethrow;
    }
  }

  Future<EstadoDeposito> createEstado(EstadoDeposito estado) async {
    try {
      final response = await _supabase
          .from('dep_nom_estado_deposito')
          .insert(estado.toJson())
          .select()
          .single();
      return EstadoDeposito.fromJson(response);
    } catch (e) {
      print('❌ Error creando estado: $e');
      rethrow;
    }
  }

  Future<EstadoDeposito> updateEstado(int id, EstadoDeposito estado) async {
    try {
      final response = await _supabase
          .from('dep_nom_estado_deposito')
          .update(estado.toJson())
          .eq('id', id)
          .select()
          .single();
      return EstadoDeposito.fromJson(response);
    } catch (e) {
      print('❌ Error actualizando estado: $e');
      rethrow;
    }
  }

  Future<void> deleteEstado(int id) async {
    try {
      await _supabase.from('dep_nom_estado_deposito').delete().eq('id', id);
    } catch (e) {
      print('❌ Error eliminando estado: $e');
      rethrow;
    }
  }

  Future<EstadoDeposito?> getEstadoInicial() async {
    try {
      final response = await _supabase
          .from('dep_nom_estado_deposito')
          .select()
          .eq('activo', true)
          .order('orden', ascending: true)
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return EstadoDeposito.fromJson(response);
    } catch (e) {
      print('❌ Error obteniendo estado inicial: $e');
      return null;
    }
  }

  // ==================== SALDO DISPONIBLE ====================

  Future<double> getSaldoDisponible(int idBanco) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('dep_dat_saldo')
          .select('saldo_disponible')
          .eq('idtienda', storeId)
          .eq('id_banco', idBanco)
          .maybeSingle();

      if (response == null) return 0.0;
      return (response['saldo_disponible'] ?? 0.0).toDouble();
    } catch (e) {
      print('❌ Error obteniendo saldo: $e');
      return 0.0;
    }
  }

  Future<void> _upsertSaldo(
    int storeId,
    int idBanco,
    double nuevoSaldo,
    double saldoAnterior,
    String tipoOperacion,
    String referencia, {
    int? idRecarga,
  }) async {
    await _supabase.from('dep_dat_saldo').upsert({
      'idtienda': storeId,
      'id_banco': idBanco,
      'saldo_disponible': nuevoSaldo,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'idtienda,id_banco');

    final histRow = <String, dynamic>{
      'idtienda': storeId,
      'id_banco': idBanco,
      'monto_anterior': saldoAnterior,
      'monto_nuevo': nuevoSaldo,
      'diferencia': nuevoSaldo - saldoAnterior,
      'tipo_operacion': tipoOperacion,
      'referencia': referencia,
      'created_at': DateTime.now().toIso8601String(),
    };
    if (idRecarga != null) histRow['id_recarga'] = idRecarga;

    await _supabase.from('dep_hist_saldo').insert(histRow);
  }

  // ==================== RECARGAS DE SALDO ====================

  Future<List<RecargaSaldoDeposito>> getRecargas(int idBanco) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('dep_dat_recarga_saldo')
          .select()
          .eq('idtienda', storeId)
          .eq('id_banco', idBanco)
          .order('created_at', ascending: false);

      return response
          .map<RecargaSaldoDeposito>((j) => RecargaSaldoDeposito.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo recargas: $e');
      rethrow;
    }
  }

  Future<void> agregarRecarga({
    required int idBanco,
    required double monto,
    required DateTime fechaPago,
    String? observacion,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final saldoActual = await getSaldoDisponible(idBanco);
      final nuevoSaldo = saldoActual + monto;

      final recargaRow = await _supabase
          .from('dep_dat_recarga_saldo')
          .insert({
            'idtienda': storeId,
            'id_banco': idBanco,
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
        idBanco,
        nuevoSaldo,
        saldoActual,
        'recarga',
        refRecarga,
        idRecarga: recargaId,
      );

      print(
        '✅ Recarga de \$${monto.toStringAsFixed(2)} registrada. Nuevo saldo: \$${nuevoSaldo.toStringAsFixed(2)}',
      );
    } catch (e) {
      print('❌ Error agregando recarga: $e');
      rethrow;
    }
  }

  /// Cancela un pago (recarga): resta el monto del saldo y elimina recarga + historial.
  Future<void> cancelarPagoRecarga({
    required int idBanco,
    required int idRecarga,
    int? idHistorial,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final recargaRow = await _supabase
          .from('dep_dat_recarga_saldo')
          .select('id, monto')
          .eq('id', idRecarga)
          .eq('idtienda', storeId)
          .eq('id_banco', idBanco)
          .maybeSingle();
      if (recargaRow == null) {
        throw Exception('No se encontró el pago a cancelar');
      }

      final monto = (recargaRow['monto'] as num).toDouble();
      final saldoActual = await getSaldoDisponible(idBanco);
      if (saldoActual < monto) {
        throw Exception(
          'Saldo insuficiente para cancelar este pago. '
          'Saldo actual: \$${saldoActual.toStringAsFixed(2)}, '
          'monto del pago: \$${monto.toStringAsFixed(2)}',
        );
      }

      if (idHistorial != null) {
        await _supabase
            .from('dep_hist_saldo')
            .delete()
            .eq('id', idHistorial)
            .eq('idtienda', storeId)
            .eq('id_banco', idBanco);
      } else {
        await _supabase
            .from('dep_hist_saldo')
            .delete()
            .eq('id_recarga', idRecarga)
            .eq('idtienda', storeId)
            .eq('id_banco', idBanco);
      }

      await _supabase
          .from('dep_dat_recarga_saldo')
          .delete()
          .eq('id', idRecarga)
          .eq('idtienda', storeId)
          .eq('id_banco', idBanco);

      await _supabase.from('dep_dat_saldo').upsert({
        'idtienda': storeId,
        'id_banco': idBanco,
        'saldo_disponible': saldoActual - monto,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'idtienda,id_banco');

      print(
        '✅ Pago recarga #$idRecarga cancelado. Monto descontado: \$${monto.toStringAsFixed(2)}',
      );
    } catch (e) {
      print('❌ Error cancelando pago: $e');
      rethrow;
    }
  }

  /// Resuelve el id de recarga asociado a un movimiento del historial.
  int? resolverRecargaId(
    HistorialSaldoDeposito historial,
    List<RecargaSaldoDeposito> recargas,
  ) {
    if (historial.idRecarga != null) return historial.idRecarga;

    RecargaSaldoDeposito? mejor;
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

  Future<List<HistorialSaldoDeposito>> getHistorialSaldo(int idBanco) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      List<dynamic> response;
      try {
        response = await _supabase
            .from('dep_hist_saldo')
            .select('*, recarga:dep_dat_recarga_saldo(observacion)')
            .eq('idtienda', storeId)
            .eq('id_banco', idBanco)
            .order('created_at', ascending: false)
            .limit(100);
      } catch (_) {
        response = await _supabase
            .from('dep_hist_saldo')
            .select(
              'id, idtienda, id_banco, monto_anterior, monto_nuevo, diferencia, tipo_operacion, referencia, id_recarga, created_at',
            )
            .eq('idtienda', storeId)
            .eq('id_banco', idBanco)
            .order('created_at', ascending: false)
            .limit(100);
      }

      return response
          .map<HistorialSaldoDeposito>(
            (j) => HistorialSaldoDeposito.fromJson(j),
          )
          .toList();
    } catch (e) {
      print('❌ Error obteniendo historial de saldo: $e');
      rethrow;
    }
  }

  // ==================== DEPÓSITOS ====================

  Future<List<DepositoBancario>> getDepositos(int idBanco) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('dep_dat_deposito')
          .select(
            '*, estado:id_estado(denominacion, color), banco:id_banco(denominacion), fotos:dep_dat_deposito_foto(id, id_deposito, foto_url, numero_pagina, nombre_archivo, mime_type, created_at)',
          )
          .eq('idtienda', storeId)
          .eq('id_banco', idBanco)
          .order('created_at', ascending: false);

      return response
          .map<DepositoBancario>((j) => DepositoBancario.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo depósitos: $e');
      rethrow;
    }
  }

  Future<List<DepositoFoto>> getFotosDeposito(int idDeposito) async {
    try {
      final response = await _supabase
          .from('dep_dat_deposito_foto')
          .select()
          .eq('id_deposito', idDeposito)
          .order('numero_pagina', ascending: true);
      return response
          .map<DepositoFoto>((j) => DepositoFoto.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo fotos de depósito: $e');
      rethrow;
    }
  }

  Future<DepositoFoto> agregarFotoDeposito({
    required int idDeposito,
    required Uint8List bytes,
    required String fileName,
    required int numeroPagina,
    String mimeType = 'image/jpeg',
    String? nombreArchivo,
  }) async {
    try {
      final url = await uploadDepositoFoto(
        bytes,
        fileName,
        contentType: mimeType,
      );
      if (url == null) throw Exception('No se pudo subir el archivo');

      final response = await _supabase
          .from('dep_dat_deposito_foto')
          .insert({
            'id_deposito': idDeposito,
            'foto_url': url,
            'numero_pagina': numeroPagina,
            'mime_type': mimeType,
            'nombre_archivo': nombreArchivo ?? fileName,
          })
          .select()
          .single();

      print(
        '✅ Archivo p.$numeroPagina añadido a depósito $idDeposito ($mimeType)',
      );
      return DepositoFoto.fromJson(response);
    } catch (e) {
      print('❌ Error añadiendo archivo: $e');
      rethrow;
    }
  }

  Future<void> eliminarFotoDeposito(int idFoto) async {
    try {
      await _supabase.from('dep_dat_deposito_foto').delete().eq('id', idFoto);
      print('✅ Foto $idFoto eliminada');
    } catch (e) {
      print('❌ Error eliminando foto: $e');
      rethrow;
    }
  }

  Future<DepositoBancario> crearDeposito({
    required int idBanco,
    required String numeroDeposito,
    required double valor,
    required DateTime fechaProcesamiento,
    List<({Uint8List bytes, String nombre, String mimeType})> fotosEntradas =
        const [],
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final saldoActual = await getSaldoDisponible(idBanco);
      if (saldoActual < valor) {
        throw Exception(
          'Saldo insuficiente. Saldo disponible: \$${saldoActual.toStringAsFixed(2)}, valor de depósito: \$${valor.toStringAsFixed(2)}',
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
        'id_banco': idBanco,
        'numero_deposito': numeroDeposito,
        'valor': valor,
        'fecha_procesamiento': fechaProcesamiento
            .toIso8601String()
            .split('T')
            .first,
        'id_estado': estadoInicial.id,
        'created_at': DateTime.now().toIso8601String(),
      };
      print('🔍 Insertando depósito con id_estado=${insertData['id_estado']}');

      final response = await _supabase
          .from('dep_dat_deposito')
          .insert(insertData)
          .select(
            '*, estado:id_estado(denominacion, color), banco:id_banco(denominacion)',
          )
          .single();

      print(
        '🔍 Respuesta insert depósito: id_estado=${response['id_estado']} estado=${response['estado']}',
      );

      final deposito = DepositoBancario.fromJson(response);

      for (int i = 0; i < fotosEntradas.length; i++) {
        final entrada = fotosEntradas[i];
        await agregarFotoDeposito(
          idDeposito: deposito.id!,
          bytes: entrada.bytes,
          fileName: entrada.nombre,
          numeroPagina: i + 1,
          mimeType: entrada.mimeType,
          nombreArchivo: entrada.nombre,
        );
      }

      await _upsertSaldo(
        storeId,
        idBanco,
        saldoActual - valor,
        saldoActual,
        'descuento_deposito',
        'Depósito #$numeroDeposito: -\$${valor.toStringAsFixed(2)}',
      );

      await _supabase.from('dep_hist_estado_deposito').insert({
        'id_deposito': deposito.id,
        'id_estado_anterior': estadoInicial.id,
        'id_estado_nuevo': estadoInicial.id,
        'observacion': 'Depósito creado',
        'created_at': DateTime.now().toIso8601String(),
      });

      print(
        '✅ Depósito #$numeroDeposito creado con ${fotosEntradas.length} foto(s). Saldo descontado: \$${valor.toStringAsFixed(2)}',
      );
      return deposito;
    } catch (e) {
      print('❌ Error creando depósito: $e');
      rethrow;
    }
  }

  Future<void> cambiarEstadoDeposito({
    required int idDeposito,
    required int idEstadoAnterior,
    required int idEstadoNuevo,
    String? observacion,
  }) async {
    try {
      await _supabase
          .from('dep_dat_deposito')
          .update({'id_estado': idEstadoNuevo})
          .eq('id', idDeposito);

      await _supabase.from('dep_hist_estado_deposito').insert({
        'id_deposito': idDeposito,
        'id_estado_anterior': idEstadoAnterior,
        'id_estado_nuevo': idEstadoNuevo,
        'observacion': observacion,
        'created_at': DateTime.now().toIso8601String(),
      });

      print(
        '✅ Estado de depósito $idDeposito cambiado de $idEstadoAnterior a $idEstadoNuevo',
      );
    } catch (e) {
      print('❌ Error cambiando estado de depósito: $e');
      rethrow;
    }
  }

  Future<List<HistorialEstadoDeposito>> getHistorialEstadoDeposito(
    int idDeposito,
  ) async {
    try {
      final response = await _supabase
          .from('dep_hist_estado_deposito')
          .select(
            '*, estado_anterior:id_estado_anterior(denominacion), estado_nuevo:id_estado_nuevo(denominacion)',
          )
          .eq('id_deposito', idDeposito)
          .order('created_at', ascending: false);

      return response
          .map<HistorialEstadoDeposito>(
            (j) => HistorialEstadoDeposito.fromJson(j),
          )
          .toList();
    } catch (e) {
      print('❌ Error obteniendo historial de estados: $e');
      rethrow;
    }
  }

  // ==================== FOTO DE DEPÓSITO ====================

  Future<String?> uploadDepositoFoto(
    Uint8List imageBytes,
    String fileName, {
    String contentType = 'image/jpeg',
  }) async {
    try {
      final uniqueFileName =
          'deposito_bancario_${DateTime.now().millisecondsSinceEpoch}_${sanitizeStorageKey(fileName)}';
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
      if (response.isEmpty) throw Exception('Error al subir foto de depósito');
      final url = _supabase.storage
          .from('images_back')
          .getPublicUrl(uniqueFileName);
      print('✅ Foto de depósito subida: $url');
      return url;
    } catch (e) {
      print('❌ Error subiendo foto de depósito: $e');
      return null;
    }
  }

  Future<void> actualizarDetallesDeposito({
    required int idBanco,
    required int idDeposito,
    required String numeroDepositoAnterior,
    required String nuevoNumeroDeposito,
    required double valorAnterior,
    required double nuevoValor,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final diferencia = nuevoValor - valorAnterior;

      if (diferencia > 0) {
        final saldoActual = await getSaldoDisponible(idBanco);
        if (saldoActual < diferencia) {
          throw Exception(
            'Saldo insuficiente para aumentar el valor. Diferencia: \$${diferencia.toStringAsFixed(2)}, saldo disponible: \$${saldoActual.toStringAsFixed(2)}',
          );
        }
      }

      await _supabase
          .from('dep_dat_deposito')
          .update({'numero_deposito': nuevoNumeroDeposito, 'valor': nuevoValor})
          .eq('id', idDeposito);

      if (diferencia != 0) {
        final saldoActual = await getSaldoDisponible(idBanco);
        final nuevoSaldo = saldoActual - diferencia;
        await _upsertSaldo(
          storeId,
          idBanco,
          nuevoSaldo,
          saldoActual,
          'ajuste_deposito',
          'Ajuste Depósito #$nuevoNumeroDeposito: ${diferencia > 0 ? '-' : '+'}\$${diferencia.abs().toStringAsFixed(2)}',
        );
      }

      print(
        '✅ Depósito #$nuevoNumeroDeposito actualizado. Diferencia de saldo: \$${diferencia.toStringAsFixed(2)}',
      );
    } catch (e) {
      print('❌ Error actualizando detalles de depósito: $e');
      rethrow;
    }
  }

  Future<void> actualizarFotoDeposito(int idDeposito, String fotoUrl) async {
    try {
      await _supabase
          .from('dep_dat_deposito')
          .update({'foto_url': fotoUrl})
          .eq('id', idDeposito);
      print('✅ foto_url actualizada en depósito $idDeposito');
    } catch (e) {
      print('❌ Error actualizando foto de depósito: $e');
      rethrow;
    }
  }

  Future<void> inicializarEstadosEstandar() async {
    final estadosEstandar = [
      {
        'denominacion': 'Registrado',
        'descripcion': 'Depósito registrado pendiente de confirmación',
        'color': '#FF9800',
        'orden': 1,
        'activo': true,
      },
      {
        'denominacion': 'Confirmado',
        'descripcion': 'Depósito confirmado por el banco',
        'color': '#2196F3',
        'orden': 2,
        'activo': true,
      },
      {
        'denominacion': 'En Proceso',
        'descripcion': 'Depósito en proceso de acreditación',
        'color': '#9C27B0',
        'orden': 3,
        'activo': true,
      },
      {
        'denominacion': 'Finalizado',
        'descripcion': 'Depósito acreditado / finalizado',
        'color': '#4CAF50',
        'orden': 4,
        'activo': true,
      },
    ];

    for (final estado in estadosEstandar) {
      try {
        await _supabase.from('dep_nom_estado_deposito').insert(estado);
      } catch (e) {
        if (!e.toString().contains('duplicate') &&
            !e.toString().contains('unique')) {
          print('❌ Error insertando estado estándar: $e');
        }
      }
    }
    print('✅ Estados estándar inicializados');
  }
}
