import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/presentacion_cadena_local.dart';

/// Una linea capturada: cuanto se movio de una presentacion concreta.
class LineaPresentacion {
  final PresentacionLocal presentacion;
  final double cantidad;

  const LineaPresentacion({
    required this.presentacion,
    required this.cantidad,
  });

  double get equivalenteBase => cantidad * presentacion.factorRel;
}

/// Captura de cantidades por presentacion para las pantallas del vendedor.
///
/// FASE 2 de presentaciones (docs/PLAN_PRESENTACIONES_INVENTARIO.md).
///
/// Funciona SIN RED: la cadena se resuelve desde el payload cacheado en
/// `offline_products` con [PresentacionCadenaLocal], que replica la cascada de
/// `fn_presentaciones_producto`. Esta app es offline-first y el vendedor mueve
/// mercancia sin conexion, asi que pedirle la cadena al servidor no era opcion.
///
/// Lo que NO hace, a proposito:
///   - no convierte cantidades a la presentacion base (eso murio en la Fase 1);
///   - no valida contra el stock disponible: en los egresos, si falta saldo
///     suelto, `fn_descontar_con_rebalanceo` abre el empaque mayor en el
///     servidor. Validar aca rechazaria movimientos que el servidor si puede
///     cumplir.
class CapturaMixtaPresentacion extends StatefulWidget {
  /// Producto tal como vino del cache (`listCachedProducts`).
  final Map<String, dynamic> producto;

  /// Se llama en cada cambio con las lineas que tienen cantidad > 0.
  final ValueChanged<List<LineaPresentacion>> onChanged;

  /// Texto del boton de accion. Null oculta el boton (el padre pone el suyo).
  final String? textoBoton;

  /// Accion del boton propio.
  final VoidCallback? onSubmit;

  /// En egresos avisa que el servidor puede romper un empaque.
  final bool avisarRebalanceo;

  const CapturaMixtaPresentacion({
    super.key,
    required this.producto,
    required this.onChanged,
    this.textoBoton,
    this.onSubmit,
    this.avisarRebalanceo = false,
  });

  @override
  State<CapturaMixtaPresentacion> createState() =>
      _CapturaMixtaPresentacionState();
}

class _CapturaMixtaPresentacionState extends State<CapturaMixtaPresentacion> {
  List<PresentacionLocal> _cadena = [];
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _resolver();
  }

  @override
  void didUpdateWidget(CapturaMixtaPresentacion old) {
    super.didUpdateWidget(old);
    // Si cambia el producto hay que rearmar los campos: los ids de presentacion
    // del producto anterior no significan nada en el nuevo.
    if (old.producto['id'] != widget.producto['id']) {
      _resolver();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _resolver() {
    final cadena = PresentacionCadenaLocal.resolver(widget.producto);

    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    for (final p in cadena) {
      _controllers[p.idPresentacion] = TextEditingController();
    }

    setState(() => _cadena = cadena);
    widget.onChanged(const []);
  }

  double _valorDe(int id) {
    final txt = _controllers[id]?.text.trim().replaceAll(',', '.');
    if (txt == null || txt.isEmpty) return 0;
    return double.tryParse(txt) ?? 0;
  }

  List<LineaPresentacion> get _lineas {
    final out = <LineaPresentacion>[];
    // Se recorre la cadena, no el mapa: las lineas salen ordenadas del empaque
    // mayor al menor, igual que en los reportes.
    for (final p in _cadena) {
      final v = _valorDe(p.idPresentacion);
      if (v > 0) out.add(LineaPresentacion(presentacion: p, cantidad: v));
    }
    return out;
  }

  String get _nombreBase =>
      PresentacionCadenaLocal.base(_cadena)?.nombre ?? 'unidad';

  void _notificar() {
    setState(() {});
    widget.onChanged(_lineas);
  }

  @override
  Widget build(BuildContext context) {
    if (_cadena.isEmpty) {
      // Sin cadena conocida no se inventa una presentacion: se avisa. Mandar un
      // id adivinado es justo el bug que la Fase 1 elimino.
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Este producto no tiene presentaciones en el caché. '
                'Sincroniza el dispositivo con conexión.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final lineas = _lineas;
    final equivalente = lineas.fold<double>(
      0,
      (s, l) => s + l.equivalenteBase,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._cadena.map(_buildCampo),

        if (lineas.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lineas
                      .map((l) =>
                          '${FormatoPresentacion.cantidad(l.cantidad)} '
                          '${FormatoPresentacion.plural(l.presentacion.nombre, l.cantidad)}')
                      .join(' + '),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade900,
                  ),
                ),
                // Con una sola presentacion el equivalente repetiria lo mismo.
                if (lineas.length > 1)
                  Text(
                    '= ${FormatoPresentacion.cantidad(equivalente)} '
                    '${FormatoPresentacion.plural(_nombreBase, equivalente)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
              ],
            ),
          ),
          if (widget.avisarRebalanceo && lineas.length == 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Si no hay saldo suelto de esa presentación, el sistema abrirá '
                'el empaque mayor y lo dejará registrado.',
                style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
              ),
            ),
        ],

        if (widget.textoBoton != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onSubmit,
              child: Text(widget.textoBoton!),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCampo(PresentacionLocal p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.nombre,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  FormatoPresentacion.equivalencia(p, _nombreBase),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _controllers[p.idPresentacion],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                hintText: '0',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _notificar(),
            ),
          ),
        ],
      ),
    );
  }
}
