import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../services/catalogo_service.dart';
import '../../services/imagen_service.dart';

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
                                ? CachedNetworkImageProvider(s.foto!)
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

  @override
  void initState() {
    super.initState();
    _nombreCtrl =
        TextEditingController(text: widget.servicio?.nombre ?? '');
    _descCtrl =
        TextEditingController(text: widget.servicio?.descripcion ?? '');
    _fotoUrl = widget.servicio?.foto;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
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
    setState(() => _saving = true);
    try {
      String? fotoFinal = _fotoUrl;
      if (widget.servicio == null) {
        final nuevo = await CatalogoService.createServicio(
          nombre: _nombreCtrl.text.trim(),
          descripcion: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          idEntidad: widget.idEntidad,
        );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.servicio == null ? 'Nuevo Servicio' : 'Editar Servicio',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
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
                          ? CachedNetworkImage(
                              imageUrl: _fotoUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (_, __) => const Center(
                                  child: CircularProgressIndicator()),
                              errorWidget: (_, __, ___) => _SrvImagePlaceholder(),
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
