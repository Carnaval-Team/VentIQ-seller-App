import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../models/tipo_actividad.dart';
import '../services/categoria_admin_service.dart';
import '../widgets/app_drawer.dart';

/// Gestión de la taxonomía de servicios de Inventtia Flow.
///
/// Dos niveles (migración `47_categorias_reales_subcategorias.sql`):
/// * **Categoría**: lo que el Home del cliente pinta como riel de filtros.
/// * **Subcategoría**: hija de una categoría; el Home la ofrece en una segunda
///   fila de chips y el catálogo la muestra como "Categoría › Subcategoría".
///
/// Un servicio se asigna a una hoja: la categoría sin subcategoría, o una de sus
/// subcategorías. Desde aquí el superadmin gobierna las dos cosas para TODAS las
/// entidades: crear, renombrar, reordenar, activar/desactivar y borrar.
class FlowCategoriasScreen extends StatefulWidget {
  const FlowCategoriasScreen({super.key});

  @override
  State<FlowCategoriasScreen> createState() => _FlowCategoriasScreenState();
}

class _FlowCategoriasScreenState extends State<FlowCategoriasScreen> {
  Taxonomia _taxonomia = Taxonomia.vacia;
  bool _cargando = true;
  bool _error = false;
  String? _mensajeError;

  /// Categorías abiertas, para ver y gestionar sus subcategorías.
  final Set<int> _expandidas = <int>{};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
      _mensajeError = null;
    });
    try {
      final taxonomia = await CategoriaAdminService.taxonomia();
      if (!mounted) return;
      setState(() {
        _taxonomia = taxonomia;
        _cargando = false;
        _expandidas.removeWhere(
          (id) => !_taxonomia.todas.any((t) => t.id == id),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
        _mensajeError = _mensajeErrorDe(e);
      });
    }
  }

  String _mensajeErrorDe(Object e) {
    final t = e.toString();
    if (t.contains('PGRST202') || t.contains('Could not find the function')) {
      return 'Falta aplicar la migración 47_categorias_reales_subcategorias.sql '
          'en este proyecto de Supabase.';
    }
    if (t.contains('42P01') || t.contains('does not exist')) {
      return 'La tabla de categorías no existe todavía en el esquema flow.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  Future<void> _abrirFormulario({TipoActividad? tipo, int? idPadre}) async {
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
    final esSub = tipo?.esSubcategoria ?? idPadre != null;
    final que = esSub ? 'Subcategoría' : 'Categoría';
    _avisar(tipo == null ? '$que creada.' : '$que actualizada.');
  }

  Future<void> _alternar(TipoActividad tipo) async {
    final hijas = tipo.esSubcategoria
        ? const <TipoActividad>[]
        : _taxonomia.subcategoriasDe(tipo.id);
    try {
      await CategoriaAdminService.alternar(id: tipo.id, activo: !tipo.activo);
      await _cargar();
      if (!mounted) return;
      if (tipo.activo) {
        _avisar(
          hijas.isEmpty
              ? '«${tipo.nombre}» desactivada: desaparece del Home del cliente.'
              : '«${tipo.nombre}» y sus ${hijas.length} subcategorías '
                    'desactivadas: desaparecen del Home del cliente.',
        );
      } else {
        _avisar('«${tipo.nombre}» activada.');
      }
    } catch (e) {
      if (mounted) _avisar(_mensajeErrorDe(e), error: true);
    }
  }

  Future<void> _eliminar(TipoActividad tipo) async {
    final esSub = tipo.esSubcategoria;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(esSub ? 'Eliminar subcategoría' : 'Eliminar categoría'),
        content: Text(
          esSub
              ? '¿Eliminar «${tipo.nombre}»? No se puede deshacer. Si algún '
                    'servicio la usa, el servidor rechazará la operación: '
                    'reasígnalo antes.'
              : '¿Eliminar «${tipo.nombre}»? No se puede deshacer. Si algún '
                    'servicio la usa o todavía tiene subcategorías, el servidor '
                    'rechazará la operación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    try {
      await CategoriaAdminService.eliminar(id: tipo.id);
      await _cargar();
      if (mounted) {
        _avisar(esSub ? 'Subcategoría eliminada.' : 'Categoría eliminada.');
      }
    } catch (e) {
      if (mounted) _avisar(_mensajeErrorDe(e), error: true);
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? AppColors.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final categorias = _taxonomia.raices;
    final totalSub = _taxonomia.todas.where((t) => t.esSubcategoria).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Categorías Flow'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
          ),
        ],
      ),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva categoría'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _cargar,
        child: _cargando && _taxonomia.estaVacia
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _ResumenCard(
                    categorias: categorias.length,
                    subcategorias: totalSub,
                    activas: _taxonomia.todas.where((t) => t.activo).length,
                  ),
                  if (_error) ...[
                    const SizedBox(height: 12),
                    _ErrorCard(
                      mensaje: _mensajeError ?? 'No se pudieron leer.',
                      onReintentar: _cargar,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (categorias.isEmpty && !_error)
                    const _VacioCard()
                  else
                    ...categorias.map(
                      (categoria) => _CategoriaCard(
                        categoria: categoria,
                        subcategorias: _taxonomia.subcategoriasDe(categoria.id),
                        expandida: _expandidas.contains(categoria.id),
                        onToggle: () => setState(() {
                          if (!_expandidas.remove(categoria.id)) {
                            _expandidas.add(categoria.id);
                          }
                        }),
                        onEditar: () => _abrirFormulario(tipo: categoria),
                        onAlternar: () => _alternar(categoria),
                        onEliminar: () => _eliminar(categoria),
                        onNuevaSubcategoria: () =>
                            _abrirFormulario(idPadre: categoria.id),
                        onEditarSub: (s) => _abrirFormulario(tipo: s),
                        onAlternarSub: (s) => _alternar(s),
                        onEliminarSub: (s) => _eliminar(s),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ResumenCard extends StatelessWidget {
  const _ResumenCard({
    required this.categorias,
    required this.subcategorias,
    required this.activas,
  });

  final int categorias;
  final int subcategorias;
  final int activas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_tree_outlined, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Categorías y subcategorías del Home',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Las categorías activas son el riel de filtros del Home del cliente; '
            'al tocar una se muestran sus subcategorías como chips. Un servicio '
            'puede quedar en la categoría o en una de sus subcategorías. Al '
            'desactivar una categoría se desactivan también sus subcategorías, '
            'pero los servicios siguen publicados.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(texto: '$categorias categorías'),
              _Pill(texto: '$subcategorias subcategorías'),
              _Pill(texto: '$activas activas'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final Future<void> Function() onReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: AppColors.error, size: 20),
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
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
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
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.category_outlined,
            size: 38,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: 10),
          Text(
            'Todavía no hay categorías',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text(
            'Crea la primera para que los servicios de todas las entidades '
            'puedan clasificarse.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CategoriaCard extends StatelessWidget {
  const _CategoriaCard({
    required this.categoria,
    required this.subcategorias,
    required this.expandida,
    required this.onToggle,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
    required this.onNuevaSubcategoria,
    required this.onEditarSub,
    required this.onAlternarSub,
    required this.onEliminarSub,
  });

  final TipoActividad categoria;
  final List<TipoActividad> subcategorias;
  final bool expandida;
  final VoidCallback onToggle;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;
  final VoidCallback onNuevaSubcategoria;
  final void Function(TipoActividad) onEditarSub;
  final void Function(TipoActividad) onAlternarSub;
  final void Function(TipoActividad) onEliminarSub;

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
              ? AppColors.divider
              : AppColors.textSecondary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: onToggle,
                  tooltip: expandida
                      ? 'Ocultar subcategorías'
                      : 'Ver subcategorías',
                  icon: Icon(
                    expandida
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: AppColors.textSecondary,
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
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
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
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: categoria.activo,
                  activeTrackColor: AppColors.primary,
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
                          color: AppColors.error,
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
              padding: const EdgeInsets.fromLTRB(14, 4, 6, 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                border: const Border(top: BorderSide(color: AppColors.divider)),
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
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    )
                  else
                    ...subcategorias.map(
                      (sub) => _SubcategoriaTile(
                        subcategoria: sub,
                        onEditar: () => onEditarSub(sub),
                        onAlternar: () => onAlternarSub(sub),
                        onEliminar: () => onEliminarSub(sub),
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
  const _SubcategoriaTile({
    required this.subcategoria,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
  });

  final TipoActividad subcategoria;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 17,
            color: AppColors.textSecondary.withValues(alpha: 0.7),
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
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
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
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: subcategoria.activo,
            activeTrackColor: AppColors.primary,
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
                    color: AppColors.error,
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
        color: AppColors.textSecondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'INACTIVA',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Formulario de alta/edición de categoría o subcategoría.
class _TipoActividadSheet extends StatefulWidget {
  const _TipoActividadSheet({this.tipo, this.idPadre});

  final TipoActividad? tipo;

  /// Categoría padre al crear una subcategoría. Al editar se usa la del propio
  /// nodo: es la que el RPC necesita para no cambiar de nivel.
  final int? idPadre;

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
  bool get _esSub => widget.tipo?.esSubcategoria ?? widget.idPadre != null;
  int? get _idPadre => widget.tipo?.idPadre ?? widget.idPadre;
  String get _que => _esSub ? 'subcategoría' : 'categoría';

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.tipo?.nombre ?? '');
    _codigo = TextEditingController(text: widget.tipo?.codigo ?? '');
    _orden = TextEditingController(text: '${widget.tipo?.orden ?? 0}');
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
    setState(() => _guardando = true);
    try {
      await CategoriaAdminService.guardar(
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
            backgroundColor: AppColors.error,
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
        : (_esSub ? 'Nueva subcategoría' : 'Nueva categoría');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + insets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _esSub
                    ? 'Segundo nivel dentro de la categoría. El Home del cliente '
                          'la ofrece como chip al tocar la categoría.'
                    : 'Es el filtro principal del Home del cliente.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
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
                  hintText: _esSub
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
                      ? 'El código no se puede cambiar: ya viaja en las reservas '
                            'y en los RPC del catálogo.'
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
                activeTrackColor: AppColors.primary,
                onChanged: (v) => setState(() => _activo = v),
                title: const Text('Activa'),
                subtitle: Text(
                  _esSub
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
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_esEdicion ? 'Guardar cambios' : 'Crear $_que'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
