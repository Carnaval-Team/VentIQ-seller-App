import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Gráfico de barras mínimo, sin dependencias externas.
///
/// Se escribió a mano en vez de añadir `fl_chart` porque la app no tiene (ni
/// necesita) ninguna librería de gráficos: publicar el paquete obligaría a un
/// `pub get` con red en 7 apps para pintar 30 barras estáticas. Un
/// `CustomPainter` cubre el caso — serie diaria, eje de fechas, selección para
/// ver el valor exacto — y no añade riesgo de versión.
class GraficoBarras extends StatefulWidget {
  const GraficoBarras({
    super.key,
    required this.valores,
    required this.etiquetas,
    this.maxValor,
    this.color,
    this.altura = 140,
    this.textoVacio = 'Sin datos en el período',
  });

  /// Altura de cada barra, en el orden de [etiquetas].
  final List<double> valores;

  /// Etiqueta de cada barra (la fecha, ya formateada).
  final List<String> etiquetas;

  /// Escala superior. Si es null se usa el máximo de [valores] (mínimo 1).
  final double? maxValor;

  final Color? color;
  final double altura;

  /// Qué decir cuando la serie está vacía o es todo ceros.
  final String textoVacio;

  @override
  State<GraficoBarras> createState() => _GraficoBarrasState();
}

class _GraficoBarrasState extends State<GraficoBarras> {
  int? _seleccionado;

  double get _max {
    final explicito = widget.maxValor;
    if (explicito != null && explicito > 0) return explicito;
    var max = 0.0;
    for (final v in widget.valores) {
      if (v > max) max = v;
    }
    return max < 1 ? 1 : max;
  }

  bool get _sinDatos =>
      widget.valores.isEmpty || widget.valores.every((v) => v <= 0);

  @override
  void didUpdateWidget(GraficoBarras oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si la serie cambia (otra entidad, otro período), la barra seleccionada ya
    // no significa lo mismo.
    if (oldWidget.valores.length != widget.valores.length) {
      _seleccionado = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.primary;

    if (_sinDatos) {
      return SizedBox(
        height: widget.altura,
        child: Center(
          child: Text(
            widget.textoVacio,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    final etiquetaSel = _seleccionado == null
        ? null
        : '${widget.etiquetas[_seleccionado!]}: '
              '${_formatoValor(widget.valores[_seleccionado!])}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reserva de altura fija: si el rótulo apareciera y desapareciera, el
        // gráfico daría un salto al tocar una barra.
        SizedBox(
          height: 22,
          child: etiquetaSel == null
              ? null
              : Text(
                  etiquetaSel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Semantics(
          label: 'Gráfico de barras con ${widget.valores.length} puntos',
          child: SizedBox(
            height: widget.altura,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (detalle) => _seleccionar(
                    detalle.localPosition.dx,
                    constraints.maxWidth,
                  ),
                  onHorizontalDragUpdate: (detalle) => _seleccionar(
                    detalle.localPosition.dx,
                    constraints.maxWidth,
                  ),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, widget.altura),
                    painter: _PintorBarras(
                      valores: widget.valores,
                      max: _max,
                      color: color,
                      lineaGuia: AppTheme.border,
                      seleccionado: _seleccionado,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Sólo los extremos: con 30 días, una etiqueta por barra es ilegible en
        // móvil y el rótulo de selección ya da la fecha exacta.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.etiquetas.first, style: _estiloEje),
            if (widget.etiquetas.length > 2)
              Text(
                widget.etiquetas[widget.etiquetas.length ~/ 2],
                style: _estiloEje,
              ),
            Text(widget.etiquetas.last, style: _estiloEje),
          ],
        ),
      ],
    );
  }

  void _seleccionar(double dx, double ancho) {
    if (widget.valores.isEmpty || ancho <= 0) return;
    final indice = (dx / (ancho / widget.valores.length)).floor().clamp(
      0,
      widget.valores.length - 1,
    );
    if (indice != _seleccionado) setState(() => _seleccionado = indice);
  }

  static const TextStyle _estiloEje = TextStyle(
    fontSize: 11,
    color: AppTheme.textSecondary,
  );

  /// Los totales son enteros, pero la clase acepta dobles por si mañana se
  /// grafica una media.
  static String _formatoValor(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _PintorBarras extends CustomPainter {
  _PintorBarras({
    required this.valores,
    required this.max,
    required this.color,
    required this.lineaGuia,
    required this.seleccionado,
  });

  final List<double> valores;
  final double max;
  final Color color;
  final Color lineaGuia;
  final int? seleccionado;

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty || size.width <= 0 || size.height <= 0) return;

    final pinturaGuia = Paint()
      ..color = lineaGuia
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      pinturaGuia,
    );

    final anchoRanura = size.width / valores.length;
    // 2 px de aire por lado; con 30 barras en un móvil quedan ~4 px de barra.
    final anchoBarra = (anchoRanura - 4).clamp(1.5, 32.0);

    for (var i = 0; i < valores.length; i++) {
      final v = valores[i];
      if (v <= 0) continue;
      final alto = (v / max * size.height).clamp(2.0, size.height);
      final izquierda = anchoRanura * i + (anchoRanura - anchoBarra) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(izquierda, size.height - alto, anchoBarra, alto),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = i == seleccionado
              ? AppTheme.primaryDark
              : color.withValues(alpha: seleccionado == null ? 0.85 : 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_PintorBarras old) =>
      old.max != max ||
      old.seleccionado != seleccionado ||
      old.color != color ||
      !_mismaSerie(old.valores, valores);

  static bool _mismaSerie(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
