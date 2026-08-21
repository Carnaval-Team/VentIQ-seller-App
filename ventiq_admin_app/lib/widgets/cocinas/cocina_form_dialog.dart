import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/cocina.dart';
import '../../services/cocina_service.dart';

/// Diálogos del módulo de cocinas: crear, editar y eliminar.
///
/// Sigue el patrón de `TpvDetailsDialog`: métodos estáticos que muestran un
/// diálogo y llaman a `onSuccess` cuando la operación termina bien.
class CocinaFormDialog {
  /// Crear una cocina nueva.
  ///
  /// Ofrece dos vías: crear un almacén nuevo (lo normal) o convertir uno que ya
  /// existe. Los almacenes que abastecen a un TPV no se ofrecen: el backend los
  /// rechaza porque mezclarían barra y cocina.
  static Future<void> mostrarCrear({
    required BuildContext context,
    required VoidCallback onSuccess,
  }) async {
    final almacenes = await _cargarConvertibles(context);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _CocinaFormSheet(
        almacenesConvertibles: almacenes,
        onSuccess: onSuccess,
      ),
    );
  }

  /// Editar una cocina existente. No permite cambiar de almacén.
  static Future<void> mostrarEditar({
    required BuildContext context,
    required Cocina cocina,
    required VoidCallback onSuccess,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _CocinaFormSheet(
        cocina: cocina,
        almacenesConvertibles: const [],
        onSuccess: onSuccess,
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> _cargarConvertibles(
    BuildContext context,
  ) async {
    try {
      return await CocinaService.listarAlmacenesConvertibles();
    } catch (_) {
      // Si falla, se sigue permitiendo crear un almacén nuevo.
      return const [];
    }
  }

  /// Confirmación de borrado.
  ///
  /// Si la cocina tiene platos asignados, el backend responde
  /// `COCINA_CON_PRODUCTOS`; entonces se vuelve a preguntar ofreciendo liberar
  /// esos platos. Nunca se fuerza sin avisar.
  static Future<void> mostrarEliminar({
    required BuildContext context,
    required Cocina cocina,
    required VoidCallback onSuccess,
  }) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            const SizedBox(width: 8),
            const Expanded(child: Text('Eliminar cocina')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Eliminar la cocina "${cocina.denominacion}"?'),
            const SizedBox(height: 12),
            _AvisoInfo(
              icono: Icons.inventory_2_outlined,
              texto:
                  'El almacén "${cocina.almacen}" y su inventario se conservan. '
                  'Solo se desliga de la cocina.',
            ),
            if (cocina.tpvs.isNotEmpty) ...[
              const SizedBox(height: 8),
              _AvisoInfo(
                icono: Icons.link_off,
                texto:
                    'Se desligará de ${cocina.tpvs.length} '
                    '${cocina.tpvs.length == 1 ? "TPV" : "TPVs"}.',
              ),
            ],
          ],
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
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !context.mounted) return;

    try {
      await CocinaService.eliminarCocina(idCocina: cocina.id);
      if (!context.mounted) return;
      _snack(context, 'Cocina eliminada', AppColors.success);
      onSuccess();
    } on CocinaException catch (e) {
      if (!context.mounted) return;

      // Caso esperado: tiene platos asignados. Se pregunta antes de forzar.
      if (e.codigo == 'COCINA_CON_PRODUCTOS') {
        final forzar = await _confirmarLiberarProductos(
          context,
          cocina,
          e.productosBloqueando,
        );
        if (forzar != true || !context.mounted) return;

        try {
          final r = await CocinaService.eliminarCocina(
            idCocina: cocina.id,
            forzar: true,
          );
          if (!context.mounted) return;
          final liberados = (r['productos_liberados'] as num?)?.toInt() ?? 0;
          _snack(
            context,
            'Cocina eliminada. $liberados plato(s) quedaron sin cocina.',
            AppColors.success,
          );
          onSuccess();
        } on CocinaException catch (e2) {
          if (context.mounted) _snack(context, e2.mensaje, AppColors.error);
        }
        return;
      }

      _snack(context, e.mensaje, AppColors.error);
    }
  }

  static Future<bool?> _confirmarLiberarProductos(
    BuildContext context,
    Cocina cocina,
    int cantidad,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('La cocina tiene platos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${cocina.denominacion}" tiene $cantidad '
              '${cantidad == 1 ? "plato asignado" : "platos asignados"}.',
            ),
            const SizedBox(height: 12),
            _AvisoInfo(
              icono: Icons.info_outline,
              color: AppColors.warning,
              texto:
                  'Si continúas, esos platos quedarán sin cocina y dejarán de '
                  'aparecer en los TPVs hasta que les asignes otra.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('Liberar y eliminar'),
          ),
        ],
      ),
    );
  }

  static void _snack(BuildContext context, String texto, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: color),
    );
  }
}

/// Formulario de alta/edición. Se usa para ambos casos: si recibe [cocina]
/// edita, si no crea.
class _CocinaFormSheet extends StatefulWidget {
  const _CocinaFormSheet({
    this.cocina,
    required this.almacenesConvertibles,
    required this.onSuccess,
  });

  final Cocina? cocina;
  final List<Map<String, dynamic>> almacenesConvertibles;
  final VoidCallback onSuccess;

  @override
  State<_CocinaFormSheet> createState() => _CocinaFormSheetState();
}

class _CocinaFormSheetState extends State<_CocinaFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late final TextEditingController _impresora;
  late final TextEditingController _orden;

  /// null = crear almacén nuevo; distinto de null = convertir ese almacén.
  int? _idAlmacenExistente;
  bool _activa = true;
  bool _guardando = false;

  bool get _esEdicion => widget.cocina != null;

  @override
  void initState() {
    super.initState();
    final c = widget.cocina;
    _nombre = TextEditingController(text: c?.denominacion ?? '');
    _descripcion = TextEditingController(text: c?.descripcion ?? '');
    _impresora = TextEditingController(text: c?.impresora ?? '');
    _orden = TextEditingController(text: (c?.orden ?? 0).toString());
    _activa = c?.activa ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _impresora.dispose();
    _orden.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _guardando = true);
    try {
      final orden = int.tryParse(_orden.text.trim()) ?? 0;

      if (_esEdicion) {
        await CocinaService.actualizarCocina(
          idCocina: widget.cocina!.id,
          denominacion: _nombre.text,
          descripcion: _descripcion.text,
          impresora: _impresora.text,
          orden: orden,
          activa: _activa,
        );
      } else {
        await CocinaService.crearCocina(
          denominacion: _nombre.text,
          descripcion: _descripcion.text.isEmpty ? null : _descripcion.text,
          impresora: _impresora.text.isEmpty ? null : _impresora.text,
          orden: orden,
          idAlmacenExistente: _idAlmacenExistente,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_esEdicion ? 'Cocina actualizada' : 'Cocina creada'),
          backgroundColor: AppColors.success,
        ),
      );
      widget.onSuccess();
    } on CocinaException catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error inesperado: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      title: _Cabecera(
        titulo: _esEdicion ? 'Editar cocina' : 'Nueva cocina',
        subtitulo: _esEdicion
            ? widget.cocina!.almacen
            : 'Se creará como almacén propio',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                TextFormField(
                  controller: _nombre,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la cocina *',
                    hintText: 'Cocina caliente, Pizzería, Barra fría...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.soup_kitchen_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Escribe un nombre'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descripcion,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 14),

                // Al crear: elegir si se crea almacén nuevo o se convierte uno.
                if (!_esEdicion && widget.almacenesConvertibles.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    initialValue: _idAlmacenExistente,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Almacén de la cocina',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.warehouse_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Crear un almacén nuevo'),
                      ),
                      ...widget.almacenesConvertibles.map((a) {
                        return DropdownMenuItem<int?>(
                          value: (a['id'] as num).toInt(),
                          child: Text(
                            'Usar "${a['denominacion']}"',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (v) => setState(() => _idAlmacenExistente = v),
                  ),
                  const SizedBox(height: 14),
                ],

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _impresora,
                        decoration: const InputDecoration(
                          labelText: 'Impresora',
                          hintText: 'Opcional',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.print_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _orden,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Orden',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_esEdicion) ...[
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _activa,
                    activeThumbColor: AppColors.success,
                    title: const Text('Cocina activa'),
                    subtitle: Text(
                      _activa
                          ? 'Recibe comandas de sus TPVs'
                          : 'No recibe comandas aunque esté ligada',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onChanged: (v) => setState(() => _activa = v),
                  ),
                ],

                if (!_esEdicion) ...[
                  const SizedBox(height: 10),
                  _AvisoInfo(
                    icono: Icons.lightbulb_outline,
                    texto: _idAlmacenExistente == null
                        ? 'Se creará un almacén con una ubicación inicial para '
                              'guardar la materia prima de esta cocina.'
                        : 'Ese almacén se marcará como cocina. Su inventario '
                              'actual se conserva.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _guardando ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          icon: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(_esEdicion ? 'Guardar' : 'Crear cocina'),
        ),
      ],
    );
  }
}

/// Cabecera con gradiente, igual que las tarjetas de stats del admin.
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.soup_kitchen,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitulo,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nota informativa con icono, para explicar consecuencias sin alarmar.
class _AvisoInfo extends StatelessWidget {
  const _AvisoInfo({required this.icono, required this.texto, this.color});

  final IconData icono;
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.info;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
