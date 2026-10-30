import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/versiones_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/suscripcion_ui.dart';
import '../widgets/versiones_ui.dart';

/// Versiones y changelogs de las 5 apps del ecosistema Inventtia.
///
/// El panel deja de depender de SQL a mano: desde aquí se publica la versión
/// (versión, build, versión mínima, obligatoria), el changelog que verá el
/// usuario en el móvil (lista de novedades) y la URL de descarga opcional.
///
/// La escritura va por los RPC de la migración 75; la lectura del historial usa
/// PostgREST sobre `public.app_versiones` para poder ver también las versiones
/// inactivas (documentado en [VersionesService]). La pantalla es tolerante: si
/// el servidor aún no tiene la migración, los campos nuevos llegan vacíos y se
/// muestra lo que haya.
class VersionesScreen extends StatefulWidget {
  const VersionesScreen({super.key});

  @override
  State<VersionesScreen> createState() => _VersionesScreenState();
}

class _VersionesScreenState extends State<VersionesScreen> {
  String _appId = appsEcosistema.first.id;
  List<Map<String, dynamic>> _versiones = const [];
  bool _cargando = true;
  String? _error;

  AppEcosistema get _app => appEcosistema(_appId);

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
      final versiones = await VersionesService.historial(_appId);
      if (!mounted) return;
      setState(() {
        _versiones = versiones;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e';
      });
    }
  }

  Future<void> _seleccionarApp(String appId) async {
    if (appId == _appId) return;
    setState(() {
      _appId = appId;
      _versiones = const [];
    });
    await _cargar();
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

  Future<void> _editar([Map<String, dynamic>? version]) async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoVersion(appInicial: _app, version: version),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _eliminar(Map<String, dynamic> version) async {
    final id = idDeVersion(version);
    if (id <= 0) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Eliminar versión'),
            content: Text(
              'Se eliminará la versión v${versionDe(version)} '
              '(build ${buildDeVersion(version)}) de ${_app.nombre}.\n\n'
              'Los usuarios que ya la tengan instalada no se ven afectados, '
              'pero dejará de ofrecerse la actualización.',
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
                  foregroundColor: Colors.white,
                ),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (confirmado != true) return;

    try {
      final res = await VersionesService.eliminar(id);
      final aviso = textoDe(res['aviso']).trim();
      _avisar(aviso.isEmpty ? 'Versión eliminada.' : aviso, esError: false);
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
        title: const Text('Versiones de las apps'),
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
        onPressed: () => _editar(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva versión'),
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

    final ultima = _versiones.isEmpty ? null : _versiones.first;
    final hayActiva = _versiones.any(activaDeVersion);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _SelectorApp(seleccionada: _appId, onSeleccionar: _seleccionarApp),
          const SizedBox(height: 14),
          if (ultima == null)
            _Vacio(app: _app, onCrear: () => _editar())
          else ...[
            ResumenUltimaVersion(
              version: ultima,
              app: _app,
              onEditar: () => _editar(ultima),
            ),
            const SizedBox(height: 12),
            if (novedadesDeVersion(ultima).isEmpty)
              const _Aviso(
                color: AppColors.warning,
                icono: Icons.notes_outlined,
                texto:
                    'La última versión no tiene novedades en el changelog: los '
                    'usuarios verán el aviso de actualización sin detalle de '
                    'cambios. Edítala para añadirlas.',
              ),
            if (!hayActiva)
              _Aviso(
                color: AppColors.warning,
                icono: Icons.visibility_off_outlined,
                texto:
                    'Ninguna versión de ${_app.nombre} está activa: la app no '
                    'está ofreciendo actualizaciones a sus usuarios.',
              ),
            const SizedBox(height: 4),
            _EncabezadoHistorial(
              total: _versiones.length,
              onRefrescar: _cargando ? null : _cargar,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _versiones.length; i++)
              TarjetaVersion(
                key: ValueKey('version-$_appId-${idDeVersion(_versiones[i])}'),
                version: _versiones[i],
                app: _app,
                expandida: i == 0,
                onEditar: () => _editar(_versiones[i]),
                onEliminar: () => _eliminar(_versiones[i]),
              ),
          ],
        ],
      ),
    );
  }
}

/// Selector de app del ecosistema (chips con icono y color de cada app).
class _SelectorApp extends StatelessWidget {
  const _SelectorApp({required this.seleccionada, required this.onSeleccionar});

  final String seleccionada;
  final ValueChanged<String> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'APP',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final app in appsEcosistema)
              ChoiceChip(
                avatar: Icon(
                  app.icono,
                  size: 17,
                  color: seleccionada == app.id ? Colors.white : app.color,
                ),
                label: Text(app.nombre),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      seleccionada == app.id
                          ? FontWeight.w700
                          : FontWeight.w500,
                  color:
                      seleccionada == app.id
                          ? Colors.white
                          : AppColors.textPrimary,
                ),
                selected: seleccionada == app.id,
                selectedColor: app.color,
                backgroundColor: AppColors.cardBackground,
                showCheckmark: false,
                side: BorderSide(
                  color: seleccionada == app.id ? app.color : AppColors.divider,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onSelected: (_) => onSeleccionar(app.id),
              ),
          ],
        ),
      ],
    );
  }
}

/// Cabecera del historial con el total de versiones y el refresco.
class _EncabezadoHistorial extends StatelessWidget {
  const _EncabezadoHistorial({required this.total, this.onRefrescar});

  final int total;
  final VoidCallback? onRefrescar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.history_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 7),
        const Text(
          'Historial',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$total versión(es)',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Actualizar historial',
          onPressed: onRefrescar,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
    );
  }
}

/// Estado vacío: la app todavía no tiene versiones publicadas.
class _Vacio extends StatelessWidget {
  const _Vacio({required this.app, required this.onCrear});

  final AppEcosistema app;
  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    return TarjetaFlow(
      child: Column(
        children: [
          IconoApp(app: app, tamano: 52),
          const SizedBox(height: 10),
          Text(
            '${app.nombre} todavía no tiene versiones publicadas.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Publica la primera versión con su changelog: la app la ofrecerá a '
            'sus usuarios como actualización.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onCrear,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Publicar la primera versión'),
          ),
        ],
      ),
    );
  }
}

// ── Editor de versión ────────────────────────────────────────────────────────

/// Alta y edición de una versión con su changelog.
///
/// Diálogo ancho en secciones (datos, changelog, publicación) con una **vista
/// previa móvil** al lado en pantallas anchas; en pantallas estrechas la vista
/// previa se abre con el botón "Ver como el usuario" de la cabecera.
class _DialogoVersion extends StatefulWidget {
  const _DialogoVersion({required this.appInicial, this.version});

  final AppEcosistema appInicial;
  final Map<String, dynamic>? version;

  @override
  State<_DialogoVersion> createState() => _DialogoVersionState();
}

class _DialogoVersionState extends State<_DialogoVersion> {
  static final RegExp _patronVersion = RegExp(r'^\d+(\.\d+){1,3}$');

  late final TextEditingController _version;
  late final TextEditingController _build;
  late final TextEditingController _versionMinima;
  late final TextEditingController _titulo;
  late final TextEditingController _url;
  late final List<_NovedadEditable> _novedades;

  late String _appId;
  late bool _obligatoria;
  late bool _activa;

  bool _guardando = false;
  String? _error;

  /// `version_minima` es NOT NULL en la tabla: mientras el superadmin no la
  /// escriba, se sugiere la misma versión que está teclando (lo habitual en una
  /// primera publicación). En cuanto la toca, deja de sincronizarse.
  bool _minimaTocada = false;

  bool get _esNueva => widget.version == null;

  AppEcosistema get _appActual => appEcosistema(_appId);

  @override
  void initState() {
    super.initState();
    final v = widget.version ?? const <String, dynamic>{};
    _appId = textoDe(v['app_name'], porDefecto: widget.appInicial.id);
    _version = TextEditingController(text: textoDe(v['version_actual']));
    _build = TextEditingController(
      text: enteroDe(v['build_number'])?.toString() ?? '',
    );
    _versionMinima = TextEditingController(text: textoDe(v['version_minima']));
    _minimaTocada = _versionMinima.text.trim().isNotEmpty;
    _titulo = TextEditingController(text: textoDe(v['titulo']));
    _url = TextEditingController(text: textoDe(v['url_descarga']));
    _obligatoria = obligatoriaDeVersion(v);
    _activa = _esNueva ? true : activaDeVersion(v);
    _novedades = [
      for (final novedad in novedadesDeVersion(v))
        _NovedadEditable.desde(novedad),
    ];
  }

  @override
  void dispose() {
    _version.dispose();
    _build.dispose();
    _versionMinima.dispose();
    _titulo.dispose();
    _url.dispose();
    for (final novedad in _novedades) {
      novedad.dispose();
    }
    super.dispose();
  }

  /// Novedades con título: las filas vacías se ignoran al guardar y previsualizar.
  List<NovedadVersion> _novedadesValidas() {
    return [
      for (final novedad in _novedades)
        if (novedad.titulo.text.trim().isNotEmpty) novedad.aNovedad(),
    ];
  }

  void _agregarNovedad() {
    setState(() => _novedades.add(_NovedadEditable.nueva()));
  }

  void _quitarNovedad(int indice) {
    setState(() {
      _novedades.removeAt(indice).dispose();
    });
  }

  Future<void> _abrirVistaPrevia() async {
    await showDialog<void>(
      context: context,
      builder:
          (_) => _DialogoVistaPrevia(
            app: _appActual,
            version: _version.text,
            buildNumber: int.tryParse(_build.text.trim()) ?? 1,
            titulo: _titulo.text,
            novedades: _novedadesValidas(),
            obligatoria: _obligatoria,
            versionMinima: _versionMinima.text.trim(),
            urlDescarga: _url.text.trim(),
            fecha:
                widget.version == null
                    ? null
                    : textoFechaVersion(widget.version!),
          ),
    );
  }

  void _alCambiarVersion(String valor) {
    if (!_minimaTocada) {
      _versionMinima.text = valor.trim();
      _versionMinima.selection = TextSelection.collapsed(
        offset: _versionMinima.text.length,
      );
    }
    setState(() {});
  }

  Future<void> _guardar() async {
    final version = _version.text.trim();
    final build = int.tryParse(_build.text.trim()) ?? -1;
    final minima = _versionMinima.text.trim();
    final titulo = _titulo.text.trim();
    final url = _url.text.trim();

    if (version.isEmpty) {
      setState(() => _error = 'La versión es obligatoria (p. ej. 1.4.2).');
      return;
    }
    if (!_patronVersion.hasMatch(version)) {
      setState(
        () =>
            _error =
                'La versión debe tener el formato 1.2.3: solo números y puntos.',
      );
      return;
    }
    if (build < 1) {
      setState(
        () => _error = 'El número de build debe ser un entero mayor que 0.',
      );
      return;
    }
    if (minima.isEmpty) {
      setState(
        () =>
            _error =
                'La versión mínima es obligatoria: la columna no admite vacío. '
                'Si la actualización aplica a cualquier versión instalada, usa '
                '1.0.0.',
      );
      return;
    }
    if (!_patronVersion.hasMatch(minima)) {
      setState(() => _error = 'La versión mínima debe tener el formato 1.2.3.');
      return;
    }
    if (url.isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      setState(
        () =>
            _error = 'La URL de descarga debe empezar por http:// o https://.',
      );
      return;
    }
    for (final novedad in _novedades) {
      final tituloNovedad = novedad.titulo.text.trim();
      final descripcion = novedad.descripcion.text.trim();
      if (tituloNovedad.isEmpty && descripcion.isNotEmpty) {
        setState(
          () =>
              _error =
                  'Cada novedad con descripción necesita un título. Revisa la '
                  'lista del changelog.',
        );
        return;
      }
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final resultado = await VersionesService.guardar(
        id: enteroDe(widget.version?['id']),
        appName: _appActual.id,
        versionActual: version,
        buildNumber: build,
        versionMinima: minima,
        obligatoria: _obligatoria,
        titulo: titulo.isEmpty ? null : titulo,
        // Siempre se manda la lista: una lista vacía borra el changelog.
        novedades: _novedadesValidas(),
        // Cadena vacía quita la URL; null conservaría la anterior.
        urlDescarga: url.isEmpty ? '' : url,
        activa: _activa,
      );
      if (!mounted) return;

      final creado = boolDe(resultado['creado']);
      final id = enteroDe(resultado['id']);
      final mensajes = <String>[
        creado ? 'Versión publicada.' : 'Versión actualizada.',
        if (id != null) 'id $id',
      ];
      final aviso = textoDe(resultado['aviso']).trim();
      if (aviso.isNotEmpty) mensajes.add(aviso);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensajes.join(' · '))));
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
    final alto = MediaQuery.sizeOf(context).height;
    final ancho = MediaQuery.sizeOf(context).width;
    final mostrarPanelPrevia = ancho >= 1150;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1040,
          maxHeight: alto * 0.92 < 420 ? 420 : alto * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cabecera(mostrarPanelPrevia),
            Flexible(
              child:
                  mostrarPanelPrevia
                      ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                              child: _formulario(),
                            ),
                          ),
                          SizedBox(
                            width: 340,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(4, 12, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'VISTA PREVIA DEL USUARIO',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Center(child: _vistaPrevia()),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                      : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: _formulario(),
                      ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _guardando ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    child:
                        _guardando
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Text(
                              _esNueva ? 'Publicar versión' : 'Guardar cambios',
                            ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaPrevia() {
    return VistaPreviaMovil(
      app: _appActual,
      version: _version.text,
      buildNumber: int.tryParse(_build.text.trim()) ?? 1,
      titulo: _titulo.text,
      novedades: _novedadesValidas(),
      obligatoria: _obligatoria,
      versionMinima: _versionMinima.text.trim(),
      urlDescarga: _url.text.trim(),
      fecha: widget.version == null ? null : textoFechaVersion(widget.version!),
    );
  }

  Widget _cabecera(bool mostrarPanelPrevia) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _esNueva ? Icons.new_releases_outlined : Icons.edit_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _esNueva
                      ? 'Nueva versión de ${_appActual.nombre}'
                      : 'Editar versión de ${_appActual.nombre}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'El changelog es lo que verá el usuario en el móvil. '
                  'Revísalo en la vista previa antes de publicar.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!mostrarPanelPrevia)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: OutlinedButton.icon(
                onPressed: _abrirVistaPrevia,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Ver como el usuario'),
              ),
            ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: _guardando ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _formulario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Seccion(
          icono: Icons.apps,
          titulo: 'App y versión',
          hijo: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _appId,
                decoration: const InputDecoration(
                  labelText: 'App *',
                  helperText: 'La versión se publica solo para esta app',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final app in appsEcosistema)
                    DropdownMenuItem<String>(
                      value: app.id,
                      child: Row(
                        children: [
                          Icon(app.icono, size: 16, color: app.color),
                          const SizedBox(width: 8),
                          Text(app.nombre),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _appId = v);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _version,
                      onChanged: _alCambiarVersion,
                      decoration: const InputDecoration(
                        labelText: 'Versión *',
                        hintText: '1.4.2',
                        helperText: 'Formato 1.2.3',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _build,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Build *',
                        hintText: '402',
                        helperText: 'Entero, siempre creciente',
                        helperMaxLines: 2,
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
                      controller: _versionMinima,
                      onChanged: (_) {
                        _minimaTocada = true;
                        setState(() {});
                      },
                      decoration: const InputDecoration(
                        labelText: 'Versión mínima *',
                        hintText: '1.4.0',
                        helperText:
                            'Obligatoria: desde qué versión se ofrece. Se '
                            'sugiere la versión nueva hasta que la edites',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Obligatoria',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'El usuario no puede omitirla',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _obligatoria,
                      onChanged: (v) => setState(() => _obligatoria = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Seccion(
          icono: Icons.campaign_outlined,
          titulo: 'Changelog',
          subtitulo:
              'Cada cambio lleva su tipo (novedad, mejora o corrección). Es lo '
              'que verá el usuario en el móvil; sin título no se muestra.',
          hijo: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titulo,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Título del changelog',
                  hintText: 'Ej. Caja más rápida y arqueo por turno',
                  helperText: 'Se muestra como cabecera del aviso',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'NOVEDADES',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _agregarNovedad,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Añadir cambio'),
                  ),
                ],
              ),
              if (_novedades.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Text(
                    'Sin cambios añadidos. El usuario verá el aviso de '
                    'actualización sin detalle del changelog.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                for (var i = 0; i < _novedades.length; i++) _editorNovedad(i),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Seccion(
          icono: Icons.public,
          titulo: 'Publicación',
          hijo: Column(
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL de descarga (opcional)',
                  hintText: 'https://…',
                  helperText:
                      'Enlace directo al APK o a la tienda; si se deja vacío '
                      'se usa el canal habitual',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Se ofrece a los usuarios como actualización disponible',
                  style: TextStyle(fontSize: 11),
                ),
                value: _activa,
                onChanged: (v) => setState(() => _activa = v),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _editorNovedad(int indice) {
    final novedad = _novedades[indice];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CAMBIO ${indice + 1}',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textHint,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 165,
                child: DropdownButtonFormField<String>(
                  initialValue: novedad.tipo,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final tipo in NovedadVersion.tipos)
                      DropdownMenuItem<String>(
                        value: tipo,
                        child: Text(
                          etiquetaTipoNovedad(tipo),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => novedad.tipo = v);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Quitar cambio',
                onPressed: () => _quitarNovedad(indice),
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: novedad.titulo,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Título *',
              hintText: 'Ej. Arqueo de caja por turno',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: novedad.descripcion,
            onChanged: (_) => setState(() {}),
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              hintText: 'Una frase que explique el cambio al usuario',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Novedad en edición: tipo + dos controladores de texto.
class _NovedadEditable {
  _NovedadEditable({
    required this.tipo,
    required this.titulo,
    required this.descripcion,
  });

  factory _NovedadEditable.nueva() {
    return _NovedadEditable(
      tipo: NovedadVersion.tipoNovedad,
      titulo: TextEditingController(),
      descripcion: TextEditingController(),
    );
  }

  factory _NovedadEditable.desde(NovedadVersion novedad) {
    return _NovedadEditable(
      tipo: novedad.tipo,
      titulo: TextEditingController(text: novedad.titulo),
      descripcion: TextEditingController(text: novedad.descripcion),
    );
  }

  String tipo;
  final TextEditingController titulo;
  final TextEditingController descripcion;

  NovedadVersion aNovedad() {
    return NovedadVersion(
      tipo: tipo,
      titulo: titulo.text.trim(),
      descripcion: descripcion.text.trim(),
    );
  }

  void dispose() {
    titulo.dispose();
    descripcion.dispose();
  }
}

/// Diálogo de vista previa para pantallas donde no cabe el panel al lado.
class _DialogoVistaPrevia extends StatelessWidget {
  const _DialogoVistaPrevia({
    required this.app,
    required this.version,
    required this.buildNumber,
    required this.titulo,
    required this.novedades,
    required this.obligatoria,
    this.versionMinima,
    this.urlDescarga,
    this.fecha,
  });

  final AppEcosistema app;
  final String version;
  final int buildNumber;
  final String titulo;
  final List<NovedadVersion> novedades;
  final bool obligatoria;
  final String? versionMinima;
  final String? urlDescarga;
  final String? fecha;

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.sizeOf(context).height;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: alto * 0.88),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Cómo lo verá el usuario',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Center(
                    child: VistaPreviaMovil(
                      app: app,
                      version: version,
                      buildNumber: buildNumber,
                      titulo: titulo,
                      novedades: novedades,
                      obligatoria: obligatoria,
                      versionMinima: versionMinima,
                      urlDescarga: urlDescarga,
                      fecha: fecha,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sección con título dentro del editor de versión.
class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.icono,
    required this.titulo,
    required this.hijo,
    this.subtitulo,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 17, color: AppColors.primary),
              const SizedBox(width: 7),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          hijo,
        ],
      ),
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
