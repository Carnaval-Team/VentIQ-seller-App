/// Sección 1 de Reportes: conciliación de saldos y caja.
///
/// La alarma manda: si hay descuadres, el aviso rojo va **arriba del todo**,
/// antes de cualquier tarjeta; dentro de la tarjeta la banda de estado también
/// pasa a rojo. La conciliación se ejecuta en vivo (`fn_fdi_conciliacion`) y la
/// nota de última revisión automática es opcional: si la RPC no existe o no ha
/// corrido, la sección funciona igual sin mostrarla.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import 'reportes_calculos.dart';
import 'reportes_widgets.dart';

class SeccionConciliacion extends StatelessWidget {
  final BloqueReporte conciliacion;
  final BloqueReporte ultima;
  final BloqueReporte caja;
  final bool conciliando;
  final VoidCallback onConciliar;
  final VoidCallback onReintentar;

  const SeccionConciliacion({
    super.key,
    required this.conciliacion,
    required this.ultima,
    required this.caja,
    required this.conciliando,
    required this.onConciliar,
    required this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    final datos = conciliacion.datos;
    final filas = listaDeMapas(datos?['filas']);
    final diferencia = diferenciaTotalConciliacion(filas);
    final descuadres = descuadresEfectivos(
      descuadres: datos?['descuadres'],
      filas: filas,
    );
    final claves = numero(datos?['claves']).round();
    final hayAlarma =
        descuadres > 0 ||
        diferencia.values.any((valor) => valor > umbralDescuadre);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hayAlarma) ...[
          bannerAlarma(
            titulo: 'El saldo no cuadra con los movimientos',
            detalle:
                '$claves ${claves == 1 ? 'clave' : 'claves'} · '
                '$descuadres ${descuadres == 1 ? 'descuadre' : 'descuadres'}',
            etiquetaDerecha: 'Diferencia total',
            valorDerecha: totalesPorMoneda(diferencia),
          ),
          const SizedBox(height: 16),
        ],
        _tarjetaConciliacion(
          filas: filas,
          claves: claves,
          descuadres: descuadres,
          diferencia: diferencia,
          hayAlarma: hayAlarma,
        ),
        const SizedBox(height: 16),
        _tarjetaCaja(),
      ],
    );
  }

  // ==========================================================================
  // Conciliación
  // ==========================================================================

  Widget _tarjetaConciliacion({
    required List<Map<String, dynamic>> filas,
    required int claves,
    required int descuadres,
    required Map<String, double> diferencia,
    required bool hayAlarma,
  }) {
    if (conciliacion.conError) {
      return panelReporte(
        children: [
          cabeceraReporte('Conciliación de saldos'),
          errorReporte(
            mensaje: conciliacion.error!,
            onReintentar: onReintentar,
          ),
        ],
      );
    }
    if (!conciliacion.conDatos) {
      return panelReporte(
        children: [
          cabeceraReporte('Conciliación de saldos'),
          panelCargandoReporte(texto: 'Conciliando saldos…'),
        ],
      );
    }

    final cuadradas = (claves - descuadres).clamp(0, claves);
    final notas = _notasConciliacion();

    return panelReporte(
      children: [
        cabeceraReporte(
          'Conciliación de saldos',
          subtitulo:
              'Cuenta · medio de pago · moneda contra la suma de movimientos '
              'y el último saldo. Ejecución en vivo.',
          trailing: FilledButton.icon(
            onPressed: conciliando ? null : onConciliar,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            icon: conciliando
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync, size: 16),
            label: const Text('Conciliar ahora'),
          ),
        ),
        bandaEstado(
          alarma: hayAlarma,
          titulo: hayAlarma ? 'Hay descuadres' : 'Todo cuadra',
          detalle:
              '$claves ${claves == 1 ? 'clave' : 'claves'} · '
              '$descuadres ${descuadres == 1 ? 'descuadre' : 'descuadres'}',
          etiquetaDerecha: 'Diferencia total',
          valorDerecha: totalesPorMoneda(diferencia),
        ),
        const SizedBox(height: 16),
        _cifrasConciliacion(
          claves: claves,
          cuadradas: cuadradas,
          descuadres: descuadres,
          diferencia: diferencia,
        ),
        const Divider(height: 24, color: AppColors.border),
        if (filas.isEmpty)
          mensajeVacioReporte(
            titulo: 'No hay claves que conciliar',
            detalle:
                'La tienda no tiene cuentas con saldo. Registra una cuenta y '
                'su saldo inicial para poder compararlo con los movimientos.',
            icono: Icons.account_balance_outlined,
          )
        else
          TablaReporte(
            columnas: const [
              ColumnaReporte('Cuenta', 18),
              ColumnaReporte('Medio', 13),
              ColumnaReporte('Moneda', 7),
              ColumnaReporte('Saldo', 11, derecha: true),
              ColumnaReporte('Suma movimientos', 12, derecha: true),
              ColumnaReporte('Último saldo', 10, derecha: true),
              ColumnaReporte('Dif. vs movimientos', 11, derecha: true),
              ColumnaReporte('Dif. vs último', 10, derecha: true),
              ColumnaReporte('Estado', 14),
            ],
            filas: [for (final fila in filas) _filaConciliacion(fila)],
          ),
        if (notas.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final nota in notas)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: notaReporte(nota),
            ),
        ],
      ],
    );
  }

  FilaReporte _filaConciliacion(Map<String, dynamic> fila) {
    final ok = filaConciliacionOk(fila);
    final vsMov = numero(fila['dif_saldo_vs_mov']);
    final vsUltimo = numero(fila['dif_saldo_vs_ultimo']);
    final ultimoSaldo = numeroONulo(fila['ultimo_saldo_nuevo']);

    return FilaReporte([
      celdaTexto(textoOGuion(fila['cuenta'])),
      celdaTexto(textoOGuion(fila['medio_pago'])),
      celdaTexto(monedaDe(fila), negrita: true),
      celdaCifra(cifra(numero(fila['saldo']))),
      celdaCifra(cifra(numero(fila['suma_movimientos']))),
      celdaCifra(ultimoSaldo == null ? '—' : cifra(ultimoSaldo)),
      celdaCifra(
        cifraConSigno(vsMov),
        color: vsMov.abs() > umbralDescuadre ? rojoTexto : null,
      ),
      celdaCifra(
        cifraConSigno(vsUltimo),
        color: vsUltimo.abs() > umbralDescuadre ? rojoTexto : null,
      ),
      celdaChip(
        chipReporte(
          ok ? 'ok' : 'descuadre',
          color: ok ? verdeTexto : rojoTexto,
          fondo: ok ? verdeFondo : rojoFondo,
          borde: ok ? verdeBorde : rojoBorde,
          icono: ok ? Icons.check : Icons.priority_high,
        ),
      ),
    ]);
  }

  Widget _cifrasConciliacion({
    required int claves,
    required int cuadradas,
    required int descuadres,
    required Map<String, double> diferencia,
  }) {
    return Wrap(
      spacing: 28,
      runSpacing: 14,
      children: [
        SizedBox(
          width: 150,
          child: cifraKpi(
            'Claves',
            '$claves',
            apoyo: '$cuadradas de $claves cuadradas',
          ),
        ),
        SizedBox(
          width: 150,
          child: cifraKpi(
            'Descuadres',
            '$descuadres',
            apoyo: descuadres == 0 ? 'ninguno detectado' : 'requieren revisión',
            color: descuadres > 0 ? rojoTexto : null,
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 150, maxWidth: 420),
          child: _cifraDiferenciaTotal(diferencia),
        ),
      ],
    );
  }

  /// La diferencia total puede tener una cifra por moneda; se pinta el
  /// desglose completo en lugar de un número único que habría que inventar.
  Widget _cifraDiferenciaTotal(Map<String, double> diferencia) {
    final entradas = diferencia.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'DIFERENCIA TOTAL',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        if (entradas.isEmpty)
          const Text(
            '—',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final entrada in entradas)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cifra(entrada.value),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: entrada.value > umbralDescuadre
                            ? rojoTexto
                            : AppColors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      entrada.key.trim().isEmpty ? '' : entrada.key,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        const SizedBox(height: 2),
        notaReporte('Por moneda: no se suman monedas distintas.'),
      ],
    );
  }

  /// Nota de última revisión automática. Sin dato, sin nota.
  List<String> _notasConciliacion() {
    final notas = <String>[];
    final datos = ultima.datos;
    if (datos != null) {
      final ejecutada = fechaDe(datos['ejecutada_at']);
      if (ejecutada != null) {
        final partes = <String>[
          'Última revisión automática: ${fechaHora(ejecutada)}',
          '${numero(datos['claves']).round()} claves',
          '${numero(datos['descuadres']).round()} descuadres',
        ];
        final diferencia = numeroONulo(datos['diferencia_total']);
        if (diferencia != null && diferencia.abs() > umbralDescuadre) {
          partes.add('diferencia ${cifra(diferencia)}');
        }
        final origen = textoONulo(datos['origen']);
        if (origen != null) partes.add('origen $origen');
        notas.add(partes.join(' · '));
      }
    }
    notas.add(
      'Si una clave no cuadra, esta tarjeta pasa a rojo y la diferencia se '
      'muestra en su moneda.',
    );
    return notas;
  }

  // ==========================================================================
  // Caja
  // ==========================================================================

  Widget _tarjetaCaja() {
    if (caja.conError) {
      return panelReporte(
        children: [
          cabeceraReporte('Caja'),
          errorReporte(mensaje: caja.error!, onReintentar: onReintentar),
        ],
      );
    }
    if (!caja.conDatos) {
      return panelReporte(
        children: [
          cabeceraReporte('Caja'),
          panelCargandoReporte(texto: 'Cargando caja…'),
        ],
      );
    }

    final claves = listaDeMapas(caja.datos?['claves']);
    final totales = listaDeMapas(caja.datos?['totales_por_moneda']);
    final desde = fechaDe(caja.datos?['desde']);
    final hasta = fechaDe(caja.datos?['hasta']);
    final ventana = numeroONulo(caja.datos?['ventana_dias']);
    final piezasVentana = <String>[
      if (desde != null && hasta != null)
        'Ventana: ${rangoTexto(desde, hasta)}',
      if (ventana != null) '${ventana.round()} días',
    ];

    return panelReporte(
      children: [
        cabeceraReporte(
          'Caja',
          subtitulo:
              'Saldo bruto, reservado y disponible por cuenta y moneda'
              '${piezasVentana.isEmpty ? '' : ' · ${piezasVentana.join(' · ')}'}',
          trailing: notaReporte(
            'El reservado no está disponible para nuevas compras.',
          ),
        ),
        if (claves.isEmpty)
          mensajeVacioReporte(
            titulo: 'No hay cuentas con saldo',
            detalle:
                'Cuando existan saldos en las cuentas del fondo, aquí se verá '
                'lo bruto, lo reservado y lo disponible por moneda.',
            icono: Icons.savings_outlined,
          )
        else
          TablaReporte(
            columnas: const [
              ColumnaReporte('Cuenta', 18),
              ColumnaReporte('Medio', 14),
              ColumnaReporte('Moneda', 7),
              ColumnaReporte('Saldo bruto', 11, derecha: true),
              ColumnaReporte('Reservado', 11, derecha: true),
              ColumnaReporte('Disponible', 11, derecha: true),
              ColumnaReporte('Movido en el periodo', 12, derecha: true),
            ],
            filas: [
              for (final fila in claves) _filaCaja(fila),
              for (final total in totales) _filaTotalCaja(total),
            ],
          ),
      ],
    );
  }

  FilaReporte _filaCaja(Map<String, dynamic> fila) {
    final movido = numero(fila['ejecutado_periodo']);
    return FilaReporte([
      celdaTexto(textoOGuion(fila['cuenta'])),
      celdaTexto(textoOGuion(fila['medio_pago'])),
      celdaTexto(monedaDe(fila), negrita: true),
      celdaCifra(cifra(numero(fila['saldo'])), negrita: true),
      celdaCifra(cifra(numero(fila['reservado']))),
      celdaCifra(cifra(numero(fila['disponible'])), negrita: true),
      celdaCifra(
        cifraConSigno(movido),
        color: movido < 0 ? naranjaTexto : verdeTexto,
      ),
    ]);
  }

  FilaReporte _filaTotalCaja(Map<String, dynamic> total) {
    final moneda = monedaDe(total);
    final movido = numero(total['ejecutado_periodo']);
    return FilaReporte([
      celdaTexto('Total $moneda', negrita: true),
      celdaTexto('—', color: AppColors.textLight),
      celdaTexto(moneda, negrita: true),
      celdaCifra(cifra(numero(total['saldo'])), negrita: true),
      celdaCifra(cifra(numero(total['reservado'])), negrita: true),
      celdaCifra(cifra(numero(total['disponible'])), negrita: true),
      celdaCifra(
        cifraConSigno(movido),
        negrita: true,
        color: movido < 0 ? naranjaTexto : verdeTexto,
      ),
    ], resaltada: true);
  }
}
