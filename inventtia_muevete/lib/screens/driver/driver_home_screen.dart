import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/transport_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/driver_service.dart';
import '../../services/vehicle_type_service.dart';
import '../../models/vehicle_type_model.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import 'active_ride_screen.dart';
import 'incoming_requests_screen.dart';
import 'driver_wallet_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with TickerProviderStateMixin {
  final DriverService _driverService = DriverService();
  final MapController _mapController = MapController();

  bool _isOnline = false;
  bool _isTogglingStatus = false;
  int _currentNavIndex = 0;

  // Periodic location tracker while online
  Timer? _locationTimer;

  // Solicitudes pendientes cercanas cargadas al iniciar / cambiar a online
  List<Map<String, dynamic>> _nearbyRequests = [];

  // IDs de solicitudes a las que el driver ya envió oferta (no mostrar)
  final Set<int> _offeredRequestIds = {};

  final List<TransportRequestModel> _incomingRequests = [];
  AnimationController? _slideController;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController!,
      curve: Curves.easeOutCubic,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDriver();
    });
  }

  Future<void> _initializeDriver() async {
    final locationProvider = context.read<LocationProvider>();
    final authProvider = context.read<AuthProvider>(); // read before await
    await locationProvider.initLocation();
    locationProvider.startTracking();

    if (!mounted) return;
    final driverProfile = authProvider.driverProfile;
    if (driverProfile != null) {
      final estado = driverProfile['estado'] as bool? ?? false;
      setState(() => _isOnline = estado);
      if (_isOnline) {
        _subscribeToRequests();
        _startLocationTracking();
        await _loadNearbyRequests();
      }
    }
  }

  void _startLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) return;
      // Read all context-dependent values synchronously before any await
      final authProvider = context.read<AuthProvider>();
      final driverProfile = authProvider.driverProfile;
      final driverId = driverProfile?['id'] as int?;
      final vehiculo = driverProfile?['vehiculos'] as Map<String, dynamic>?;
      final vehicleId = vehiculo?['id'] as int?;
      if (driverId == null || vehicleId == null) return;
      final loc = context.read<LocationProvider>().locationOrDefault;
      // No more context access after this point
      try {
        await _driverService.upsertDriverLocation(
          driverId: driverId,
          vehicleId: vehicleId,
          lat: loc.latitude,
          lon: loc.longitude,
          online: true,
        );
      } catch (e) {
        dev.log('[Tracking] Error actualizando posición: $e', name: 'DriverHome');
      }
    });
  }

  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _loadNearbyRequests() async {
    if (!mounted) return;
    final driverProfile = context.read<AuthProvider>().driverProfile;
    final driverId = driverProfile?['id'] as int?;
    final loc = context.read<LocationProvider>().locationOrDefault;
    try {
      final rows = await _driverService.fetchNearbyPendingRequests(
        loc.latitude,
        loc.longitude,
        AppConstants.defaultSearchRadiusKm,
      );

      // Load IDs where this driver already has an offer, filter them out
      final Set<int> alreadyOffered = {};
      if (driverId != null) {
        for (final row in rows) {
          final rid = row['id'] as int?;
          if (rid != null) {
            final has = await _driverService.hasExistingOffer(rid, driverId);
            if (has) alreadyOffered.add(rid);
          }
        }
      }

      final filtered =
          rows.where((r) => !alreadyOffered.contains(r['id'])).toList();

      for (final row in filtered) {
        dev.log(
          '[NearbyRequest] id=${row['id']} '
          'origen=(${row['lat_origen']}, ${row['lon_origen']}) '
          'destino=${row['direccion_destino']} precio=${row['precio_oferta']}',
          name: 'DriverHome',
        );
      }

      if (mounted) {
        setState(() {
          _offeredRequestIds.addAll(alreadyOffered);
          _nearbyRequests = filtered;
        });
      }
    } catch (e) {
      dev.log('[NearbyRequest] Error: $e', name: 'DriverHome');
    }
  }

  void _subscribeToRequests() {
    final locationProvider = context.read<LocationProvider>();
    final location = locationProvider.locationOrDefault;

    _driverService.subscribeToRequests(
      location.latitude,
      location.longitude,
      AppConstants.defaultSearchRadiusKm,
      (request) {
        // Skip if we already offered on this request
        if (request.id != null && _offeredRequestIds.contains(request.id)) {
          return;
        }
        if (mounted) {
          setState(() {
            _incomingRequests.insert(0, request);
            _nearbyRequests.removeWhere((r) => r['id'] == request.id);
          });
          _slideController?.forward();
        }
      },
    );
  }

  Future<void> _toggleOnlineStatus() async {
    final authProvider = context.read<AuthProvider>();
    final driverProfile = authProvider.driverProfile;
    if (driverProfile == null) return;

    final driverId = driverProfile['id'] as int?;
    if (driverId == null) return;

    // Block going online if no vehicle assigned
    final vehiculo = driverProfile['vehiculos'] as Map<String, dynamic>?;
    if (vehiculo == null && !_isOnline) {
      _showRegisterVehicleSheet();
      return;
    }

    setState(() => _isTogglingStatus = true);

    try {
      final newStatus = !_isOnline;
      final locationProvider = context.read<LocationProvider>();
      final loc = locationProvider.locationOrDefault;
      final vehicleId = vehiculo?['id'] as int?;

      if (newStatus && vehicleId != null) {
        // Upsert place immediately on go-online (creates row if missing)
        await _driverService.upsertDriverLocation(
          driverId: driverId,
          vehicleId: vehicleId,
          lat: loc.latitude,
          lon: loc.longitude,
          online: true,
        );
      } else {
        // Go offline — update estado only
        await _driverService.toggleOnlineStatus(driverId, false);
      }

      setState(() => _isOnline = newStatus);

      if (newStatus) {
        _subscribeToRequests();
        _startLocationTracking();
        await _loadNearbyRequests();
      } else {
        await _driverService.unsubscribe();
        _stopLocationTracking();
        setState(() {
          _incomingRequests.clear();
          _nearbyRequests.clear();
        });
        _slideController?.reverse();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar estado: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingStatus = false);
    }
  }

  Future<void> _showRegisterVehicleSheet() async {
    final authProvider = context.read<AuthProvider>();
    final driverId = authProvider.driverProfile?['id'] as int?;
    if (driverId == null) return;

    final vehicleTypes = await VehicleTypeService().getActiveTypes();
    if (!mounted) return;

    VehicleTypeModel? selectedType =
        vehicleTypes.isNotEmpty ? vehicleTypes.first : null;
    final marcaCtrl = TextEditingController();
    final modeloCtrl = TextEditingController();
    final chapaCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    final capacidadCtrl = TextEditingController();
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A2232),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Registrar vehículo',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Debes tener un vehículo para activarte',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: Colors.white54)),
                  const SizedBox(height: 20),
                  // Vehicle type selector
                  Text('Tipo de vehículo',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: vehicleTypes.map((vt) {
                      final selected = selectedType?.id == vt.id;
                      return ChoiceChip(
                        label: Text(vt.displayName),
                        selected: selected,
                        onSelected: (_) =>
                            setSheet(() => selectedType = vt),
                        selectedColor: AppTheme.primaryColor,
                        backgroundColor: const Color(0xFF111621),
                        labelStyle: GoogleFonts.plusJakartaSans(
                          color: selected
                              ? Colors.white
                              : Colors.white60,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  _sheetField(marcaCtrl, 'Marca', 'Ej: Toyota'),
                  const SizedBox(height: 12),
                  _sheetField(modeloCtrl, 'Modelo', 'Ej: Corolla'),
                  const SizedBox(height: 12),
                  _sheetField(chapaCtrl, 'Chapa / Matrícula', 'Ej: ABC-1234'),
                  const SizedBox(height: 12),
                  _sheetField(colorCtrl, 'Color', 'Ej: Blanco'),
                  const SizedBox(height: 12),
                  _sheetField(capacidadCtrl, 'Capacidad (pasajeros)', '4',
                      keyboard: TextInputType.number),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: saving
                          ? null
                          : () async {
                              if (selectedType == null ||
                                  marcaCtrl.text.trim().isEmpty ||
                                  modeloCtrl.text.trim().isEmpty ||
                                  chapaCtrl.text.trim().isEmpty ||
                                  colorCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Completa todos los campos')),
                                );
                                return;
                              }
                              setSheet(() => saving = true);
                              try {
                                await _driverService.createVehicleForDriver(
                                  driverId: driverId,
                                  vehicleTypeId: selectedType!.id,
                                  marca: marcaCtrl.text.trim(),
                                  modelo: modeloCtrl.text.trim(),
                                  chapa: chapaCtrl.text.trim(),
                                  color: colorCtrl.text.trim(),
                                  capacidad: capacidadCtrl.text.trim()
                                          .isEmpty
                                      ? null
                                      : capacidadCtrl.text.trim(),
                                );
                                await authProvider.refreshDriverProfile();
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                setSheet(() => saving = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: AppTheme.error),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text('Guardar vehículo',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField(
    TextEditingController ctrl,
    String label,
    String hint, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white70)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          style: GoogleFonts.plusJakartaSans(
              color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
                color: Colors.white30, fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF111621),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: AppTheme.primaryColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  void _dismissRequest(int index) {
    setState(() {
      _incomingRequests.removeAt(index);
    });
    if (_incomingRequests.isEmpty) {
      _slideController?.reverse();
    }
  }

  Future<void> _showMakeOfferDialog(TransportRequestModel request) async {
    final priceController = TextEditingController(
      text: request.precioOferta?.toStringAsFixed(2) ?? '0.00',
    );
    final messageController = TextEditingController();
    final estimatedMinController = TextEditingController(text: '15');

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A2232),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Hacer Oferta',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${request.direccionOrigen ?? "Origen"} -> ${request.direccionDestino ?? "Destino"}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  'Precio del cliente: ${Helpers.formatCurrency(request.precioOferta ?? 0)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryLight,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Tu precio (\$)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: GoogleFonts.plusJakartaSans(
                      color: AppTheme.primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF111621),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tiempo estimado (min)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: estimatedMinController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    suffixText: 'min',
                    suffixStyle: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF111621),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Mensaje (opcional)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  maxLines: 2,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ej: Estoy a 5 minutos de tu ubicación...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF111621),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      final price =
                          double.tryParse(priceController.text) ?? 0;
                      final minutes =
                          int.tryParse(estimatedMinController.text) ?? 15;
                      Navigator.of(ctx).pop({
                        'price': price,
                        'minutes': minutes,
                        'message': messageController.text.isEmpty
                            ? null
                            : messageController.text,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Enviar Oferta',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );

    if (result != null && mounted) {
      await _submitOffer(
        request,
        result['price'] as double,
        result['minutes'] as int,
        result['message'] as String?,
      );
    }
  }

  Future<void> _submitOffer(
    TransportRequestModel request,
    double price,
    int estimatedMinutes,
    String? message,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final driverProfile = authProvider.driverProfile;
    final driverId = driverProfile?['id'] as int?;
    if (driverId == null || request.id == null) return;

    try {
      await _driverService.makeOffer(
        request.id!,
        driverId,
        price,
        estimatedMinutes,
        message: message,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Oferta enviada: ${Helpers.formatCurrency(price)}',
              style: GoogleFonts.plusJakartaSans(),
            ),
            backgroundColor: AppTheme.success,
          ),
        );

        setState(() {
          // Mark as offered so it won't show again in map or cards
          if (request.id != null) _offeredRequestIds.add(request.id!);
          _incomingRequests.removeWhere((r) => r.id == request.id);
          _nearbyRequests.removeWhere((r) => r['id'] == request.id);
        });
        if (_incomingRequests.isEmpty) {
          _slideController?.reverse();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar oferta: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _checkForActiveRide() async {
    final authProvider = context.read<AuthProvider>();
    final driverProfile = authProvider.driverProfile;
    final driverId = driverProfile?['id'] as int?;
    if (driverId == null) return;

    final activeTrip = await _driverService.getActiveTrip(driverId);
    if (activeTrip != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActiveRideScreen(tripData: activeTrip),
        ),
      );
    }
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;

    switch (index) {
      case 0:
        // Already on home
        break;
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const IncomingRequestsScreen(),
          ),
        );
        return;
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DriverWalletScreen(),
          ),
        );
        return;
      case 3:
        // Profile screen placeholder
        break;
    }

    setState(() {
      _currentNavIndex = index;
    });
  }

  @override
  void dispose() {
    _stopLocationTracking();
    _slideController?.dispose();
    _driverService.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;

    final driverProfile = authProvider.driverProfile;
    final driverName = driverProfile?['name'] as String? ?? 'Conductor';
    final vehiculo = driverProfile?['vehiculos'] as Map<String, dynamic>?;
    final vehicleType =
        vehiculo?['vehicle_type'] as Map<String, dynamic>?;
    final location = locationProvider.locationOrDefault;

    final tileUrl =
        isDark ? AppTheme.cartoDarkTileUrl : AppTheme.osmTileUrl;

    return Scaffold(
      backgroundColor: const Color(0xFF111621),
      body: Stack(
        children: [
          // Full-screen map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: location,
              initialZoom: AppConstants.defaultZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'com.inventtia.muevete',
              ),
              MarkerLayer(
                markers: [
                  // Driver marker
                  Marker(
                    point: location,
                    width: 50,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  // Nearby client request markers
                  ..._nearbyRequests.map((row) {
                    final lat = (row['lat_origen'] as num?)?.toDouble();
                    final lon = (row['lon_origen'] as num?)?.toDouble();
                    if (lat == null || lon == null) return null;
                    // No user join (FK to auth.users, inaccessible from REST)
                    final name = row['direccion_origen'] as String? ?? 'Cliente';
                    const String? photoUrl = null;
                    final request = TransportRequestModel.fromJson(row);
                    return Marker(
                      point: LatLng(lat, lon),
                      width: 56,
                      height: 56,
                      child: GestureDetector(
                        onTap: () => _showMakeOfferDialog(request),
                        child: Tooltip(
                          message: name,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.success.withValues(alpha: 0.45),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: photoUrl != null && photoUrl.isNotEmpty
                                  ? Image.network(
                                      photoUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Text(
                                          name[0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        name[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).whereType<Marker>(),
                ],
              ),
            ],
          ),

          // Top bar with greeting and online toggle
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2232).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name + status + vehicle info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hola, $driverName',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isOnline
                                      ? AppTheme.success
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _isOnline ? 'En línea' : 'Desconectado',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: _isOnline
                                      ? AppTheme.success
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Vehicle chip
                          vehiculo != null
                              ? GestureDetector(
                                  onTap: _showRegisterVehicleSheet,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: AppTheme.primaryColor
                                              .withValues(alpha: 0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.directions_car,
                                            color: AppTheme.primaryColor,
                                            size: 12),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${vehiculo['marca'] ?? ''} ${vehiculo['modelo'] ?? ''} · ${vehiculo['chapa'] ?? ''}'
                                              .trim(),
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryColor,
                                          ),
                                        ),
                                        if (vehicleType != null) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            '(${vehicleType['tipo'] ?? ''})',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 10,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                )
                              : GestureDetector(
                                  onTap: _showRegisterVehicleSheet,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.error
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: AppTheme.error
                                              .withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.warning_amber_rounded,
                                            color: AppTheme.error, size: 12),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Sin vehículo · Registrar',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.error,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                    // Online toggle
                    _isTogglingStatus
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryColor,
                            ),
                          )
                        : Switch(
                            value: _isOnline,
                            onChanged: (_) => _toggleOnlineStatus(),
                            activeColor: AppTheme.success,
                            activeTrackColor:
                                AppTheme.success.withValues(alpha: 0.3),
                            inactiveThumbColor: vehiculo == null
                                ? AppTheme.error
                                : Colors.grey,
                            inactiveTrackColor: vehiculo == null
                                ? AppTheme.error.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.3),
                          ),
                  ],
                ),
              ),
            ),
          ),

          // Re-center button
          Positioned(
            right: 16,
            bottom: _incomingRequests.isNotEmpty ? 340 : 100,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: () {
                _mapController.move(location, AppConstants.defaultZoom);
              },
              backgroundColor: const Color(0xFF1A2232),
              child: const Icon(
                Icons.my_location,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
          ),

          // Check active ride button
          if (_isOnline)
            Positioned(
              left: 16,
              bottom: _incomingRequests.isNotEmpty ? 340 : 100,
              child: FloatingActionButton.small(
                heroTag: 'activeride',
                onPressed: _checkForActiveRide,
                backgroundColor: const Color(0xFF1A2232),
                child: const Icon(
                  Icons.route,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
            ),

          // Incoming request cards sliding from bottom
          if (_incomingRequests.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 80,
              child: SlideTransition(
                position: _slideAnimation!,
                child: SizedBox(
                  height: 250,
                  child: PageView.builder(
                    itemCount: _incomingRequests.length,
                    controller: PageController(viewportFraction: 0.92),
                    itemBuilder: (context, index) {
                      final request = _incomingRequests[index];
                      return _buildRequestCard(request, index);
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
        backgroundColor: const Color(0xFF1A2232),
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            activeIcon: Icon(Icons.list_alt),
            label: 'Viajes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Billetera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(TransportRequestModel request, int index) {
    final vehicleType = request.tipoVehiculo ?? 'auto';
    final vehicleLabel = vehicleType[0].toUpperCase() + vehicleType.substring(1);
    final iconCodePoint =
        AppConstants.vehicleIcons[vehicleLabel] ?? 0xe531;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2232),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: vehicle type + price
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  IconData(iconCodePoint, fontFamily: 'MaterialIcons'),
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                vehicleLabel,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  Helpers.formatCurrency(request.precioOferta ?? 0),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Pickup address
          Row(
            children: [
              const Icon(Icons.circle, color: AppTheme.success, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.direccionOrigen ?? 'Punto de recogida',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Dropoff address
          Row(
            children: [
              const Icon(Icons.circle, color: AppTheme.error, size: 10),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  request.direccionDestino ?? 'Destino',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Distance
          Row(
            children: [
              Icon(
                Icons.straighten,
                color: Colors.white.withValues(alpha: 0.5),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                Helpers.formatDistance(request.distanciaKm ?? 0),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              if (request.createdAt != null) ...[
                const SizedBox(width: 16),
                Icon(
                  Icons.access_time,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  Helpers.formatRelativeTime(request.createdAt!),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),

          const Spacer(),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _dismissRequest(index),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Rechazar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _showMakeOfferDialog(request),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Hacer Oferta',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
