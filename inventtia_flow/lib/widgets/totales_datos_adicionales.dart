import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';
import '../models/campo_adicional.dart';
import '../utils/precio_reserva.dart';
import '../utils/reserva_listado.dart';

/// Total calculado para un campo adicional marcado como "contabilizar".
///
/// Según el tipo del campo:
///  - numero  -> [suma] (multiplicada por la cantidad de la reserva)
///  - booleano -> [conteoSi] (cuántos turnos con valor "Sí")
///  - select / texto -> [porOpcion] (conteo de turnos por cada valor)
class TotalCampo {
  final String clave;
  final String etiqueta;
  final TipoCampo tipo;
  double suma;
  int conteoSi;
  final Map<String, int> porOpcion;

  TotalCampo({
    required this.clave,
    required this.etiqueta,
    required this.tipo,
  })  : suma = 0,
        conteoSi = 0,
        porOpcion = {};
}

bool _asBool(Object? v) {
  if (v is bool) return v;
  final s = v?.toString().toLowerCase().trim();
  return s == 'true' || s == 'sí' || s == 'si' || s == '1';
}

/// True si la reserva cuenta para los totales: solo las Completadas.
bool _cuentaParaTotales(Agenda r) =>
    r.estado?.esCompletado == true || r.idEstado == 3;

/// Calcula los totales de los campos contabilizables presentes en [reservas].
/// Solo se contabilizan las reservas **Completadas**. Ida+vuelta mismo día
/// cuenta una sola vez (usa la agenda representativa del ítem agrupado).
List<TotalCampo> calcularTotales(List<Agenda> reservasTodas) {
  final completadas = reservasTodas.where(_cuentaParaTotales).toList();
  final reservas = agendasRepresentativas(completadas);
  final campos = <String, CampoAdicional>{};
  final orden = <String>[];
  for (final r in reservas) {
    for (final c in r.localServicio?.servicio?.camposAdicionales ??
        const <CampoAdicional>[]) {
      if (!c.contabilizar) continue;
      if (!campos.containsKey(c.clave)) {
        campos[c.clave] = c;
        orden.add(c.clave);
      }
    }
  }
  if (campos.isEmpty) return const [];

  final totales = {
    for (final k in orden)
      k: TotalCampo(
          clave: k, etiqueta: campos[k]!.etiqueta, tipo: campos[k]!.tipo),
  };

  for (final r in reservas) {
    final peso = r.cantidad <= 0 ? 1 : r.cantidad;
    final datos = r.datosAdicionales;
    if (datos == null) continue;
    for (final k in orden) {
      final valor = datos[k];
      if (valor == null) continue;
      final t = totales[k]!;
      switch (t.tipo) {
        case TipoCampo.numero:
          t.suma += (double.tryParse(valor.toString()) ?? 0) * peso;
          break;
        case TipoCampo.booleano:
          if (_asBool(valor)) t.conteoSi += peso;
          break;
        case TipoCampo.select:
        case TipoCampo.texto:
          final s = valor.toString().trim();
          if (s.isEmpty) break;
          t.porOpcion[s] = (t.porOpcion[s] ?? 0) + peso;
          break;
      }
    }
  }

  return orden.map((k) => totales[k]!).toList();
}

/// Panel con totales: conteo agrupado, importes y campos adicionales.
class TotalesPanel extends StatelessWidget {
  final List<Agenda> reservas;
  const TotalesPanel({super.key, required this.reservas});

  static final _fmtDia = DateFormat('dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final completadas = reservas.where(_cuentaParaTotales).toList();
    final totales = calcularTotales(completadas);
    final importes = sumarPreciosReservas(reservas);
    final nReservas =
        contarReservasAgrupadas(reservas, excluirCanceladas: false);
    final nActivas = contarReservasAgrupadas(reservas);

    if (totales.isEmpty && importes.isEmpty) {
      return const SizedBox.shrink();
    }

    final porDia = <DateTime, List<Agenda>>{};
    for (final r in completadas) {
      final f = r.fechaHoraReserva;
      final dia = DateTime(f.year, f.month, f.day);
      porDia.putIfAbsent(dia, () => []).add(r);
    }
    final dias = porDia.keys.toList()..sort();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      color: AppTheme.primary.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.functions, size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                const Text('Totales',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.primary)),
                const Spacer(),
                Text(
                  '$nActivas activas · $nReservas total',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
            if (importes.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final e in importes.entries)
                _fila(
                  'Importe (${e.key})',
                  PrecioReserva.formatear(e.value, e.key),
                ),
            ],
            if (totales.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._buildTotales(totales),
            ],
            if (dias.length > 1 && (totales.isNotEmpty || importes.isNotEmpty)) ...[
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: const Text('Ver por día',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary)),
                  children: [
                    for (final dia in dias) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 2),
                        child: Text(_fmtDia.format(dia),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary)),
                      ),
                      for (final e
                          in sumarPreciosReservas(porDia[dia]!).entries)
                        _fila(
                          'Importe (${e.key})',
                          PrecioReserva.formatear(e.value, e.key),
                        ),
                      ..._buildTotales(calcularTotales(porDia[dia]!)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTotales(List<TotalCampo> totales) {
    final out = <Widget>[];
    for (final t in totales) {
      switch (t.tipo) {
        case TipoCampo.numero:
          out.add(_fila(t.etiqueta, _fmtNum(t.suma)));
          break;
        case TipoCampo.booleano:
          out.add(_fila(t.etiqueta, '${t.conteoSi} Sí'));
          break;
        case TipoCampo.select:
        case TipoCampo.texto:
          if (t.porOpcion.isEmpty) {
            out.add(_fila(t.etiqueta, '-'));
          } else {
            final entries = t.porOpcion.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            out.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.etiqueta,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 2),
                  ...entries.map((e) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 1),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(e.key,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textPrimary)),
                            ),
                            Text('${e.value}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary)),
                          ],
                        ),
                      )),
                ],
              ),
            ));
          }
          break;
      }
    }
    return out;
  }

  Widget _fila(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ),
            Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary)),
          ],
        ),
      );

  static String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }
}
