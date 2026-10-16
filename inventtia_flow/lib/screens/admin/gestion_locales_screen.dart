import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../services/catalogo_service.dart';
import '../../services/geonames_service.dart';
import '../../services/imagen_service.dart';
import '../../tutorial/tutorial_anchor.dart';
import '../../utils/foto_obligatoria.dart';
import '../../utils/horario_atencion.dart';
import '../../widgets/campo_foto_obligatoria.dart';

class GestionLocalesScreen extends StatefulWidget {
  final Entidad entidad;
  const GestionLocalesScreen({super.key, required this.entidad});

  @override
  State<GestionLocalesScreen> createState() => _GestionLocalesScreenState();
}

class _GestionLocalesScreenState extends State<GestionLocalesScreen> {
  List<Local> _locales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      _locales = await CatalogoService.getLocalesByEntidad(widget.entidad.id);
    } catch (e) {
      print('[flow] GestionLocalesScreen _cargar ERROR: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _nuevoLocal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LocalFormSheet(idEntidad: widget.entidad.id),
    ).then((_) => _cargar());
  }

  void _editarLocal(Local local) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          LocalFormSheet(idEntidad: widget.entidad.id, local: local),
    ).then((_) => _cargar());
  }

  Future<void> _eliminarLocal(Local local) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Local'),
        content: Text(
          '¿Eliminar "${local.nombre}"? Se eliminarán sus servicios y colas asociados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await CatalogoService.deleteLocal(local.id);
        await _cargar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Locales · ${widget.entidad.denominacion}')),
      floatingActionButton: TutorialAnchor(
        id: 'admin_nuevo_local',
        child: FloatingActionButton.extended(
          onPressed: _nuevoLocal,
          icon: const Icon(Icons.add),
          label: const Text('Nuevo Local'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _locales.isEmpty
          ? const Center(
              child: Text(
                'Sin locales registrados',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _locales.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final l = _locales[i];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    // Un local desactivado sigue en la lista (el admin tiene
                    // que poder reactivarlo) pero se atenúa para que se note
                    // de un vistazo que los clientes no lo ven.
                    child: Opacity(
                      opacity: l.activo ? 1 : 0.6,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.surface,
                          backgroundImage: l.foto != null
                              ? (kIsWeb
                                    ? NetworkImage(
                                            ImagenService.conVersion(l.foto),
                                          )
                                          as ImageProvider
                                    : CachedNetworkImageProvider(
                                        ImagenService.conVersion(l.foto),
                                      ))
                              : null,
                          child: l.foto == null
                              ? const Icon(
                                  Icons.store_outlined,
                                  color: AppTheme.primary,
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                l.nombre,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!l.activo)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: _ChipInactivo(),
                              ),
                          ],
                        ),
                        subtitle: l.direccion != null
                            ? Text(
                                l.direccion!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: AppTheme.primary,
                              ),
                              onPressed: () => _editarLocal(l),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: AppTheme.error,
                              ),
                              onPressed: () => _eliminarLocal(l),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class LocalFormSheet extends StatefulWidget {
  final int idEntidad;
  final Local? local;
  const LocalFormSheet({super.key, required this.idEntidad, this.local});

  @override
  State<LocalFormSheet> createState() => LocalFormSheetState();
}

class LocalFormSheetState extends State<LocalFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _horarioCtrl;

  // Imagen
  XFile? _imagenFile;
  String? _fotoUrl;

  // GeoNames
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedState;
  bool _loadingCountries = false;
  bool _loadingStates = false;

  // ── Punto 3 del plan: publicación del local ──
  late bool _activo;

  // ── Punto 10 del plan: horario estructurado ──
  //
  // Dos modos excluyentes:
  //  · estructurado → días + apertura + cierre ⇒ se guarda `horario_detalle`
  //    y se genera el texto canónico en `horario_atencion`;
  //  · texto libre  → sólo `horario_atencion`, y `horario_detalle` queda NULL.
  // Nunca los dos: así no hay dos fuentes de verdad que puedan divergir.
  late final Set<int> _dias;
  TimeOfDay? _apertura;
  TimeOfDay? _cierre;
  late bool _textoLibre;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.local?.nombre ?? '');
    _descCtrl = TextEditingController(text: widget.local?.descripcion ?? '');
    _dirCtrl = TextEditingController(text: widget.local?.direccion ?? '');
    _horarioCtrl = TextEditingController(
      text: widget.local?.horarioAtencion ?? '',
    );
    _fotoUrl = widget.local?.foto;
    _activo = widget.local?.activo ?? true;

    final detalle = HorarioDetalle.fromJson(widget.local?.horarioDetalle);
    if (detalle != null) {
      _dias = detalle.dias.toSet();
      _apertura = _horaDeMinutos(detalle.desdeMinutos);
      _cierre = _horaDeMinutos(detalle.hastaMinutos);
      _textoLibre = false;
    } else if (widget.local == null) {
      // Local nuevo: se propone el constructor estructurado, que es el arreglo
      // del punto 10. Lunes a viernes 08:00–17:00 es el caso más común.
      _dias = {1, 2, 3, 4, 5};
      _apertura = const TimeOfDay(hour: 8, minute: 0);
      _cierre = const TimeOfDay(hour: 17, minute: 0);
      _textoLibre = false;
    } else {
      // Local existente con texto libre: NO se reinterpreta ni se pisa. Se abre
      // en modo texto libre y se conserva lo que ya estaba.
      _dias = <int>{};
      _textoLibre = true;
    }

    _loadCountries();
  }

  /// Convierte minutos desde medianoche a [TimeOfDay]. `1440` (24 h) se muestra
  /// como 00:00, que es justo lo que el constructor interpreta de vuelta.
  static TimeOfDay _horaDeMinutos(int minutos) {
    final m = minutos % 1440;
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  static String _textoHora(TimeOfDay hora) =>
      '${hora.hour.toString().padLeft(2, '0')}:'
      '${hora.minute.toString().padLeft(2, '0')}';

  /// El detalle que se va a guardar, o `null` si está incompleto/ inválido.
  HorarioDetalle? get _detalleActual => HorarioDetalle.crear(
    dias: _dias,
    apertura: _apertura == null ? null : _textoHora(_apertura!),
    cierre: _cierre == null ? null : _textoHora(_cierre!),
  );

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    _dirCtrl.dispose();
    _horarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    setState(() => _loadingCountries = true);
    try {
      final countries = await GeonamesService.getCountries();
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _loadingCountries = false;
      });
      // Si el local ya tiene país, preseleccionar
      final existingPais = widget.local?.pais;
      if (existingPais != null && existingPais.isNotEmpty) {
        final match = countries.firstWhere(
          (c) => (c['countryName'] as String) == existingPais,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          setState(() => _selectedCountry = match);
          await _loadStates(
            match['countryCode'] as String,
            preselectedProvincia: widget.local?.provincia,
          );
        }
      }
    } catch (e) {
      print('[flow] _loadCountries ERROR: $e');
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _loadStates(
    String countryCode, {
    String? preselectedProvincia,
  }) async {
    setState(() {
      _loadingStates = true;
      _states = [];
      _selectedState = null;
    });
    try {
      final states = await GeonamesService.getStates(countryCode);
      if (!mounted) return;
      setState(() {
        _states = states;
        _loadingStates = false;
      });
      if (preselectedProvincia != null && preselectedProvincia.isNotEmpty) {
        final match = states.firstWhere(
          (s) => (s['name'] as String) == preselectedProvincia,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) setState(() => _selectedState = match);
      }
    } catch (e) {
      print('[flow] _loadStates ERROR: $e');
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  Future<void> _pickImagen(ImageSource source) async {
    final file = await ImagenService.seleccionarImagen(source: source);
    if (file != null) setState(() => _imagenFile = file);
  }

  void _showImagenPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImagen(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cámara'),
              onTap: () {
                Navigator.pop(context);
                _pickImagen(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Defensa en profundidad: la foto la valida `CampoFotoObligatoria`, pero el
    // alta no puede depender de que ese campo esté montado. Sin foto no se
    // escribe nada, y menos una fila nueva.
    if (errorFotoObligatoria(
          queEs: 'local',
          fotoGuardada: _fotoUrl,
          archivoElegido: _imagenFile != null,
        ) !=
        null) {
      setState(() {});
      return;
    }

    String? _v(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    // Horario: se resuelve ANTES de escribir nada, para no crear un local y
    // fallar después al validar.
    final String? horarioTexto;
    final Map<String, dynamic>? horarioJson;
    if (_textoLibre) {
      horarioTexto = _v(_horarioCtrl);
      horarioJson = null;
    } else {
      final detalle = _detalleActual;
      if (detalle == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Revisa el horario: elige al menos un día y la hora de apertura '
              'y de cierre.',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
      horarioTexto = textoDesdeDetalle(detalle);
      horarioJson = detalle.toJson();
    }

    setState(() => _saving = true);
    final paisNombre = _selectedCountry != null
        ? _selectedCountry!['countryName'] as String
        : null;
    final provinciaNombre = _selectedState != null
        ? _selectedState!['name'] as String
        : null;
    try {
      String? fotoFinal = _fotoUrl;

      if (widget.local == null) {
        // Se crea primero la fila (el path de la foto necesita su id) y después
        // se sube la imagen. Si esa subida falla, el alta se **deshace**: la foto
        // es obligatoria, así que un local recién creado sin ella no puede
        // quedarse en el catálogo. Antes se quedaba, en silencio.
        final nuevo = await CatalogoService.createLocal(
          nombre: _nombreCtrl.text.trim(),
          descripcion: _v(_descCtrl),
          direccion: _v(_dirCtrl),
          horarioAtencion: horarioTexto,
          horarioDetalle: horarioJson,
          pais: paisNombre,
          provincia: provinciaNombre,
          idEntidad: widget.idEntidad,
          activo: _activo,
        );
        try {
          fotoFinal = await ImagenService.subirImagen(
            imagen: _imagenFile!,
            path: ImagenService.pathLocal(nuevo.id),
          );
          await CatalogoService.updateLocal(
            id: nuevo.id,
            nombre: nuevo.nombre,
            descripcion: nuevo.descripcion,
            direccion: nuevo.direccion,
            horarioAtencion: nuevo.horarioAtencion,
            horarioDetalle: horarioJson,
            pais: nuevo.pais,
            provincia: nuevo.provincia,
            foto: fotoFinal,
            activo: _activo,
          );
        } catch (e) {
          final deshecho = await _deshacerAlta(
            idLocal: nuevo.id,
            pathSubido: ImagenService.pathLocal(nuevo.id),
          );
          throw Exception(
            deshecho
                ? 'No se pudo guardar la foto ($e), así que el local no se creó. '
                      'Vuelve a intentarlo.'
                : 'No se pudo guardar la foto ($e) y el local quedó creado SIN '
                      'foto. Edítalo para añadirla.',
          );
        }
      } else {
        if (_imagenFile != null) {
          fotoFinal = await ImagenService.subirImagen(
            imagen: _imagenFile!,
            path: ImagenService.pathLocal(widget.local!.id),
          );
        }
        await CatalogoService.updateLocal(
          id: widget.local!.id,
          nombre: _nombreCtrl.text.trim(),
          descripcion: _v(_descCtrl),
          direccion: _v(_dirCtrl),
          horarioAtencion: horarioTexto,
          // `null` explícito cuando el admin pasó a texto libre: así se borra el
          // detalle viejo y no queda un horario estructurado fantasma.
          horarioDetalle: horarioJson,
          pais: paisNombre,
          provincia: provinciaNombre,
          foto: fotoFinal,
          activo: _activo,
        );
      }
      if (!mounted) return;
      // La URL guardada ya trae su propio `?v=` (ver `ImagenService.subirImagen`),
      // así que cualquier cliente descarga la foto nueva. `invalidar` queda como
      // red de seguridad para una sesión que ya tenía la URL vieja en pantalla.
      ImagenService.invalidar(fotoFinal);
      Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${_mensajeLegible(e)}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  /// Deshace un alta que quedó a medias: la fila se creó pero la foto no llegó a
  /// guardarse.
  ///
  /// Solo se llama desde la rama de **crear** y solo con el id que acaba de
  /// devolver `createLocal`: en editar nunca se borra nada.
  ///
  /// El orden importa: primero se borra la fila y **después** el archivo. Si el
  /// borrado de la fila falla, el archivo se conserva — la fila sigue viva y su
  /// foto con ella, así que el admin la arregla editando. Al revés se quedaría
  /// una fila sin foto apuntando a un archivo que ya no está.
  ///
  /// Devuelve `true` si el alta quedó deshecha. Si el borrado falla, se registra
  /// y el aviso al admin cambia: hay que decirle que el local existe sin foto,
  /// no mentirle diciendo que no se creó.
  Future<bool> _deshacerAlta({
    required int idLocal,
    required String pathSubido,
  }) async {
    try {
      await CatalogoService.deleteLocal(idLocal);
    } catch (e) {
      debugPrint(
        '[flow] LocalFormSheet: no se pudo deshacer el alta $idLocal: $e',
      );
      return false;
    }
    try {
      await ImagenService.eliminarImagen(pathSubido);
    } catch (e) {
      // Un archivo huérfano en el bucket es inofensivo; la fila ya no está.
      debugPrint('[flow] LocalFormSheet: no se pudo borrar $pathSubido: $e');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.local == null ? 'Nuevo Local' : 'Editar Local',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      foregroundColor: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Foto del local (obligatoria) ──────────────
              // El campo valida por su cuenta: es un `FormField`, así que el
              // error de la foto sale junto al del nombre al pulsar Guardar.
              CampoFotoObligatoria(
                queEs: 'local',
                fotoGuardada: _fotoUrl,
                archivo: _imagenFile,
                alto: 140,
                placeholder: const _ImagePlaceholder(
                  icon: Icons.store_outlined,
                ),
                onElegir: _showImagenPicker,
              ),
              const SizedBox(height: 8),

              // Nombre
              TextFormField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  prefixIcon: Icon(Icons.store_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              // Descripción
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 12),

              // Dirección
              TextFormField(
                controller: _dirCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // ── Horario de atención (punto 10) ────────────
              _HorarioEditor(
                textoLibre: _textoLibre,
                dias: _dias,
                apertura: _apertura,
                cierre: _cierre,
                textoCtrl: _horarioCtrl,
                onTextoLibre: (v) => setState(() => _textoLibre = v),
                onDias: (d) => setState(() {
                  _dias
                    ..clear()
                    ..addAll(d);
                }),
                onApertura: (h) => setState(() => _apertura = h),
                onCierre: (h) => setState(() => _cierre = h),
              ),
              const SizedBox(height: 12),

              // ── País (dropdown GeoNames) ──────────────────
              _GeoDropdown(
                label: 'País',
                icon: Icons.flag_outlined,
                loading: _loadingCountries,
                hint: _loadingCountries
                    ? 'Cargando países...'
                    : 'Seleccionar país',
                value: _selectedCountry,
                items: _countries,
                displayKey: 'countryName',
                onChanged: (country) {
                  setState(() {
                    _selectedCountry = country;
                    _selectedState = null;
                    _states = [];
                  });
                  if (country != null) {
                    _loadStates(country['countryCode'] as String);
                  }
                },
              ),
              const SizedBox(height: 12),

              // ── Estado/Provincia (dropdown GeoNames) ──────
              _GeoDropdown(
                label: 'Estado / Provincia',
                icon: Icons.map_outlined,
                loading: _loadingStates,
                hint: _selectedCountry == null
                    ? 'Selecciona un país primero'
                    : _loadingStates
                    ? 'Cargando estados...'
                    : _states.isEmpty
                    ? 'Sin estados disponibles'
                    : 'Seleccionar estado',
                value: _selectedState,
                items: _states,
                displayKey: 'name',
                enabled:
                    _selectedCountry != null &&
                    !_loadingStates &&
                    _states.isNotEmpty,
                onChanged: (state) => setState(() => _selectedState = state),
              ),
              const SizedBox(height: 8),

              // ── Publicación del local (punto 3) ───────────
              _SwitchActivo(
                valor: _activo,
                titulo: 'Local activo',
                ayuda: _activo
                    ? 'Visible para los clientes.'
                    : 'Oculto: este local y TODOS sus servicios dejan de '
                          'aparecer y de poder reservarse.',
                onChanged: (v) => setState(() => _activo = v),
              ),
              const SizedBox(height: 12),

              // Botón guardar
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        widget.local == null ? 'Crear Local' : 'Guardar',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dropdown genérico para GeoNames ──────────────────────────
//
// Se usa `DropdownButtonFormField` (y NO `InputDecorator` + `DropdownButton`)
// porque el `InputDecorator` obligaba a inventar un `contentPadding` propio y
// ese era justo el bug del punto 2: con `vertical: 4` la etiqueta flotante se
// dibujaba encima del valor. `DropdownButtonFormField` toma el
// `inputDecorationTheme` de la app (`vertical: 14`), que ya está calibrado, y
// deriva `isEmpty` solo.
class _GeoDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final String hint;
  final Map<String, dynamic>? value;
  final List<Map<String, dynamic>> items;
  final String displayKey;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const _GeoDropdown({
    required this.label,
    required this.icon,
    required this.loading,
    required this.hint,
    required this.value,
    required this.items,
    required this.displayKey,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // El valor debe existir entre los items: si GeoNames aún no cargó la lista
    // (o el país ya no está), `DropdownButtonFormField` lanzaría.
    final seleccionado = items.contains(value) ? value : null;

    return DropdownButtonFormField<Map<String, dynamic>>(
      initialValue: seleccionado,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Icon(icon),
      ),
      hint: Text(
        hint,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
      ),
      icon: const Icon(Icons.expand_more),
      onChanged: enabled && !loading ? onChanged : null,
      items: items
          .map(
            (item) => DropdownMenuItem<Map<String, dynamic>>(
              value: item,
              child: Text(
                item[displayKey] as String,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Editor de horario de atención (punto 10 del plan de mejoras).
///
/// Dos modos mutuamente excluyentes: días + apertura/cierre, o texto libre. El
/// modo estructurado es el que arregla el bug por el que "Lun, Mié, Vie" se
/// interpretaba como lunes a viernes.
class _HorarioEditor extends StatelessWidget {
  const _HorarioEditor({
    required this.textoLibre,
    required this.dias,
    required this.apertura,
    required this.cierre,
    required this.textoCtrl,
    required this.onTextoLibre,
    required this.onDias,
    required this.onApertura,
    required this.onCierre,
  });

  final bool textoLibre;
  final Set<int> dias;
  final TimeOfDay? apertura;
  final TimeOfDay? cierre;
  final TextEditingController textoCtrl;
  final ValueChanged<bool> onTextoLibre;
  final ValueChanged<Set<int>> onDias;
  final ValueChanged<TimeOfDay> onApertura;
  final ValueChanged<TimeOfDay> onCierre;

  static String _hhmm(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:'
      '${h.minute.toString().padLeft(2, '0')}';

  HorarioDetalle? get _detalle => HorarioDetalle.crear(
    dias: dias,
    apertura: apertura == null ? null : _hhmm(apertura!),
    cierre: cierre == null ? null : _hhmm(cierre!),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Horario de atención',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => onTextoLibre(!textoLibre),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  textoLibre ? 'Usar días y horas' : 'Texto libre',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (textoLibre) ...[
            const SizedBox(height: 4),
            TextFormField(
              controller: textoCtrl,
              decoration: const InputDecoration(
                labelText: 'Horario (texto libre)',
                hintText: 'Ej: Lun-Vie 8:00-17:00',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Se guarda tal cual. El cliente lo interpreta con el lector de '
              'texto, que entiende los formatos habituales.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'Días que abre',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(
                      HorarioDetalle.abreviaturasDia[d - 1],
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: dias.contains(d),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (sel) {
                      final nuevo = Set<int>.from(dias);
                      if (sel) {
                        nuevo.add(d);
                      } else {
                        nuevo.remove(d);
                      }
                      onDias(nuevo);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BotonHora(
                    etiqueta: 'Apertura',
                    valor: apertura,
                    onElegir: onApertura,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BotonHora(
                    etiqueta: 'Cierre',
                    valor: cierre,
                    onElegir: onCierre,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _detalle?.etiqueta ?? 'Elige al menos un día y las horas',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _detalle == null
                          ? AppTheme.warning
                          : AppTheme.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => onDias({1, 2, 3, 4, 5, 6, 7}),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'Todos los días',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BotonHora extends StatelessWidget {
  const _BotonHora({
    required this.etiqueta,
    required this.valor,
    required this.onElegir,
  });

  final String etiqueta;
  final TimeOfDay? valor;
  final ValueChanged<TimeOfDay> onElegir;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final elegida = await showTimePicker(
          context: context,
          initialTime: valor ?? const TimeOfDay(hour: 8, minute: 0),
          helpText: etiqueta,
        );
        if (elegida != null) onElegir(elegida);
      },
      icon: const Icon(Icons.access_time, size: 16),
      label: Text(
        valor == null ? etiqueta : _HorarioEditor._hhmm(valor!),
        style: const TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Switch reutilizable de publicación con su texto de ayuda.
class _SwitchActivo extends StatelessWidget {
  const _SwitchActivo({
    required this.valor,
    required this.titulo,
    required this.ayuda,
    required this.onChanged,
  });

  final bool valor;
  final String titulo;
  final String ayuda;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: valor
            ? AppTheme.surface
            : AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: valor
              ? AppTheme.border
              : AppTheme.warning.withValues(alpha: 0.4),
        ),
      ),
      // `Material` transparente: el `SwitchListTile` pinta su fondo y su splash
      // en el `Material` más cercano, y el `Container` de arriba tiene color
      // propio, así que sin esto los efectos quedaban ocultos (Flutter lo
      // asevera en debug: "ListTile background color or ink splashes may be
      // invisible").
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          value: valor,
          onChanged: onChanged,
          dense: true,
          visualDensity: VisualDensity.compact,
          activeThumbColor: AppTheme.primary,
          title: Text(
            titulo,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            ayuda,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// Chip "Inactivo" para las listas del admin.
class _ChipInactivo extends StatelessWidget {
  const _ChipInactivo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Inactivo',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.warning,
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final IconData icon;
  const _ImagePlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: AppTheme.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 6),
          Text(
            'Toca para agregar imagen',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quita el prefijo `Exception: ` que Dart añade en `toString()`, para que el
/// aviso al admin se lea como el mensaje real y no como un volcado técnico.
String _mensajeLegible(Object e) {
  const prefijo = 'Exception: ';
  final texto = e.toString();
  return texto.startsWith(prefijo) ? texto.substring(prefijo.length) : texto;
}
