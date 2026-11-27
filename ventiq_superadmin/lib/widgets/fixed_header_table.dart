import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Tabla que usa todo el ancho disponible: el encabezado queda fijo y
/// solo el cuerpo hace scroll. Las columnas se reparten el ancho según
/// [flex]; si el contenido mínimo supera el ancho, habilita scroll
/// horizontal manteniendo alineados encabezado y filas.
class FixedHeaderTable extends StatelessWidget {
  /// Textos de las columnas (también acepta widgets vía [headerWidgets]).
  final List<String> headers;
  final List<Widget>? headerWidgets;

  /// Peso relativo de cada columna (mismo largo que [headers]).
  final List<int> flex;

  /// Cada fila es una lista de celdas (mismo largo que [headers]).
  final List<List<Widget>> rows;

  /// Ancho mínimo de la tabla; por debajo de este valor hay scroll horizontal.
  final double minWidth;

  /// Alto máximo del área de filas (el encabezado no se mueve).
  final double maxHeight;

  /// Padding vertical de cada celda.
  final double cellPadding;

  /// Se llama al tocar una fila (índice).
  final void Function(int index)? onRowTap;

  /// Índices de filas a resaltar (navegación "ver origen").
  final Set<int>? highlightedRows;

  const FixedHeaderTable({
    super.key,
    required this.headers,
    this.headerWidgets,
    required this.flex,
    required this.rows,
    this.minWidth = 0,
    this.maxHeight = 480,
    this.cellPadding = 10,
    this.onRowTap,
    this.highlightedRows,
  }) : assert(
         headerWidgets == null || headerWidgets.length == headers.length,
       );

  Widget _cell(Widget child, int index, {bool header = false}) {
    return Expanded(
      flex: flex[index],
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: header ? 10 : cellPadding,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const headerHeight = 48.0;
    final bounded = maxHeight.isFinite;
    final body = ListView.separated(
      shrinkWrap: bounded,
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5),
      itemBuilder: (context, index) {
        final highlighted = highlightedRows?.contains(index) ?? false;
        return InkWell(
          onTap: onRowTap == null ? null : () => onRowTap!(index),
          child: Container(
            color:
                highlighted
                    ? AppColors.warning.withValues(alpha: 0.18)
                    : null,
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < headers.length; i++)
                _cell(
                  i < rows[index].length
                      ? rows[index][i]
                      : const SizedBox.shrink(),
                  i,
                ),
              ],
            ),
          ),
        );
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite
                ? constraints.maxWidth.clamp(minWidth, double.infinity)
                : minWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: headerHeight,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE5E7EB), width: 2),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < headers.length; i++)
                        _cell(
                          headerWidgets != null
                              ? headerWidgets![i]
                              : Text(
                                headers[i],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          i,
                          header: true,
                        ),
                    ],
                  ),
                ),
                if (bounded)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: body,
                  )
                else
                  Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }
}
