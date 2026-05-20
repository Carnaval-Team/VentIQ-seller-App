import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/importadora_factura.dart';
import 'user_preferences_service.dart';

class ImportadoraFacturasService {
  static final ImportadoraFacturasService _instance =
      ImportadoraFacturasService._internal();
  factory ImportadoraFacturasService() => _instance;
  ImportadoraFacturasService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  // ==================== ESTADOS DE FACTURA (NOMENCLADOR) ====================

  Future<List<EstadoFactura>> getEstados() async {
    try {
      final response = await _supabase
          .from('imp_nom_estado_factura')
          .select()
          .order('orden');
      return response
          .map<EstadoFactura>((j) => EstadoFactura.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo estados de factura: $e');
      rethrow;
    }
  }

  Future<EstadoFactura> createEstado(EstadoFactura estado) async {
    try {
      final response =
          await _supabase
              .from('imp_nom_estado_factura')
              .insert(estado.toJson())
              .select()
              .single();
      return EstadoFactura.fromJson(response);
    } catch (e) {
      print('❌ Error creando estado: $e');
      rethrow;
    }
  }

  Future<EstadoFactura> updateEstado(int id, EstadoFactura estado) async {
    try {
      final response =
          await _supabase
              .from('imp_nom_estado_factura')
              .update(estado.toJson())
              .eq('id', id)
              .select()
              .single();
      return EstadoFactura.fromJson(response);
    } catch (e) {
      print('❌ Error actualizando estado: $e');
      rethrow;
    }
  }

  Future<void> deleteEstado(int id) async {
    try {
      await _supabase.from('imp_nom_estado_factura').delete().eq('id', id);
    } catch (e) {
      print('❌ Error eliminando estado: $e');
      rethrow;
    }
  }

  Future<EstadoFactura?> getEstadoInicial() async {
    try {
      final response = await _supabase
          .from('imp_nom_estado_factura')
          .select()
          .eq('activo', true)
          .order('orden', ascending: true)
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return EstadoFactura.fromJson(response);
    } catch (e) {
      print('❌ Error obteniendo estado inicial: $e');
      return null;
    }
  }

  // ==================== SALDO DISPONIBLE ====================

  Future<double> getSaldoDisponible() async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('imp_dat_saldo')
          .select('saldo_disponible')
          .eq('idtienda', storeId)
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
    double nuevoSaldo,
    double saldoAnterior,
    String tipoOperacion,
    String referencia,
  ) async {
    await _supabase.from('imp_dat_saldo').upsert({
      'idtienda': storeId,
      'saldo_disponible': nuevoSaldo,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'idtienda');

    await _supabase.from('imp_hist_saldo').insert({
      'idtienda': storeId,
      'monto_anterior': saldoAnterior,
      'monto_nuevo': nuevoSaldo,
      'diferencia': nuevoSaldo - saldoAnterior,
      'tipo_operacion': tipoOperacion,
      'referencia': referencia,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ==================== RECARGAS DE SALDO ====================

  Future<List<RecargaSaldo>> getRecargas() async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('imp_dat_recarga_saldo')
          .select()
          .eq('idtienda', storeId)
          .order('created_at', ascending: false);

      return response
          .map<RecargaSaldo>((j) => RecargaSaldo.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo recargas: $e');
      rethrow;
    }
  }

  Future<void> agregarRecarga({
    required double monto,
    required DateTime fechaPago,
    String? observacion,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final saldoActual = await getSaldoDisponible();
      final nuevoSaldo = saldoActual + monto;

      await _supabase.from('imp_dat_recarga_saldo').insert({
        'idtienda': storeId,
        'monto': monto,
        'fecha_pago': fechaPago.toIso8601String().split('T').first,
        'observacion': observacion,
        'created_at': DateTime.now().toIso8601String(),
      });

      await _upsertSaldo(
        storeId,
        nuevoSaldo,
        saldoActual,
        'recarga',
        'Recarga de saldo: \$${monto.toStringAsFixed(2)}',
      );

      print('✅ Recarga de \$${monto.toStringAsFixed(2)} registrada. Nuevo saldo: \$${nuevoSaldo.toStringAsFixed(2)}');
    } catch (e) {
      print('❌ Error agregando recarga: $e');
      rethrow;
    }
  }

  // ==================== HISTORIAL DE SALDO ====================

  Future<List<HistorialSaldo>> getHistorialSaldo() async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('imp_hist_saldo')
          .select()
          .eq('idtienda', storeId)
          .order('created_at', ascending: false)
          .limit(100);

      return response
          .map<HistorialSaldo>((j) => HistorialSaldo.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo historial de saldo: $e');
      rethrow;
    }
  }

  // ==================== FACTURAS ====================

  Future<List<ImportadoraFactura>> getFacturas() async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final response = await _supabase
          .from('imp_dat_factura')
          .select('*, estado:id_estado(denominacion, color)')
          .eq('idtienda', storeId)
          .order('created_at', ascending: false);

      return response
          .map<ImportadoraFactura>((j) => ImportadoraFactura.fromJson(j))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo facturas: $e');
      rethrow;
    }
  }

  Future<ImportadoraFactura> crearFactura({
    required String numeroFactura,
    required double valor,
    required DateTime fechaProcesamiento,
    String? fotoUrl,
  }) async {
    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener ID de tienda');

      final saldoActual = await getSaldoDisponible();
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

      print('🔍 Estado inicial resuelto: id=${estadoInicial.id} denominacion=${estadoInicial.denominacion} orden=${estadoInicial.orden}');

      final insertData = {
        'idtienda': storeId,
        'numero_factura': numeroFactura,
        'valor': valor,
        'fecha_procesamiento':
            fechaProcesamiento.toIso8601String().split('T').first,
        'foto_url': fotoUrl,
        'id_estado': estadoInicial.id,
        'created_at': DateTime.now().toIso8601String(),
      };
      print('🔍 Insertando factura con id_estado=${insertData['id_estado']}');

      final response = await _supabase
          .from('imp_dat_factura')
          .insert(insertData)
          .select('*, estado:id_estado(denominacion, color)')
          .single();

      print('🔍 Respuesta insert factura: id_estado=${response['id_estado']} estado=${response['estado']}');

      final factura = ImportadoraFactura.fromJson(response);

      await _upsertSaldo(
        storeId,
        saldoActual - valor,
        saldoActual,
        'descuento_factura',
        'Factura #$numeroFactura: -\$${valor.toStringAsFixed(2)}',
      );

      await _supabase.from('imp_hist_estado_factura').insert({
        'id_factura': factura.id,
        'id_estado_anterior': estadoInicial.id,
        'id_estado_nuevo': estadoInicial.id,
        'observacion': 'Factura creada',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Factura #$numeroFactura creada. Saldo descontado: \$${valor.toStringAsFixed(2)}');
      return factura;
    } catch (e) {
      print('❌ Error creando factura: $e');
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
          .from('imp_dat_factura')
          .update({'id_estado': idEstadoNuevo})
          .eq('id', idFactura);

      await _supabase.from('imp_hist_estado_factura').insert({
        'id_factura': idFactura,
        'id_estado_anterior': idEstadoAnterior,
        'id_estado_nuevo': idEstadoNuevo,
        'observacion': observacion,
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Estado de factura $idFactura cambiado de $idEstadoAnterior a $idEstadoNuevo');
    } catch (e) {
      print('❌ Error cambiando estado de factura: $e');
      rethrow;
    }
  }

  Future<List<HistorialEstadoFactura>> getHistorialEstadoFactura(
    int idFactura,
  ) async {
    try {
      final response = await _supabase
          .from('imp_hist_estado_factura')
          .select(
            '*, estado_anterior:id_estado_anterior(denominacion), estado_nuevo:id_estado_nuevo(denominacion)',
          )
          .eq('id_factura', idFactura)
          .order('created_at', ascending: false);

      return response
          .map<HistorialEstadoFactura>(
            (j) => HistorialEstadoFactura.fromJson(j),
          )
          .toList();
    } catch (e) {
      print('❌ Error obteniendo historial de estados: $e');
      rethrow;
    }
  }

  // ==================== FOTO DE FACTURA ====================

  Future<String?> uploadFacturaFoto(Uint8List imageBytes, String fileName) async {
    try {
      final uniqueFileName =
          'factura_${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final response = await _supabase.storage
          .from('images_back')
          .uploadBinary(
            uniqueFileName,
            imageBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
      if (response.isEmpty) throw Exception('Error al subir foto de factura');
      final url = _supabase.storage.from('images_back').getPublicUrl(uniqueFileName);
      print('✅ Foto de factura subida: $url');
      return url;
    } catch (e) {
      print('❌ Error subiendo foto de factura: $e');
      return null;
    }
  }

  Future<void> actualizarFotoFactura(int idFactura, String fotoUrl) async {
    try {
      await _supabase
          .from('imp_dat_factura')
          .update({'foto_url': fotoUrl})
          .eq('id', idFactura);
      print('✅ foto_url actualizada en factura $idFactura');
    } catch (e) {
      print('❌ Error actualizando foto de factura: $e');
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
        'denominacion': 'Pagado a Importadora',
        'descripcion': 'El pago ha sido realizado a la importadora',
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
        await _supabase.from('imp_nom_estado_factura').insert(estado);
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
