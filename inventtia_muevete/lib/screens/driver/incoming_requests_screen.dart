import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/tarifa_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/transport_provider.dart';
import '../../utils/gate_seguridad.dart';
import '../../utils/helpers.dart';
import 'active_ride_screen.dart';

/// "Viajes disponibles" para el chofer.
///
/// El precio ya viene calculado por la plataforma (`fn_viajes_disponibles`):
/// el chofer sólo decide si lo toma. No se oferta ni se negocia nada.
class IncomingRequestsScreen extends StatefulWidget {
  const IncomingRequestsScreen({super.key});

  @override
  State<IncomingRequestsScreen> createState() => _IncomingRequestsScreenState();
}

class _IncomingRequestsScreenState extends State<IncomingRequestsScreen> {
  TransportProvider? _provider;
  Timer? _tick;
  DateTime _cargadoEn = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Cuenta atrás del TTL: sólo repinta, no vuelve a pedir la lista.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tp = context.read<TransportProvider>();
      _provider = tp;
      _cargadoEn = DateTime.now();
      final ubicacion = context.read<LocationProvider>().locationOrDefault;
      tp.iniciarViajesDisponibles(ubicacion);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _provider?.detenerViajesDisponibles();
    super.dispose();
  }

  Future<void> _recargar() async {
    final tp = _provider ?? context.read<TransportProvider>();
    _cargadoEn = DateTime.now();
    await tp.cargarViajesDisponibles(
      ubicacion: context.read<LocationProvider>().locationOrDefault,
    );
    if (mounted) setState(() {});
  }

  int _segundosRestantes(ViajeDisponible viaje) {
    final transcurridos = DateTime.now().difference(_cargadoEn).inSeconds;
    final restante = viaje.segundosRestantes - transcurridos;
    return restante < 0 ? 0 : restante;
  }

  String _formatoCuenta(int segundos) {
    final minutos = segundos ~/ 60;
    final resto = segundos % 60;
    return '${minutos.toString().padLeft(2, '0')}:'
        '${resto.toString().padLeft(2, '0')}';
  }

  Future<void> _tomar(ViajeDisponible viaje) async {
    final tp = _provider ?? context.read<TransportProvider>();

    // Gate H1/H2 antes de tomar el viaje: identidad, consentimiento y
    // contacto de emergencia. Si falta algo se abre la pantalla que toca.
    final habilitado = await GateSeguridad.asegurar(context);
    if (!mounted || !habilitado) return;

    final resultado = await tp.tomarViaje(viaje.solicitudId);
    if (!mounted) return;

    if (resultado == null) {
      // Si otro chofer llegó primero, el provider ya refrescó la lista.
      await _recargar();
      if (!mounted) return;
      // P0050 / P0053 / P0110: abrir la pantalla que falta.
      final abierto =
          await GateSeguridad.desdeCodigoError(context, tp.errorClave);
      if (!mounted) return;
      if (abierto) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tp.error ?? 'No se pudo tomar el viaje. Intenta de nuevo.',
            style: GoogleFonts.plusJakartaSans(),
          ),
          backgroundColor: tp.errorClave == 'ya_tomado'
              ? AppTheme.warning
              : AppTheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final solicitud = resultado['solicitud'] is Map
        ? Map<String, dynamic>.from(resultado['solicitud'] as Map)
        : const <String, dynamic>{};
    final cliente = resultado['cliente'] is Map
        ? Map<String, dynamic>.from(resultado['cliente'] as Map)
        : const <String, dynamic>{};

    final viajeId = (resultado['viaje_id'] as num?)?.toInt();
    final tripData = <String, dynamic>{
      'solicitud_id': viaje.solicitudId,
      'viaje_id': viajeId,
      'client_name': cliente['name'] as String? ?? 'Pasajero',
      'client_phone': cliente['phone'] as String? ?? '',
      'precio': resultado['precio_plataforma'] ??
          solicitud['precio_plataforma'] ??
          viaje.precioPlataforma,
      'pago_chofer': resultado['precio_chofer'] ?? viaje.precioChofer,
      'comision_pct': resultado['comision_pct'] ?? viaje.comisionPct,
      'comision_monto': resultado['comision_monto'] ?? viaje.comisionMonto,
      'metodo_pago': resultado['metodo_pago'] ?? 'efectivo',
      'direccion_origen':
          solicitud['direccion_origen'] ?? viaje.direccionOrigen,
      'direccion_destino':
          solicitud['direccion_destino'] ?? viaje.direccionDestino,
      'lat_origen': solicitud['lat_origen'] ?? viaje.latOrigen,
      'lon_origen': solicitud['lon_origen'] ?? viaje.lonOrigen,
      'lat_destino': solicitud['lat_destino'] ?? viaje.latDestino,
      'lon_destino': solicitud['lon_destino'] ?? viaje.lonDestino,
      'user_id': solicitud['user_id'] ?? viaje.userId,
      'estado': false,
    };

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveRideScreen(tripData: tripData),
      ),
    );
    if (mounted) await _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final tp = context.watch<TransportProvider>();

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(isDark),
        foregroundColor: AppTheme.textPrimary(isDark),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Viajes disponibles',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: tp.cargandoViajes ? null : _recargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        backgroundColor: AppTheme.surface(isDark),
        onRefresh: _recargar,
        child: _buildCuerpo(isDark, tp),
      ),
    );
  }

  Widget _buildCuerpo(bool isDark, TransportProvider tp) {
    // Primera carga: spinner a pantalla completa.
    if (!tp.viajesCargados && tp.cargandoViajes) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    // Error de red/RPC (lista vacía NO es error).
    if (tp.errorViajes != null && tp.viajesDisponibles.isEmpty) {
      return _estadoConScroll(
        _estado(
          isDark,
          icono: Icons.cloud_off,
          color: AppTheme.error,
          titulo: 'No se pudieron cargar los viajes',
          subtitulo: tp.errorViajes!,
          accion: 'Reintentar',
          onAccion: _recargar,
        ),
      );
    }

    if (tp.viajesDisponibles.isEmpty) {
      return _estadoConScroll(
        _estado(
          isDark,
          icono: Icons.location_searching,
          color: AppTheme.primaryColor,
          titulo: 'Esperando viajes en tu zona...',
          subtitulo: 'Los nuevos viajes aparecen solos. También puedes '
              'actualizar manualmente.',
          accion: 'Actualizar',
          onAccion: _recargar,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: tp.viajesDisponibles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final viaje = tp.viajesDisponibles[i];
        final segundos = _segundosRestantes(viaje);
        return _buildTarjeta(isDark, tp, viaje, segundos);
      },
    );
  }

  Widget _buildTarjeta(
    bool isDark,
    TransportProvider tp,
    ViajeDisponible viaje,
    int segundos,
  ) {
    final tomando = tp.tomandoViajeId == viaje.solicitudId;
    final expirado = segundos <= 0;
    final habilitado = viaje.puedeTomar && !expirado && !tomando;

    final tarjeta = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: viaje.puedeTomar
              ? AppTheme.border(isDark)
              : AppTheme.warning.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado: tipo + zona + distancia al origen
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (viaje.tipoVehiculo ?? 'Viaje').toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              if ((viaje.zonaNombre ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    viaje.zonaNombre!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppTheme.textTertiary(isDark),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (viaje.distanciaAOrigenKm != null) ...[
                Icon(
                  Icons.near_me_outlined,
                  size: 14,
                  color: AppTheme.textSecondary(isDark),
                ),
                const SizedBox(width: 4),
                Text(
                  'a ${viaje.distanciaAOrigenKm!.toStringAsFixed(1)} km de ti',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(isDark),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Ruta origen → destino
          Row(
            children: [
              const Icon(Icons.circle, color: AppTheme.success, size: 9),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  viaje.direccionOrigen ?? 'Punto de recogida',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textPrimary(isDark),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3, top: 2, bottom: 2),
            child: Container(
              width: 1,
              height: 12,
              color: AppTheme.shimmer(isDark),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.circle, color: AppTheme.error, size: 9),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  viaje.direccionDestino ?? 'Destino',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textPrimary(isDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.straighten,
                size: 14,
                color: AppTheme.textTertiary(isDark),
              ),
              const SizedBox(width: 5),
              Text(
                Helpers.formatDistance(viaje.km),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textTertiary(isDark),
                ),
              ),
              const SizedBox(width: 14),
              Icon(
                Icons.person_outline,
                size: 14,
                color: AppTheme.textTertiary(isDark),
              ),
              const SizedBox(width: 5),
              Text(
                viaje.capacidadVehiculo > 0
                    ? '${viaje.pasajeros} pasajeros · tu vehículo: '
                        '${viaje.capacidadVehiculo}'
                    : '${viaje.pasajeros} pasajeros',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textTertiary(isDark),
                ),
              ),
            ],
          ),

          const Divider(height: 22),

          // Dinero — CÓMO SE MUEVE DE VERDAD (no "te tocan X"):
          //   efectivo → el chofer recibe el total en mano y la comisión se le
          //              DESCUENTA del wallet (deuda hasta el tope configurado).
          //   wallet   → se le retiene el total al cliente y se le ABONA el
          //              neto al chofer en su wallet.
          Text(
            viaje.metodoPago == 'wallet'
                ? 'El cliente paga ${Helpers.formatCup(viaje.precioPlataforma)} con wallet'
                : 'El cliente paga ${Helpers.formatCup(viaje.precioPlataforma)} en efectivo',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: (viaje.metodoPago == 'wallet'
                      ? AppTheme.success
                      : AppTheme.warning)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (viaje.metodoPago == 'wallet'
                        ? AppTheme.success
                        : AppTheme.warning)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  viaje.metodoPago == 'wallet'
                      ? Icons.account_balance_wallet_rounded
                      : Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: viaje.metodoPago == 'wallet'
                      ? AppTheme.success
                      : AppTheme.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    viaje.metodoPago == 'wallet'
                        ? 'Se te acreditarán ${Helpers.formatCup(viaje.precioChofer)} en tu wallet'
                        : 'Se te descontarán ${Helpers.formatCup(viaje.comisionMonto)} de tu wallet',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            viaje.metodoPago == 'wallet'
                ? 'El cliente paga con wallet: se retiene el total y a ti se te abona el neto.'
                : 'Recibes el total en mano; la comisión del '
                    '${viaje.comisionPct.toStringAsFixed(0)}% se te cobra como deuda en la wallet.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textTertiary(isDark),
              height: 1.3,
            ),
          ),
          if (viaje.deudaDisponible > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Margen de deuda disponible después de este viaje: '
              '${Helpers.formatCup(viaje.deudaDisponible)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: AppTheme.textTertiary(isDark),
              ),
            ),
          ],

          // Cuenta atrás del TTL
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (expirado ? AppTheme.error : AppTheme.warning)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      expirado ? Icons.timer_off : Icons.timer_outlined,
                      size: 14,
                      color: expirado ? AppTheme.error : AppTheme.warning,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      expirado ? 'Expirado' : _formatoCuenta(segundos),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: expirado ? AppTheme.error : AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // El método de pago no viene en `fn_viajes_disponibles`
              // (sólo en `fn_tomar_viaje`), así que aquí no se muestra.
            ],
          ),

          // Motivo de bloqueo
          if (!viaje.puedeTomar && !expirado) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 15,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      viaje.motivoBloqueo ?? 'No puedes tomar este viaje.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: habilitado ? () => _tomar(viaje) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.border(isDark),
                disabledForegroundColor: AppTheme.textTertiary(isDark),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: tomando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      habilitado
                          ? 'Tomar viaje'
                          : expirado
                              ? 'Solicitud expirada'
                              : 'No disponible',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );

    // Tarjeta atenuada cuando no se puede tomar (regla 4 del plan: se ve,
    // no se oculta).
    return Opacity(
      opacity: viaje.puedeTomar || expirado ? 1 : 0.72,
      child: tarjeta,
    );
  }

  Widget _estadoConScroll(Widget hijo) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: hijo,
        ),
      ),
    );
  }

  Widget _estado(
    bool isDark, {
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    String? accion,
    VoidCallback? onAccion,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 40, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textSecondary(isDark),
              ),
            ),
            if (accion != null && onAccion != null) ...[
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: onAccion,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(
                  accion,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: const BorderSide(color: AppTheme.primaryColor),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}