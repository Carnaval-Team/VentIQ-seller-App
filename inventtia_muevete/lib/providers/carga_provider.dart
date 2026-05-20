import 'package:flutter/foundation.dart';

import '../models/carga_model.dart';
import '../models/estado_carga_model.dart';
import '../models/oferta_carga_model.dart';
import '../services/carga_service.dart';
import '../services/oferta_carga_service.dart';

class CargaProvider extends ChangeNotifier {
  final _cargaService = CargaService();
  final _ofertaService = OfertaCargaService();

  // ── State ────────────────────────────────────────────────────────────────
  List<CargaModel> _misCargas = [];          // shipper: sus cargas publicadas
  List<CargaModel> _cargasDisponibles = [];  // carrier: cargas para ofertar
  List<CargaModel> _cargasActivas = [];      // carrier/dispatcher: en curso
  List<OfertaCargaModel> _misOfertas = [];   // carrier: ofertas enviadas
  List<OfertaCargaModel> _ofertasCarga = []; // shipper: ofertas recibidas
  CargaModel? _cargaDetalle;

  List<EstadoCargaModel> _historialEstados = [];
  List<NomEstadoModel> _nomEstados = [];

  bool _loadingMisCargas = false;
  bool _loadingDisponibles = false;
  bool _loadingOfertas = false;
  bool _loadingHistorial = false;
  bool _actionLoading = false;
  String? _error;

  // Filtros carrier
  String? filtroTipoEquipo;
  String? filtroCiudadOrigen;
  String? filtroCiudadDestino;

  // ── Getters ───────────────────────────────────────────────────────────────
  List<CargaModel> get misCargas => _misCargas;
  List<CargaModel> get cargasDisponibles => _cargasDisponibles;
  List<CargaModel> get cargasActivas => _cargasActivas;
  List<OfertaCargaModel> get misOfertas => _misOfertas;
  List<OfertaCargaModel> get ofertasCarga => _ofertasCarga;
  CargaModel? get cargaDetalle => _cargaDetalle;

  List<EstadoCargaModel> get historialEstados => _historialEstados;
  List<NomEstadoModel> get nomEstados => _nomEstados;

  bool get loadingMisCargas => _loadingMisCargas;
  bool get loadingDisponibles => _loadingDisponibles;
  bool get loadingOfertas => _loadingOfertas;
  bool get loadingHistorial => _loadingHistorial;
  bool get actionLoading => _actionLoading;
  String? get error => _error;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── SHIPPER ───────────────────────────────────────────────────────────────

  Future<void> loadMisCargas(String shipperUuid) async {
    _loadingMisCargas = true;
    _error = null;
    notifyListeners();
    try {
      _misCargas = await _cargaService.getCargasShipper(shipperUuid);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingMisCargas = false;
      notifyListeners();
    }
  }

  Future<bool> publicarCarga(CargaModel carga) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      final nueva = await _cargaService.publicarCarga(carga);
      if (nueva != null) {
        _misCargas = [nueva, ..._misCargas];
      }
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadOfertasCarga(int cargaId) async {
    _loadingOfertas = true;
    _error = null;
    notifyListeners();
    try {
      _ofertasCarga = await _ofertaService.getOfertasCarga(cargaId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingOfertas = false;
      notifyListeners();
    }
  }

  Future<bool> aceptarOferta(
      int ofertaId, int cargaId, int driverId) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _ofertaService.aceptarOferta(ofertaId, cargaId, driverId);
      // Update local state
      _ofertasCarga = _ofertasCarga
          .map((o) => o.id == ofertaId
              ? OfertaCargaModel.fromJson(
                  {..._ofertaJsonMap(o), 'estado': 'aceptada'})
              : o)
          .toList();
      _misCargas = _misCargas
          .map((c) => c.id == cargaId
              ? CargaModel.fromJson(
                  {..._cargaJsonMap(c), 'estado': 'aceptada'})
              : c)
          .toList();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<bool> cancelarCarga(int cargaId, {String? usuarioUuid}) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _cargaService.cancelarCarga(cargaId, usuarioUuid: usuarioUuid);
      _refreshCargaEstado(cargaId, 'cancelada');
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  // ── CARRIER ───────────────────────────────────────────────────────────────

  Future<void> loadCargasDisponibles() async {
    _loadingDisponibles = true;
    _error = null;
    notifyListeners();
    try {
      _cargasDisponibles = await _cargaService.getCargasDisponibles(
        tipoEquipo: filtroTipoEquipo,
        ciudadOrigen: filtroCiudadOrigen,
        ciudadDestino: filtroCiudadDestino,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingDisponibles = false;
      notifyListeners();
    }
  }

  Future<void> loadCargasCarrier(int driverId) async {
    _loadingMisCargas = true;
    _error = null;
    notifyListeners();
    try {
      _cargasActivas = await _cargaService.getCargasCarrier(driverId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingMisCargas = false;
      notifyListeners();
    }
  }

  Future<void> loadMisOfertas(int driverId) async {
    _loadingOfertas = true;
    _error = null;
    notifyListeners();
    try {
      _misOfertas = await _ofertaService.getOfertasCarrier(driverId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingOfertas = false;
      notifyListeners();
    }
  }

  Future<bool> enviarOferta(OfertaCargaModel oferta) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      final nueva = await _ofertaService.hacerOferta(oferta);
      if (nueva != null) {
        _misOfertas = [nueva, ..._misOfertas];
      }
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<bool> retirarOferta(int ofertaId) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _ofertaService.retirarOferta(ofertaId);
      _misOfertas = _misOfertas
          .map((o) => o.id == ofertaId
              ? OfertaCargaModel.fromJson(
                  {..._ofertaJsonMap(o), 'estado': 'retirada'})
              : o)
          .toList();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmarRecogida(int cargaId, {int? driverId}) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _cargaService.confirmarRecogida(cargaId, driverId: driverId);
      _refreshCargaEstado(cargaId, 'en_transito');
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmarEntrega(int cargaId, {int? driverId}) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _cargaService.confirmarEntrega(cargaId, driverId: driverId);
      _refreshCargaEstado(cargaId, 'completada_carrier');
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<bool> marcarComoTomada(
    int cargaId, {
    required int carrierDriverId,
    required String carrierUuid,
    String? shipperUuid,
  }) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _cargaService.marcarComoTomada(
        cargaId,
        carrierDriverId: carrierDriverId,
        carrierUuid: carrierUuid,
        shipperUuid: shipperUuid,
      );
      _refreshCargaEstado(cargaId, 'tomada');
      // Remove from available loads list
      _cargasDisponibles =
          _cargasDisponibles.where((c) => c.id != cargaId).toList();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<bool> completarCargaCarrier(int cargaId, {int? driverId}) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _cargaService.completarCargaCarrier(cargaId, driverId: driverId);
      _refreshCargaEstado(cargaId, 'completada_carrier');
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<bool> completarCargaShipper(int cargaId, {String? shipperUuid}) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _cargaService.completarCargaShipper(cargaId,
          shipperUuid: shipperUuid);
      _refreshCargaEstado(cargaId, 'completada');
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCargasCarrierByUuid(String carrierUuid) async {
    _loadingMisCargas = true;
    _error = null;
    notifyListeners();
    try {
      _cargasActivas =
          await _cargaService.getCargasCarrierByUuid(carrierUuid);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingMisCargas = false;
      notifyListeners();
    }
  }

  // ── DISPATCHER ────────────────────────────────────────────────────────────

  Future<void> loadCargasDispatcher(List<int> carrierIds) async {
    _loadingMisCargas = true;
    _error = null;
    notifyListeners();
    try {
      _cargasActivas =
          await _cargaService.getCargasDispatcher(carrierIds);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingMisCargas = false;
      notifyListeners();
    }
  }

  Future<bool> asignarCargaACarrier(
      int cargaId, int carrierDriverId, {String? usuarioUuid}) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _cargaService.asignarCargaACarrier(
          cargaId, carrierDriverId, usuarioUuid: usuarioUuid);
      _cargasDisponibles =
          _cargasDisponibles.where((c) => c.id != cargaId).toList();
      _refreshCargaEstado(cargaId, 'aceptada');
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  // ── Historial de estados ──────────────────────────────────────────────────

  Future<void> loadHistorialEstados(int cargaId) async {
    _loadingHistorial = true;
    _error = null;
    notifyListeners();
    try {
      _historialEstados =
          await _cargaService.getHistorialEstados(cargaId);
      if (_nomEstados.isEmpty) {
        _nomEstados = await _cargaService.getNomEstados();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loadingHistorial = false;
      notifyListeners();
    }
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  Future<void> loadCargaDetalle(int id) async {
    _error = null;
    notifyListeners();
    try {
      _cargaDetalle = await _cargaService.getCargaById(id);
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  void setFiltros({
    String? tipoEquipo,
    String? ciudadOrigen,
    String? ciudadDestino,
  }) {
    filtroTipoEquipo = tipoEquipo;
    filtroCiudadOrigen = ciudadOrigen;
    filtroCiudadDestino = ciudadDestino;
    notifyListeners();
  }

  void resetFiltros() {
    filtroTipoEquipo = null;
    filtroCiudadOrigen = null;
    filtroCiudadDestino = null;
    notifyListeners();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _refreshCargaEstado(int cargaId, String estado) {
    _cargasActivas = _cargasActivas
        .map((c) => c.id == cargaId
            ? CargaModel.fromJson({..._cargaJsonMap(c), 'estado': estado})
            : c)
        .toList();
    _cargasDisponibles = _cargasDisponibles
        .map((c) => c.id == cargaId
            ? CargaModel.fromJson({..._cargaJsonMap(c), 'estado': estado})
            : c)
        .toList();
  }

  Map<String, dynamic> _cargaJsonMap(CargaModel c) => {
        'id': c.id,
        'shipper_id': c.shipperId,
        'tipo': c.tipo,
        'estado': c.estado,
        'dir_origen': c.dirOrigen,
        'lat_origen': c.latOrigen,
        'lon_origen': c.lonOrigen,
        'ciudad_origen': c.ciudadOrigen,
        'estado_origen': c.estadoOrigen,
        'pais_origen': c.paisOrigen,
        'dir_destino': c.dirDestino,
        'lat_destino': c.latDestino,
        'lon_destino': c.lonDestino,
        'ciudad_destino': c.ciudadDestino,
        'estado_destino': c.estadoDestino,
        'pais_destino': c.paisDestino,
        'descripcion': c.descripcion,
        'tipo_mercancia_id': c.tipoMercanciaId,
        'peso_kg': c.pesoKg,
        'volumen_m3': c.volumenM3,
        'valor_declarado': c.valorDeclarado,
        'requiere_refrigeracion': c.requiereRefrigeracion,
        'requiere_seguro': c.requiereSeguro,
        'instrucciones': c.instrucciones,
        'tipo_equipo': c.tipoEquipo,
        'fecha_recogida': c.fechaRecogida?.toIso8601String().split('T').first,
        'fecha_entrega': c.fechaEntrega?.toIso8601String().split('T').first,
        'precio_ofertado': c.precioOfertado,
        'precio_final': c.precioFinal,
        'moneda': c.moneda,
        'destacada': c.destacada,
        'es_ltl': c.esLtl,
        'es_recurrente': c.esRecurrente,
        'carrier_driver_id': c.carrierDriverId,
        'carrier_uuid': c.carrierUuid,
        'oferta_aceptada_id': c.ofertaAceptadaId,
        'ultima_lat': c.ultimaLat,
        'ultima_lon': c.ultimaLon,
        'distancia_km': c.distanciaKm,
        'distancia_millas': c.distanciaMillas,
        'unidad_peso': c.unidadPeso,
        'horas_carga': c.horasCarga,
        'horas_descarga': c.horasDescarga,
        'created_at': c.createdAt.toIso8601String(),
        'updated_at': c.updatedAt?.toIso8601String(),
        'shipper_nombre': c.shipperNombre,
        'carrier_nombre': c.carrierNombre,
        'ofertas_count': c.ofertasCount,
      };

  Map<String, dynamic> _ofertaJsonMap(OfertaCargaModel o) => {
        'id': o.id,
        'carga_id': o.cargaId,
        'driver_id': o.driverId,
        'precio': o.precio,
        'tarifa_por_milla': o.tarifaPorMilla,
        'tiempo_estimado_dias': o.tiempoEstimadoDias,
        'fecha_recogida_prop':
            o.fechaRecogidaProp?.toIso8601String().split('T').first,
        'fecha_entrega_prop':
            o.fechaEntregaProp?.toIso8601String().split('T').first,
        'vehiculo_id': o.vehiculoId,
        'incluye_seguro': o.incluyeSeguro,
        'notas': o.notas,
        'estado': o.estado,
        'matching_score': o.matchingScore,
        'created_at': o.createdAt.toIso8601String(),
        'updated_at': o.updatedAt?.toIso8601String(),
        'driver_nombre': o.driverNombre,
        'driver_tipo_usuario': o.driverTipoUsuario,
        'driver_rating': o.driverRating,
        'driver_mc_dot_verificado': o.driverMcDotVerificado,
        'vehiculo_descripcion': o.vehiculoDescripcion,
      };
}
