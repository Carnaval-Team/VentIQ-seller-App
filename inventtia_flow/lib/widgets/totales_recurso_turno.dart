import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';
import '../utils/precio_reserva.dart';
import '../utils/reserva_listado.dart';

/// Totalización de reservas por recurso → turno para la fecha filtrada.
///
/// Cuenta las reservas **activas + completadas** (no las canceladas) que tienen
/// un turno asignado (`idTurno != null`). Cada reserva pesa por su `cantidad`.
/// Ida+vuelta el mismo día con el mismo turno combinado cuenta **una sola vez**.
/// Los servicios sin recursos (turno null) no aparecen aquí.

/// Total acumulado de un turno concreto dentro de un recurso.
class _TotalTurno {
  final String turno;
  int cantidad = 0;
  double importe = 0;
  String? moneda;
  _TotalTurno(this.turno);
}

/// Total de un recurso, con el desglose por turno.
class TotalRecurso {
  final String recurso;
  int cantidad = 0;
  double importe = 0;
  String? moneda;
  final Map<String, _TotalTurno> _turnos = {};
  TotalRecurso(this.recurso);

  List<MapEntry<String, ({int cantidad, double importe, String? moneda})>>
      get turnos {
    final list = _turnos.values
        .map(
          (t) => MapEntry(t.turno, (
            cantidad: t.cantidad,
            importe: t.importe,
            moneda: t.moneda,
          )),
        )
        .toList()
      ..sort((a, b) => b.value.cantidad.compareTo(a.value.cantidad));
    return list;
  }
}

/// Resultado de la totalización: recursos ordenados + total global + dinero.
class TotalesRecursoTurno {
  final List<TotalRecurso> recursos;
  final int total;
  final Map<String, double> importesPorMoneda;
  const TotalesRecursoTurno(this.recursos, this.total, this.importesPorMoneda);

  bool get isEmpty => recursos.isEmpty && importesPorMoneda.isEmpty;
}

bool _cuenta(Agenda r) => !(r.estado?.esCancelado == true);

void _acumular(
  Map<String, TotalRecurso> recursos,
  List<String> orden,
  Agenda r,
  int peso,
  double? importeParte,
) {
  if (r.idTurno == null || !_cuenta(r)) return;
  final recNombre = r.recursoNombre ?? 'Recurso';
  final turNombre = r.turnoNombre ?? 'Turno';
  final rec = recursos.putIfAbsent(recNombre, () {
    orden.add(recNombre);
    return TotalRecurso(recNombre);
  });
  rec.cantidad += peso;
  final t = rec._turnos.putIfAbsent(turNombre, () => _TotalTurno(turNombre));
  t.cantidad += peso;
  if (importeParte != null && importeParte > 0) {
    final mon = r.moneda ?? 'USD';
    rec.importe += importeParte;
    rec.moneda ??= mon;
    t.importe += importeParte;
    t.moneda ??= mon;
  }
}

/// Calcula los totales por recurso-turno de [reservas].
TotalesRecursoTurno calcularTotalesRecursoTurno(List<Agenda> reservas) {
  final recursos = <String, TotalRecurso>{};
  final orden = <String>[];
  var totalPasajeros = 0;
  final importes = <String, double>{};

  for (final item in agruparReservasParaListado(reservas)) {
    if (item.esCancelada) continue;
    final peso = item.pasajeros;
    totalPasajeros += peso;

    final precioItem = item.precioTotal ?? 0;
    final mon = item.moneda ?? 'USD';
    if (precioItem > 0) {
      importes[mon] = (importes[mon] ?? 0) + precioItem;
    }

    if (item.esIdaVueltaMismoDia) {
      final ida = item.principal;
      final vuelta = item.pareja!;
      if (ida.idTurno != null && ida.idTurno == vuelta.idTurno) {
        // Paquete mismo día: un solo cupo en el turno combinado.
        _acumular(recursos, orden, ida, peso, precioItem > 0 ? precioItem : null);
      } else {
        // Turnos simples el mismo día: capacidad en cada tramo; precio repartido.
        final pIda = ida.precioTotal ?? 0;
        final pVuelta = vuelta.precioTotal ?? 0;
        _acumular(recursos, orden, ida, peso, pIda > 0 ? pIda : null);
        _acumular(recursos, orden, vuelta, peso, pVuelta > 0 ? pVuelta : null);
      }
    } else {
      final p = item.principal.precioTotal ?? 0;
      _acumular(
        recursos,
        orden,
        item.principal,
        peso,
        p > 0 ? p : null,
      );
    }
  }

  return TotalesRecursoTurno(
    orden.map((k) => recursos[k]!).toList(),
    totalPasajeros,
    importes,
  );
}

/// Chip compacto con total de pasajeros por recurso-turno e importe.
class TotalesRecursoTurnoBadge extends StatelessWidget {
  final List<Agenda> reservas;
  const TotalesRecursoTurnoBadge({super.key, required this.reservas});

  @override
  Widget build(BuildContext context) {
    final totales = calcularTotalesRecursoTurno(reservas);
    if (totales.isEmpty) return const SizedBox.shrink();

    final dinero = totales.importesPorMoneda.entries
        .map((e) => PrecioReserva.formatear(e.value, e.key))
        .join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _mostrarDetalle(context, totales),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_car_filled_outlined,
                size: 14, color: AppTheme.accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                dinero.isEmpty
                    ? '${totales.total} pasaje${totales.total == 1 ? '' : 's'}'
                    : '${totales.total} · $dinero',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.expand_more, size: 14, color: AppTheme.accent),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalle(BuildContext context, TotalesRecursoTurno totales) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DetalleSheet(totales: totales),
    );
  }
}

class _DetalleSheet extends StatelessWidget {
  final TotalesRecursoTurno totales;
  const _DetalleSheet({required this.totales});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.functions, size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Resumen por recurso y turno',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${totales.total} pasaje(s)',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accent)),
                ),
              ],
            ),
            if (totales.importesPorMoneda.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final e in totales.importesPorMoneda.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.payments_outlined,
                          size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Importe total',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        PrecioReserva.formatear(e.value, e.key),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 14),
            if (totales.recursos.isEmpty)
              const Text(
                'Sin turnos asignados en estas reservas.',
                style: TextStyle(color: AppTheme.textSecondary),
              )
            else
              for (final rec in totales.recursos) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2)),
                    color: AppTheme.primary.withValues(alpha: 0.03),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Row(
                          children: [
                            const Icon(Icons.widgets_outlined,
                                size: 16, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(rec.recurso,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary)),
                            ),
                            Text('${rec.cantidad}',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primary)),
                            if (rec.importe > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                PrecioReserva.formatear(
                                    rec.importe, rec.moneda ?? 'USD'),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      for (final t in rec.turnos)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 6, 12, 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(t.key,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textPrimary)),
                              ),
                              Text('${t.value.cantidad}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary)),
                              if (t.value.importe > 0) ...[
                                const SizedBox(width: 8),
                                Text(
                                  PrecioReserva.formatear(
                                    t.value.importe,
                                    t.value.moneda ?? 'USD',
                                  ),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}
