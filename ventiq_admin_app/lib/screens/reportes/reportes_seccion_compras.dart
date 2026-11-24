/// Sección 2 de Reportes: compras por estado, costo real vs factura y
/// diferencias cambiarias.
///
/// Tres bloques apilados, cada uno con su tabla densa y su fila de totales
/// **por moneda**. `pct_desvio` va en chip (verde si ≤ 0, naranja si > 0) y el
/// `signo` cambiario siempre en texto: nunca se depende solo del color.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../compras/compras_widgets.dart' show chipEstadoCompra;
import 'reportes_calculos.dart';
import 'reportes_widgets.dart';

class SeccionComprasCosto extends StatelessWidget {
  final BloqueReporte compras;
  final BloqueReporte costo;
  final BloqueReporte cambiario;
  final VoidCallback onReintentar;

  const SeccionComprasCosto({
    super.key,
    required this.compras,
    required this.costo,
    required this.cambiario,
    required this.onReintentar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tarjetaComprasPorEstado(),
        const SizedBox(height: 16),
        _tarjetaCosto(),
        const SizedBox(height: 16),
        _tarjetaCambiario(),
      ],
    );
  }

  // ==========================================================================
  // Compras por estado
  // ==========================================================================

  Widget _tarjetaComprasPorEstado() {
    if (compras.conError) {
      return panelReporte(
        children: [
          cabeceraReporte('Compras por estado'),
          errorReporte(mensaje: compras.error!, onReintentar: onReintentar),
        ],
      );
    }
    if (!compras.conDatos) {
      return panelReporte(
        children: [
          cabeceraReporte('Compras por estado'),
          panelCargandoReporte(texto: 'Cargando compras…'),
        ],
      );
    }

    final filas = listaDeMapas(compras.datos?['por_estado']);
    final totales = listaDeMapas(compras.datos?['totales_por_moneda']);
    final nCompras = filas.fold<int>(
      0,
      (suma, fila) => suma + numero(fila['compras']).round(),
    );

    return panelReporte(
      children: [
        cabeceraReporte(
          'Compras por estado',
          subtitulo:
              '$nCompras ${nCompras == 1 ? 'compra' : 'compras'} en el periodo · '
              'facturado, aterrizado y pagado en la moneda de cada compra.',
          trailing: notaReporte('Diferencia = aterrizado − facturado.'),
        ),
        if (filas.isEmpty)
          mensajeVacioReporte(
            titulo: 'Sin compras en el periodo',
            detalle:
                'No hay compras con fecha de factura dentro de la ventana. '
                'Prueba con otro rango de fechas.',
            icono: Icons.shopping_cart_outlined,
          )
        else
          TablaReporte(
            columnas: const [
              ColumnaReporte('Estado', 18),
              ColumnaReporte('Moneda', 8),
              ColumnaReporte('Compras', 8, derecha: true),
              ColumnaReporte('Facturado', 12, derecha: true),
              ColumnaReporte('Aterrizado', 12, derecha: true),
              ColumnaReporte('Pagado', 12, derecha: true),
              ColumnaReporte('Reservado', 11, derecha: true),
              ColumnaReporte('Diferencia', 12, derecha: true),
            ],
            filas: [
              for (final fila in filas) _filaComprasPorEstado(fila),
              for (final total in totales) _filaTotalCompras(total),
            ],
          ),
      ],
    );
  }

  FilaReporte _filaComprasPorEstado(Map<String, dynamic> fila) {
    final diferencia = numero(fila['diferencia']);
    return FilaReporte([
      celdaChip(chipEstadoCompra(textoOGuion(fila['estado']), denso: true)),
      celdaTexto(monedaDe(fila), negrita: true),
      celdaCifra(cifra(numero(fila['compras']))),
      celdaCifra(cifra(numero(fila['facturado']))),
      celdaCifra(cifra(numero(fila['aterrizado']))),
      celdaCifra(cifra(numero(fila['pagado']))),
      celdaCifra(cifra(numero(fila['reservado_activo']))),
      celdaCifra(
        cifraConSigno(diferencia),
        color: diferencia.abs() > umbralDescuadre
            ? (diferencia < 0 ? verdeTexto : naranjaTexto)
            : null,
        negrita: true,
      ),
    ]);
  }

  FilaReporte _filaTotalCompras(Map<String, dynamic> total) {
    final moneda = monedaDe(total);
    final diferencia = numero(total['diferencia']);
    return FilaReporte([
      celdaTexto('Total $moneda', negrita: true),
      celdaTexto(moneda, negrita: true),
      celdaCifra(cifra(numero(total['compras'])), negrita: true),
      celdaCifra(cifra(numero(total['facturado'])), negrita: true),
      celdaCifra(cifra(numero(total['aterrizado'])), negrita: true),
      celdaCifra(cifra(numero(total['pagado'])), negrita: true),
      celdaCifra(cifra(numero(total['reservado_activo'])), negrita: true),
      celdaCifra(
        cifraConSigno(diferencia),
        negrita: true,
        color: diferencia.abs() > umbralDescuadre
            ? (diferencia < 0 ? verdeTexto : naranjaTexto)
            : null,
      ),
    ], resaltada: true);
  }

  // ==========================================================================
  // Costo real vs factura
  // ==========================================================================

  Widget _tarjetaCosto() {
    if (costo.conError) {
      return panelReporte(
        children: [
          cabeceraReporte('Costo real vs factura'),
          errorReporte(mensaje: costo.error!, onReintentar: onReintentar),
        ],
      );
    }
    if (!costo.conDatos) {
      return panelReporte(
        children: [
          cabeceraReporte('Costo real vs factura'),
          panelCargandoReporte(texto: 'Cargando costos…'),
        ],
      );
    }

    final filas = listaDeMapas(costo.datos?['compras']);
    final resumen = costo.datos?['resumen'];
    final resumenMap = resumen is Map
        ? Map<String, dynamic>.from(resumen)
        : <String, dynamic>{};
    final porMoneda = listaDeMapas(resumenMap['por_moneda']);
    final nCompras = numero(resumenMap['compras']).round();

    return panelReporte(
      children: [
        cabeceraReporte(
          'Costo real vs factura',
          subtitulo:
              'Mercancía + adicionales = costo aterrizado. Desvío verde si es '
              '≤ 0 %, naranja si es > 0 %.'
              '${nCompras > 0 ? ' · $nCompras ${nCompras == 1 ? 'compra' : 'compras'}' : ''}',
          trailing: notaReporte('Adicionales negativos = a favor.'),
        ),
        if (filas.isEmpty)
          mensajeVacioReporte(
            titulo: 'Sin compras en el periodo',
            detalle:
                'No hay compras con fecha de factura dentro de la ventana. '
                'Prueba con otro rango de fechas.',
            icono: Icons.receipt_long_outlined,
          )
        else
          TablaReporte(
            columnas: const [
              ColumnaReporte('Compra', 22),
              ColumnaReporte('Moneda', 8),
              ColumnaReporte('Mercancía', 12, derecha: true),
              ColumnaReporte('Adicionales', 12, derecha: true),
              ColumnaReporte('Aterrizado', 12, derecha: true),
              ColumnaReporte('Desvío', 12, derecha: true),
              ColumnaReporte('% recibido', 10, derecha: true),
            ],
            filas: [
              for (final fila in filas) _filaCosto(fila),
              for (final total in porMoneda) _filaTotalCosto(total),
            ],
          ),
      ],
    );
  }

  FilaReporte _filaCosto(Map<String, dynamic> fila) {
    final numeroCompra = textoONulo(fila['numero_compra']);
    final proveedor = textoONulo(fila['proveedor']);
    final recibido = numeroONulo(fila['recibido_pct']);
    return FilaReporte([
      celdaDoble(numeroCompra == null ? '—' : '#$numeroCompra', proveedor),
      celdaTexto(monedaDe(fila), negrita: true),
      celdaCifra(cifra(numero(fila['mercancia']))),
      celdaCifra(cifraConSigno(numero(fila['adicionales']))),
      celdaCifra(cifra(numero(fila['aterrizado'])), negrita: true),
      celdaChip(chipDesvio(numeroONulo(fila['pct_desvio']))),
      celdaCifra(
        recibido == null ? '—' : cifraPorcentaje(recibido.clamp(0, 1) * 100),
      ),
    ]);
  }

  FilaReporte _filaTotalCosto(Map<String, dynamic> total) {
    final moneda = monedaDe(total);
    final desvio = numero(total['desvio']);
    return FilaReporte([
      celdaTexto('Total $moneda', negrita: true),
      celdaTexto(moneda, negrita: true),
      celdaCifra(cifra(numero(total['mercancia'])), negrita: true),
      celdaCifra(cifraConSigno(numero(total['adicionales'])), negrita: true),
      celdaCifra(
        cifra(numero(total['aterrizado'])),
        negrita: true,
        subtexto: 'desvío ${cifraConSigno(desvio)}',
      ),
      celdaChip(chipDesvio(numeroONulo(total['pct_desvio']))),
      celdaCifra('—', color: AppColors.textLight),
    ], resaltada: true);
  }

  // ==========================================================================
  // Diferencias cambiarias
  // ==========================================================================

  Widget _tarjetaCambiario() {
    if (cambiario.conError) {
      return panelReporte(
        children: [
          cabeceraReporte('Diferencias cambiarias'),
          errorReporte(mensaje: cambiario.error!, onReintentar: onReintentar),
        ],
      );
    }
    if (!cambiario.conDatos) {
      return panelReporte(
        children: [
          cabeceraReporte('Diferencias cambiarias'),
          panelCargandoReporte(texto: 'Cargando diferencias…'),
        ],
      );
    }

    final filas = listaDeMapas(cambiario.datos?['compras']);
    final totales = listaDeMapas(cambiario.datos?['totales_por_moneda']);

    return panelReporte(
      children: [
        cabeceraReporte(
          'Diferencias cambiarias',
          subtitulo:
              'Tasa de factura contra tasa de pago: equivalente real y '
              'equivalente a la tasa de factura, en la moneda de la compra.',
          trailing: notaReporte('Signo = real − a tasa factura.'),
        ),
        if (filas.isEmpty)
          mensajeVacioReporte(
            titulo: 'Sin compras en el periodo',
            detalle:
                'No hay compras con fecha de factura dentro de la ventana. '
                'Prueba con otro rango de fechas.',
            icono: Icons.currency_exchange,
          )
        else ...[
          TablaReporte(
            columnas: const [
              ColumnaReporte('Compra', 22),
              ColumnaReporte('Moneda', 8),
              ColumnaReporte('N pagos', 8, derecha: true),
              ColumnaReporte('Tasa factura', 10, derecha: true),
              ColumnaReporte('Equiv. real', 13, derecha: true),
              ColumnaReporte('Equiv. a tasa factura', 14, derecha: true),
              ColumnaReporte('Diferencia', 12, derecha: true),
              ColumnaReporte('Signo', 14),
            ],
            filas: [
              for (final fila in filas) _filaCambiario(fila),
              for (final total in totales) _filaTotalCambiario(total),
            ],
          ),
          const SizedBox(height: 12),
          for (final total in totales) _resumenCambiario(total),
        ],
      ],
    );
  }

  FilaReporte _filaCambiario(Map<String, dynamic> fila) {
    final numeroCompra = textoONulo(fila['numero_compra']);
    final factura = textoONulo(fila['numero_factura']);
    final pagos = listaDeMapas(fila['pagos']);
    final porMoneda = listaDeMapas(fila['pagos_por_moneda']);
    final tasaFactura = numeroONulo(fila['tasa_factura']);
    final tasaPago = pagos.length == 1
        ? numeroONulo(pagos.first['tasa_pago'])
        : null;
    final diferencia = numero(fila['diferencia']);

    final piezas = <String>[
      if (factura != null) 'Factura $factura',
      if (porMoneda.isNotEmpty)
        'Pagado: ${porMoneda.map((p) => '${cifra(numero(p['monto']))} ${monedaDe(p)}').join(' · ')}',
    ];

    return FilaReporte([
      celdaDoble(
        numeroCompra == null ? '—' : '#$numeroCompra',
        piezas.isEmpty ? null : piezas.join(' · '),
      ),
      celdaTexto(monedaDe(fila), negrita: true),
      celdaCifra(cifra(numero(fila['n_pagos']))),
      celdaCifra(
        tasaFactura == null ? '—' : cifra(tasaFactura),
        subtexto: tasaPago == null ? null : 'pago ${cifra(tasaPago)}',
      ),
      celdaCifra(cifra(numero(fila['equivalente_real']))),
      celdaCifra(cifra(numero(fila['equivalente_a_tasa_factura']))),
      celdaCifra(
        cifraConSigno(diferencia),
        negrita: true,
        color: diferencia.abs() > umbralDescuadre
            ? (diferencia <= 0 ? verdeTexto : naranjaTexto)
            : null,
      ),
      celdaChip(chipSigno(textoOGuion(fila['signo']))),
    ]);
  }

  FilaReporte _filaTotalCambiario(Map<String, dynamic> total) {
    final moneda = monedaDe(total);
    final diferencia = numero(total['diferencia']);
    return FilaReporte([
      celdaTexto('Total $moneda', negrita: true),
      celdaTexto(moneda, negrita: true),
      celdaCifra(cifra(numero(total['pagos'])), negrita: true),
      celdaTexto('—', color: AppColors.textLight),
      celdaCifra(cifra(numero(total['equivalente_real'])), negrita: true),
      celdaCifra(
        cifra(numero(total['equivalente_a_tasa_factura'])),
        negrita: true,
      ),
      celdaCifra(
        cifraConSigno(diferencia),
        negrita: true,
        color: diferencia.abs() > umbralDescuadre
            ? (diferencia <= 0 ? verdeTexto : naranjaTexto)
            : null,
      ),
      celdaChip(chipSigno(textoOGuion(total['signo']))),
    ], resaltada: true);
  }

  /// Banda de cifras del mockup, una por moneda: real, a tasa de factura,
  /// diferencia neta y el signo en texto.
  Widget _resumenCambiario(Map<String, dynamic> total) {
    final moneda = monedaDe(total);
    final diferencia = numero(total['diferencia']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _cifraResumen(
            'Equivalente real',
            cifra(numero(total['equivalente_real'])),
            moneda: moneda,
          ),
          _cifraResumen(
            'Equivalente a tasa factura',
            cifra(numero(total['equivalente_a_tasa_factura'])),
            moneda: moneda,
          ),
          _cifraResumen(
            'Diferencia neta',
            cifraConSigno(diferencia),
            moneda: moneda,
            color: diferencia.abs() > umbralDescuadre
                ? (diferencia <= 0 ? verdeTexto : naranjaTexto)
                : null,
          ),
          chipSigno(textoOGuion(total['signo'])),
        ],
      ),
    );
  }

  Widget _cifraResumen(
    String etiqueta,
    String valor, {
    String? moneda,
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          moneda == null || moneda.trim().isEmpty ? valor : '$valor $moneda',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
