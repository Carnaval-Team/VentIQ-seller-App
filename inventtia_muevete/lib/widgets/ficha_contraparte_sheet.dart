import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/seguridad_service.dart';
import '../utils/app_error.dart';

/// Ficha de la contraparte antes de abordar (H2 · F4).
///
/// Muestra exactamente lo que devuelve `fn_ficha_contraparte`: foto, nombre
/// público, tipo de vehículo, chapa y **CI parcial**. Nunca teléfono, CI
/// completa ni documentos.
///
/// El chofer debe marcar que la persona coincide para poder iniciar el viaje
/// (el servidor exige `p_chapa_confirmada` cuando la ficha se sirvió).
class FichaContraparteSheet {
  /// Devuelve `true` si el abordaje quedó confirmado.
  static Future<bool?> mostrar(
    BuildContext context, {
    required int solicitudId,
    required String rolPropio,
    int? viajeId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FichaContraparteContenido(
        solicitudId: solicitudId,
        rolPropio: rolPropio,
        viajeId: viajeId,
      ),
    );
  }
}

class _FichaContraparteContenido extends StatefulWidget {
  final int solicitudId;
  final String rolPropio;
  final int? viajeId;

  const _FichaContraparteContenido({
    required this.solicitudId,
    required this.rolPropio,
    this.viajeId,
  });

  @override
  State<_FichaContraparteContenido> createState() =>
      _FichaContraparteContenidoState();
}

class _FichaContraparteContenidoState
    extends State<_FichaContraparteContenido> {
  final SeguridadService _seguridad = SeguridadService();

  FichaContraparte? _ficha;
  bool _cargando = true;
  bool _confirmando = false;
  bool _coincide = false;
  String? _error;

  bool get _esChofer => widget.rolPropio == 'chofer';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final ficha = await _seguridad.fichaContraparte(widget.solicitudId);
      if (!mounted) return;
      setState(() {
        _ficha = ficha;
        _cargando = false;
      });
    } on SeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _ficha = FichaContraparte.noDisponible;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.message(e, action: 'ver los datos del viaje');
        _ficha = FichaContraparte.noDisponible;
        _cargando = false;
      });
    }
  }

  Future<void> _confirmar({bool sinVerificacion = false}) async {
    if (_confirmando) return;
    final viajeId = widget.viajeId;
    setState(() => _confirmando = true);

    try {
      if (viajeId != null) {
        await _seguridad.confirmarAbordaje(
          viajeId,
          chapaConfirmada: !sinVerificacion,
          metodo: sinVerificacion ? 'sin_verificacion' : 'ficha',
        );
      }
      if (!mounted) return;
      setState(() => _confirmando = false);
      Navigator.pop(context, true);
    } on SeguridadException catch (e) {
      if (!mounted) return;
      setState(() => _confirmando = false);
      _aviso(e.mensaje);
    } catch (e) {
      if (!mounted) return;
      setState(() => _confirmando = false);
      _aviso(AppError.message(e, action: 'confirmar el abordaje'));
    }
  }

  Future<void> _reportarNoCoincide() async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('¿Qué no coincide?'),
        children: [
          for (final opcion in const [
            'La foto',
            'El nombre',
            'La chapa',
            'El carro',
            'Otra cosa',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, opcion),
              child: Text(opcion, style: GoogleFonts.plusJakartaSans()),
            ),
        ],
      ),
    );
    if (motivo == null) return;

    final tipo = motivo == 'La chapa' || motivo == 'El carro'
        ? 'vehiculo_incorrecto'
        : 'suplantacion';

    try {
      await _seguridad.reportarIncidente(
        solicitudId: widget.solicitudId,
        tipo: tipo,
        descripcion:
            'Antes de abordar no coincidió: ${motivo.toLowerCase()}. '
            'Reportado desde la ficha de la contraparte.',
        noEmparejar: true,
      );
      if (!mounted) return;
      Navigator.pop(context, false);
      _aviso('Reporte enviado. No subas si algo no cuadra');
    } catch (e) {
      if (!mounted) return;
      _aviso(AppError.message(e, action: 'enviar el reporte'));
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje, style: GoogleFonts.plusJakartaSans())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border(isDark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _esChofer
                    ? 'Confirma que es tu pasajero'
                    : 'Revisa antes de subir',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_ficha == null || !_ficha!.ok)
                _fichaNoDisponible(isDark, textPrimary, textSecondary)
              else
                _contenidoFicha(_ficha!, isDark, textPrimary, textSecondary),
              const SizedBox(height: 16),
              Text(
                'Muevete no sustituye a la policía. Si algo no cuadra, no '
                'sigas el viaje y llama al 106.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  height: 1.3,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fichaNoDisponible(
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.warning.withValues(alpha: 0.5)),
          ),
          child: Text(
            'No pudimos verificar los datos del viaje. No subas si la chapa no '
            'coincide. Si algo no cuadra, llama al 106.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.35,
              color: textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_esChofer)
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: _confirmando
                  ? null
                  : () => _confirmar(sinVerificacion: true),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Iniciar sin verificar los datos'),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _reportarNoCoincide,
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Reportar que no coincide'),
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
    );
  }

  Widget _contenidoFicha(
    FichaContraparte ficha,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.4),
                  width: 2,
                ),
                image: (ficha.fotoUrl ?? '').isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(ficha.fotoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: (ficha.fotoUrl ?? '').isEmpty
                  ? const Icon(
                      Icons.person,
                      size: 34,
                      color: AppTheme.primaryColor,
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ficha.nombrePublico.isEmpty
                        ? 'Sin nombre'
                        : ficha.nombrePublico,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: AppTheme.warning),
                      const SizedBox(width: 4),
                      Text(
                        '${ficha.rating.toStringAsFixed(1)} · '
                        '${ficha.viajes} viajes',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                      if (ficha.verificado) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.verified,
                          size: 14,
                          color: AppTheme.success,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'CI ${ficha.ciParcial ?? '••••'}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (ficha.muestraVehiculo) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.card(isDark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border(isDark)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ficha.vehiculoLegible,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ficha.chapa ?? '',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: textPrimary,
                    height: 1.1,
                  ),
                ),
                Text(
                  'CHAPA',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Si la chapa o la cara no coinciden, no subas. Toca "No coincide".',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              height: 1.35,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Text(
            'Compara la cara con la persona que va a subir.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _coincide,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppTheme.primaryColor,
            title: Text(
              'La persona coincide con la foto',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: textPrimary,
              ),
            ),
            onChanged: (v) => setState(() => _coincide = v == true),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed:
                (_confirmando ||
                    (_esChofer && !_coincide && !ficha.muestraVehiculo))
                ? null
                : () => _confirmar(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.success.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _confirmando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _esChofer ? 'Iniciar viaje' : 'Estoy en el carro correcto',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _reportarNoCoincide,
            icon: const Icon(Icons.block, size: 18),
            label: const Text('No coincide'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: const BorderSide(color: AppTheme.error),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
