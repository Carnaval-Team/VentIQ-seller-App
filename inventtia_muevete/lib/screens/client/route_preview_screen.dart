import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../providers/transport_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../utils/constants.dart';
import '../../utils/gate_seguridad.dart';
import '../../utils/helpers.dart';
import '../../widgets/map_widget.dart';
import 'driver_offers_screen.dart';

/// Vista previa de la ruta con el precio calculado por la plataforma.
///
/// El monto es de SÓLO LECTURA: no hay campo de precio, slider ni botón de
/// ofertar. El cliente elige tipo de vehículo, pasajeros y método de pago.
class RoutePreviewScreen extends StatefulWidget {
  const RoutePreviewScreen({super.key});

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  final MapController _mapController = MapController();
  String _metodoPago = 'efectivo';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _inicializar());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _inicializar() async {
    final tp = context.read<TransportProvider>();
    tp.loadVehicleTypes();
    tp.startVehicleTypesRealtime();

    await tp.cargarCatalogoVehiculos();
    if (!mounted) return;

    await tp.calculateRoute();
    if (!mounted) return;

    // Si la ruta no llegó a cotizar (o el catálogo cargó después), forzamos.
    if (tp.cotizacion == null) {
      await tp.cotizar();
    }
  }

  Future<void> _reintentarCotizacion() async {
    final tp = context.read<TransportProvider>();
    if (tp.cotizacion == null) {
      await tp.cotizar();
    } else {
      await tp.calculateRoute();
    }
  }

  void _mostrarMensaje(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto, style: GoogleFonts.plusJakartaSans()),
        backgroundColor: error ? AppTheme.error : AppTheme.success,
      ),
    );
  }

  Future<void> _onSolicitar() async {
    final tp = context.read<TransportProvider>();
    final auth = context.read<AuthProvider>();
    final wallet = context.read<WalletProvider>();
    final cotizacion = tp.cotizacion;
    if (cotizacion == null) {
      _mostrarMensaje('Espera a que se calcule la tarifa.', error: true);
      return;
    }

    if (_metodoPago == 'wallet') {
      final userId = auth.user?.id ?? '';
      await wallet.loadClientBalance(userId);
      if (!mounted) return;
      if (!wallet.hasSufficientBalance(cotizacion.precioPlataforma)) {
        _mostrarMensaje(
          'Saldo insuficiente: necesitas '
          '${Helpers.formatCup(cotizacion.precioPlataforma)} y tienes '
          '${Helpers.formatCup(wallet.balance)}.',
          error: true,
        );
        return;
      }
      tp.setPaymentMethod('wallet');
    } else {
      tp.setPaymentMethod('efectivo');
    }

    final ok = await tp.crearSolicitud();
    if (!mounted) return;
    if (!ok) {
      // P0050 / P0053 / P0110: en vez de un snackbar genérico, abrir la
      // pantalla que falta (perfil, consentimiento o contacto de emergencia).
      final abierto =
          await GateSeguridad.desdeCodigoError(context, tp.errorClave);
      if (!mounted) return;
      if (!abierto) {
        _mostrarMensaje(tp.error ?? 'No se pudo publicar el viaje.',
            error: true);
      }
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverOffersScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final transportProvider = context.watch<TransportProvider>();
    final isDark = themeProvider.isDark;

    final pickup = transportProvider.pickupLocation;
    final dropoff = transportProvider.dropoffLocation;
    final polyline = transportProvider.routePolyline;

    final markers = <Marker>[];
    if (pickup != null) {
      markers.add(
        Marker(
          point: pickup,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.my_location, color: Colors.white, size: 18),
          ),
        ),
      );
    }
    if (dropoff != null) {
      markers.add(
        Marker(
          point: dropoff,
          width: 60,
          height: 70,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  '${transportProvider.routeDurationMin.round()} min',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.location_on, color: AppTheme.error, size: 30),
            ],
          ),
        ),
      );
    }

    final polylines = <Polyline>[];
    if (polyline != null && polyline.isNotEmpty) {
      polylines.addAll([
        Polyline(points: polyline, strokeWidth: 7.0, color: Colors.white),
        Polyline(
          points: polyline,
          strokeWidth: 4.0,
          color: AppTheme.primaryColor,
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkBg : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'En línea',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapWidget(
              isDark: isDark,
              mapController: _mapController,
              center: pickup ??
                  LatLng(AppConstants.defaultLat, AppConstants.defaultLon),
              zoom: 14.0,
              markers: markers,
              polylines: polylines,
            ),
          ),

          if (transportProvider.state == TransportState.calculatingRoute)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildRouteInfoCard(isDark, transportProvider),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.58,
            minChildSize: 0.12,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const [0.12, 0.58, 0.92],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface(isDark),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 15,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: _buildBottomSheet(
                  isDark,
                  transportProvider,
                  scrollController,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoCard(
    bool isDark,
    TransportProvider transportProvider,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.success,
                ),
              ),
              Container(
                width: 2,
                height: 30,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: CustomPaint(
                  painter: _DashedLinePainter(
                    color: isDark ? Colors.white24 : Colors.grey[400]!,
                  ),
                ),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transportProvider.pickupAddress ?? 'Ubicación actual',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Text(
                  transportProvider.dropoffAddress ?? 'Destino seleccionado',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.edit_outlined,
              color: AppTheme.primaryColor,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet(
    bool isDark,
    TransportProvider tp,
    ScrollController scrollController,
  ) {
    final cotizacion = tp.cotizacion;
    final precio = cotizacion?.precioPlataforma ?? 0;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.shimmer(isDark),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              Icons.verified_outlined,
              size: 18,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Precio calculado por la plataforma',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(isDark),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'El monto no se negocia: es la tarifa oficial del viaje.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppTheme.textTertiary(isDark),
          ),
        ),
        const SizedBox(height: 16),

        // ── Tipo de vehículo ─────────────────────────────────────────────
        Text(
          'Tipo de vehículo',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary(isDark),
          ),
        ),
        const SizedBox(height: 8),
        _buildSelectorVehiculos(isDark, tp),
        const SizedBox(height: 18),

        // ── Pasajeros ────────────────────────────────────────────────────
        Row(
          children: [
            Text(
              'Pasajeros',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary(isDark),
              ),
            ),
            const Spacer(),
            _buildStepperPasajeros(isDark, tp),
          ],
        ),
        const SizedBox(height: 18),

        // ── Desglose de precio (sólo lectura) ───────────────────────────
        _buildTarjetaPrecio(isDark, tp),
        const SizedBox(height: 16),

        // ── Método de pago ───────────────────────────────────────────────
        Text(
          'Método de pago',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary(isDark),
          ),
        ),
        const SizedBox(height: 8),
        _buildSelectorPago(isDark),
        const SizedBox(height: 18),

        // ── CTA ──────────────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (cotizacion == null ||
                    tp.state == TransportState.requesting)
                ? null
                : _onSolicitar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.primaryColor.withValues(
                alpha: 0.35,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: tp.state == TransportState.requesting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cotizacion == null
                          ? 'Solicitar viaje'
                          : 'Solicitar viaje · ${Helpers.formatCup(precio)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Al solicitar aceptas las tarifas vigentes de Muévete.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textTertiary(isDark),
            ),
          ),
        ),
      ],
    );
  }

  // ── Selector de vehículos ───────────────────────────────────────────────

  Widget _buildSelectorVehiculos(bool isDark, TransportProvider tp) {
    if (tp.cargandoCatalogo && tp.catalogoVehiculos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (tp.catalogoVehiculos.isEmpty) {
      return _buildAviso(
        isDark,
        icono: Icons.directions_car_outlined,
        mensaje: tp.errorCatalogo ?? 'No hay tipos de vehículo disponibles.',
        accion: 'Reintentar',
        onAccion: () => tp.cargarCatalogoVehiculos(force: true),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tp.catalogoVehiculos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final vehiculo = tp.catalogoVehiculos[i];
          final seleccionado = tp.vehiculoSeleccionado?.id == vehiculo.id;
          return GestureDetector(
            onTap: () => tp.setVehiculo(vehiculo),
            child: Container(
              width: 104,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: seleccionado
                    ? AppTheme.primaryColor.withValues(alpha: 0.12)
                    : AppTheme.card(isDark),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: seleccionado
                      ? AppTheme.primaryColor
                      : AppTheme.border(isDark),
                  width: seleccionado ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    vehiculo.icon,
                    size: 26,
                    color: seleccionado
                        ? AppTheme.primaryColor
                        : AppTheme.iconColor(isDark),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    vehiculo.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: seleccionado
                          ? AppTheme.primaryColor
                          : AppTheme.textPrimary(isDark),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${vehiculo.pasajerosMax} pas.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: AppTheme.textTertiary(isDark),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Stepper de pasajeros ────────────────────────────────────────────────

  Widget _buildStepperPasajeros(bool isDark, TransportProvider tp) {
    final max = tp.pasajerosMax;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: tp.pasajeros > 1
                ? () => tp.setPasajeros(tp.pasajeros - 1)
                : null,
            icon: const Icon(Icons.remove, size: 18),
            tooltip: 'Quitar pasajero',
          ),
          SizedBox(
            width: 26,
            child: Text(
              '${tp.pasajeros}',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(isDark),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: tp.pasajeros < max
                ? () => tp.setPasajeros(tp.pasajeros + 1)
                : null,
            icon: const Icon(Icons.add, size: 18),
            tooltip: 'Añadir pasajero',
          ),
        ],
      ),
    );
  }

  // ── Tarjeta de precio (sólo lectura) ────────────────────────────────────

  Widget _buildTarjetaPrecio(bool isDark, TransportProvider tp) {
    final cotizacion = tp.cotizacion;

    if (tp.cotizando || (cotizacion == null && tp.errorCotizacion == null)) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border(isDark)),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (cotizacion == null) {
      return _buildAviso(
        isDark,
        icono: Icons.error_outline,
        mensaje: tp.errorCotizacion ??
            'No se pudo calcular la tarifa del viaje.',
        accion: 'Reintentar',
        onAccion: _reintentarCotizacion,
      );
    }

    final recargo = cotizacion.recargoNocturno;
    final base = cotizacion.precioAntesRedondeo - recargo;

    return Container(
      key: const Key('precio_plataforma_readonly'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 15,
                color: AppTheme.textTertiary(isDark),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cotizacion.zonaEtiqueta,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  cotizacion.tarifaModoEtiqueta,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _filaDesglose(
            isDark,
            etiqueta: 'Tarifa de la zona',
            detalle: '${cotizacion.kmTotal.toStringAsFixed(1)} km',
            valor: Helpers.formatCup(base),
          ),
          _filaDesglose(
            isDark,
            etiqueta: 'Recargo nocturno',
            valor: cotizacion.esNocturno && recargo > 0
                ? Helpers.formatCupSigned(recargo)
                : '—',
            resaltado: cotizacion.esNocturno && recargo > 0,
          ),
          if (cotizacion.aplicaPrecioCorto)
            _filaDesglose(
              isDark,
              etiqueta: 'Precio corto aplicado',
              detalle: 'trayecto corto',
              valor: 'Incluido',
              resaltado: true,
            ),
          const Divider(height: 20),
          _filaDesglose(
            isDark,
            etiqueta: 'Subtotal',
            valor: Helpers.formatCup(cotizacion.precioAntesRedondeo),
          ),
          _filaDesglose(
            isDark,
            etiqueta: 'Redondeo',
            valor: cotizacion.redondeoCup == 0
                ? '—'
                : Helpers.formatCupSigned(cotizacion.redondeoCup),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'TOTAL',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.textSecondary(isDark),
                  ),
                ),
              ),
              Text(
                Helpers.formatCup(cotizacion.precioPlataforma),
                key: const Key('precio_plataforma_valor'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary(isDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: AppTheme.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cotizacion.comisionMonto > 0
                        ? 'Incluye ${Helpers.formatCup(cotizacion.comisionMonto)} '
                            'de servicio de la plataforma'
                        : 'Sin cargo de servicio',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.success,
                    ),
                  ),
                ),
                Text(
                  '${cotizacion.comisionPct.toStringAsFixed(0)}% servicio',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(isDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaDesglose(
    bool isDark, {
    required String etiqueta,
    required String valor,
    String? detalle,
    bool resaltado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                text: etiqueta,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppTheme.textSecondary(isDark),
                ),
                children: detalle == null
                    ? null
                    : [
                        TextSpan(
                          text: '  ·  $detalle',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppTheme.textTertiary(isDark),
                          ),
                        ),
                      ],
              ),
            ),
          ),
          Text(
            valor,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: resaltado
                  ? AppTheme.warning
                  : AppTheme.textPrimary(isDark),
            ),
          ),
        ],
      ),
    );
  }

  // ── Selector de pago ────────────────────────────────────────────────────

  Widget _buildSelectorPago(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _opcionPago(
            isDark,
            key: 'efectivo',
            icono: Icons.payments_outlined,
            etiqueta: 'Efectivo',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _opcionPago(
            isDark,
            key: 'wallet',
            icono: Icons.account_balance_wallet_outlined,
            etiqueta: 'Wallet',
          ),
        ),
      ],
    );
  }

  Widget _opcionPago(
    bool isDark, {
    required String key,
    required IconData icono,
    required String etiqueta,
  }) {
    final seleccionado = _metodoPago == key;
    return GestureDetector(
      onTap: () => setState(() => _metodoPago = key),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: seleccionado
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                seleccionado ? AppTheme.primaryColor : AppTheme.border(isDark),
            width: seleccionado ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icono,
              size: 19,
              color: seleccionado
                  ? AppTheme.primaryColor
                  : AppTheme.iconColor(isDark),
            ),
            const SizedBox(width: 8),
            Text(
              etiqueta,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: seleccionado
                    ? AppTheme.primaryColor
                    : AppTheme.textPrimary(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Aviso reutilizable (vacío / error) ──────────────────────────────────

  Widget _buildAviso(
    bool isDark, {
    required IconData icono,
    required String mensaje,
    String? accion,
    VoidCallback? onAccion,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(
        children: [
          Icon(icono, size: 28, color: AppTheme.textTertiary(isDark)),
          const SizedBox(height: 8),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
          if (accion != null && onAccion != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: onAccion,
              child: Text(
                accion,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Custom painter for dashed vertical line between pickup and dropoff dots.
class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 4.0;
    const dashSpace = 3.0;
    double startY = 0;

    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}