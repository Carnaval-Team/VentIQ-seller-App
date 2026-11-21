import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/sales.dart';

/// Curva de salida fuerte para entradas de UI (ease-out con punch).
const Curve _easeOut = Cubic(0.23, 1, 0.32, 1);

/// Muestra el detalle de egresos de un vendedor/turno.
///
/// Es un diálogo que se adapta a pantallas pequeñas: nunca fija una altura,
/// usa como máximo el 85 % del alto disponible y reparte el contenido en una
/// cabecera fija, un resumen por divisa y una lista que es lo único que se
/// desplaza. Se anima una sola vez, al abrir (200 ms, ease-out, desde 96 %
/// con fundido: nada nace de la nada). Con «reducir movimiento» solo hay
/// fundido.
Future<void> showEgresosTurnoDialog({
  required BuildContext context,
  required String titulo,
  required List<CashDelivery> egresos,
  required String monedaBase,
  required String Function(double monto, String moneda) formatMonto,
  required String Function(DateTime fecha) formatFecha,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, __) => EgresosTurnoDialog(
      titulo: titulo,
      egresos: egresos,
      monedaBase: monedaBase,
      formatMonto: formatMonto,
      formatFecha: formatFecha,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: _easeOut,
        // Salir es responder al usuario: más rápido que entrar.
        reverseCurve: Curves.easeOut,
      );
      final reducir = MediaQuery.of(context).disableAnimations;
      return FadeTransition(
        opacity: curved,
        child: reducir
            ? child
            : ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                child: child,
              ),
      );
    },
  );
}

class EgresosTurnoDialog extends StatelessWidget {
  final String titulo;
  final List<CashDelivery> egresos;
  final String monedaBase;
  final String Function(double monto, String moneda) formatMonto;
  final String Function(DateTime fecha) formatFecha;

  const EgresosTurnoDialog({
    super.key,
    required this.titulo,
    required this.egresos,
    required this.monedaBase,
    required this.formatMonto,
    required this.formatFecha,
  });

  String _monedaDe(CashDelivery e) =>
      e.moneda.isEmpty ? monedaBase.trim().toUpperCase() : e.moneda;

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height;
    final totales = egresosPorMoneda(egresos, monedaBase: monedaBase);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: alto * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cabecera(titulo: titulo, cantidad: egresos.length),
            const Divider(height: 1, color: AppColors.border),
            if (egresos.isNotEmpty && totales.isNotEmpty)
              _ResumenPorDivisa(
                totales: totales,
                monedaBase: monedaBase,
                formatMonto: formatMonto,
              ),
            Flexible(
              child: egresos.isEmpty
                  ? const _SinEgresos()
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: egresos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _TarjetaEgreso(
                        egreso: egresos[i],
                        moneda: _monedaDe(egresos[i]),
                        formatMonto: formatMonto,
                        formatFecha: formatFecha,
                      ),
                    ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  final String titulo;
  final int cantidad;

  const _Cabecera({required this.titulo, required this.cantidad});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cantidad == 1 ? '1 egreso' : '$cantidad egresos',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            // Objetivo táctil de 48 px sin ensanchar la cabecera.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }
}

/// Un total por divisa: las monedas no se suman entre sí.
class _ResumenPorDivisa extends StatelessWidget {
  final Map<String, double> totales;
  final String monedaBase;
  final String Function(double monto, String moneda) formatMonto;

  const _ResumenPorDivisa({
    required this.totales,
    required this.monedaBase,
    required this.formatMonto,
  });

  @override
  Widget build(BuildContext context) {
    final base = monedaBase.trim().toUpperCase();
    final monedas = totales.keys.toList()
      ..sort((a, b) {
        if (a == base) return -1;
        if (b == base) return 1;
        return a.compareTo(b);
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final moneda in monedas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total $moneda',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '-${formatMonto(totales[moneda] ?? 0, moneda)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TarjetaEgreso extends StatelessWidget {
  final CashDelivery egreso;
  final String moneda;
  final String Function(double monto, String moneda) formatMonto;
  final String Function(DateTime fecha) formatFecha;

  const _TarjetaEgreso({
    required this.egreso,
    required this.moneda,
    required this.formatMonto,
    required this.formatFecha,
  });

  @override
  Widget build(BuildContext context) {
    final motivo = egreso.motivoEntrega.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Importe y fecha en un Wrap: en un ancho estrecho la fecha baja a
          // la línea siguiente en vez de pisar el importe.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 2,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.money_off,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '-${formatMonto(egreso.montoEntrega, moneda)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
              Text(
                formatFecha(egreso.fechaEntrega),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (motivo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              motivo,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Dato(etiqueta: 'Recibe', valor: egreso.nombreRecibe),
              _Dato(etiqueta: 'Autoriza', valor: egreso.nombreAutoriza),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;

  const _Dato({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    final texto = valor.trim().isEmpty ? '—' : valor.trim();
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        children: [
          TextSpan(text: '$etiqueta: '),
          TextSpan(
            text: texto,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SinEgresos extends StatelessWidget {
  const _SinEgresos();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long, size: 36, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text(
            'No hay egresos registrados en este turno',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
