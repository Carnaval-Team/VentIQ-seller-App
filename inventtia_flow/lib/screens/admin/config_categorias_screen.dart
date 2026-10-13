import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/tipo_actividad_service.dart';

/// Gestión de categorías de servicio (`flow.nom_tipo_actividad_servicio`).
///
/// Es la taxonomía que el administrador asigna a cada servicio y la que el Home
/// del cliente pinta en su riel de categorías. Antes de esta pantalla, el
/// nomenclador solo se podía editar por SQL: existían únicamente `general` y
/// `transporte_omnibus`, así que el catálogo entero caía en una sola categoría.
class ConfigCategoriasScreen extends StatefulWidget {
  const ConfigCategoriasScreen({super.key});

  @override
  State<ConfigCategoriasScreen> createState() => _ConfigCategoriasScreenState();
}

class _ConfigCategoriasScreenState extends State<ConfigCategoriasScreen> {
  List<TipoActividad> _tipos = const [];
  bool _cargando = true;
  String? _error;

  /// `true` cuando el RPC de escritura todavía no existe en la base de datos
  /// (migración `22_categorias_marketplace.sql` sin aplicar). La lectura
  /// funciona igual, así que se avisa en vez de romper la pantalla.
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
      final tipos = await TipoActividadService.listar();
      if (!mounted) return;
      setState(() {
        _tipos = tipos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos leer las categorías: $e';
        _cargando = false;
      });
    }
  }

  Future<void> _abrirFormulario({TipoActividad? tipo}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TipoActividadSheet(tipo: tipo),
    );
    if (guardado != true || !mounted) return;
    await _cargar();
    if (mounted) {
      _avisar(tipo == null ? 'Categoría creada.' : 'Categoría actualizada.');
    }
  }

  Future<void> _alternarActivo(TipoActividad tipo) async {
    if (AuthService.currentUserId == null) return;
    try {
      await TipoActividadService.guardar(
        id: tipo.id,
        nombre: tipo.nombre,
        codigo: tipo.codigo,
        activo: !tipo.activo,
      );
      await _cargar();
      if (mounted) {
        _avisar(
          tipo.activo
              ? '${tipo.nombre} desactivada: ya no aparece en el Home.'
              : '${tipo.nombre} activada.',
        );
      }
    } catch (e) {
      _marcarMigracionSiAplica(e);
      if (mounted) _avisar('No se pudo cambiar el estado: $e', error: true);
    }
  }

  Future<void> _eliminar(TipoActividad tipo) async {
    if (AuthService.currentUserId == null) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Eliminar categoría'),
        content: Text(
          '¿Eliminar «${tipo.nombre}»? No se puede deshacer. Si algún servicio '
          'la usa, la operación se rechazará.',
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
      if (mounted) _avisar('Categoría eliminada.');
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
        texto.contains('admin_eliminar_tipo_actividad');
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
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Categorías')),
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
        child: _cargando && _tipos.isEmpty
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
                    _tipos.length == 1
                        ? '1 categoría'
                        : '${_tipos.length} categorías',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_tipos.isEmpty && _error == null)
                    const _VacioCard()
                  else
                    ..._tipos.map(
                      (tipo) => _TipoActividadTile(
                        tipo: tipo,
                        onEditar: () => _abrirFormulario(tipo: tipo),
                        onAlternar: () => _alternarActivo(tipo),
                        onEliminar: () => _eliminar(tipo),
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
                  'Cada servicio pertenece a una categoría. Las categorías '
                  'activas son las que el cliente ve como filtros en el Home; '
                  'si desactivas una, sus servicios siguen publicados pero dejan '
                  'de aparecer bajo ese filtro.',
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
              'La lectura funciona, pero guardar y eliminar todavía no: falta '
              'aplicar `22_categorias_marketplace.sql` en este proyecto de '
              'Supabase. Hasta entonces esta pantalla es de solo consulta.',
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

class _TipoActividadTile extends StatelessWidget {
  final TipoActividad tipo;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;

  const _TipoActividadTile({
    required this.tipo,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tipo.nombre,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: tipo.activo
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (!tipo.activo) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.textSecondary.withValues(
                              alpha: 0.12,
                            ),
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
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tipo.codigo,
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
              value: tipo.activo,
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
      ),
    );
  }
}

/// Formulario de alta/edición. El código se propone desde el nombre y se puede
/// ajustar, pero no se puede cambiar al editar: es la clave que ya viaja en las
/// reservas y en el RPC del catálogo.
class _TipoActividadSheet extends StatefulWidget {
  final TipoActividad? tipo;

  const _TipoActividadSheet({this.tipo});

  @override
  State<_TipoActividadSheet> createState() => _TipoActividadSheetState();
}

class _TipoActividadSheetState extends State<_TipoActividadSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _codigo;
  late bool _activo;
  bool _guardando = false;
  bool _codigoEditadoAMano = false;

  bool get _esEdicion => widget.tipo != null;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.tipo?.nombre ?? '');
    _codigo = TextEditingController(text: widget.tipo?.codigo ?? '');
    _activo = widget.tipo?.activo ?? true;
    _codigoEditadoAMano = _esEdicion;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + insets.bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _esEdicion ? 'Editar categoría' : 'Nueva categoría',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Aparecerá como filtro en el Home del cliente.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              onChanged: _sugerirCodigo,
              decoration: const InputDecoration(
                labelText: 'Nombre visible',
                hintText: 'Uñas, Cejas y Pestañas, Salud…',
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
                    ? 'El código no se puede cambiar una vez creada.'
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
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _activo,
              activeTrackColor: AppTheme.primary,
              onChanged: (v) => setState(() => _activo = v),
              title: const Text('Activa'),
              subtitle: const Text(
                'Solo las activas se ofrecen como filtro en el Home.',
                style: TextStyle(fontSize: 11.5),
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
                    : Text(_esEdicion ? 'Guardar cambios' : 'Crear categoría'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
