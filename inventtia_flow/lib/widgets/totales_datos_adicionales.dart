import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';
import '../models/campo_adicional.dart';
import '../utils/reserva_listado.dart';
import 'totales_recurso_turno.dart';

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

/// True si la reserva cuenta para campos adicionales: solo Completadas.
bool _cuentaParaTotales(Agenda r) =>
    r.estado?.esCompletado == true || r.idEstado == 3;

/// True si la reserva cuenta para el monto: Reservado o Completado.
bool _cuentaParaMonto(Agenda r) {
  if (r.estado?.esCancelado == true || r.idEstado == 2) return false;
  return r.estado?.esReservado == true ||
      r.estado?.esCompletado == true ||
      r.idEstado == 1 ||
      r.idEstado == 3;
}

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

/// Panel con totales de la vista: solo cantidades por tramo (Ida / Regreso).
/// Importes, locales (recogida/destino) y detalle fino van en el PDF/Excel.
class TotalesPanel extends StatelessWidget {
  final List<Agenda> reservas;
  const TotalesPanel({super.key, required this.reservas});

  static const _estiloCantidad = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: AppTheme.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    final paraMonto = reservas.where(_cuentaParaMonto).toList();
    final porTramo = calcularTotalesPorTramo(paraMonto);
    final nReservas =
        contarReservasAgrupadas(reservas, excluirCanceladas: false);
    final nActivas = contarReservasAgrupadas(reservas);

    if (porTramo.tramos.isEmpty && nReservas == 0) {
      return const SizedBox.shrink();
    }

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
                const Icon(Icons.functions, size: 20, color: AppTheme.primary),
                const SizedBox(width: 6),
                const Text('Totales',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: AppTheme.primary)),
                const Spacer(),
                Text(
                  '$nActivas activas · $nReservas total',
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary),
                ),
              ],
            ),
            if (porTramo.tramos.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._buildPorTramo(porTramo),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPorTramo(TotalesPorTramo porTramo) {
    final out = <Widget>[];
    for (final t in porTramo.tramos) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            const Icon(Icons.route_outlined,
                size: 20, color: AppTheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                t.tramo,
                style: _estiloCantidad.copyWith(
                  fontSize: 18,
                  color: AppTheme.primary,
                ),
              ),
            ),
            Text('${t.cantidad}', style: _estiloCantidad),
          ],
        ),
      ));
    }
    return out;
  }
}
