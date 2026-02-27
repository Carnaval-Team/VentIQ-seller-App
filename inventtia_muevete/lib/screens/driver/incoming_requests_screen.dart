import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_theme.dart';
import '../../models/transport_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/driver_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import 'active_trip_screen.dart';

class IncomingRequestsScreen extends StatefulWidget {
  const IncomingRequestsScreen({super.key});

  @override
  State<IncomingRequestsScreen> createState() => _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState extends State<IncomingRequestsScreen>
    with SingleTickerProviderStateMixin {
  final DriverService _driverService = DriverService();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<TransportRequestModel> _pendingRequests = [];
  List<_AcceptedRequest> _acceptedRequests = [];
  bool _isLoading = true;
  String? _error;

  late TabController _tabController;
  RealtimeChannel? _newSolicitudChannel;
  RealtimeChannel? _ofertaUpdateChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadAll();
      _subscribeRealtime();
    });
  }

  /// Subscribe to:
  /// 1. New pending solicitudes (INSERT) → add to pending tab if nearby
  /// 2. Driver's own ofertas being updated (UPDATE) → refresh accepted tab
  void _subscribeRealtime() {
    final authProvider = context.read<AuthProvider>();
    final rawId = authProvider.driverProfile?['id'];
    final driverId =
        rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

    // 1 — New solicitud inserts: reload pending list
    _newSolicitudChannel = _supabase
        .channel('driver_new_solicitudes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'muevete',
          table: 'solicitudes_transporte',
          callback: (_) {
            if (mounted) _loadNearbyPending();
          },
        )
        .subscribe();

    // 2 — Solicitud updates (accepted/cancelled/completed): reload pending + accepted
    _supabase
        .channel('driver_solicitud_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'muevete',
          table: 'solicitudes_transporte',
          callback: (_) {
            if (mounted) _loadAll();
          },
        )
        .subscribe();

    // 3 — This driver's oferta updates (e.g. client accepted) → refresh accepted
    if (driverId != null) {
      _ofertaUpdateChannel = _supabase
          .channel('driver_oferta_updates_$driverId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'muevete',
            table: 'ofertas_chofer',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'driver_id',
              value: driverId.toString(),
            ),
            callback: (payload) async {
              if (!mounted) return;
              final newEstado = payload.newRecord['estado'] as String?;
              if (newEstado == 'aceptada') {
                // Switch to accepted tab, reload, then auto-open the active trip
                _tabController.animateTo(1);
                await _loadAccepted();
                if (!mounted) return;
                // Find the newly accepted request and navigate
                if (_acceptedRequests.isNotEmpty) {
                  final solicitudId = payload.newRecord['solicitud_id'] as int?;
                  final ar = solicitudId != null
                      ? _acceptedRequests.firstWhere(
                          (r) => r.solicitud.id == solicitudId,
                          orElse: () => _acceptedRequests.first,
                        )
                      : _acceptedRequests.first;
                  _openActiveTrip(ar);
                }
              } else {
                _loadAll();
              }
            },
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_newSolicitudChannel != null) {
      try {
        _supabase.removeChannel(_newSolicitudChannel!);
      } catch (_) {}
    }
    if (_ofertaUpdateChannel != null) {
      try {
        _supabase.removeChannel(_ofertaUpdateChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await Future.wait([
        _loadNearbyPending(),
        _loadAccepted(),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadNearbyPending() async {
    final locationProvider = context.read<LocationProvider>();
    final location = locationProvider.locationOrDefault;

    final response = await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .select()
        .eq('estado', 'pendiente')
        .order('created_at', ascending: false);

    final allRequests = (response as List<dynamic>)
        .map((e) => TransportRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final nearby = allRequests.where((r) {
      final lat = r.latOrigen;
      final lon = r.lonOrigen;
      if (lat == null || lon == null) return false;
      return _haversine(location.latitude, location.longitude, lat, lon) <=
          AppConstants.defaultSearchRadiusKm;
    }).toList();

    if (mounted) setState(() => _pendingRequests = nearby);
  }

  Future<void> _loadAccepted() async {
    final authProvider = context.read<AuthProvider>();
    final rawId = authProvider.driverProfile?['id'];
    final driverId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (driverId == null) return;

    // Fetch ofertas_chofer with estado=aceptada for this driver
    // (the client accepted this driver's offer → solicitud.estado = 'aceptada')
    final ofertas = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .select('id, solicitud_id, precio, tiempo_estimado, mensaje')
        .eq('driver_id', driverId)
        .eq('estado', 'aceptada');

    final List<_AcceptedRequest> accepted = [];
    for (final oferta in (ofertas as List<dynamic>)) {
      final solicitudId = oferta['solicitud_id'] as int?;
      if (solicitudId == null) continue;

      // Fetch the solicitud
      final solicitudRow = await _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .select()
          .eq('id', solicitudId)
          .maybeSingle();
      if (solicitudRow == null) continue;

      // Only show non-completed solicitudes
      final estado = solicitudRow['estado'] as String? ?? '';
      if (estado == 'completada' || estado == 'cancelada') continue;

      final solicitud =
          TransportRequestModel.fromJson(solicitudRow);

      // Fetch client phone from muevete.users via uuid = user_id
      String? clientPhone;
      String? clientName;
      final userId = solicitudRow['user_id'] as String?;
      if (userId != null) {
        final userRow = await _supabase
            .schema('muevete')
            .from('users')
            .select('phone, name')
            .eq('uuid', userId)
            .maybeSingle();
        clientPhone = userRow?['phone'] as String?;
        clientName = userRow?['name'] as String?;
      }

      accepted.add(_AcceptedRequest(
        solicitud: solicitud,
        ofertaId: oferta['id'] as int?,
        precio: (oferta['precio'] as num?)?.toDouble(),
        tiempoEstimado: oferta['tiempo_estimado'] as int?,
        mensaje: oferta['mensaje'] as String?,
        clientPhone: clientPhone,
        clientName: clientName,
      ));
    }

    if (mounted) setState(() => _acceptedRequests = accepted);
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
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
                  'Precio del cliente: ${Helpers.formatCurrency(request.precioOferta ?? 0)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryLight,
                  ),
                ),
                const SizedBox(height: 20),
                _sheetField(
                  label: 'Tu precio (\$)',
                  controller: priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  prefixText: '\$ ',
                ),
                const SizedBox(height: 16),
                _sheetField(
                  label: 'Tiempo estimado (min)',
                  controller: estimatedMinController,
                  keyboardType: TextInputType.number,
                  suffixText: 'min',
                ),
                const SizedBox(height: 16),
                _sheetField(
                  label: 'Mensaje (opcional)',
                  controller: messageController,
                  maxLines: 2,
                  hint: 'Ej: Llego en 5 minutos...',
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

  Widget _sheetField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? prefixText,
    String? suffixText,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.3),
            ),
            prefixText: prefixText,
            prefixStyle: GoogleFonts.plusJakartaSans(
              color: AppTheme.primaryColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            suffixText: suffixText,
            suffixStyle: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: const Color(0xFF111621),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppTheme.primaryColor, width: 2),
            ),
          ),
        ),
      ],
    );
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
        _loadAll();
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

  Future<void> _completeRide(_AcceptedRequest ar) async {
    final solicitudId = ar.solicitud.id;
    if (solicitudId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2232),
        title: Text(
          'Completar viaje',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '¿Confirmas que el viaje ha finalizado?',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
            ),
            child: Text(
              'Completar',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .update({'estado': 'completada'}).eq('id', solicitudId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Viaje completado',
              style: GoogleFonts.plusJakartaSans(),
            ),
            backgroundColor: AppTheme.success,
          ),
        );
        _loadAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  /// Looks up the viaje for this solicitud, then pushes ActiveTripScreen.
  Future<void> _openActiveTrip(_AcceptedRequest ar) async {
    final solicitudId = ar.solicitud.id;
    if (solicitudId == null) return;

    final destLat = ar.solicitud.latDestino;
    final destLon = ar.solicitud.lonDestino;
    if (destLat == null || destLon == null) return;

    // Find the active viaje for this solicitud's driver + matching destination
    final authProvider = context.read<AuthProvider>();
    final rawId = authProvider.driverProfile?['id'];
    final driverId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');

    Map<String, dynamic>? viajeRow;
    if (driverId != null) {
      try {
        final rows = await _supabase
            .schema('muevete')
            .from('viajes')
            .select()
            .eq('driver_id', driverId)
            .eq('completado', false)
            .order('created_at', ascending: false)
            .limit(1);
        if ((rows as List).isNotEmpty) {
          viajeRow = rows.first;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveTripScreen(
          viajeId: viajeRow?['id'] as int? ?? 0,
          destLat: destLat,
          destLon: destLon,
          destAddress: ar.solicitud.direccionDestino,
          clientPhone: ar.clientPhone,
          clientName: ar.clientName,
        ),
      ),
    );
  }

  Future<void> _launchCall(String phone) async {
    final url = Uri.parse(Helpers.buildPhoneUrl(phone));
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _launchWhatsApp(String phone) async {
    final url = Uri.parse(
      Helpers.buildWhatsAppUrl(phone, message: 'Hola, soy tu conductor'),
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111621),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111621),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Actividad',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: Colors.white38,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: [
            Tab(
              text:
                  'Pendientes${_pendingRequests.isNotEmpty ? ' (${_pendingRequests.length})' : ''}',
            ),
            Tab(
              text:
                  'Aceptadas${_acceptedRequests.isNotEmpty ? ' (${_acceptedRequests.length})' : ''}',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : _error != null
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPendingTab(),
                    _buildAcceptedTab(),
                  ],
                ),
    );
  }

  Widget _buildPendingTab() {
    if (_pendingRequests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.location_off_outlined,
        title: 'No hay solicitudes cercanas',
        subtitle: 'Las nuevas solicitudes aparecerán aquí',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF1A2232),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingRequests.length,
        itemBuilder: (context, index) =>
            _buildPendingItem(_pendingRequests[index]),
      ),
    );
  }

  Widget _buildAcceptedTab() {
    if (_acceptedRequests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Sin viajes aceptados',
        subtitle: 'Los viajes que aceptes aparecerán aquí',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: AppTheme.primaryColor,
      backgroundColor: const Color(0xFF1A2232),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _acceptedRequests.length,
        itemBuilder: (context, index) =>
            _buildAcceptedItem(_acceptedRequests[index]),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40,
                color: Colors.white.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              'Actualizar',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: const BorderSide(color: AppTheme.primaryColor),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 16),
          Text(
            'Error al cargar solicitudes',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? '',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadAll,
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingItem(TransportRequestModel request) {
    final vehicleType = request.tipoVehiculo ?? 'auto';
    final vehicleLabel =
        vehicleType[0].toUpperCase() + vehicleType.substring(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2232),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  AppConstants.vehicleIconData(vehicleLabel),
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (request.createdAt != null)
                      Text(
                        Helpers.formatRelativeTime(request.createdAt!),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          const SizedBox(height: 16),

          // Route
          _buildRouteInfo(
              request.direccionOrigen, request.direccionDestino),
          const SizedBox(height: 12),

          // Footer
          Row(
            children: [
              Icon(Icons.straighten,
                  color: Colors.white.withValues(alpha: 0.5), size: 16),
              const SizedBox(width: 6),
              Text(
                Helpers.formatDistance(request.distanciaKm ?? 0),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _showMakeOfferDialog(request),
                  icon: const Icon(Icons.local_offer, size: 16),
                  label: Text(
                    'Hacer Oferta',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedItem(_AcceptedRequest ar) {
    final request = ar.solicitud;
    final vehicleType = request.tipoVehiculo ?? 'auto';
    final vehicleLabel =
        vehicleType[0].toUpperCase() + vehicleType.substring(1);
    final hasPhone =
        ar.clientPhone != null && ar.clientPhone!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2232),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.success.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  AppConstants.vehicleIconData(vehicleLabel),
                  color: AppTheme.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ar.clientName != null && ar.clientName!.isNotEmpty
                          ? ar.clientName!
                          : 'Cliente',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      vehicleLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Accepted badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppTheme.success, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Aceptada',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Price + ETA row
          Row(
            children: [
              if (ar.precio != null) ...[
                Icon(Icons.attach_money,
                    color: AppTheme.success, size: 16),
                const SizedBox(width: 4),
                Text(
                  Helpers.formatCurrency(ar.precio!),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 16),
              ],
              if (ar.tiempoEstimado != null) ...[
                Icon(Icons.schedule,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 16),
                const SizedBox(width: 4),
                Text(
                  '${ar.tiempoEstimado} min',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Route
          _buildRouteInfo(
              request.direccionOrigen, request.direccionDestino),

          // Driver mensaje if any
          if (ar.mensaje != null && ar.mensaje!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF111621),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.4)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ar.mensaje!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Action buttons: call, whatsapp, complete
          Row(
            children: [
              if (hasPhone) ...[
                // Call button
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => _launchCall(ar.clientPhone!),
                    icon: const Icon(Icons.phone, size: 16),
                    label: Text(
                      'Llamar',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // WhatsApp button
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => _launchWhatsApp(ar.clientPhone!),
                    icon: const Icon(Icons.chat, size: 16),
                    label: Text(
                      'WhatsApp',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Ver ruta button
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _openActiveTrip(ar),
                  icon: const Icon(Icons.navigation, size: 16),
                  label: Text(
                    'Ver ruta',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A6FBF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              // Complete button
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _completeRide(ar),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    'Completar',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfo(String? origin, String? destination) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111621),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, color: AppTheme.success, size: 10),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  origin ?? 'Punto de recogida',
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
          Row(
            children: [
              const Icon(Icons.circle, color: AppTheme.error, size: 10),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destination ?? 'Destino',
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
        ],
      ),
    );
  }
}

/// Data holder for an accepted solicitud + client info
class _AcceptedRequest {
  final TransportRequestModel solicitud;
  final int? ofertaId;
  final double? precio;
  final int? tiempoEstimado;
  final String? mensaje;
  final String? clientPhone;
  final String? clientName;

  const _AcceptedRequest({
    required this.solicitud,
    this.ofertaId,
    this.precio,
    this.tiempoEstimado,
    this.mensaje,
    this.clientPhone,
    this.clientName,
  });
}
