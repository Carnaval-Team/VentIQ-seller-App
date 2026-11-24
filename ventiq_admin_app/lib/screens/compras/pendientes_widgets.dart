/// Piezas de presentación de la fase 9 de Compras: panel de pendientes,
/// detalle de faltantes y vista de facturas.
///
/// Solo estilo y composición: la verdad de las cifras llega ya parseada desde
/// `models/pendientes.dart` y `pendientes_service.dart`. Las tablas reutilizan
/// `TablaReporte` (fase 8) para no tener dos lenguajes de tabla densa: cabecera
/// de 11 px en mayúsculas, cifras tabulares a la derecha y desplazamiento
/// horizontal cuando el ancho no alcanza (nunca se corta una columna).
///
/// Los colores de estado salen de `compras_widgets.dart` (`colorEstadoCompra`,
/// `chipEstadoCompra`, `chipEstadoRecepcion`), no de la maqueta.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pendientes.dart';
import '../reportes/reportes_widgets.dart'
    show
        ColumnaReporte,
        FilaReporte,
        TablaReporte,
        celdaChip,
        celdaCifra,
        celdaDoble,
        celdaTexto,
        cifraKpi,
        mensajeVacioReporte,
        notaReporte,
        panelCargandoReporte,
        errorReporte;
import 'compras_widgets.dart';

// ===========================================================================
// Chips y barras
// ===========================================================================

/// Chip de antigüedad: naranja cuando supera el umbral, neutro cuando no.
///
/// El umbral **no filtra**: el panel sigue mostrando todas las compras abiertas
/// y este chip solo avisa.
Widget chipAntiguedad(
  int dias, {
  int umbral = umbralAntiguedadDias,
  bool denso = true,
}) {
  final supera = superaUmbralAntiguedad(dias, umbral: umbral);
  return pastillaCompras(
    textoDiasCorto(dias),
    color: supera ? AppColors.warning : AppColors.secondary,
    icono: supera ? Icons.schedule : null,
    denso: denso,
  );
}

/// Barra fina de avance de recepción con su porcentaje al lado.
///
/// Es una razón sin moneda: no cambia con el permiso de importes.
Widget barraRecibido(
  double pct, {
  double ancho = 64,
  double grosor = 5,
  bool conTexto = true,
}) {
  final valor = pct.clamp(0.0, 1.0);
  final porcentaje = porcentajeRecibido(valor);
  final barra = SizedBox(
    width: ancho,
    height: grosor,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(grosor),
      child: LinearProgressIndicator(
        value: valor,
        minHeight: grosor,
        backgroundColor: AppColors.border,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
      ),
    ),
  );
  if (!conTexto) return barra;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      barra,
      const SizedBox(width: 6),
      Text(
        '$porcentaje %',
        maxLines: 1,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// Celda de la columna «% recibido»: barra + porcentaje.
///
/// Va en `FittedBox` para que una columna estrecha escale la barra en vez de
/// desbordar: el porcentaje no se pierde nunca.
Widget celdaRecibido(double pct) => Align(
  alignment: Alignment.centerLeft,
  child: FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: barraRecibido(pct, ancho: 56),
  ),
);

// ===========================================================================
// Franja de resumen del panel
// ===========================================================================

/// Franja de resumen: compras abiertas, monto pendiente **por moneda** y la
/// más antigua.
///
/// Sin permiso de importes, cada bloque de monto se sustituye por el conteo de
/// compras de esa moneda: mismo número de bloques, sin huecos y sin dinero.
Widget franjaResumenPendientes({
  required PendientesPanel panel,
  required bool puedeVerImportes,
  int umbral = umbralAntiguedadDias,
}) {
  final monedas = panel.totalesPorMoneda;
  final conteos = panel.comprasPorMoneda;
  final masAntigua = panel.masAntigua;

  final bloques = <Widget>[
    cifraKpi(
      'Compras abiertas',
      '${panel.comprasAbiertas}',
      apoyo: panel.comprasAbiertas == 1 ? 'compra' : 'compras',
    ),
    if (puedeVerImportes)
      for (final total in monedas)
        cifraKpi(
          'Pendiente ${total.moneda.isEmpty ? 's/moneda' : total.moneda}',
          formatearImporte(total.montoPendiente),
          apoyo: '${total.moneda.isEmpty ? '—' : total.moneda} · '
              '${total.compras} ${total.compras == 1 ? 'compra' : 'compras'}',
        )
    else
      for (final entrada in conteos.entries)
        cifraKpi(
          'Compras ${entrada.key}',
          '${entrada.value}',
          apoyo: 'sin importes',
        ),
    cifraKpi(
      'Sin recepción',
      '${panel.sinRecepcion} de ${panel.comprasAbiertas}',
      apoyo: 'nada recibido',
    ),
    cifraKpi(
      'La más antigua',
      masAntigua == null ? '—' : textoDias(masAntigua.diasAntiguedad),
      apoyo: masAntigua == null
          ? 'sin compras abiertas'
          : '${masAntigua.etiquetaCompra} · '
                '${superaUmbralAntiguedad(masAntigua.diasAntiguedad, umbral: umbral) ? 'supera el umbral' : 'dentro del umbral'}',
    ),
  ];

  final nota = puedeVerImportes
      ? _notaMonedas(monedas)
      : 'Vista sin importes: se muestran cantidades, avance y conteos; '
            'ningún monto ni costo.';

  return panelCompras(
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final anchoBloque = constraints.maxWidth < 640
              ? (constraints.maxWidth - 24) / 2
              : null;
          return Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              for (var i = 0; i < bloques.length; i++)
                SizedBox(
                  width: anchoBloque,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == bloques.length - 1 ? 0 : 4,
                    ),
                    child: bloques[i],
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 10),
      notaReporte(nota),
    ],
  );
}

String _notaMonedas(List<TotalPendienteMoneda> monedas) {
  if (monedas.length <= 1) {
    final moneda = monedas.isEmpty ? '' : monedas.first.moneda;
    return moneda.isEmpty
        ? 'El monto pendiente usa la moneda de la factura.'
        : 'El monto pendiente está en $moneda (moneda de la factura).';
  }
  final nombres = monedas
      .map((m) => m.moneda.isEmpty ? 's/moneda' : m.moneda)
      .toSet()
      .join(' y ');
  return '$nombres no se suman: cada moneda se informa por separado.';
}

// ===========================================================================
// Tabla del panel (tablet y PC)
// ===========================================================================

/// Tabla densa de compras abiertas. En PC lleva las diez columnas de la
/// maqueta; en tablet se queda con las que se leen y el resto se consulta en el
/// detalle (el ancho no se fuerza: si no cabe, la tabla se desplaza).
///
/// Con [puedeVerImportes] en false la columna de monto **no existe**: no queda
/// una columna vacía ni un hueco entre celdas.
Widget tablaPendientes({
  required List<PendienteCompra> compras,
  required bool puedeVerImportes,
  required ValueChanged<PendienteCompra> onAbrir,
  int umbral = umbralAntiguedadDias,
  bool compacta = false,
}) {
  final columnas = <ColumnaReporte>[
    const ColumnaReporte('Compra / factura', 148),
    ColumnaReporte('Proveedor', compacta ? 170 : 190),
    const ColumnaReporte('Fecha', 92),
    const ColumnaReporte('Antigüedad', 100),
    const ColumnaReporte('% recibido', 120),
    const ColumnaReporte('Pedido / recibido', 118, derecha: true),
    if (puedeVerImportes)
      const ColumnaReporte('Monto pendiente', 138, derecha: true),
    if (!compacta) const ColumnaReporte('Últ. recep.', 104),
    const ColumnaReporte('Días s/mov.', 92, derecha: true),
    const ColumnaReporte('Estado', 128),
  ];

  final filas = <FilaReporte>[
    for (final compra in compras)
      FilaReporte(
        [
          celdaDoble(
            compra.etiquetaCompra,
            compra.numeroFactura == null
                ? 'Sin factura'
                : 'Factura ${compra.numeroFactura}',
          ),
          celdaTexto(compra.proveedor ?? '—'),
          celdaTexto(formatearFecha(compra.fechaFactura)),
          Align(
            alignment: Alignment.centerLeft,
            child: chipAntiguedad(compra.diasAntiguedad, umbral: umbral),
          ),
          celdaRecibido(compra.recibidoPct),
          celdaCifra(compra.textoPedidoRecibido),
          if (puedeVerImportes)
            celdaCifra(
              formatearImporteMoneda(compra.montoPendiente, compra.moneda),
              negrita: true,
            ),
          if (!compacta)
            celdaTexto(
              compra.ultimaRecepcion == null
                  ? 'Sin recepción'
                  : formatearFecha(compra.ultimaRecepcion),
              color: compra.ultimaRecepcion == null
                  ? AppColors.textSecondary
                  : null,
            ),
          celdaCifra(textoDiasCorto(compra.diasSinMovimiento)),
          celdaChip(chipEstadoCompra(compra.estado, denso: true)),
        ],
        onTap: () => onAbrir(compra),
      ),
  ];

  return TablaReporte(columnas: columnas, filas: filas);
}

// ===========================================================================
// Tarjetas del panel (móvil)
// ===========================================================================

/// Lista de tarjetas apiladas para pantallas estrechas
/// (`pendientes-movil.png`): el detalle denso no cabe y la fila se lee mejor
/// como tarjeta.
Widget tarjetasPendientes({
  required List<PendienteCompra> compras,
  required bool puedeVerImportes,
  required ValueChanged<PendienteCompra> onAbrir,
  int umbral = umbralAntiguedadDias,
}) {
  return Column(
    children: [
      for (final compra in compras)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: tarjetaPendiente(
            compra,
            puedeVerImportes: puedeVerImportes,
            onTap: () => onAbrir(compra),
            umbral: umbral,
          ),
        ),
    ],
  );
}

Widget tarjetaPendiente(
  PendienteCompra compra, {
  required bool puedeVerImportes,
  required VoidCallback onTap,
  int umbral = umbralAntiguedadDias,
}) {
  final factura = compra.numeroFactura;
  final subtitulo = [
    if (factura != null) 'Factura $factura',
    formatearFecha(compra.fechaFactura),
  ].join(' · ');

  return Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          compra.etiquetaCompra,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      chipEstadoCompra(compra.estado, denso: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    compra.proveedor ?? 'Sin proveedor',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      chipAntiguedad(compra.diasAntiguedad, umbral: umbral),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recibido ${porcentajeRecibido(compra.recibidoPct)} %',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      barraRecibido(compra.recibidoPct, ancho: 96, conTexto: false),
                    ],
                  ),
                  if (puedeVerImportes) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Pendiente',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          formatearImporteMoneda(
                            compra.montoPendiente,
                            compra.moneda,
                          ),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(11),
                ),
              ),
              child: Text(
                textoRecepcionYDias(
                  compra.ultimaRecepcion,
                  compra.diasSinMovimiento,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ===========================================================================
// Tabla de líneas del detalle
// ===========================================================================

/// «Faltantes por producto y línea»: una fila por línea de la compra.
Widget tablaLineasPendientes({
  required List<LineaPendienteCompra> lineas,
  required String moneda,
  required bool puedeVerImportes,
  int umbral = umbralAntiguedadDias,
  bool compacta = false,
}) {
  final columnas = <ColumnaReporte>[
    const ColumnaReporte('Producto', 200),
    const ColumnaReporte('Presentación', 120),
    const ColumnaReporte('Cant.', 70, derecha: true),
    const ColumnaReporte('Recibido', 78, derecha: true),
    const ColumnaReporte('Pendiente', 80, derecha: true),
    if (puedeVerImportes)
      const ColumnaReporte('Costo unit.', 96, derecha: true),
    if (puedeVerImportes)
      const ColumnaReporte('Monto pend.', 108, derecha: true),
    if (!compacta) const ColumnaReporte('Últ. recep.', 96),
    const ColumnaReporte('Días s/mov.', 88, derecha: true),
  ];

  final filas = <FilaReporte>[
    for (final linea in lineas)
      FilaReporte([
        celdaDoble(
          linea.producto.isEmpty ? 'Producto sin nombre' : linea.producto,
          linea.variante,
        ),
        celdaTexto(linea.textoPresentacion),
        celdaCifra(formatearCantidad(linea.cantidad)),
        celdaCifra(
          formatearCantidad(linea.recibido),
          color: linea.recibido > 0 ? AppColors.success : AppColors.textLight,
        ),
        celdaCifra(
          formatearCantidad(linea.pendiente),
          negrita: linea.tienePendiente,
          color: linea.tienePendiente ? AppColors.warning : AppColors.textLight,
        ),
        if (puedeVerImportes)
          celdaCifra(formatearImporteMoneda(linea.costoUnitario, moneda)),
        if (puedeVerImportes)
          celdaCifra(
            formatearImporteMoneda(linea.montoPendiente, moneda),
            negrita: true,
          ),
        if (!compacta)
          celdaTexto(
            linea.ultimaRecepcion == null
                ? 'Sin recepción'
                : formatearFecha(linea.ultimaRecepcion),
            color: linea.ultimaRecepcion == null ? AppColors.warning : null,
          ),
        celdaCifra(
          textoDiasCorto(linea.diasSinMovimiento),
          color: superaUmbralAntiguedad(linea.diasSinMovimiento, umbral: umbral)
              ? AppColors.warning
              : null,
        ),
      ]),
  ];

  return TablaReporte(columnas: columnas, filas: filas);
}

/// Cabecera de la compra en el detalle: avance recibido/total y las cuatro
/// cifras de la operación (pedido, recibido, pendiente y monto pendiente).
Widget avanceCompraPendiente({
  required CompraPendienteCabecera compra,
  required bool puedeVerImportes,
}) {
  final pendiente = compra.pedido - compra.recibido;
  return panelCompras(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Recibido ${formatearCantidad(compra.recibido)} de '
              '${formatearCantidad(compra.pedido)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '${porcentajeRecibido(compra.recibidoPct)} %',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: compra.recibidoPct.clamp(0.0, 1.0),
          minHeight: 8,
          backgroundColor: AppColors.border,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, constraints) {
          final widgets = <Widget>[
            cifraCompra(
              'Pedido',
              formatearCantidad(compra.pedido),
              helper: 'unidades',
            ),
            cifraCompra(
              'Recibido',
              formatearCantidad(compra.recibido),
              color: AppColors.success,
              helper: 'unidades',
            ),
            cifraCompra(
              'Pendiente',
              formatearCantidad(pendiente < 0 ? 0 : pendiente),
              destacada: true,
              color: AppColors.warning,
              helper: 'unidades',
            ),
            if (puedeVerImportes)
              cifraCompra(
                'Monto pendiente',
                formatearImporte(compra.montoPendiente),
                destacada: true,
                helper: compra.moneda.isEmpty
                    ? null
                    : 'moneda de la factura (${compra.moneda})',
              ),
          ];
          if (constraints.maxWidth < 620) {
            return Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                for (final w in widgets)
                  SizedBox(width: (constraints.maxWidth - 20) / 2, child: w),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widgets.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      height: 40,
                      child: VerticalDivider(width: 1, color: AppColors.border),
                    ),
                  ),
                Expanded(child: widgets[i]),
              ],
            ],
          );
        },
      ),
    ],
  );
}

// ===========================================================================
// Estados vacíos, cargando y error
// ===========================================================================

/// Estado vacío del panel: nunca una tabla con cabecera y cero filas.
Widget estadoVacioPendientes({
  String titulo = 'Ninguna compra abierta',
  String detalle =
      'Todas las compras registradas están completadas o canceladas: no queda '
      'mercancía por recibir.',
}) => mensajeVacioReporte(
  titulo: titulo,
  detalle: detalle,
  icono: Icons.inventory_2_outlined,
);

/// Cargando del panel y de las listas.
Widget cargandoPendientes({String texto = 'Cargando pendientes...'}) =>
    panelCargandoReporte(texto: texto);

/// Error del panel con su botón de reintento (idéntico al de Reportes).
Widget errorPendientes({
  required String mensaje,
  required VoidCallback onReintentar,
  String titulo = 'No se pudieron cargar los pendientes',
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        titulo,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      errorReporte(mensaje: mensaje, onReintentar: onReintentar),
    ],
  );
}

// ===========================================================================
// Selector de orden
// ===========================================================================

/// Selector de orden del panel. Cambiarlo **vuelve a pedir al servidor**: el
/// orden es parte de la respuesta (`orden`) y no se reordena en cliente.
Widget selectorOrdenPendientes({
  required PendientesOrden valor,
  required ValueChanged<PendientesOrden> onCambio,
  bool habilitado = true,
}) {
  return SegmentedButton<PendientesOrden>(
    segments: [
      for (final orden in PendientesOrden.values)
        ButtonSegment<PendientesOrden>(
          value: orden,
          label: Text(
            orden.etiqueta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    selected: {valor},
    showSelectedIcon: false,
    style: ButtonStyle(
      visualDensity: VisualDensity.compact,
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    ),
    onSelectionChanged: habilitado
        ? (seleccion) {
            if (seleccion.isEmpty) return;
            onCambio(seleccion.first);
          }
        : null,
  );
}