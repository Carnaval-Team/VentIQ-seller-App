import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/suscripcion_admin_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/suscripcion_ui.dart';

/// Planes de suscripción de Inventtia Flow.
///
/// Un plan es solo duración + precio: lo que se vende es tiempo. Se pueden
/// desactivar en vez de borrar, y el borrado real está protegido en el servidor
/// (si alguien compró el plan, la historia queda y el plan se desactiva).
///
/// Los planes nacen **desactivados** en la base: son un ejemplo con precio 0, y
/// hasta que el superadmin ponga el precio real no deben poder comprarse. Por eso
/// el primer aviso de esta pantalla es cuántos planes activos hay.
class FlowPlanesScreen extends StatefulWidget {
  const FlowPlanesScreen({super.key});

  @override
  State<FlowPlanesScreen> createState() => _FlowPlanesScreenState();
}

class _FlowPlanesScreenState extends State<FlowPlanesScreen> {
  List<Map<String, dynamic>> _planes = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final planes = await SuscripcionAdminService.planes();
      if (!mounted) return;
      setState(() {
        _planes = planes;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  void _avisar(String mensaje, {required bool esError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppColors.error : AppColors.success,
      ),
    );
  }

  int get _activos => _planes.where((p) => boolDe(p['activo'])).length;

  /// ¿Hay algún plan activo con precio 0? Sería vendible gratis por descuido.
  bool get _hayActivoSinPrecio => _planes.any(
    (p) => boolDe(p['activo']) && (decimalDe(p['precio']) ?? 0) <= 0,
  );

  Future<void> _editar(Map<String, dynamic>? plan) async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoPlan(plan: plan),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _alternarActivo(Map<String, dynamic> plan) async {
    final id = enteroDe(plan['id']);
    if (id == null) return;
    final activo = !boolDe(plan['activo']);

    try {
      await SuscripcionAdminService.guardarPlan(id: id, activo: activo);
      _avisar(activo ? 'Plan activado.' : 'Plan desactivado.', esError: false);
      await _cargar();
    } catch (e) {
      _avisar('$e', esError: true);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> plan) async {
    final id = enteroDe(plan['id']);
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Eliminar plan'),
            content: Text(
              'Se intentará borrar "${textoDe(plan['nombre'])}". Si alguna entidad ya '
              'lo compró, el servidor no lo borra: lo desactiva para no romper su '
              'historial.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    try {
      final res = await SuscripcionAdminService.eliminarPlan(id);
      // El servidor distingue "borrado" de "desactivado porque tenía compras" y
      // manda el motivo redactado; se muestra tal cual.
      final borrado = boolDe(res['eliminado'], porDefecto: true);
      _avisar(
        borrado
            ? 'Plan eliminado.'
            : textoDe(
                res['motivo'],
                porDefecto:
                    'El plan tenía compras: se desactivó en vez de borrarse.',
              ),
        esError: false,
      );
      await _cargar();
    } catch (e) {
      _avisar('$e', esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Planes de suscripción'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(null),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo plan'),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 44, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          if (_activos == 0)
            const _Aviso(
              color: AppColors.warning,
              icono: Icons.warning_amber_rounded,
              texto:
                  'No hay ningún plan activo. Los clientes no ven nada que '
                  'comprar en la app. Activa un plan o crea uno nuevo.',
            )
          else if (_hayActivoSinPrecio)
            const _Aviso(
              color: AppColors.error,
              icono: Icons.money_off,
              texto:
                  'Hay un plan activo con precio 0: se podría "comprar" gratis. '
                  'Ponle precio o desactívalo.',
            ),
          if (_planes.isEmpty)
            const TarjetaFlow(
              child: Text(
                'Todavía no hay planes. Crea el primero con el botón de abajo.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else
            ..._planes.map(
              (p) => _TarjetaPlan(
                plan: p,
                onEditar: () => _editar(p),
                onAlternar: () => _alternarActivo(p),
                onEliminar: () => _eliminar(p),
              ),
            ),
        ],
      ),
    );
  }
}

class _TarjetaPlan extends StatelessWidget {
  const _TarjetaPlan({
    required this.plan,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
  });

  final Map<String, dynamic> plan;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final activo = boolDe(plan['activo']);
    final dias = enteroDe(plan['duracion_dias']) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TarjetaFlow(
        borde:
            activo
                ? AppColors.divider
                : AppColors.warning.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    textoDe(plan['nombre'], porDefecto: 'Sin nombre'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (!activo)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'INACTIVO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                Switch(value: activo, onChanged: (_) => onAlternar()),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _Dato(
                  'Precio',
                  formatearMoneda(
                    decimalDe(plan['precio']),
                    textoDe(plan['moneda'], porDefecto: 'CUP'),
                  ),
                ),
                _Dato('Duración', '$dias días'),
                _Dato(
                  'Equivale a',
                  dias == 0 ? '—' : '${(dias / 30).toStringAsFixed(1)} mes(es)',
                ),
                _Dato('Código', textoDe(plan['codigo'], porDefecto: '—')),
                _Dato('Orden', enteroDe(plan['orden'])?.toString() ?? '0'),
              ],
            ),
            if (textoDe(plan['descripcion']).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                textoDe(plan['descripcion']),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onEditar,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onEliminar,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Eliminar'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Alta y edición de un plan.
///
/// El código es la clave estable del plan (`flow_mensual`): se avisa de que no
/// conviene cambiarlo en un plan ya vendido, aunque el servidor lo permita.
class _DialogoPlan extends StatefulWidget {
  const _DialogoPlan({this.plan});

  final Map<String, dynamic>? plan;

  @override
  State<_DialogoPlan> createState() => _DialogoPlanState();
}

class _DialogoPlanState extends State<_DialogoPlan> {
  late final TextEditingController _codigo;
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late final TextEditingController _dias;
  late final TextEditingController _precio;
  late final TextEditingController _orden;
  late bool _activo;
  bool _guardando = false;
  String? _error;

  bool get _esNuevo => widget.plan == null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan ?? const <String, dynamic>{};
    _codigo = TextEditingController(text: textoDe(p['codigo']));
    _nombre = TextEditingController(text: textoDe(p['nombre']));
    _descripcion = TextEditingController(text: textoDe(p['descripcion']));
    _dias = TextEditingController(
      text: '${enteroDe(p['duracion_dias']) ?? 30}',
    );
    _precio = TextEditingController(
      text: decimalDe(p['precio'])?.toStringAsFixed(2) ?? '0.00',
    );
    _orden = TextEditingController(text: '${enteroDe(p['orden']) ?? 0}');
    _activo = _esNuevo ? false : boolDe(p['activo']);
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _descripcion.dispose();
    _dias.dispose();
    _precio.dispose();
    _orden.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final codigo = _codigo.text.trim();
    final nombre = _nombre.text.trim();
    final dias = int.tryParse(_dias.text.trim()) ?? 0;
    final precio =
        double.tryParse(_precio.text.trim().replaceAll(',', '.')) ?? -1;
    final orden = int.tryParse(_orden.text.trim()) ?? 0;

    if (codigo.isEmpty || nombre.isEmpty) {
      setState(() => _error = 'Código y nombre son obligatorios.');
      return;
    }
    if (dias < 1 || dias > 3650) {
      setState(() => _error = 'La duración debe estar entre 1 y 3650 días.');
      return;
    }
    if (precio < 0) {
      setState(() => _error = 'El precio no puede ser negativo.');
      return;
    }
    // Un plan activo y gratis es casi siempre un descuido: se avisa, no se
    // bloquea, porque puede ser intencional (plan de cortesía).
    if (_activo && precio == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Plan activo con precio 0'),
              content: const Text(
                'Se podrá "comprar" sin pagar nada. ¿Seguro que es un plan de '
                'cortesía?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Revisar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Sí, activar'),
                ),
              ],
            ),
      );
      if (ok != true) return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await SuscripcionAdminService.guardarPlan(
        id: enteroDe(widget.plan?['id']),
        codigo: codigo,
        nombre: nombre,
        descripcion: _descripcion.text.trim(),
        duracionDias: dias,
        precio: precio,
        moneda: textoDe(widget.plan?['moneda'], porDefecto: 'CUP'),
        orden: orden,
        activo: _activo,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esNuevo ? 'Nuevo plan' : 'Editar plan'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _codigo,
                enabled: _esNuevo,
                decoration: InputDecoration(
                  labelText: 'Código *',
                  helperText:
                      _esNuevo
                          ? 'Identificador estable, p. ej. flow_mensual'
                          : 'No se cambia en un plan ya vendido',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nombre,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descripcion,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dias,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Días *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _precio,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _orden,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Orden',
                        helperText: 'Menor = primero',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Activo',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Visible para los clientes',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _activo,
                      onChanged: (v) => setState(() => _activo = v),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          child:
              _guardando
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.color, required this.icono, required this.texto});

  final Color color;
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TarjetaFlow(
        color: color.withValues(alpha: 0.08),
        borde: color.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
