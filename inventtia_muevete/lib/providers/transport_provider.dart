import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/transport_request_model.dart';
import '../models/driver_offer_model.dart';
import '../services/transport_request_service.dart';
import '../services/routing_service.dart';
import '../utils/constants.dart';

class TransportProvider extends ChangeNotifier {
  final TransportRequestService _requestService = TransportRequestService();
  final RoutingService _routingService = RoutingService();

  // Route planning
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  String? _pickupAddress;
  String? _dropoffAddress;
  List<LatLng>? _routePolyline;
  double _routeDistanceKm = 0;
  double _routeDurationMin = 0;

  // Transport selection
  String _selectedVehicleType = AppConstants.vehicleAuto;
  double _offerPrice = 0;
  double _pricePerKm = 1.0;

  // Active request
  TransportRequestModel? _activeRequest;
  List<DriverOfferModel> _driverOffers = [];
  DriverOfferModel? _acceptedOffer;

  // State
  TransportState _state = TransportState.idle;
  String? _error;

  // Getters
  LatLng? get pickupLocation => _pickupLocation;
  LatLng? get dropoffLocation => _dropoffLocation;
  String? get pickupAddress => _pickupAddress;
  String? get dropoffAddress => _dropoffAddress;
  List<LatLng>? get routePolyline => _routePolyline;
  double get routeDistanceKm => _routeDistanceKm;
  double get routeDurationMin => _routeDurationMin;
  String get selectedVehicleType => _selectedVehicleType;
  double get offerPrice => _offerPrice;
  TransportRequestModel? get activeRequest => _activeRequest;
  List<DriverOfferModel> get driverOffers => _driverOffers;
  DriverOfferModel? get acceptedOffer => _acceptedOffer;
  TransportState get state => _state;
  String? get error => _error;
  bool get hasRoute => _routePolyline != null && _routePolyline!.isNotEmpty;

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

  void setVehicleType(String type) {
    _selectedVehicleType = type;
    _calculatePrice();
    notifyListeners();
  }

  void setOfferPrice(double price) {
    _offerPrice = price;
    notifyListeners();
  }

  void setPricePerKm(double price) {
    _pricePerKm = price;
    _calculatePrice();
    notifyListeners();
  }

  void _calculatePrice() {
    double multiplier = 1.0;
    switch (_selectedVehicleType) {
      case AppConstants.vehicleMoto:
        multiplier = 0.6;
        break;
      case AppConstants.vehicleAuto:
        multiplier = 1.0;
        break;
      case AppConstants.vehicleMicrobus:
        multiplier = 0.4;
        break;
    }
    _offerPrice =
        double.parse((_routeDistanceKm * _pricePerKm * multiplier).toStringAsFixed(2));
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
    if (_pickupLocation == null || _dropoffLocation == null) return;

    _state = TransportState.requesting;
    notifyListeners();

    try {
      final expiresAt = DateTime.now().add(AppConstants.requestTtl);
      final request = TransportRequestModel(
        userId: userId,
        latOrigen: _pickupLocation!.latitude,
        lonOrigen: _pickupLocation!.longitude,
        latDestino: _dropoffLocation!.latitude,
        lonDestino: _dropoffLocation!.longitude,
        tipoVehiculo: TipoVehiculo.values.firstWhere(
          (e) => e.name == _selectedVehicleType.toLowerCase(),
          orElse: () => TipoVehiculo.auto,
        ),
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
        _requestService.subscribeToOffers(
          _activeRequest!.id!,
          _onNewOffer,
        );
      }

      _state = TransportState.waitingOffers;
      notifyListeners();
    } catch (e) {
      _error = 'Error enviando solicitud: $e';
      _state = TransportState.error;
      notifyListeners();
    }
  }

  void _onNewOffer(DriverOfferModel offer) {
    _driverOffers.add(offer);
    notifyListeners();
  }

  Future<void> acceptOffer(DriverOfferModel offer) async {
    try {
      await _requestService.acceptOffer(offer.id!);
      _acceptedOffer = offer.copyWith(estado: EstadoOferta.aceptada);
      _state = TransportState.rideConfirmed;
      notifyListeners();
    } catch (e) {
      _error = 'Error aceptando oferta: $e';
      notifyListeners();
    }
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
    _state = TransportState.idle;
    _error = null;
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
