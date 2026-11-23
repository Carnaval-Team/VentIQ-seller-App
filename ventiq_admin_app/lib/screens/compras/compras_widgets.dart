/// Piezas compartidas por las 3 pantallas del módulo Compras.
///
/// Aquí vive **solo presentación y la previsualización de cifras**: la verdad
/// de los totales es la que devuelve `fn_fdi_compra_crear` / `fn_fdi_compra_detalle`.
/// El cálculo local replica `fn_fdi_compra_recalcular` para que el panel de
/// cifras del formulario no obligue a esperar al servidor.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../models/compra.dart';
import '../../models/pendientes.dart' show EstadoRecepcion;

// ===========================================================================
// Cortes de layout
// ===========================================================================

/// Cortes adoptados por `docs/planes/fondo-inversion/04-diseno-ux.md` §4.
const double comprasAnchoCompacto = 600;
const double comprasAnchoExpandido = 1024;

/// A partir de aquí la tabla del listado cabe con panel lateral de 340 px.
/// Por debajo de este ancho la tabla va a ancho completo: 10 columnas
/// apretadas se cortan, y "nada de tablas que se corten" manda.
const double comprasAnchoPanelLateral = 1280;

enum ComprasTamano { compacto, medio, expandido }

ComprasTamano comprasTamanoDe(double ancho) {
  if (ancho < comprasAnchoCompacto) return ComprasTamano.compacto;
  if (ancho <= comprasAnchoExpandido) return ComprasTamano.medio;
  return ComprasTamano.expandido;
}

// ===========================================================================
// Formato
// ===========================================================================

final NumberFormat _fmtImporte = NumberFormat('#,##0.00');
final NumberFormat _fmtCantidad = NumberFormat('#,##0.####');

String formatearImporte(num valor) => _fmtImporte.format(valor);

String formatearCantidad(num valor) => _fmtCantidad.format(valor);

/// Importe con su moneda delante del número no: el repo escribe "1.240,00 CUP".
String formatearImporteMoneda(num valor, String moneda) {
  final m = moneda.trim();
  return m.isEmpty ? formatearImporte(valor) : '${formatearImporte(valor)} $m';
}

String formatearFecha(DateTime? fecha) =>
    fecha == null ? '—' : DateFormat('dd/MM/yyyy').format(fecha);

String formatearFechaHora(DateTime? fecha) =>
    fecha == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(fecha);

/// Redondeo a 2 decimales, igual que `round(x, 2)` de PostgreSQL para valores
/// no negativos (cantidades y costos tienen CHECK >= 0).
double redondear2(double valor) =>
    valor.isFinite ? (valor * 100).round() / 100 : 0;

// ===========================================================================
// Estado: color + icono + chip
// ===========================================================================

/// Paleta del nomenclador de estados de compra
/// (`docs/planes/fondo-inversion/13-ui-compras.md`, §Transversal). El esquema
/// de la app no tiene colores por estado y la RPC de compras no devuelve
/// `color_estado`, así que se replican aquí los mismos valores documentados.
const Map<String, Color> _coloresEstadoCompra = {
  'creada': Color(0xFF2196F3),
  'reservada': Color(0xFF9C27B0),
  'pagada': Color(0xFF00BCD4),
  'entrega_parcial': Color(0xFFFF9800),
  'completada': Color(0xFF4CAF50),
  'cancelada': Color(0xFF607D8B),
  'anulada': Color(0xFFF44336),
};

const Map<String, IconData> _iconosEstadoCompra = {
  'creada': Icons.edit_note,
  'reservada': Icons.lock_clock,
  'pagada': Icons.payments,
  'entrega_parcial': Icons.local_shipping,
  'completada': Icons.check_circle,
  'cancelada': Icons.cancel,
  'anulada': Icons.block,
};

Color colorEstadoCompra(String estado) =>
    _coloresEstadoCompra[estado] ?? AppColors.textSecondary;

IconData iconoEstadoCompra(String estado) =>
    _iconosEstadoCompra[estado] ?? Icons.help_outline;

/// Chip de estado: icono + texto, nunca solo color.
Widget chipEstadoCompra(String estado, {bool denso = false}) => _chipEstado(
  CompraEstado.etiquetaDe(estado),
  colorEstadoCompra(estado),
  iconoEstadoCompra(estado),
  denso,
);

/// Chip del **estado de recepción** de una factura (`fn_fdi_facturas`:
/// `sin recibir` / `parcial` / `completa`).
///
/// Sale de la misma paleta que los estados de compra —no hay una segunda
/// paleta para el mismo semáforo— y el texto siempre acompaña al color.
Widget chipEstadoRecepcion(String estado, {bool denso = false}) {
  final recepcion = EstadoRecepcion.desde(estado);
  return _chipEstado(
    recepcion.etiqueta,
    colorEstadoRecepcion(recepcion),
    iconoEstadoRecepcion(recepcion),
    denso,
  );
}

/// Color de un estado de recepción, tomado de la paleta de estados de compra:
/// completa = `completada`, parcial = `entrega_parcial`, sin recibir = `creada`.
Color colorEstadoRecepcion(EstadoRecepcion estado) {
  switch (estado) {
    case EstadoRecepcion.completa:
      return colorEstadoCompra('completada');
    case EstadoRecepcion.parcial:
      return colorEstadoCompra('entrega_parcial');
    case EstadoRecepcion.sinRecibir:
      return colorEstadoCompra('creada');
  }
}

IconData iconoEstadoRecepcion(EstadoRecepcion estado) {
  switch (estado) {
    case EstadoRecepcion.completa:
      return iconoEstadoCompra('completada');
    case EstadoRecepcion.parcial:
      return iconoEstadoCompra('entrega_parcial');
    case EstadoRecepcion.sinRecibir:
      return iconoEstadoCompra('creada');
  }
}

/// Pastilla de 22 px compartida por los chips de estado de compras.
Widget _chipEstado(
  String etiqueta,
  Color color,
  IconData icono,
  bool denso,
) {
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: denso ? 8 : 10,
      vertical: denso ? 3 : 4,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: denso ? 12 : 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            etiqueta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: denso ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Pastilla neutra (liquidación, política de pago, tasa, base de ajuste).
Widget pastillaCompras(
  String texto, {
  Color? color,
  IconData? icono,
  bool denso = false,
}) {
  final c = color ?? AppColors.secondary;
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: denso ? 8 : 10,
      vertical: denso ? 3 : 4,
    ),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: c.withValues(alpha: 0.30)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icono != null) ...[
          Icon(icono, size: denso ? 12 : 14, color: c),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: denso ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ),
      ],
    ),
  );
}

// ===========================================================================
// Contenedores
// ===========================================================================

Widget panelCompras({
  required List<Widget> children,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 12, 16, 14),
}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    ),
  );
}

Widget tituloSeccionCompras(String titulo, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
}

Widget textoMetaCompras(String texto) => Text(
  texto,
  style: const TextStyle(
    fontSize: 13,
    height: 1.35,
    color: AppColors.textSecondary,
  ),
);

/// Aviso en recuadro `warning` (recepción existente, datos incompletos...).
Widget avisoCompras(
  String texto, {
  IconData icono = Icons.info_outline,
  Color? color,
}) {
  final c = color ?? AppColors.warning;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: c),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: c,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

// ===========================================================================
// Cifras y previsualización de totales
// ===========================================================================

/// Los cuatro totales, siempre separados: nunca se suman entre ellos.
class TotalesCompra {
  final double mercancia;
  final double ajustes;
  final double financiado;
  final double aterrizado;

  const TotalesCompra({
    this.mercancia = 0,
    this.ajustes = 0,
    this.financiado = 0,
    this.aterrizado = 0,
  });

  factory TotalesCompra.de(Compra compra) => TotalesCompra(
    mercancia: compra.totalMercancia,
    ajustes: compra.totalAjustes,
    financiado: compra.totalFinanciado,
    aterrizado: compra.costoAterrizado,
  );

  static const cero = TotalesCompra();
}

TotalesCompra sumarTotalesCompra(Iterable<CompraResumen> filas) {
  var mercancia = 0.0, ajustes = 0.0, financiado = 0.0, aterrizado = 0.0;
  for (final f in filas) {
    mercancia += f.totalMercancia;
    ajustes += f.totalAjustes;
    financiado += f.totalFinanciado;
    aterrizado += f.costoAterrizado;
  }
  return TotalesCompra(
    mercancia: redondear2(mercancia),
    ajustes: redondear2(ajustes),
    financiado: redondear2(financiado),
    aterrizado: redondear2(aterrizado),
  );
}

/// `monto_capitalizado` de un ajuste, con la misma regla que
/// `fn_fdi_compra_crear`: porcentaje sobre la mercancía, unidad por la
/// cantidad total de líneas y global como valor literal.
double montoAjusteCompra(
  CompraAjuste ajuste, {
  required double mercancia,
  required double cantidad,
}) {
  switch (ajuste.base) {
    case 'porcentaje':
      return redondear2(mercancia * ajuste.valor / 100);
    case 'unidad':
      return redondear2(ajuste.valor * cantidad);
    default:
      return redondear2(ajuste.valor);
  }
}

/// Réplica en cliente de `fn_fdi_compra_recalcular` (03a_compra_esquema.sql):
///   mercancía  = suma de `costo_linea`
///   ajustes    = suma de `monto_capitalizado`
///   financiado = mercancía + ajustes cuyo `origen_pago` es `fondo`
///   aterrizado = mercancía + todos los ajustes
///
/// Es solo previsualización: al guardar manda la RPC.
TotalesCompra calcularTotalesCompra(
  List<CompraLinea> lineas,
  List<CompraAjuste> ajustes,
) {
  var mercancia = 0.0;
  var cantidad = 0.0;
  for (final l in lineas) {
    mercancia += redondear2(l.cantidad * l.costoUnitario);
    cantidad += l.cantidad;
  }

  var totalAjustes = 0.0;
  var ajustesFondo = 0.0;
  for (final a in ajustes) {
    final monto = montoAjusteCompra(
      a,
      mercancia: mercancia,
      cantidad: cantidad,
    );
    totalAjustes += monto;
    if (a.origenPago == OrigenPagoAjuste.fondo.codigo) ajustesFondo += monto;
  }

  return TotalesCompra(
    mercancia: redondear2(mercancia),
    ajustes: redondear2(totalAjustes),
    financiado: redondear2(mercancia + ajustesFondo),
    aterrizado: redondear2(mercancia + totalAjustes),
  );
}

/// Etiquetas únicas para los 4 totales: se usan en las 3 pantallas para que
/// "financiado" y "aterrizado" no se confundan nunca.
const String etiquetaMercancia = 'Mercancía';
const String etiquetaAjustes = 'Ajustes';
const String etiquetaFinanciado = 'Financiado (lo paga el fondo)';
const String etiquetaAterrizado = 'Aterrizado';

Widget cifraCompra(
  String etiqueta,
  String valor, {
  String? moneda,
  bool destacada = false,
  Color? color,
  String? helper,
  TextAlign alineacion = TextAlign.left,
}) {
  final cruce = alineacion == TextAlign.right
      ? CrossAxisAlignment.end
      : CrossAxisAlignment.start;
  return Column(
    crossAxisAlignment: cruce,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        etiqueta,
        textAlign: alineacion,
        style: const TextStyle(
          fontSize: 12,
          height: 1.2,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        valor,
        textAlign: alineacion,
        style: TextStyle(
          fontSize: destacada ? 20 : 16,
          fontWeight: destacada ? FontWeight.w700 : FontWeight.w600,
          color: color ?? AppColors.textPrimary,
          height: 1.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      if (moneda != null && moneda.trim().isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          moneda,
          textAlign: alineacion,
          style: const TextStyle(fontSize: 11, color: AppColors.textLight),
        ),
      ],
      if (helper != null) ...[
        const SizedBox(height: 4),
        Text(
          helper,
          textAlign: alineacion,
          style: const TextStyle(
            fontSize: 11,
            height: 1.3,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ],
  );
}

/// Los 4 totales rotulados. Con [apilado] se leen en columna (paneles
/// laterales); sin él, en 2×2 (bandas). El aterrizado va siempre al final,
/// tras un divisor de 2 px y con la tipografía mayor.
Widget bloqueTotalesCompra({
  required TotalesCompra totales,
  required String moneda,
  bool apilado = true,
  String? helperAterrizado,
  Color? colorAterrizado,
}) {
  Widget valor(double v) => Text(
    formatearImporte(v),
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  if (!apilado) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: cifraCompra(
                etiquetaMercancia,
                formatearImporte(totales.mercancia),
                moneda: moneda,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: cifraCompra(
                etiquetaAjustes,
                formatearImporte(totales.ajustes),
                moneda: moneda,
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Divider(height: 2, thickness: 2, color: AppColors.border),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: cifraCompra(
                etiquetaFinanciado,
                formatearImporte(totales.financiado),
                moneda: moneda,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: cifraCompra(
                etiquetaAterrizado,
                formatearImporte(totales.aterrizado),
                moneda: moneda,
                destacada: true,
                color: colorAterrizado,
                helper: helperAterrizado,
              ),
            ),
          ],
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(etiquetaMercancia, style: _estiloEtiqueta),
          ),
          valor(totales.mercancia),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Expanded(child: Text(etiquetaAjustes, style: _estiloEtiqueta)),
          valor(totales.ajustes),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Expanded(
            child: Text(etiquetaFinanciado, style: _estiloEtiqueta),
          ),
          valor(totales.financiado),
        ],
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Divider(height: 2, thickness: 2, color: AppColors.border),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Text(
              etiquetaAterrizado,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            formatearImporte(totales.aterrizado),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colorAterrizado ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          moneda.trim().isEmpty ? '' : moneda,
          style: const TextStyle(fontSize: 11, color: AppColors.textLight),
        ),
      ),
      if (helperAterrizado != null) ...[
        const SizedBox(height: 6),
        Text(
          helperAterrizado,
          style: const TextStyle(
            fontSize: 11,
            height: 1.3,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ],
  );
}

const TextStyle _estiloEtiqueta = TextStyle(
  fontSize: 13,
  color: AppColors.textSecondary,
);

/// Banda de cifras para el listado: en PC/tablet 4, en móvil 2.
Widget bandaTotalesCompra({
  required TotalesCompra totales,
  required String moneda,
  int columnas = 4,
}) {
  final items = [
    (etiquetaMercancia, totales.mercancia),
    (etiquetaAjustes, totales.ajustes),
    (etiquetaFinanciado, totales.financiado),
    (etiquetaAterrizado, totales.aterrizado),
  ];

  if (columnas <= 2) {
    // Móvil: las dos que deciden (lo que paga el fondo y el costo final).
    final visibles = [items[2], items[3]];
    return Row(
      children: [
        for (var i = 0; i < visibles.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 34,
                child: VerticalDivider(width: 1, color: AppColors.border),
              ),
            ),
          Expanded(
            child: cifraCompra(
              visibles[i].$1,
              formatearImporte(visibles[i].$2),
              moneda: moneda,
              destacada: i == 1,
            ),
          ),
        ],
      ],
    );
  }

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 34,
              child: VerticalDivider(width: 1, color: AppColors.border),
            ),
          ),
        Expanded(
          child: cifraCompra(
            items[i].$1,
            formatearImporte(items[i].$2),
            moneda: moneda,
            destacada: i == items.length - 1,
          ),
        ),
      ],
    ],
  );
}

// ===========================================================================
// Texto de importes en tablas
// ===========================================================================

/// Alineación derecha con cifras tabulares, para tablas de importes.
Text textoImporte(String texto, {bool negrita = false}) => Text(
  texto,
  textAlign: TextAlign.right,
  style: TextStyle(
    fontSize: 13,
    fontWeight: negrita ? FontWeight.w600 : FontWeight.w400,
    color: AppColors.textPrimary,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
);
