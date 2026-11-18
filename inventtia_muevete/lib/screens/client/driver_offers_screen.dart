import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../../providers/transport_provider.dart';
import '../../utils/helpers.dart';
import 'ride_confirmed_screen.dart';

/// "Buscando conductor...".
///
/// En el flujo de precio fijo ya no hay ofertas que comparar: el cliente
/// publica el viaje con el precio de la plataforma y espera a que un chofer
/// lo tome. Cuando eso pasa (`driver_id` en la solicitud) se navega a
/// [RideConfirmedScreen].
class DriverOffersScreen extends StatefulWidget {
  const DriverOffersScreen({super.key});

  @override
  State<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends State<DriverOffersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  Timer? _reloj;
  bool _cancelando = false;
  bool _navegado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Refresca la cuenta atrás del TTL.
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<TransportProvider>().resubscribeRealtime();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Cuando el chofer toma el viaje pasamos a la pantalla del viaje.
  void _irAlViajeSiCorresponde(TransportProvider tp) {
    if (_navegado || !mounted) return;
    if (tp.activeRequest?.driverId == null) return;
    _navegado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RideConfirmedScreen()),
      );
    });
  }

  Future<void> _cancelarViaje() async {
    final isDark = context.read<ThemeProvider>().isDark;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Cancelar viaje',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
        content: Text(
          '¿Seguro que quieres cancelar la solicitud de viaje?',
          style: GoogleFonts.plusJakartaSans(
            color: AppTheme.textSecondary(isDark),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'No',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary(isDark),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Sí, cancelar',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: AppTheme.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;
    setState(() => _cancelando = true);
    final tp = context.read<TransportProvider>();
    final ok = await tp.cancelarSolicitud();
    if (!mounted) return;
    setState(() => _cancelando = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tp.error ?? 'No se pudo cancelar la solicitud.',
            style: GoogleFonts.plusJakartaSans(),
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    if (tp.reembolsoCancelacion != null && tp.reembolsoCancelacion! > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Se devolvieron ${Helpers.formatCup(tp.reembolsoCancelacion!)} '
            'a tu billetera.',
            style: GoogleFonts.plusJakartaSans(),
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }

    Navigator.pushNamedAndRemoveUntil(context, '/client/home', (route) => false);
  }

  String _textoTtl(DateTime? expiresAt) {
    if (expiresAt == null) return '';
    final restante = expiresAt.difference(DateTime.now());
    if (restante.isNegative) return 'La solicitud está por expirar';
    final minutos = restante.inMinutes;
    if (minutos <= 0) return 'Vence en menos de 1 minuto';
    return 'La solicitud vence en $minutos min';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final tp = context.watch<TransportProvider>();

    _irAlViajeSiCorresponde(tp);

    final solicitud = tp.activeRequest;

    if (solicitud == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg(isDark),
        appBar: AppBar(
          backgroundColor: AppTheme.bg(isDark),
          foregroundColor: AppTheme.textPrimary(isDark),
          elevation: 0,
          title: Text(
            'Buscando conductor',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(isDark),
            ),
          ),
        ),
        body: _buildSinSolicitud(isDark),
      );
    }

    final precio = solicitud.precioMostrado;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(isDark),
        foregroundColor: AppTheme.textPrimary(isDark),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Buscando conductor',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.4,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Buscando conductor...',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary(isDark),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Estamos avisando a los conductores de tu zona. '
                'No cierres la app.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppTheme.textSecondary(isDark),
                ),
              ),
              const SizedBox(height: 24),

              // Resumen del viaje (precio de la plataforma, no negociable).
              Container(
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
                            'Precio del viaje',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary(isDark),
                            ),
                          ),
                        ),
                        Text(
                          Helpers.formatCup(precio),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary(isDark),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _filaResumen(
                      isDark,
                      icono: Icons.my_location,
                      color: AppTheme.success,
                      texto: solicitud.direccionOrigen ?? 'Origen',
                    ),
                    const SizedBox(height: 8),
                    _filaResumen(
                      isDark,
                      icono: Icons.location_on,
                      color: AppTheme.error,
                      texto: solicitud.direccionDestino ?? 'Destino',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _chip(
                          isDark,
                          icono: Icons.payments_outlined,
                          texto: (solicitud.metodoPago ?? 'efectivo') == 'wallet'
                              ? 'Wallet'
                              : 'Efectivo',
                        ),
                        const SizedBox(width: 8),
                        if ((solicitud.tipoVehiculo ?? '').isNotEmpty)
                          _chip(
                            isDark,
                            icono: Icons.directions_car_outlined,
                            texto: solicitud.tipoVehiculo!,
                          ),
                        if ((solicitud.pasajeros ?? 1) > 1) ...[
                          const SizedBox(width: 8),
                          _chip(
                            isDark,
                            icono: Icons.person_outline,
                            texto: '${solicitud.pasajeros} pas.',
                          ),
                        ],
                      ],
                    ),
                    if (_textoTtl(solicitud.expiresAt).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _textoTtl(solicitud.expiresAt),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.textTertiary(isDark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _cancelando ? null : _cancelarViaje,
                  icon: _cancelando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close, size: 18),
                  label: Text(
                    _cancelando ? 'Cancelando...' : 'Cancelar viaje',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSinSolicitud(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off,
                size: 38,
                color: AppTheme.textTertiary(isDark),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No hay una solicitud activa',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pide un viaje desde el mapa para empezar a buscar conductor.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppTheme.textSecondary(isDark),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                '/client/home',
                (route) => false,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              child: Text(
                'Pedir un viaje',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaResumen(
    bool isDark, {
    required IconData icono,
    required Color color,
    required String texto,
  }) {
    return Row(
      children: [
        Icon(icono, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.textPrimary(isDark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(
    bool isDark, {
    required IconData icono,
    required String texto,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.bg(isDark),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 13, color: AppTheme.textSecondary(isDark)),
          const SizedBox(width: 5),
          Text(
            texto,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}