import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conductor_asignado_model.dart';
import '../models/tarifa_model.dart';
import '../models/transport_request_model.dart';
import '../models/vehicle_type_model.dart';
import '../services/background_service.dart';
import '../services/routing_service.dart';
import '../services/transport_request_service.dart';
import '../services/vehicle_type_service.dart';
import '../utils/app_error.dart';
import '../utils/helpers.dart';

/// Estado del flujo de taxi con precio fijo.
///
/// Ya no existe negociación: la plataforma cotiza, publica y el chofer toma
/// el viaje de una lista. Ver `docs/plan-taxi-precio-fijo/13-contrato-app-rpc.md`.
enum TransportState {
  idle,
  calculatingRoute, // pidiendo ruta a OSRM
  routeReady, // ruta + cotización listas
  requesting, // fn_crear_solicitud en vuelo
  searchingDriver, // solicitud publicada, esperando que un chofer la tome
  driverAssigned, // driver_id != null
  rideInProgress,
  rideCompleted,
  error,
}

class TransportProvider extends ChangeNotifier {
  final TransportRequestService _requestService = TransportRequestService();
  final RoutingService _routingService = RoutingService();
  final VehicleTypeService _vehicleTypeService = VehicleTypeService();

  // ── Catálogo de vehículos (muevete.v_catalogo_vehiculos) ────────────────
  List<CatalogoVehiculo> _catalogo = [];
  bool _cargandoCatalogo = false;
  String? _errorCatalogo;
  CatalogoVehiculo? _vehiculoSeleccionado;
  int _pasajeros = 1;

  // ── Tipos de vehículo legacy (muevete.vehicle_type, mapa de inicio) ─────
  List<VehicleTypeModel> _vehicleTypes = [];
  bool _loadingVehicleTypes = false;
  bool _vehicleTypesSubscribed = false;
  VehicleTypeModel? _selectedVehicleType;

  // ── Ruta ────────────────────────────────────────────────────────────────
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  String? _pickupAddress;
  String? _dropoffAddress;
  List<LatLng>? _routePolyline;
  double _routeDistanceKm = 0;
  double _routeDurationMin = 0;

  // ── Cotización ──────────────────────────────────────────────────────────
  Cotizacion? _cotizacion;
  bool _cotizando = false;
  String? _errorCotizacion;

  // ── Pago ────────────────────────────────────────────────────────────────
  String _metodoPago = 'efectivo'; // 'efectivo' | 'wallet'

  // ── Solicitud activa (cliente) ─────────────────────────────────────────
  TransportRequestModel? _activeRequest;
  int? _activeViajeId;
  ConductorAsignado? _conductorAsignado;
  double? _reembolsoCancelacion;
  double? _saldoTrasCancelacion;
  Timer? _timerSolicitud;

  // ── Viajes disponibles (chofer) ────────────────────────────────────────
  List<ViajeDisponible> _viajesDisponibles = [];
  bool _cargandoViajes = false;
  String? _errorViajes;
  bool _viajesCargados = false;
  int? _tomandoViajeId;
  LatLng? _ubicacionChofer;
  Timer? _timerViajes;

  // ── Estado / error ─────────────────────────────────────────────────────
  TransportState _state = TransportState.idle;
  String? _error;
  String? _errorClave;
  List<String> _motivosPerfil = const [];

  // ── Getters: catálogo ───────────────────────────────────────────────────
  List<CatalogoVehiculo> get catalogoVehiculos => _catalogo;
  bool get cargandoCatalogo => _cargandoCatalogo;
  String? get errorCatalogo => _errorCatalogo;
  CatalogoVehiculo? get vehiculoSeleccionado => _vehiculoSeleccionado;
  int get pasajeros => _pasajeros;
  int get pasajerosMax => _vehiculoSeleccionado?.pasajerosMax ?? 1;

  // ── Getters: legacy vehicle_type ────────────────────────────────────────
  List<VehicleTypeModel> get vehicleTypes => _vehicleTypes;
  bool get loadingVehicleTypes => _loadingVehicleTypes;
  VehicleTypeModel? get selectedVehicleType => _selectedVehicleType;

  // ── Getters: ruta ───────────────────────────────────────────────────────
  LatLng? get pickupLocation => _pickupLocation;
  LatLng? get dropoffLocation => _dropoffLocation;
  String? get pickupAddress => _pickupAddress;
  String? get dropoffAddress => _dropoffAddress;
  List<LatLng>? get routePolyline => _routePolyline;
  double get routeDistanceKm => _routeDistanceKm;
  double get routeDurationMin => _routeDurationMin;
  bool get hasRoute => _routePolyline != null && _routePolyline!.isNotEmpty;

  // ── Getters: cotización ─────────────────────────────────────────────────
  Cotizacion? get cotizacion => _cotizacion;
  bool get cotizando => _cotizando;
  String? get errorCotizacion => _errorCotizacion;

  // ── Getters: pago y solicitud ───────────────────────────────────────────
  String get paymentMethod => _metodoPago;
  TransportRequestModel? get activeRequest => _activeRequest;
  int? get activeViajeId => _activeViajeId;
  set activeViajeId(int? value) {
    _activeViajeId = value;
    notifyListeners();
  }

  ConductorAsignado? get conductorAsignado => _conductorAsignado;
  double? get reembolsoCancelacion => _reembolsoCancelacion;
  double? get saldoTrasCancelacion => _saldoTrasCancelacion;

  // ── Getters: viajes disponibles (chofer) ────────────────────────────────
  List<ViajeDisponible> get viajesDisponibles => _viajesDisponibles;
  bool get cargandoViajes => _cargandoViajes;
  String? get errorViajes => _errorViajes;
  bool get viajesCargados => _viajesCargados;
  int? get tomandoViajeId => _tomandoViajeId;

  // ── Getters: estado ─────────────────────────────────────────────────────
  TransportState get state => _state;
  String? get error => _error;
  String? get errorClave => _errorClave;
  List<String> get motivosPerfil => _motivosPerfil;

  // ════════════════════════════════════════════════════════════════════════
  // Catálogo y selección
  // ════════════════════════════════════════════════════════════════════════

  /// Carga `muevete.v_catalogo_vehiculos` y elige el primero por defecto.
  Future<void> cargarCatalogoVehiculos({bool force = false}) async {
    if (_cargandoCatalogo) return;
    if (!force && _catalogo.isNotEmpty) return;
    _cargandoCatalogo = true;
    _errorCatalogo = null;
    notifyListeners();
    try {
      final lista = await _requestService.catalogoVehiculos();
      final previoId = _vehiculoSeleccionado?.id;
      _catalogo = lista;
      if (previoId != null) {
        final match = lista.where((v) => v.id == previoId);
        _vehiculoSeleccionado = match.isNotEmpty
            ? match.first
            : (lista.isNotEmpty ? lista.first : null);
      } else {
        _vehiculoSeleccionado = lista.isNotEmpty ? lista.first : null;
      }
      _ajustarPasajeros();
      if (lista.isEmpty) {
        _errorCatalogo = 'No hay tipos de vehículo disponibles.';
      }
    } catch (e) {
      _errorCatalogo = AppError.message(e, action: 'cargar los tipos de vehículo');
    } finally {
      _cargandoCatalogo = false;
      notifyListeners();
    }
  }

  void setVehiculo(CatalogoVehiculo vehiculo) {
    if (_vehiculoSeleccionado?.id == vehiculo.id) return;
    _vehiculoSeleccionado = vehiculo;
    _ajustarPasajeros();
    _cotizacion = null;
    _errorCotizacion = null;
    notifyListeners();
    cotizar();
  }

  void setPasajeros(int valor) {
    final max = pasajerosMax;
    final nuevo = valor < 1 ? 1 : (valor > max ? max : valor);
    if (nuevo == _pasajeros) return;
    _pasajeros = nuevo;
    notifyListeners();
  }

  void _ajustarPasajeros() {
    final max = pasajerosMax;
    if (max < 1) {
      _pasajeros = 1;
      return;
    }
    if (_pasajeros > max) _pasajeros = max;
    if (_pasajeros < 1) _pasajeros = 1;
  }

  // ── Legacy vehicle_type (mapa de inicio) ────────────────────────────────

  Future<void> loadVehicleTypes({bool force = false}) async {
    if (_loadingVehicleTypes) return;
    if (!force && _vehicleTypes.isNotEmpty) return;
    _loadingVehicleTypes = true;
    notifyListeners();
    try {
      final prevId = _selectedVehicleType?.id;
      _vehicleTypes =
          await _vehicleTypeService.getActiveTypesByCategoria('pasajero');
      if (prevId != null) {
        final match = _vehicleTypes.where((vt) => vt.id == prevId);
        _selectedVehicleType = match.isNotEmpty
            ? match.first
            : (_vehicleTypes.isNotEmpty ? _vehicleTypes.first : null);
      } else if (_vehicleTypes.isNotEmpty) {
        _selectedVehicleType = _vehicleTypes.first;
      } else {
        _selectedVehicleType = null;
      }
    } catch (e) {
      _error = AppError.message(e, action: 'cargar los tipos de vehículo');
    } finally {
      _loadingVehicleTypes = false;
      notifyListeners();
    }
  }

  void startVehicleTypesRealtime() {
    if (_vehicleTypesSubscribed) return;
    _vehicleTypesSubscribed = true;
    _vehicleTypeService.subscribeToChanges(() {
      loadVehicleTypes(force: true);
    });
  }

  /// Selección legacy (mapa de inicio). Mantiene alineado el catálogo nuevo.
  void setVehicleType(VehicleTypeModel type) {
    _selectedVehicleType = type;
    final match = _catalogo.where((v) => v.id == type.id);
    if (match.isNotEmpty) _vehiculoSeleccionado = match.first;
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════════
  // Ruta
  // ════════════════════════════════════════════════════════════════════════

  void setPickup(LatLng location, {String? address}) {
    _pickupLocation = location;
    _pickupAddress = address ?? 'Ubicación actual';
    _cotizacion = null;
    notifyListeners();
  }

  void setDropoff(LatLng location, {String? address}) {
    _dropoffLocation = location;
    _dropoffAddress = address ?? 'Destino seleccionado';
    _cotizacion = null;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    final normalizado = method == 'wallet' ? 'wallet' : 'efectivo';
    if (normalizado == _metodoPago) return;
    _metodoPago = normalizado;
    notifyListeners();
  }

  /// Calcula la ruta (OSRM) y, al terminar, cotiza con el servidor.
  Future<void> calculateRoute() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;

    _state = TransportState.calculatingRoute;
    _error = null;
    notifyListeners();

    try {
      final result =
          await _routingService.getRoute(_pickupLocation!, _dropoffLocation!);
      _routePolyline = result.polyline;
      _routeDistanceKm = result.totalDistance / 1000;
      _routeDurationMin = result.totalDuration / 60;
      _state = TransportState.routeReady;
      notifyListeners();
      await cotizar();
    } catch (e) {
      _error = AppError.message(e, action: 'calcular la ruta');
      _state = TransportState.error;
      notifyListeners();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Cotizar (fn_cotizar_viaje) — preview de sólo lectura
  // ════════════════════════════════════════════════════════════════════════

  Future<void> cotizar() async {
    final tipo = _vehiculoSeleccionado;
    if (_pickupLocation == null || _dropoffLocation == null || tipo == null) {
      return;
    }

    _cotizando = true;
    _errorCotizacion = null;
    notifyListeners();

    try {
      final json = await _requestService.cotizar(
        latOrigen: _pickupLocation!.latitude,
        lonOrigen: _pickupLocation!.longitude,
        latDestino: _dropoffLocation!.latitude,
        lonDestino: _dropoffLocation!.longitude,
        idTipo: tipo.id,
        km: _routeDistanceKm > 0 ? _routeDistanceKm : null,
      );
      if (json.isEmpty || json['precio_plataforma'] == null) {
        _cotizacion = null;
        _errorCotizacion =
            'No se pudo calcular la tarifa del viaje. Inténtalo de nuevo.';
      } else {
        _cotizacion = Cotizacion.fromJson(json);
        if (_state == TransportState.calculatingRoute) {
          _state = TransportState.routeReady;
        }
      }
    } catch (e) {
      _cotizacion = null;
      _errorCotizacion = mensajeError(e, accion: 'calcular la tarifa');
      _errorClave = claveError(e);
    } finally {
      _cotizando = false;
      notifyListeners();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Publicar (fn_crear_solicitud)
  // ════════════════════════════════════════════════════════════════════════

  /// Publica la solicitud. El precio lo pone el servidor: aquí no se envía.
  Future<bool> crearSolicitud() async {
    final tipo = _vehiculoSeleccionado;
    if (_pickupLocation == null ||
        _dropoffLocation == null ||
        tipo == null ||
        _cotizacion == null) {
      _error = 'Faltan datos del viaje. Revisa el origen, el destino y el tipo '
          'de vehículo.';
      _errorClave = null;
      notifyListeners();
      return false;
    }

    _error = null;
    _errorClave = null;
    _motivosPerfil = const [];
    _state = TransportState.requesting;
    notifyListeners();

    try {
      final row = await _requestService.crearSolicitud(
        latOrigen: _pickupLocation!.latitude,
        lonOrigen: _pickupLocation!.longitude,
        latDestino: _dropoffLocation!.latitude,
        lonDestino: _dropoffLocation!.longitude,
        idTipo: tipo.id,
        dirOrigen: _pickupAddress ?? 'Ubicación actual',
        dirDestino: _dropoffAddress ?? 'Destino seleccionado',
        km: _routeDistanceKm,
        metodoPago: _metodoPago,
        pasajeros: _pasajeros,
      );

      if (row['id'] == null) {
        throw Exception('El servidor no devolvió la solicitud creada');
      }

      _activeRequest = TransportRequestModel.fromJson(row);
      _activeViajeId = null;
      _conductorAsignado = null;
      _suscribirSolicitudActiva();

      _state = TransportState.searchingDriver;
      notifyListeners();

      BackgroundService.updateStatus(
        title: 'Muevete',
        content: 'Buscando conductor · '
            '${Helpers.formatCup(_cotizacion?.precioPlataforma ?? 0)}',
      );
      return true;
    } catch (e) {
      _error = mensajeError(e, accion: 'publicar la solicitud');
      _errorClave = claveError(e);
      if (_errorClave == 'perfil_incompleto') {
        _motivosPerfil = motivosPerfilDe(e);
      }
      _state = TransportState.error;
      notifyListeners();
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Cancelar (fn_cancelar_solicitud)
  // ════════════════════════════════════════════════════════════════════════

  Future<bool> cancelarSolicitud({String? motivo}) async {
    final solicitudId = _activeRequest?.id;
    if (solicitudId == null) return false;

    _error = null;
    _errorClave = null;
    notifyListeners();

    try {
      final res = await _requestService.cancelarSolicitud(
        solicitudId,
        motivo: motivo ?? 'Cancelada por el cliente',
      );
      _reembolsoCancelacion = (res['reembolso'] as num?)?.toDouble();
      _saldoTrasCancelacion = (res['saldo'] as num?)?.toDouble();
      resetTrip(conservarCotizacion: false);
      return true;
    } catch (e) {
      _error = mensajeError(e, accion: 'cancelar la solicitud');
      _errorClave = claveError(e);
      notifyListeners();
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Solicitud activa: realtime + refresco de seguridad
  // ════════════════════════════════════════════════════════════════════════

  void _suscribirSolicitudActiva() {
    final id = _activeRequest?.id;
    if (id == null) return;

    _requestService.subscribeToSolicitud(id, _onSolicitudUpdate);

    _timerSolicitud?.cancel();
    _timerSolicitud = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refrescarSolicitudActiva(),
    );
  }

  Future<void> _refrescarSolicitudActiva() async {
    final id = _activeRequest?.id;
    if (id == null) return;
    if (_state != TransportState.searchingDriver &&
        _state != TransportState.driverAssigned) {
      return;
    }
    final row = await _requestService.solicitudPorId(id);
    if (row != null) _onSolicitudUpdate(row);
  }

  void _onSolicitudUpdate(Map<String, dynamic> row) {
    final actual = _activeRequest;
    if (actual == null) return;

    final estado = row['estado'] as String?;
    final driverId = (row['driver_id'] as num?)?.toInt();
    final precioPlataforma = (row['precio_plataforma'] as num?)?.toDouble();

    switch (estado) {
      case 'aceptada':
        _activeRequest = actual.copyWith(
          estado: EstadoSolicitud.aceptada,
          driverId: driverId ?? actual.driverId,
          precioPlataforma: precioPlataforma ?? actual.precioPlataforma,
        );
        if (_state != TransportState.driverAssigned) {
          _state = TransportState.driverAssigned;
          _timerSolicitud?.cancel();
          _timerSolicitud = null;
          BackgroundService.updateStatus(
            title: 'Muevete',
            content: 'Conductor asignado · en camino',
          );
        }
        notifyListeners();
        cargarConductorAsignado();
        _resolverViajeId();
        break;

      case 'cancelada':
      case 'expirada':
        _timerSolicitud?.cancel();
        _timerSolicitud = null;
        _activeRequest = null;
        _conductorAsignado = null;
        if (_state != TransportState.rideCompleted) {
          _state = TransportState.idle;
        }
        notifyListeners();
        break;

      case 'completada':
        _timerSolicitud?.cancel();
        _timerSolicitud = null;
        _activeRequest = actual.copyWith(
          estado: EstadoSolicitud.completada,
          precioPlataforma: precioPlataforma ?? actual.precioPlataforma,
        );
        _state = TransportState.rideCompleted;
        notifyListeners();
        break;

      default:
        _activeRequest = actual.copyWith(
          driverId: driverId ?? actual.driverId,
          precioPlataforma: precioPlataforma ?? actual.precioPlataforma,
        );
        notifyListeners();
    }
  }

  /// Resuelve el `viaje_id` asociado a la solicitud (lo crea `fn_tomar_viaje`).
  /// Se usa para cerrar el viaje y para la valoración del cliente.
  Future<void> _resolverViajeId() async {
    final solicitudId = _activeRequest?.id;
    if (solicitudId == null || _activeViajeId != null) return;
    final id = await _requestService.viajeDeSolicitud(solicitudId);
    if (id == null) return;
    _activeViajeId = id;
    notifyListeners();
  }

  /// Carga los datos del chofer que tomó la solicitud.
  Future<void> cargarConductorAsignado() async {
    final driverId = _activeRequest?.driverId;
    if (driverId == null) {
      _conductorAsignado = null;
      notifyListeners();
      return;
    }
    try {
      final data = await _requestService.getDriverDetails(driverId);
      _conductorAsignado = ConductorAsignado.fromDriverDetails(
        data,
        precio: _activeRequest?.precioPlataforma ??
            _cotizacion?.precioPlataforma,
        tiempoEstimado:
            _routeDurationMin > 0 ? _routeDurationMin.round() : null,
      );
    } catch (_) {
      _conductorAsignado = ConductorAsignado(driverId: driverId);
    }
    notifyListeners();
  }

  /// Re-suscribe los canales realtime (llamar al volver del segundo plano).
  Future<void> resubscribeRealtime() async {
    final id = _activeRequest?.id;
    if (id == null) return;
    if (_state != TransportState.searchingDriver &&
        _state != TransportState.driverAssigned &&
        _state != TransportState.rideInProgress) {
      return;
    }
    await _requestService.unsubscribe();
    _requestService.subscribeToSolicitud(id, _onSolicitudUpdate);
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════════
  // Viajes disponibles (chofer) — fn_viajes_disponibles
  // ════════════════════════════════════════════════════════════════════════

  /// Arranca realtime (`postgres_changes` sobre `muevete.solicitudes_transporte`)
  /// y el refresco de seguridad cada 20 s.
  void iniciarViajesDisponibles(LatLng ubicacion) {
    _ubicacionChofer = ubicacion;
    _requestService.subscribeToSolicitudesDisponibles(() {
      cargarViajesDisponibles(silencioso: true);
    });
    _timerViajes?.cancel();
    _timerViajes = Timer.periodic(
      const Duration(seconds: 20),
      (_) => cargarViajesDisponibles(silencioso: true),
    );
    cargarViajesDisponibles();
  }

  void detenerViajesDisponibles() {
    _timerViajes?.cancel();
    _timerViajes = null;
  }

  Future<void> cargarViajesDisponibles({
    LatLng? ubicacion,
    bool silencioso = false,
  }) async {
    if (ubicacion != null) _ubicacionChofer = ubicacion;
    if (_cargandoViajes) return;

    _cargandoViajes = true;
    if (!silencioso) _errorViajes = null;
    notifyListeners();

    try {
      final lista = await _requestService.viajesDisponibles(
        lat: _ubicacionChofer?.latitude,
        lon: _ubicacionChofer?.longitude,
        limite: 30,
      );
      _viajesDisponibles = lista;
      _errorViajes = null;
    } catch (e) {
      _errorViajes = mensajeError(e, accion: 'cargar los viajes disponibles');
      _errorClave = claveError(e);
    } finally {
      _cargandoViajes = false;
      _viajesCargados = true;
      notifyListeners();
    }
  }

  /// Toma un viaje (fn_tomar_viaje). Devuelve el jsonb + la fila de la
  /// solicitud, o null si falló. Si otro chofer llegó primero refresca la lista.
  Future<Map<String, dynamic>?> tomarViaje(int solicitudId) async {
    if (_tomandoViajeId != null) return null;

    _tomandoViajeId = solicitudId;
    _error = null;
    _errorClave = null;
    notifyListeners();

    try {
      final res = await _requestService.tomarViaje(solicitudId);
      if (res['success'] == false) {
        throw Exception('El servidor no confirmó el viaje');
      }
      final viajeId = (res['viaje_id'] as num?)?.toInt();
      _activeViajeId = viajeId;

      final solicitud = await _requestService.solicitudPorId(solicitudId);
      if (solicitud != null) {
        _activeRequest = TransportRequestModel.fromJson(solicitud);
        _conductorAsignado = null;
      }

      Map<String, dynamic>? cliente;
      final userId = solicitud?['user_id'] as String?;
      if (userId != null) {
        cliente = await _requestService.clienteDeUsuario(userId);
      }

      return <String, dynamic>{
        ...res,
        if (solicitud != null) 'solicitud': solicitud,
        if (cliente != null) 'cliente': cliente,
      };
    } catch (e) {
      _error = mensajeError(e, accion: 'tomar el viaje');
      _errorClave = claveError(e);
      if (_errorClave == 'ya_tomado' ||
          _errorClave == 'solicitud_vencida' ||
          _errorClave == 'viaje_ya_completado') {
        await cargarViajesDisponibles(silencioso: true);
      }
      return null;
    } finally {
      _tomandoViajeId = null;
      notifyListeners();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Completar (fn_completar_viaje) — no recibe precio
  // ════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> completarViaje({
    int? viajeId,
    int? esperaMin,
  }) async {
    var id = viajeId ?? _activeViajeId;
    if (id == null) {
      final solicitudId = _activeRequest?.id;
      if (solicitudId != null) {
        id = await _requestService.viajeDeSolicitud(solicitudId);
      }
    }
    if (id == null) {
      _error = 'No se encontró el viaje que se quiere cerrar.';
      notifyListeners();
      return null;
    }

    _error = null;
    _errorClave = null;
    notifyListeners();

    try {
      final res = await _requestService.completarViaje(id, esperaMin: esperaMin);
      _activeViajeId = id;
      final precio = (res['precio_plataforma'] as num?)?.toDouble();
      if (_activeRequest != null) {
        _activeRequest = _activeRequest!.copyWith(
          estado: EstadoSolicitud.completada,
          precioPlataforma: precio ?? _activeRequest!.precioPlataforma,
        );
      }
      _state = TransportState.rideCompleted;
      notifyListeners();
      return res;
    } catch (e) {
      _error = mensajeError(e, accion: 'completar el viaje');
      _errorClave = claveError(e);
      notifyListeners();
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Restauración desde historial
  // ════════════════════════════════════════════════════════════════════════

  /// Restaura una solicitud pendiente para seguir esperando conductor.
  Future<void> restoreActiveRequest(TransportRequestModel request) async {
    _aplicarSolicitudAContexto(request);
    _state = TransportState.searchingDriver;
    _conductorAsignado = null;
    _suscribirSolicitudActiva();
    notifyListeners();
    BackgroundService.updateStatus(
      title: 'Muevete',
      content: 'Buscando conductor',
    );
  }

  /// Restaura un viaje ya tomado por un conductor.
  Future<void> restoreAcceptedRide(TransportRequestModel request) async {
    _aplicarSolicitudAContexto(request);
    _state = TransportState.driverAssigned;
    if (request.id != null) {
      _activeViajeId = await _requestService.viajeDeSolicitud(request.id!);
      _suscribirSolicitudActiva();
    }
    notifyListeners();
    await cargarConductorAsignado();
  }

  void _aplicarSolicitudAContexto(TransportRequestModel request) {
    _activeRequest = request;
    if (request.latOrigen != null && request.lonOrigen != null) {
      _pickupLocation = LatLng(request.latOrigen!, request.lonOrigen!);
    }
    if (request.latDestino != null && request.lonDestino != null) {
      _dropoffLocation = LatLng(request.latDestino!, request.lonDestino!);
    }
    _pickupAddress = request.direccionOrigen ?? _pickupAddress;
    _dropoffAddress = request.direccionDestino ?? _dropoffAddress;
    _routeDistanceKm = request.distanciaKm ?? _routeDistanceKm;
    _metodoPago = request.metodoPago ?? _metodoPago;
  }

  // ════════════════════════════════════════════════════════════════════════
  // Limpieza
  // ════════════════════════════════════════════════════════════════════════

  void resetTrip({bool conservarCotizacion = true}) {
    _timerSolicitud?.cancel();
    _timerSolicitud = null;

    _pickupLocation = null;
    _dropoffLocation = null;
    _pickupAddress = null;
    _dropoffAddress = null;
    _routePolyline = null;
    _routeDistanceKm = 0;
    _routeDurationMin = 0;
    _activeRequest = null;
    _activeViajeId = null;
    _conductorAsignado = null;
    if (!conservarCotizacion) _cotizacion = null;
    _metodoPago = 'efectivo';
    _state = TransportState.idle;
    _error = null;
    _errorClave = null;
    _motivosPerfil = const [];
    _pasajeros = 1;
    if (_vehicleTypes.isNotEmpty) {
      _selectedVehicleType = _vehicleTypes.first;
    }
    _requestService.unsubscribe();
    notifyListeners();
    BackgroundService.updateStatus(
      title: 'Muevete activo',
      content: 'Ubicación compartida en segundo plano',
    );
  }

  @override
  void dispose() {
    _timerSolicitud?.cancel();
    _timerViajes?.cancel();
    _requestService.unsubscribe();
    _vehicleTypeService.unsubscribe();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════
  // §4 Errores del servidor → mensajes en español
  // ════════════════════════════════════════════════════════════════════════

  /// Texto del servidor (mensaje + detalles) para buscar la clave del error.
  static String? _textoDe(Object? error) {
    if (error is PostgrestException) {
      return '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
          .toLowerCase();
    }
    if (error is FunctionException) {
      return '${error.details}'.toLowerCase();
    }
    return null;
  }

  /// SQLSTATE devuelto por la RPC (`P0003`, `P0020`, ...), si lo hay.
  static String? codigoError(Object? error) {
    if (error is PostgrestException) {
      final code = (error.code ?? '').trim().toUpperCase();
      if (code.isNotEmpty) return code;
    }
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map) {
        final code = details['code'];
        if (code != null) return code.toString().toUpperCase();
      }
    }
    if (error is AuthException) return null;
    return null;
  }

  /// Clave estable del error (`ya_tomado`, `servicio_en_mantenimiento`, ...).
  /// Acepta tanto el SQLSTATE como el texto que manda el servidor.
  static String? claveError(Object? error) {
    final codigo = codigoError(error);
    if (codigo != null && _clavePorSqlState.containsKey(codigo)) {
      return _clavePorSqlState[codigo];
    }
    final texto = _textoDe(error);
    if (texto != null && texto.isNotEmpty) {
      for (final clave in _mensajePorClave.keys) {
        if (texto.contains(clave)) return clave;
      }
    }
    return null;
  }

  /// Mensaje en español para la UI (§4 del contrato).
  static String mensajeError(Object? error, {String? accion}) {
    final clave = claveError(error);
    if (clave != null) return _mensajePorClave[clave]!;
    return AppError.message(error, action: accion);
  }

  /// Claves faltantes del onboarding cuando el error es `perfil_incompleto`.
  static List<String> motivosPerfilDe(Object? error) {
    Object? details;
    if (error is PostgrestException) {
      details = error.details;
    } else if (error is FunctionException) {
      details = error.details;
    }
    if (details is Map) {
      final motivos = details['motivos'];
      if (motivos is List) {
        return motivos.map((m) => m.toString()).toList();
      }
    }
    return const [];
  }

  static const Map<String, String> _clavePorSqlState = {
    'P0003': 'servicio_en_mantenimiento',
    'P0005': 'solicitud_activa_existente',
    'P0006': 'metodo_pago_invalido',
    'P0010': 'chofer_offline',
    'P0011': 'chofer_no_aprobado',
    'P0012': 'chofer_con_viaje_activo',
    'P0020': 'ya_tomado',
    'P0021': 'tipo_vehiculo_incompatible',
    'P0022': 'viaje_fuera_de_tu_zona',
    'P0023': 'limite_de_deuda_alcanzado',
    'P0024': 'cliente_sin_saldo',
    'P0025': 'solicitud_legacy_sin_tarifa',
    'P0026': 'solicitud_vencida',
    'P0030': 'viaje_no_existe',
    'P0032': 'viaje_ya_completado',
    'P0040': 'tipo_vehiculo_no_existe',
    'P0041': 'metodo_invalido',
    'P0050': 'perfil_incompleto',
    'P0051': 'capacidad_excedida_tipo',
    'P0052': 'capacidad_insuficiente',
    'P0053': 'consentimiento_pendiente',
    'P0110': 'sin_contacto_emergencia',
    'P0112': 'emparejamiento_bloqueado',
  };

  static const Map<String, String> _mensajePorClave = {
    'servicio_en_mantenimiento':
        'El servicio está en mantenimiento. Intenta más tarde.',
    'solicitud_activa_existente': 'Ya tienes un viaje activo.',
    'metodo_pago_invalido': 'Método de pago no válido.',
    'chofer_offline': 'Ponte en línea para tomar viajes.',
    'chofer_no_aprobado': 'Tu cuenta aún no está aprobada.',
    'chofer_con_viaje_activo': 'Termina el viaje que tienes en curso.',
    'ya_tomado': 'Otro conductor lo tomó primero.',
    'tipo_vehiculo_incompatible': 'El viaje pide otro tipo de vehículo.',
    'viaje_fuera_de_tu_zona': 'El viaje está fuera de tu zona.',
    'limite_de_deuda_alcanzado':
        'Alcanzaste tu límite de deuda. Recarga para seguir.',
    'cliente_sin_saldo': 'Saldo insuficiente.',
    'solicitud_legacy_sin_tarifa':
        'Este viaje es de una versión anterior de la app.',
    'solicitud_vencida': 'La solicitud expiró.',
    'viaje_no_existe': 'El viaje no existe.',
    'viaje_ya_completado': 'El viaje ya se cerró.',
    'estado_invalido': 'El viaje ya se cerró.',
    'tipo_vehiculo_no_existe': 'Tipo de vehículo no disponible.',
    'metodo_invalido': 'Método no válido.',
    'perfil_incompleto': 'Completa tu perfil para continuar.',
    'capacidad_excedida_tipo': 'Ese vehículo no admite tantos pasajeros.',
    'capacidad_insuficiente':
        'Tu vehículo no tiene capacidad para ese viaje.',
    'consentimiento_pendiente':
        'Acepta privacidad y términos para continuar.',
    'sin_contacto_emergencia':
        'Configura tu contacto de emergencia en Mi seguridad.',
    'bloqueado': 'Configura tu contacto de emergencia en Mi seguridad.',
    'emparejamiento_bloqueado': 'No puedes tomar viajes de este cliente.',
  };
}