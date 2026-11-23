/// Piezas de presentación de la pantalla de Reportes (fase 8 de Compras).
///
/// Solo estilo: la verdad de las cifras viene de `reportes_service.dart` y los
/// cálculos de `reportes_calculos.dart`. Las tablas son densas, con cabecera
/// de 11 px en mayúsculas, cifras tabulares a la derecha y chips de 22 px; sin
/// degradados ni ilustraciones.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../compras/compras_widgets.dart' show panelCompras;
import 'reportes_calculos.dart';

// ===========================================================================
// Paleta de los estados del reporte
// ===========================================================================

/// Verde de «cuadra»: el `AppColors.success` no llega a 4.5:1 sobre el fondo
/// verde claro, así que el texto usa el tono 700.
const Color verdeTexto = Color(0xFF047857);
const Color verdeFondo = Color(0xFFECFDF5);
const Color verdeBorde = Color(0xFFA7F3D0);

/// Rojo de la alarma de conciliación (valores del encargo de diseño).
const Color rojoTexto = Color(0xFFB91C1C);
const Color rojoFondo = Color(0xFFFEE2E2);
const Color rojoBorde = Color(0xFFFCA5A5);

const Color naranjaTexto = Color(0xFFC2410C);
const Color naranjaFondo = Color(0xFFFFF7ED);
const Color naranjaBorde = Color(0xFFFED7AA);

// ===========================================================================
// Cifras y chips
// ===========================================================================

/// Importe en tabla: alineado a la derecha y con cifras tabulares.
Widget celdaCifra(
  String texto, {
  bool negrita = false,
  Color? color,
  String? subtexto,
}) {
  final textoWidget = Text(
    texto,
    textAlign: TextAlign.right,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 13,
      fontWeight: negrita ? FontWeight.w600 : FontWeight.w400,
      color: color ?? AppColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  if (subtexto == null) return textoWidget;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      textoWidget,
      const SizedBox(height: 2),
      Text(
        subtexto,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: AppColors.textLight),
      ),
    ],
  );
}

/// Texto suelto de una celda.
Widget celdaTexto(
  String texto, {
  bool negrita = false,
  Color? color,
  int? maxLineas,
}) {
  return Text(
    texto,
    maxLines: maxLineas ?? 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 13,
      fontWeight: negrita ? FontWeight.w600 : FontWeight.w400,
      color: color ?? AppColors.textPrimary,
    ),
  );
}

/// Título con su línea de apoyo dentro de una celda (compra + proveedor).
Widget celdaDoble(String titulo, String? subtitulo) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        titulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      if (subtitulo != null && subtitulo.trim().isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          subtitulo.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            height: 1.25,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ],
  );
}

/// Chip de 22 px: siempre lleva texto; el color nunca es la única señal.
Widget chipReporte(
  String texto, {
  required Color color,
  Color? fondo,
  Color? borde,
  IconData? icono,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: fondo ?? color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: borde ?? color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icono != null) ...[
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Envuelve un chip para una celda de tabla: si la columna es más estrecha que
/// el chip, se escala en lugar de desbordar. Nunca se corta ni se pierde el
/// texto (la señal no puede depender solo del color).
Widget celdaChip(Widget chip) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: chip,
  );
}

/// Chip de `pct_desvio` (ya en porcentaje): verde si ≤ 0, naranja si > 0.
/// Un `null` no se inventa: se pinta «—».
Widget chipDesvio(double? pct) {
  if (pct == null) {
    return celdaCifra('—', color: AppColors.textLight);
  }
  final color = pct <= 0 ? verdeTexto : naranjaTexto;
  final fondo = pct <= 0 ? verdeFondo : naranjaFondo;
  final borde = pct <= 0 ? verdeBorde : naranjaBorde;
  return chipReporte(
    '${pct > 0 ? '+' : ''}${cifraPorcentaje(pct)} %',
    color: color,
    fondo: fondo,
    borde: borde,
  );
}

/// Chip del `signo` cambiario. El texto es obligatorio: «a favor»/«en contra».
Widget chipSigno(String signo) {
  final favorable = signo.toLowerCase().contains('favor');
  return chipReporte(
    signo,
    color: favorable ? verdeTexto : naranjaTexto,
    fondo: favorable ? verdeFondo : naranjaFondo,
    borde: favorable ? verdeBorde : naranjaBorde,
    icono: favorable ? Icons.south_east : Icons.north_east,
  );
}

// ===========================================================================
// Contenedores
// ===========================================================================

/// Tarjeta blanca de un bloque del reporte.
Widget panelReporte({
  required List<Widget> children,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
}) => panelCompras(children: children, padding: padding);

/// Cabecera de tarjeta: título, apoyo y acción opcional a la derecha.
Widget cabeceraReporte(String titulo, {String? subtitulo, Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final izquierda = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (subtitulo != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitulo,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        );
        if (trailing == null) return izquierda;
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [izquierda, const SizedBox(height: 8), trailing],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: izquierda),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: trailing,
            ),
          ],
        );
      },
    ),
  );
}

/// Texto de apoyo de una tarjeta (bajo la cabecera o al pie).
Widget notaReporte(String texto, {Color? color}) => Text(
  texto,
  style: TextStyle(
    fontSize: 11,
    height: 1.4,
    color: color ?? AppColors.textSecondary,
  ),
);

/// Franja de estado de la conciliación: verde si todo cuadra, roja si no.
Widget bandaEstado({
  required bool alarma,
  required String titulo,
  required String detalle,
  required String etiquetaDerecha,
  required String valorDerecha,
}) {
  final color = alarma ? rojoTexto : verdeTexto;
  final fondo = alarma ? rojoFondo : verdeFondo;
  final borde = alarma ? rojoBorde : verdeBorde;

  final izquierda = Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        alarma ? Icons.error_outline : Icons.check_circle_outline,
        size: 18,
        color: color,
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          titulo,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(detalle, style: TextStyle(fontSize: 13, color: color)),
      ),
    ],
  );

  final derecha = Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        etiquetaDerecha,
        style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9)),
      ),
      const SizedBox(height: 2),
      Text(
        valorDerecha,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borde),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [izquierda, const SizedBox(height: 8), derecha],
          );
        }
        return Row(
          children: [
            Expanded(child: izquierda),
            const SizedBox(width: 12),
            derecha,
          ],
        );
      },
    ),
  );
}

/// Aviso grande de conciliación rota. Va **arriba del todo** de la pantalla,
/// antes de cualquier tarjeta, y no se limita a una banda dentro de la tarjeta.
Widget bannerAlarma({
  required String titulo,
  required String detalle,
  required String etiquetaDerecha,
  required String valorDerecha,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: rojoFondo,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: rojoBorde),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final izquierda = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline, size: 24, color: rojoTexto),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: rojoTexto,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detalle,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: rojoTexto,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final derecha = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              etiquetaDerecha,
              style: const TextStyle(fontSize: 12, color: rojoTexto),
            ),
            const SizedBox(height: 2),
            Text(
              valorDerecha,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: rojoTexto,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );

        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [izquierda, const SizedBox(height: 10), derecha],
          );
        }
        return Row(
          children: [
            Expanded(child: izquierda),
            const SizedBox(width: 16),
            derecha,
          ],
        );
      },
    ),
  );
}

/// Franja de resumen (pendientes abiertos) encima de las dos tarjetas gemelas.
Widget franjaResumen({
  required IconData icono,
  required Color color,
  required Color fondo,
  required Color borde,
  required List<Widget> children,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borde),
    ),
    child: Row(
      children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final hijo in children)
                DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  child: hijo,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Cifra grande de cabecera (claves, descuadres, diferencia total).
Widget cifraKpi(String etiqueta, String valor, {String? apoyo, Color? color}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        etiqueta.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        valor,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: color ?? AppColors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      if (apoyo != null) ...[
        const SizedBox(height: 2),
        Text(
          apoyo,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    ],
  );
}

/// Estado vacío explícito: nunca una tabla con cabecera y cero filas.
Widget mensajeVacioReporte({
  required String titulo,
  required String detalle,
  IconData icono = Icons.inbox_outlined,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Icon(icono, size: 28, color: AppColors.textLight),
        const SizedBox(height: 8),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detalle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

/// Cargando de un bloque (solo mientras no hay datos ni error).
Widget panelCargandoReporte({String texto = 'Cargando…'}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28),
    alignment: Alignment.center,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

/// Error de un bloque: el resto de la pantalla sigue funcionando.
Widget errorReporte({
  required String mensaje,
  required VoidCallback onReintentar,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: rojoFondo,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: rojoBorde),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 18, color: rojoTexto),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            mensaje,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: rojoTexto,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: onReintentar,
          style: OutlinedButton.styleFrom(
            foregroundColor: rojoTexto,
            side: const BorderSide(color: rojoBorde),
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Reintentar'),
        ),
      ],
    ),
  );
}

// ===========================================================================
// Tabla densa
// ===========================================================================

/// Columna de [TablaReporte]. El ancho es relativo: si sobra espacio, las
/// columnas se reparten el ancho disponible en esa proporción; si falta, la
/// tabla se desplaza en horizontal (nunca se corta).
class ColumnaReporte {
  final String titulo;
  final double ancho;
  final bool derecha;

  const ColumnaReporte(this.titulo, this.ancho, {this.derecha = false});
}

/// Fila de [TablaReporte]: o celdas, o una banda de ancho completo.
class FilaReporte {
  final List<Widget>? celdas;
  final Widget? banda;
  final bool resaltada;

  const FilaReporte(List<Widget> this.celdas, {this.resaltada = false})
    : banda = null;

  const FilaReporte.banda(Widget this.banda) : celdas = null, resaltada = false;
}

/// Tabla densa con cabecera en mayúsculas y bandas intercaladas (subtotales
/// por día, avisos) que ocupan todo el ancho.
class TablaReporte extends StatelessWidget {
  final List<ColumnaReporte> columnas;
  final List<FilaReporte> filas;

  const TablaReporte({super.key, required this.columnas, required this.filas});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = columnas.fold<double>(0, (suma, c) => suma + c.ancho);
        if (base <= 0) return const SizedBox.shrink();
        final disponible = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : base;
        final factor = math.max(1.0, disponible / base);
        final anchoTotal = base * factor;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: anchoTotal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _cabecera(factor),
                for (final fila in filas)
                  if (fila.banda != null)
                    fila.banda!
                  else
                    _filaCeldas(fila, factor),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cabecera(double factor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (final columna in columnas)
            SizedBox(
              width: columna.ancho * factor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  columna.titulo.toUpperCase(),
                  textAlign: columna.derecha ? TextAlign.right : TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaCeldas(FilaReporte fila, double factor) {
    final celdas = fila.celdas ?? const <Widget>[];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: fila.resaltada ? AppColors.surfaceVariant : null,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columnas.length; i++)
            SizedBox(
              width: columnas[i].ancho * factor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: columnas[i].derecha
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: i < celdas.length
                      ? celdas[i]
                      : const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
