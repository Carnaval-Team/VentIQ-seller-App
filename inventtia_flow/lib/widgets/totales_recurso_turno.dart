import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';

/// Totalización de reservas por recurso → turno para la fecha filtrada.
///
/// Cuenta las reservas **activas + completadas** (no las canceladas) que tienen
/// un turno asignado (`idTurno != null`). Cada reserva pesa por su `cantidad`.
/// Los servicios sin recursos (turno null) no aparecen aquí.

/// Total acumulado de un turno concreto dentro de un recurso.
class _TotalTurno {
  final String turno;
  int cantidad = 0;
  _TotalTurno(this.turno);
}

/// Total de un recurso, con el desglose por turno.
class TotalRecurso {
  final String recurso;
  int cantidad = 0;
  final Map<String, _TotalTurno> _turnos = {};
  TotalRecurso(this.recurso);

  List<MapEntry<String, int>> get turnos {
    final list = _turnos.values
        .map((t) => MapEntry(t.turno, t.cantidad))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }
}

/// Resultado de la totalización: recursos ordenados + total global.
class TotalesRecursoTurno {
  final List<TotalRecurso> recursos;
  final int total;
  const TotalesRecursoTurno(this.recursos, this.total);

  bool get isEmpty => recursos.isEmpty;
}

/// True si la reserva cuenta para los totales: activas (Reservado) o completadas.
/// Las canceladas no ocupan capacidad, así que no se cuentan.
bool _cuenta(Agenda r) => !(r.estado?.esCancelado == true);

/// Calcula los totales por recurso-turno de [reservas].
TotalesRecursoTurno calcularTotalesRecursoTurno(List<Agenda> reservas) {
  final recursos = <String, TotalRecurso>{};
  final orden = <String>[];
  var total = 0;

  for (final r in reservas) {
    if (r.idTurno == null) continue;
    if (!_cuenta(r)) continue;
    final peso = r.cantidad <= 0 ? 1 : r.cantidad;
    final recNombre = r.recursoNombre ?? 'Recurso';
    final turNombre = r.turnoNombre ?? 'Turno';

    final rec = recursos.putIfAbsent(recNombre, () {
      orden.add(recNombre);
      return TotalRecurso(recNombre);
    });
    rec.cantidad += peso;
    final t = rec._turnos.putIfAbsent(turNombre, () => _TotalTurno(turNombre));
    t.cantidad += peso;
    total += peso;
  }

  return TotalesRecursoTurno(
    orden.map((k) => recursos[k]!).toList(),
    total,
  );
}

/// Chip compacto y representativo con el total de reservas por recurso-turno.
/// Al tocarlo abre un bottom sheet con el desglose completo. Si no hay reservas
/// con turno, no renderiza nada.
class TotalesRecursoTurnoBadge extends StatelessWidget {
  final List<Agenda> reservas;
  const TotalesRecursoTurnoBadge({super.key, required this.reservas});

  @override
  Widget build(BuildContext context) {
    final totales = calcularTotalesRecursoTurno(reservas);
    if (totales.isEmpty) return const SizedBox.shrink();

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
            Text(
              '${totales.total} en ${totales.recursos.length} '
              'recurso${totales.recursos.length == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent),
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
                  child: Text('Reservas por recurso y turno',
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
                  child: Text('${totales.total} total',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accent)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final rec in totales.recursos) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
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
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    for (final t in rec.turnos)
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(28, 6, 12, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(t.key,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textPrimary)),
                            ),
                            Text('${t.value}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary)),
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
