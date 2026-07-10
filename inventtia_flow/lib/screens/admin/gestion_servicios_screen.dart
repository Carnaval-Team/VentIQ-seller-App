import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/campo_adicional.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/imagen_service.dart';
import '../../widgets/net_image.dart';

class GestionServiciosScreen extends StatefulWidget {
  final Entidad entidad;
  const GestionServiciosScreen({super.key, required this.entidad});

  @override
  State<GestionServiciosScreen> createState() =>
      _GestionServiciosScreenState();
}

class _GestionServiciosScreenState extends State<GestionServiciosScreen> {
  List<Servicio> _servicios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      _servicios =
          await CatalogoService.getServiciosByEntidad(widget.entidad.id);
    } catch (e) {
      print('[flow] GestionServiciosScreen _cargar ERROR: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _nuevoServicio() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ServicioFormSheet(idEntidad: widget.entidad.id),
    ).then((_) => _cargar());
  }

  void _editarServicio(Servicio servicio) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ServicioFormSheet(
          idEntidad: widget.entidad.id, servicio: servicio),
    ).then((_) => _cargar());
  }

  Future<void> _eliminarServicio(Servicio servicio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Servicio'),
        content: Text('¿Eliminar "${servicio.nombre}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
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
        await CatalogoService.deleteServicio(servicio.id);
        await _cargar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Servicios · ${widget.entidad.denominacion}'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoServicio,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Servicio'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servicios.isEmpty
              ? const Center(
                  child: Text('Sin servicios registrados',
                      style: TextStyle(color: AppTheme.textSecondary)),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _servicios.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = _servicios[i];
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.surface,
                            backgroundImage: s.foto != null
                                ? (kIsWeb
                                    ? NetworkImage(s.foto!) as ImageProvider
                                    : CachedNetworkImageProvider(s.foto!))
                                : null,
                            child: s.foto == null
                                ? const Icon(
                                    Icons.miscellaneous_services_outlined,
                                    color: AppTheme.primary)
                                : null,
                          ),
                          title: Text(s.nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: s.descripcion != null
                              ? Text(s.descripcion!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 20, color: AppTheme.primary),
                                onPressed: () => _editarServicio(s),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: AppTheme.error),
                                onPressed: () => _eliminarServicio(s),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _ServicioFormSheet extends StatefulWidget {
  final int idEntidad;
  final Servicio? servicio;
  const _ServicioFormSheet({required this.idEntidad, this.servicio});

  @override
  State<_ServicioFormSheet> createState() => _ServicioFormSheetState();
}

class _ServicioFormSheetState extends State<_ServicioFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  XFile? _imagenFile;
  String? _fotoUrl;
  bool _saving = false;

  // Datos adicionales + terceros
  bool _permiteTercero = false;
  late List<_CampoEditable> _campos;

  @override
  void initState() {
    super.initState();
    _nombreCtrl =
        TextEditingController(text: widget.servicio?.nombre ?? '');
    _descCtrl =
        TextEditingController(text: widget.servicio?.descripcion ?? '');
    _fotoUrl = widget.servicio?.foto;
    _permiteTercero = widget.servicio?.permiteTercero ?? false;
    _campos = (widget.servicio?.camposAdicionales ?? [])
        .map(_CampoEditable.fromModel)
        .toList();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _campos) {
      c.dispose();
    }
    super.dispose();
  }

  /// Construye la lista de campos en formato jsonb, autogenerando claves únicas.
  /// Devuelve null si hay un campo inválido (sin etiqueta, o select sin opciones).
  List<Map<String, dynamic>>? _camposToJson() {
    // Pasada 1: calcular la clave única (slug) de cada campo, para poder
    // resolver las referencias de las reglas condicionales (si_clave).
    final claves = <_CampoEditable, String>{};
    final usadas = <String>{};
    for (final c in _campos) {
      final etiqueta = c.etiquetaCtrl.text.trim();
      if (etiqueta.isEmpty) {
        _campoError = 'Cada dato adicional necesita una etiqueta';
        return null;
      }
      var clave = CampoAdicional.slug(etiqueta);
      final base = clave;
      var n = 2;
      while (usadas.contains(clave)) {
        clave = '${base}_$n';
        n++;
      }
      usadas.add(clave);
      claves[c] = clave;
    }

    // Resuelve el slug base seleccionado en una regla a la clave final del campo.
    String? resolverSiClave(String? siBase) {
      if (siBase == null || siBase.isEmpty) return null;
      for (final c in _campos) {
        if (CampoAdicional.slug(c.etiquetaCtrl.text.trim()) == siBase) {
          return claves[c];
        }
      }
      return siBase;
    }

    // Pasada 2: construir el jsonb de cada campo.
    final out = <Map<String, dynamic>>[];
    for (final c in _campos) {
      final etiqueta = c.etiquetaCtrl.text.trim();
      final opciones = c.tipo == TipoCampo.select
          ? c.opcionesCtrl.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];
      if (c.tipo == TipoCampo.select && opciones.isEmpty) {
        _campoError = '"$etiqueta": un seleccionable necesita opciones';
        return null;
      }

      // Valor por defecto fijo según el tipo.
      Object? defaultVal;
      if (c.tipo == TipoCampo.booleano) {
        if (c.defaultBool) defaultVal = true; // false == ausencia
      } else {
        final dt = c.defaultCtrl.text.trim();
        if (dt.isNotEmpty) {
          defaultVal = c.tipo == TipoCampo.numero ? (int.tryParse(dt) ?? dt) : dt;
        }
      }

      // Reglas de default condicional (se ignoran las incompletas).
      final reglasJson = <Map<String, dynamic>>[];
      for (final r in c.reglas) {
        final si = resolverSiClave(r.siClave);
        final ig = r.igualCtrl.text.trim();
        final va = r.valorCtrl.text.trim();
        if (si == null || si.isEmpty || ig.isEmpty || va.isEmpty) continue;
        reglasJson.add({
          'si_clave': si,
          'igual': ig,
          'valor': c.tipo == TipoCampo.numero ? (int.tryParse(va) ?? va) : va,
        });
      }

      out.add({
        'clave': claves[c],
        'etiqueta': etiqueta,
        'tipo': c.tipo.valor,
        'requerido': c.requerido,
        'opciones': opciones,
        if (c.min != null) 'min': c.min,
        if (c.max != null) 'max': c.max,
        if (defaultVal != null) 'default': defaultVal,
        if (c.contabilizar) 'contabilizar': true,
        if (reglasJson.isNotEmpty) 'reglas': reglasJson,
      });
    }
    _campoError = null;
    return out;
  }

  String? _campoError;

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
    final campos = _camposToJson();
    if (campos == null) {
      setState(() {}); // refresca para mostrar _campoError
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_campoError ?? 'Revisa los datos adicionales'),
            backgroundColor: AppTheme.error),
      );
      return;
    }
    final uuid = AuthService.currentUserId ?? '';
    setState(() => _saving = true);
    try {
      String? fotoFinal = _fotoUrl;
      int idServicio;
      if (widget.servicio == null) {
        final nuevo = await CatalogoService.createServicio(
          nombre: _nombreCtrl.text.trim(),
          descripcion: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          idEntidad: widget.idEntidad,
        );
        idServicio = nuevo.id;
        if (_imagenFile != null) {
          fotoFinal = await ImagenService.subirImagen(
            imagen: _imagenFile!,
            path: ImagenService.pathServicio(nuevo.id),
          );
          await CatalogoService.updateServicio(
            id: nuevo.id,
            nombre: nuevo.nombre,
            descripcion: nuevo.descripcion,
            foto: fotoFinal,
          );
        }
      } else {
        idServicio = widget.servicio!.id;
        if (_imagenFile != null) {
          fotoFinal = await ImagenService.subirImagen(
            imagen: _imagenFile!,
            path: ImagenService.pathServicio(widget.servicio!.id),
          );
        }
        await CatalogoService.updateServicio(
          id: widget.servicio!.id,
          nombre: _nombreCtrl.text.trim(),
          descripcion: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          foto: fotoFinal,
        );
      }
      // Guarda datos adicionales + flag de terceros (RPC admin)
      await CatalogoService.guardarDatosServicio(
        uuidUsuario: uuid,
        idServicio: idServicio,
        campos: campos,
        permiteTercero: _permiteTercero,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  void _agregarCampo() {
    setState(() => _campos.add(_CampoEditable.nuevo()));
  }

  void _quitarCampo(int i) {
    setState(() {
      _campos[i].dispose();
      _campos.removeAt(i);
    });
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
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.servicio == null ? 'Nuevo Servicio' : 'Editar Servicio',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
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

            // ── Selector de imagen ────────────────────────
            GestureDetector(
              onTap: _showImagenPicker,
              child: Container(
                height: 130,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: _imagenFile != null
                      ? Image.file(File(_imagenFile!.path),
                          fit: BoxFit.cover, width: double.infinity)
                      : _fotoUrl != null
                          ? NetImage(
                              url: _fotoUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: () => const Center(
                                  child: CircularProgressIndicator()),
                              errorWidget: () => _SrvImagePlaceholder(),
                            )
                          : _SrvImagePlaceholder(),
                ),
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: _showImagenPicker,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                label: Text(_imagenFile != null || _fotoUrl != null
                    ? 'Cambiar imagen'
                    : 'Agregar imagen'),
              ),
            ),
            const SizedBox(height: 4),

            TextFormField(
              controller: _nombreCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                prefixIcon:
                    Icon(Icons.miscellaneous_services_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),

            // ── Reservar para terceros ────────────────────
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _permiteTercero,
              onChanged: (v) => setState(() => _permiteTercero = v),
              title: const Text('Permitir reservar para terceros'),
              subtitle: const Text(
                  'El cliente podrá reservar a nombre de otra persona',
                  style: TextStyle(fontSize: 12)),
            ),
            const Divider(),

            // ── Datos adicionales ─────────────────────────
            Row(
              children: [
                const Expanded(
                  child: Text('Datos adicionales',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                TextButton.icon(
                  onPressed: _agregarCampo,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            if (_campos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                    'Sin datos adicionales. El cliente solo verá lo básico.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ),
            for (var i = 0; i < _campos.length; i++)
              _CampoEditableTile(
                key: ValueKey(_campos[i]),
                campo: _campos[i],
                todosCampos: _campos,
                onChanged: () => setState(() {}),
                onRemove: () => _quitarCampo(i),
              ),
            if (_campoError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_campoError!,
                    style: const TextStyle(
                        color: AppTheme.error, fontSize: 12)),
              ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      widget.servicio == null
                          ? 'Crear Servicio'
                          : 'Guardar',
                      style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Estado mutable de una regla de default condicional mientras se edita.
class _ReglaEditable {
  String? siClave; // slug base del campo del que depende (etiqueta -> slug)
  final TextEditingController igualCtrl;
  final TextEditingController valorCtrl;

  _ReglaEditable({this.siClave, String igual = '', String valor = ''})
      : igualCtrl = TextEditingController(text: igual),
        valorCtrl = TextEditingController(text: valor);

  void dispose() {
    igualCtrl.dispose();
    valorCtrl.dispose();
  }
}

/// Estado mutable de un campo adicional mientras se edita en el formulario.
class _CampoEditable {
  final TextEditingController etiquetaCtrl;
  final TextEditingController opcionesCtrl; // CSV para select
  TipoCampo tipo;
  bool requerido;
  int? min;
  int? max;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;

  // Datos adicionales nuevos: default, contabilizar, reglas.
  final TextEditingController defaultCtrl; // default para texto/numero/select
  bool defaultBool; // default para booleano
  bool contabilizar;
  final List<_ReglaEditable> reglas;

  _CampoEditable({
    required String etiqueta,
    required this.tipo,
    required this.requerido,
    required List<String> opciones,
    this.min,
    this.max,
    String defaultTexto = '',
    this.defaultBool = false,
    this.contabilizar = false,
    List<_ReglaEditable>? reglas,
  })  : etiquetaCtrl = TextEditingController(text: etiqueta),
        opcionesCtrl = TextEditingController(text: opciones.join(', ')),
        minCtrl = TextEditingController(text: min?.toString() ?? ''),
        maxCtrl = TextEditingController(text: max?.toString() ?? ''),
        defaultCtrl = TextEditingController(text: defaultTexto),
        reglas = reglas ?? [];

  factory _CampoEditable.nuevo() => _CampoEditable(
        etiqueta: '',
        tipo: TipoCampo.texto,
        requerido: false,
        opciones: [],
      );

  factory _CampoEditable.fromModel(CampoAdicional c) => _CampoEditable(
        etiqueta: c.etiqueta,
        tipo: c.tipo,
        requerido: c.requerido,
        opciones: c.opciones,
        min: c.min,
        max: c.max,
        defaultTexto:
            c.tipo == TipoCampo.booleano ? '' : (c.valorDefault?.toString() ?? ''),
        defaultBool: c.tipo == TipoCampo.booleano &&
            DatosAdicionalesBoolParse.asBool(c.valorDefault),
        contabilizar: c.contabilizar,
        reglas: c.reglas
            .map((r) => _ReglaEditable(
                  siClave: r.siClave,
                  igual: r.igual,
                  valor: r.valor.toString(),
                ))
            .toList(),
      );

  void dispose() {
    etiquetaCtrl.dispose();
    opcionesCtrl.dispose();
    minCtrl.dispose();
    maxCtrl.dispose();
    defaultCtrl.dispose();
    for (final r in reglas) {
      r.dispose();
    }
  }
}

/// Pequeño helper para interpretar un default booleano guardado como bool o texto.
class DatosAdicionalesBoolParse {
  static bool asBool(Object? v) {
    if (v is bool) return v;
    final s = v?.toString().toLowerCase().trim();
    return s == 'true' || s == 'sí' || s == 'si' || s == '1';
  }
}

/// Tarjeta editable para un campo adicional (etiqueta, tipo, requerido, opciones,
/// min/max, valor por defecto, contabilizar y reglas de default condicional).
class _CampoEditableTile extends StatelessWidget {
  final _CampoEditable campo;
  final List<_CampoEditable> todosCampos;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _CampoEditableTile({
    super.key,
    required this.campo,
    required this.todosCampos,
    required this.onChanged,
    required this.onRemove,
  });

  /// Opciones del dropdown "depende de": los demás campos con etiqueta no vacía.
  List<DropdownMenuItem<String>> _otrosCamposItems() {
    final items = <DropdownMenuItem<String>>[];
    for (final c in todosCampos) {
      if (identical(c, campo)) continue;
      final etq = c.etiquetaCtrl.text.trim();
      if (etq.isEmpty) continue;
      items.add(DropdownMenuItem(
        value: CampoAdicional.slug(etq),
        child: Text(etq, overflow: TextOverflow.ellipsis),
      ));
    }
    return items;
  }

  Widget _buildDefault() {
    if (campo.tipo == TipoCampo.booleano) {
      return Row(
        children: [
          const Text('Valor por defecto', style: TextStyle(fontSize: 13)),
          const Spacer(),
          Switch(
            value: campo.defaultBool,
            onChanged: (v) {
              campo.defaultBool = v;
              onChanged();
            },
          ),
        ],
      );
    }
    if (campo.tipo == TipoCampo.select) {
      final opciones = campo.opcionesCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final current = campo.defaultCtrl.text.trim();
      return DropdownButtonFormField<String>(
        value: opciones.contains(current) ? current : null,
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Valor por defecto',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('— Ninguno —')),
          ...opciones
              .map((o) => DropdownMenuItem(value: o, child: Text(o))),
        ],
        onChanged: (v) {
          campo.defaultCtrl.text = v ?? '';
          onChanged();
        },
      );
    }
    return TextField(
      controller: campo.defaultCtrl,
      keyboardType:
          campo.tipo == TipoCampo.numero ? TextInputType.number : TextInputType.text,
      decoration: const InputDecoration(
        labelText: 'Valor por defecto',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => onChanged(),
    );
  }

  Widget _buildReglas() {
    final otros = _otrosCamposItems();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Default según otro campo',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: otros.isEmpty
                  ? null
                  : () {
                      campo.reglas.add(_ReglaEditable());
                      onChanged();
                    },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Regla'),
            ),
          ],
        ),
        if (otros.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Agrega otros campos para poder condicionar.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ),
        for (var i = 0; i < campo.reglas.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Si ', style: TextStyle(fontSize: 12)),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: otros.any((o) => o.value == campo.reglas[i].siClave)
                        ? campo.reglas[i].siClave
                        : null,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    hint: const Text('campo', style: TextStyle(fontSize: 12)),
                    items: otros,
                    onChanged: (v) {
                      campo.reglas[i].siClave = v;
                      onChanged();
                    },
                  ),
                ),
                const Text(' = ', style: TextStyle(fontSize: 12)),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: campo.reglas[i].igualCtrl,
                    decoration: const InputDecoration(
                      hintText: 'valor',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const Text(' → ', style: TextStyle(fontSize: 12)),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: campo.reglas[i].valorCtrl,
                    decoration: const InputDecoration(
                      hintText: 'default',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppTheme.error),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    campo.reglas[i].dispose();
                    campo.reglas.removeAt(i);
                    onChanged();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: campo.etiquetaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Etiqueta',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.error, size: 20),
                onPressed: onRemove,
                tooltip: 'Quitar',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TipoCampo>(
                  value: campo.tipo,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: TipoCampo.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(t.etiqueta)))
                      .toList(),
                  onChanged: (t) {
                    if (t != null) {
                      campo.tipo = t;
                      onChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Checkbox(
                      value: campo.requerido,
                      onChanged: (v) {
                        campo.requerido = v ?? false;
                        onChanged();
                      },
                    ),
                    const Flexible(child: Text('Requerido')),
                  ],
                ),
              ),
            ],
          ),
          if (campo.tipo == TipoCampo.select) ...[
            const SizedBox(height: 8),
            TextField(
              controller: campo.opcionesCtrl,
              decoration: const InputDecoration(
                labelText: 'Opciones (separadas por coma)',
                hintText: 'Casado, Viudo, Soltero',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
            ),
          ],
          if (campo.tipo == TipoCampo.numero || campo.tipo == TipoCampo.texto) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: campo.minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: campo.tipo == TipoCampo.numero
                          ? 'Mín. dígitos'
                          : 'Mín. caracteres',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => campo.min = int.tryParse(v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: campo.maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: campo.tipo == TipoCampo.numero
                          ? 'Máx. dígitos'
                          : 'Máx. caracteres',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => campo.max = int.tryParse(v.trim()),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          _buildDefault(),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(
                value: campo.contabilizar,
                onChanged: (v) {
                  campo.contabilizar = v ?? false;
                  onChanged();
                },
              ),
              const Flexible(
                child: Text('Totalizar en reportes',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const Divider(height: 12),
          _buildReglas(),
        ],
      ),
    );
  }
}

class _SrvImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.miscellaneous_services_outlined,
              size: 36, color: AppTheme.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 6),
          Text('Toca para agregar imagen',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary.withOpacity(0.6))),
        ],
      ),
    );
  }
}
