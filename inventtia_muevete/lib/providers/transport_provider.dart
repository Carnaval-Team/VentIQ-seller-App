import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/transport_request_model.dart';
import '../models/driver_offer_model.dart';
import '../models/vehicle_type_model.dart';
import '../services/transport_request_service.dart';
import '../services/driver_service.dart';
import '../services/routing_service.dart';
import '../services/vehicle_type_service.dart';

class TransportProvider extends ChangeNotifier {
  final TransportRequestService _requestService = TransportRequestService();
  final DriverService _driverService = DriverService();
  final RoutingService _routingService = RoutingService();
  final VehicleTypeService _vehicleTypeService = VehicleTypeService();

  // Vehicle types loaded from DB
  List<VehicleTypeModel> _vehicleTypes = [];
  bool _loadingVehicleTypes = false;

  // Route planning
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  String? _pickupAddress;
  String? _dropoffAddress;
  List<LatLng>? _routePolyline;
  double _routeDistanceKm = 0;
  double _routeDurationMin = 0;

  // Transport selection — full model from DB
  VehicleTypeModel? _selectedVehicleType;
  double _offerPrice = 0;

  // Active request
  TransportRequestModel? _activeRequest;
  List<DriverOfferModel> _driverOffers = [];
  DriverOfferModel? _acceptedOffer;
  int? _activeViajeId; // viaje created after offer accepted
  int? get activeViajeId => _activeViajeId;

  // State
  TransportState _state = TransportState.idle;
  String? _error;

  // Getters
  List<VehicleTypeModel> get vehicleTypes => _vehicleTypes;
  bool get loadingVehicleTypes => _loadingVehicleTypes;
  LatLng? get pickupLocation => _pickupLocation;
  LatLng? get dropoffLocation => _dropoffLocation;
  String? get pickupAddress => _pickupAddress;
  String? get dropoffAddress => _dropoffAddress;
  List<LatLng>? get routePolyline => _routePolyline;
  double get routeDistanceKm => _routeDistanceKm;
  double get routeDurationMin => _routeDurationMin;
  VehicleTypeModel? get selectedVehicleType => _selectedVehicleType;
  double get offerPrice => _offerPrice;
  TransportRequestModel? get activeRequest => _activeRequest;
  List<DriverOfferModel> get driverOffers => _driverOffers;
  DriverOfferModel? get acceptedOffer => _acceptedOffer;
  TransportState get state => _state;
  String? get error => _error;
  bool get hasRoute => _routePolyline != null && _routePolyline!.isNotEmpty;

  /// Loads active vehicle types from muevete.vehicle_type.
  /// Skips if already loaded or currently loading.
  Future<void> loadVehicleTypes() async {
    if (_loadingVehicleTypes || _vehicleTypes.isNotEmpty) return;
    _loadingVehicleTypes = true;
    notifyListeners();
    try {
      _vehicleTypes = await _vehicleTypeService.getActiveTypes();
      if (_vehicleTypes.isNotEmpty) {
        _selectedVehicleType = _vehicleTypes.first;
        _calculatePrice();
      }
    } catch (e) {
      _error = 'Error cargando tipos de vehículo: $e';
    } finally {
      _loadingVehicleTypes = false;
      notifyListeners();
    }
  }

  void setPickup(LatLng location, {String? address}) {
    _pickupLocation = location;
    _pickupAddress = address ?? 'Ubicación actual';
    notifyListeners();
  }

  void setDropoff(LatLng location, {String? address}) {
    _dropoffLocation = location;
    _dropoffAddress = address ?? 'Destino seleccionado';
    notifyListeners();
  }

  void setVehicleType(VehicleTypeModel type) {
    _selectedVehicleType = type;
    _calculatePrice();
    notifyListeners();
  }

  void setOfferPrice(double price) {
    _offerPrice = price;
    notifyListeners();
  }

  void _calculatePrice() {
    if (_selectedVehicleType == null || _routeDistanceKm == 0) return;
    final pricePerKm = _selectedVehicleType!.precioKmDefault;
    _offerPrice = double.parse(
        (_routeDistanceKm * pricePerKm).toStringAsFixed(2));
  }

  Future<void> calculateRoute() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;

    _state = TransportState.calculatingRoute;
    notifyListeners();

    try {
      final result =
          await _routingService.getRoute(_pickupLocation!, _dropoffLocation!);
      _routePolyline = result.polyline;
      _routeDistanceKm = result.totalDistance / 1000;
      _routeDurationMin = result.totalDuration / 60;
      _calculatePrice();
      _state = TransportState.routeReady;
    } catch (e) {
      _error = 'Error calculando ruta: $e';
      _state = TransportState.error;
    }
    notifyListeners();
  }

  Future<void> sendRequest(String userId) async {
    if (_pickupLocation == null ||
        _dropoffLocation == null ||
        _selectedVehicleType == null) return;

    _state = TransportState.requesting;
    notifyListeners();

    try {
      final expiresAt = DateTime.now().add(const Duration(hours: 1));
      final request = TransportRequestModel(
        userId: userId,
        latOrigen: _pickupLocation!.latitude,
        lonOrigen: _pickupLocation!.longitude,
        latDestino: _dropoffLocation!.latitude,
        lonDestino: _dropoffLocation!.longitude,
        tipoVehiculo: _selectedVehicleType!.tipo,
        idTipoVehiculo: _selectedVehicleType!.id,
        precioOferta: _offerPrice,
        estado: EstadoSolicitud.pendiente,
        direccionOrigen: _pickupAddress,
        direccionDestino: _dropoffAddress,
        distanciaKm: _routeDistanceKm,
        expiresAt: expiresAt,
      );

      final result = await _requestService.createRequest(request);
      _activeRequest = TransportRequestModel.fromJson(result);

      if (_activeRequest?.id != null) {
        final rid = _activeRequest!.id!;
        // Load any offers that arrived before we subscribed
        _driverOffers = await _requestService.getExistingOffers(rid);
        // New offer INSERTs
        _requestService.subscribeToOffers(rid, _onNewOffer);
        // Offer estado UPDATEs (e.g. driver's offer got accepted by client)
        _requestService.subscribeToOfertaUpdates(rid, _onOfertaUpdate);
        // Solicitud estado UPDATEs (e.g. cancelled externally)
        _requestService.subscribeToSolicitudChanges(rid, _onSolicitudEstadoChange);
      }

      _state = TransportState.waitingOffers;
      notifyListeners();
    } catch (e) {
      _error = 'Error enviando solicitud: $e';
      _state = TransportState.error;
      notifyListeners();
    }
  }

  /// Removes an offer from the local list (client-side decline, no DB write).
  void declineOffer(DriverOfferModel offer) {
    _driverOffers.removeWhere((o) => o.id == offer.id);
    notifyListeners();
  }

  void _onNewOffer(DriverOfferModel offer) {
    // Avoid duplicates if offer was already loaded via getExistingOffers
    if (offer.id != null && _driverOffers.any((o) => o.id == offer.id)) return;
    _driverOffers.add(offer);
    notifyListeners();
  }

  /// Called when an oferta row is updated in DB (e.g. client accepted it).
  /// If the update marks this offer as 'aceptada' we move to rideConfirmed.
  void _onOfertaUpdate(Map<String, dynamic> row) {
    final estado = row['estado'] as String?;
    if (estado == 'aceptada') {
      // Find the matching local offer and promote it
      final offerId = row['id'];
      final existing = _driverOffers.firstWhere(
        (o) => o.id == offerId,
        orElse: () => DriverOfferModel.fromJson(row),
      );
      _acceptedOffer = existing.copyWith(estado: EstadoOferta.aceptada);
      _state = TransportState.rideConfirmed;
      notifyListeners();
    }
  }

  /// Called when the solicitud itself is updated (e.g. cancelled externally).
  void _onSolicitudEstadoChange(String newEstado) {
    if (newEstado == 'cancelada') {
      _state = TransportState.idle;
      _activeRequest = null;
      _driverOffers = [];
      notifyListeners();
    } else if (newEstado == 'aceptada' && _state == TransportState.waitingOffers) {
      // Already handled via _onOfertaUpdate; ignore duplicate signal
    } else if (newEstado == 'completada') {
      _state = TransportState.rideCompleted;
      notifyListeners();
    }
  }

  Future<void> acceptOffer(DriverOfferModel offer) async {
    try {
      final solicitud = await _requestService.acceptOffer(offer.id!);
      _acceptedOffer = offer.copyWith(estado: EstadoOferta.aceptada);

      // Create viaje row so driver can track destination in real-time
      final latDest = (solicitud['lat_destino'] as num?)?.toDouble();
      final lonDest = (solicitud['lon_destino'] as num?)?.toDouble();
      final userId = solicitud['user_id'] as String?;
      final driverId = offer.driverId;

      if (driverId != null && userId != null && latDest != null && lonDest != null) {
        final viaje = await _driverService.createViaje(
          driverId: driverId,
          userId: userId,
          latDestino: latDest,
          lonDestino: lonDest,
        );
        _activeViajeId = viaje['id'] as int?;
      }

      _state = TransportState.rideConfirmed;
      notifyListeners();
    } catch (e) {
      _error = 'Error aceptando oferta: $e';
      notifyListeners();
    }
  }

  /// Restores a pending request from history so the user can resume offer search.
  Future<void> restoreActiveRequest(TransportRequestModel request) async {
    _activeRequest = request;
    if (request.latOrigen != null && request.lonOrigen != null) {
      _pickupLocation = LatLng(request.latOrigen!, request.lonOrigen!);
    }
    if (request.latDestino != null && request.lonDestino != null) {
      _dropoffLocation = LatLng(request.latDestino!, request.lonDestino!);
    }
    _pickupAddress = request.direccionOrigen;
    _dropoffAddress = request.direccionDestino;
    _routeDistanceKm = request.distanciaKm ?? 0;
    _offerPrice = request.precioOferta ?? 0;
    _state = TransportState.waitingOffers;
    if (request.id != null) {
      final rid = request.id!;
      // Load existing offers first, then subscribe for new ones
      _driverOffers = await _requestService.getExistingOffers(rid);
      _requestService.subscribeToOffers(rid, _onNewOffer);
      _requestService.subscribeToOfertaUpdates(rid, _onOfertaUpdate);
      _requestService.subscribeToSolicitudChanges(rid, _onSolicitudEstadoChange);
    }
    notifyListeners();
  }

  /// Restores an accepted (in-progress) ride from history.
  /// Loads the accepted offer so RideConfirmedScreen can show real driver data.
  Future<void> restoreAcceptedRide(TransportRequestModel request) async {
    _activeRequest = request;
    if (request.latOrigen != null && request.lonOrigen != null) {
      _pickupLocation = LatLng(request.latOrigen!, request.lonOrigen!);
    }
    if (request.latDestino != null && request.lonDestino != null) {
      _dropoffLocation = LatLng(request.latDestino!, request.lonDestino!);
    }
    _pickupAddress = request.direccionOrigen;
    _dropoffAddress = request.direccionDestino;
    _routeDistanceKm = request.distanciaKm ?? 0;
    _offerPrice = request.precioOferta ?? 0;

    if (request.id != null) {
      final rid = request.id!;
      // Find the accepted offer for this solicitud
      final offers = await _requestService.getExistingOffers(rid);
      final accepted = offers.where((o) => o.estado == EstadoOferta.aceptada);
      if (accepted.isNotEmpty) {
        _acceptedOffer = accepted.first;
      } else if (offers.isNotEmpty) {
        _acceptedOffer = offers.first;
      }
      // Keep listening for solicitud estado changes (e.g. completada)
      _requestService.subscribeToSolicitudChanges(rid, _onSolicitudEstadoChange);
    }

    _state = TransportState.rideConfirmed;
    notifyListeners();
  }

  Future<void> cancelRequest() async {
    if (_activeRequest?.id == null) return;
    try {
      await _requestService.cancelRequest(_activeRequest!.id!);
      _requestService.unsubscribe();
      resetTrip();
    } catch (e) {
      _error = 'Error cancelando solicitud: $e';
      notifyListeners();
    }
  }

  void resetTrip() {
    _pickupLocation = null;
    _dropoffLocation = null;
    _pickupAddress = null;
    _dropoffAddress = null;
    _routePolyline = null;
    _routeDistanceKm = 0;
    _routeDurationMin = 0;
    _activeRequest = null;
    _driverOffers = [];
    _acceptedOffer = null;
    _activeViajeId = null;
    _state = TransportState.idle;
    _error = null;
    if (_vehicleTypes.isNotEmpty) {
      _selectedVehicleType = _vehicleTypes.first;
    }
    _requestService.unsubscribe();
    notifyListeners();
  }

  @override
  void dispose() {
    _requestService.unsubscribe();
    super.dispose();
  }
}

enum TransportState {
  idle,
  calculatingRoute,
  routeReady,
  requesting,
  waitingOffers,
  rideConfirmed,
  rideInProgress,
  rideCompleted,
  error,
}
