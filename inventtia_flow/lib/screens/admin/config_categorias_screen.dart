import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/tipo_actividad_service.dart';

/// Gestión de la taxonomía de servicios (`flow.nom_tipo_actividad_servicio`).
///
/// Son **dos niveles** (migración `47_categorias_reales_subcategorias.sql`):
/// * **Categoría**: la raíz. Es lo que el Home pinta como filtro principal.
/// * **Subcategoría**: hija de una categoría. El Home la ofrece en una segunda
///   fila de chips y el catálogo la muestra como "Categoría › Subcategoría".
///
/// Un servicio se asigna a una **hoja**: o a la categoría sin subcategoría, o a
/// una de sus subcategorías. Aquí se gestionan las dos cosas: crear/editar/
/// activar/eliminar categorías, y dentro de cada una sus subcategorías.
///
/// La escritura va por RPC (la tabla no se toca a mano): el servidor valida el
/// código, el máximo de dos niveles y que no se borre algo con servicios o hijas.
class ConfigCategoriasScreen extends StatefulWidget {
  const ConfigCategoriasScreen({super.key});

  @override
  State<ConfigCategoriasScreen> createState() => _ConfigCategoriasScreenState();
}

class _ConfigCategoriasScreenState extends State<ConfigCategoriasScreen> {
  Taxonomia _taxonomia = Taxonomia.vacia;
  bool _cargando = true;
  String? _error;

  /// Categorías abiertas en el acordeón, para ver y gestionar sus subcategorías.
  final Set<int> _expandidas = <int>{};

  /// `true` cuando los RPC de escritura todavía no existen (migración sin
  /// aplicar). La lectura funciona igual, así que se avisa en vez de romper.
  bool _migracionPendiente = false;

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
      // Sin `soloActivos`: aquí hay que ver también lo apagado para reactivarlo.
      final taxonomia = await TipoActividadService.taxonomia();
      if (!mounted) return;
      setState(() {
        _taxonomia = taxonomia;
        _cargando = false;
        // Si una categoría abierta desapareció, se deja de recordar.
        _expandidas.removeWhere(
          (id) => !_taxonomia.todas.any((t) => t.id == id),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos leer las categorías: $e';
        _cargando = false;
      });
    }
  }

  List<TipoActividad> get _categorias => _taxonomia.raices;

  /// Abre el formulario de alta/edición de una categoría o subcategoría.
  Future<void> _abrirFormulario({
    TipoActividad? tipo,
    int? idPadre,
  }) async {
    final esSubcategoria = tipo?.esSubcategoria ?? idPadre != null;
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TipoActividadSheet(tipo: tipo, idPadre: idPadre),
    );
    if (guardado != true || !mounted) return;
    await _cargar();
    if (!mounted) return;
    final que = esSubcategoria ? 'Subcategoría' : 'Categoría';
    _avisar(tipo == null ? '$que creada.' : '$que actualizada.');
  }

  Future<void> _alternar(TipoActividad tipo) async {
    if (AuthService.currentUserId == null) return;
    final hijas = tipo.esSubcategoria
        ? const <TipoActividad>[]
        : _taxonomia.subcategoriasDe(tipo.id);
    try {
      await TipoActividadService.alternar(id: tipo.id, activo: !tipo.activo);
      await _cargar();
      if (!mounted) return;
      if (tipo.activo) {
        // Apagar una categoría apaga sus subcategorías (lo hace el RPC): se dice
        // para que no sorprenda verlas apagadas después.
        _avisar(
          hijas.isEmpty
              ? '${tipo.nombre} desactivada: ya no aparece en el Home.'
              : '${tipo.nombre} y sus ${hijas.length} subcategorías '
                    'desactivadas: ya no aparecen en el Home.',
        );
      } else {
        _avisar('${tipo.nombre} activada.');
      }
    } catch (e) {
      _marcarMigracionSiAplica(e);
      if (mounted) _avisar('No se pudo cambiar el estado: $e', error: true);
    }
  }

  Future<void> _eliminar(TipoActividad tipo) async {
    if (AuthService.currentUserId == null) return;
    final esSubcategoria = tipo.esSubcategoria;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(esSubcategoria ? 'Eliminar subcategoría' : 'Eliminar categoría'),
        content: Text(
          esSubcategoria
              ? '¿Eliminar «${tipo.nombre}»? No se puede deshacer. Si algún '
                    'servicio la usa, la operación se rechazará: reasígnalo '
                    'antes.'
              : '¿Eliminar «${tipo.nombre}»? No se puede deshacer. Si algún '
                    'servicio la usa o todavía tiene subcategorías, la operación '
                    'se rechazará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    try {
      await TipoActividadService.eliminar(id: tipo.id);
      await _cargar();
      if (mounted) {
        _avisar(esSubcategoria ? 'Subcategoría eliminada.' : 'Categoría eliminada.');
      }
    } catch (e) {
      _marcarMigracionSiAplica(e);
      if (mounted) _avisar('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _marcarMigracionSiAplica(Object error) {
    final texto = error.toString();
    final esFaltaDeFuncion =
        texto.contains('PGRST202') ||
        texto.contains('Could not find the function') ||
        texto.contains('admin_guardar_tipo_actividad') ||
        texto.contains('admin_eliminar_tipo_actividad') ||
        texto.contains('admin_alternar_tipo_actividad') ||
        texto.contains('id_padre');
    if (esFaltaDeFuncion && mounted) {
      setState(() => _migracionPendiente = true);
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: error ? AppTheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final categorias = _categorias;
    final totalSubcategorias = _taxonomia.todas
        .where((t) => t.esSubcategoria)
        .length;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Categorías y subcategorías')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva categoría'),
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _cargar,
        child: _cargando && _taxonomia.estaVacia
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  const _ExplicacionCard(),
                  if (_migracionPendiente) ...[
                    const SizedBox(height: 12),
                    const _AvisoMigracionCard(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorCard(mensaje: _error!, onReintentar: _cargar),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    categorias.length == 1
                        ? '1 categoría · $totalSubcategorias subcategorías'
                        : '${categorias.length} categorías · '
                              '$totalSubcategorias subcategorías',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (categorias.isEmpty && _error == null)
                    const _VacioCard()
                  else
                    ...categorias.map(
                      (categoria) => _CategoriaCard(
                        categoria: categoria,
                        subcategorias: _taxonomia.subcategoriasDe(categoria.id),
                        expandida: _expandidas.contains(categoria.id),
                        onToggleExpandir: () => setState(() {
                          if (!_expandidas.remove(categoria.id)) {
                            _expandidas.add(categoria.id);
                          }
                        }),
                        onEditar: () => _abrirFormulario(tipo: categoria),
                        onAlternar: () => _alternar(categoria),
                        onEliminar: () => _eliminar(categoria),
                        onNuevaSubcategoria: () =>
                            _abrirFormulario(idPadre: categoria.id),
                        onEditarSubcategoria: (sub) =>
                            _abrirFormulario(tipo: sub),
                        onAlternarSubcategoria: (sub) => _alternar(sub),
                        onEliminarSubcategoria: (sub) => _eliminar(sub),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ExplicacionCard extends StatelessWidget {
  const _ExplicacionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cómo se usan',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cada servicio pertenece a una categoría y, si quieres, a una '
                  'de sus subcategorías. Las categorías activas son el riel de '
                  'filtros del Home; al tocar una, el cliente ve sus '
                  'subcategorías como chips debajo. Si desactivas una categoría '
                  'se desactivan también sus subcategorías, y sus servicios '
                  'siguen publicados pero dejan de aparecer bajo ese filtro.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoMigracionCard extends StatelessWidget {
  const _AvisoMigracionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'La lectura funciona, pero guardar, activar y eliminar todavía no: '
              'falta aplicar en este proyecto de Supabase las migraciones '
              '`22_categorias_marketplace.sql` y '
              '`47_categorias_reales_subcategorias.sql`. Hasta entonces esta '
              'pantalla es de solo consulta.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _ErrorCard({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: AppTheme.error, size: 20),
              SizedBox(width: 8),
              Text(
                'No se pudo leer',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mensaje,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _VacioCard extends StatelessWidget {
  const _VacioCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.category_outlined,
            size: 38,
            color: AppTheme.textSecondary,
          ),
          SizedBox(height: 10),
          Text(
            'Todavía no hay categorías',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text(
            'Crea la primera para que los servicios puedan clasificarse.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de una categoría con su lista desplegable de subcategorías.
class _CategoriaCard extends StatelessWidget {
  final TipoActividad categoria;
  final List<TipoActividad> subcategorias;
  final bool expandida;
  final VoidCallback onToggleExpandir;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;
  final VoidCallback onNuevaSubcategoria;
  final void Function(TipoActividad) onEditarSubcategoria;
  final void Function(TipoActividad) onAlternarSubcategoria;
  final void Function(TipoActividad) onEliminarSubcategoria;

  const _CategoriaCard({
    required this.categoria,
    required this.subcategorias,
    required this.expandida,
    required this.onToggleExpandir,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
    required this.onNuevaSubcategoria,
    required this.onEditarSubcategoria,
    required this.onAlternarSubcategoria,
    required this.onEliminarSubcategoria,
  });

  @override
  Widget build(BuildContext context) {
    final activas = subcategorias.where((s) => s.activo).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: categoria.activo
              ? AppTheme.border
              : AppTheme.textSecondary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: Row(
              children: [
                // Desplegar solo tiene sentido si hay hijas, pero se deja también
                // sin ellas para poder añadir la primera con un toque.
                IconButton(
                  onPressed: onToggleExpandir,
                  tooltip: expandida ? 'Ocultar subcategorías' : 'Ver subcategorías',
                  icon: Icon(
                    expandida
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: AppTheme.textSecondary,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              categoria.nombre,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: categoria.activo
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          if (!categoria.activo) ...[
                            const SizedBox(width: 7),
                            const _EtiquetaInactiva(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subcategorias.isEmpty
                            ? '${categoria.codigo} · sin subcategorías'
                            : '${categoria.codigo} · $activas de '
                                  '${subcategorias.length} subcategorías activas',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: categoria.activo,
                  activeTrackColor: AppTheme.primary,
                  onChanged: (_) => onAlternar(),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (valor) {
                    if (valor == 'editar') onEditar();
                    if (valor == 'nueva_sub') onNuevaSubcategoria();
                    if (valor == 'eliminar') onEliminar();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'editar',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined, size: 19),
                        title: Text('Editar categoría'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'nueva_sub',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.add_rounded, size: 19),
                        title: Text('Nueva subcategoría'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'eliminar',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: AppTheme.error,
                        ),
                        title: Text('Eliminar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (expandida)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 4, 8, 6),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                border: const Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subcategorias.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Esta categoría no tiene subcategorías: sus servicios se '
                        'clasifican solo por ella.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    )
                  else
                    ...subcategorias.map(
                      (sub) => _SubcategoriaTile(
                        subcategoria: sub,
                        onEditar: () => onEditarSubcategoria(sub),
                        onAlternar: () => onAlternarSubcategoria(sub),
                        onEliminar: () => onEliminarSubcategoria(sub),
                      ),
                    ),
                  TextButton.icon(
                    onPressed: onNuevaSubcategoria,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Añadir subcategoría'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SubcategoriaTile extends StatelessWidget {
  final TipoActividad subcategoria;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;

  const _SubcategoriaTile({
    required this.subcategoria,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 17,
            color: AppTheme.textSecondary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        subcategoria.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: subcategoria.activo
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    if (!subcategoria.activo) ...[
                      const SizedBox(width: 6),
                      const _EtiquetaInactiva(),
                    ],
                  ],
                ),
                Text(
                  subcategoria.codigo,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: subcategoria.activo,
            activeTrackColor: AppTheme.primary,
            onChanged: (_) => onAlternar(),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            onSelected: (valor) {
              if (valor == 'editar') onEditar();
              if (valor == 'eliminar') onEliminar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'editar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 19),
                  title: Text('Editar'),
                ),
              ),
              PopupMenuItem(
                value: 'eliminar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: AppTheme.error,
                  ),
                  title: Text('Eliminar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EtiquetaInactiva extends StatelessWidget {
  const _EtiquetaInactiva();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.textSecondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'INACTIVA',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

/// Formulario de alta/edición de categoría **o** subcategoría.
///
/// El código se propone desde el nombre y se puede ajustar, pero no se puede
/// cambiar al editar: es la clave que ya viaja en las reservas y en el RPC del
/// catálogo (por ejemplo `transporte_omnibus`).
class _TipoActividadSheet extends StatefulWidget {
  final TipoActividad? tipo;

  /// Categoría padre al **crear** una subcategoría. Al editar se usa la del
  /// propio nodo, que es la que el RPC necesita para no cambiar de nivel.
  final int? idPadre;

  const _TipoActividadSheet({this.tipo, this.idPadre});

  @override
  State<_TipoActividadSheet> createState() => _TipoActividadSheetState();
}

class _TipoActividadSheetState extends State<_TipoActividadSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _codigo;
  late final TextEditingController _orden;
  late bool _activo;
  bool _guardando = false;
  bool _codigoEditadoAMano = false;

  bool get _esEdicion => widget.tipo != null;

  bool get _esSubcategoria =>
      widget.tipo?.esSubcategoria ?? widget.idPadre != null;

  /// Padre efectivo: el del nodo editado o el de creación.
  int? get _idPadre => widget.tipo?.idPadre ?? widget.idPadre;

  String get _que => _esSubcategoria ? 'subcategoría' : 'categoría';

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.tipo?.nombre ?? '');
    _codigo = TextEditingController(text: widget.tipo?.codigo ?? '');
    _orden = TextEditingController(
      text: (widget.tipo?.orden ?? 0).toString(),
    );
    _activo = widget.tipo?.activo ?? true;
    _codigoEditadoAMano = _esEdicion;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
    _orden.dispose();
    super.dispose();
  }

  void _sugerirCodigo(String nombre) {
    if (_codigoEditadoAMano) return;
    _codigo.text = TipoActividad.codigoDesdeNombre(nombre);
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (AuthService.currentUserId == null) return;
    setState(() => _guardando = true);
    try {
      await TipoActividadService.guardar(
        id: widget.tipo?.id,
        nombre: _nombre.text.trim(),
        codigo: _codigo.text.trim(),
        activo: _activo,
        idPadre: _idPadre,
        orden: int.tryParse(_orden.text.trim()) ?? 0,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', '')),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final titulo = _esEdicion
        ? 'Editar $_que'
        : (_esSubcategoria ? 'Nueva subcategoría' : 'Nueva categoría');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + insets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _esSubcategoria
                  ? 'Segundo nivel dentro de la categoría. El cliente la verá '
                        'como un chip al tocar la categoría.'
                  : 'Aparecerá como filtro en el Home del cliente.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _sugerirCodigo,
              decoration: InputDecoration(
                labelText: 'Nombre visible',
                hintText: _esSubcategoria
                    ? 'Uñas / Manicure, Restaurantes…'
                    : 'Belleza, Gastronomía, Transporte…',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codigo,
              enabled: !_esEdicion,
              onChanged: (_) => _codigoEditadoAMano = true,
              decoration: InputDecoration(
                labelText: 'Código interno',
                helperText: _esEdicion
                    ? 'El código no se puede cambiar una vez creado.'
                    : 'Solo minúsculas, números y guion bajo.',
              ),
              validator: (v) {
                final codigo = (v ?? '').trim();
                if (codigo.isEmpty) return 'Escribe un código';
                if (!TipoActividad.codigoValido(codigo)) {
                  return 'Mínimo 3 caracteres: a-z, 0-9 o _';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _orden,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Orden',
                helperText: 'Menor número = aparece antes. Los empates se '
                    'ordenan por nombre.',
              ),
              validator: (v) {
                final texto = (v ?? '').trim();
                if (texto.isEmpty) return null;
                return int.tryParse(texto) == null
                    ? 'Solo números enteros'
                    : null;
              },
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _activo,
              activeTrackColor: AppTheme.primary,
              onChanged: (v) => setState(() => _activo = v),
              title: const Text('Activa'),
              subtitle: Text(
                _esSubcategoria
                    ? 'Solo las activas se ofrecen como chip en el Home.'
                    : 'Solo las activas se ofrecen como filtro en el Home. Al '
                          'desactivarla se desactivan sus subcategorías.',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _esEdicion ? 'Guardar cambios' : 'Crear $_que',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
