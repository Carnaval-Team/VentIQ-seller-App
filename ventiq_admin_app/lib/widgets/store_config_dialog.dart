import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_colors.dart';
import '../services/carnaval_service.dart';

class StoreConfigDialog extends StatefulWidget {
  final int storeId;
  final Map<String, dynamic> currentStoreInfo;

  const StoreConfigDialog({
    super.key,
    required this.storeId,
    required this.currentStoreInfo,
  });

  @override
  State<StoreConfigDialog> createState() => _StoreConfigDialogState();
}

class _StoreConfigDialogState extends State<StoreConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _locationController;
  late TextEditingController _phoneController;

  String? _imageUrl;
  Uint8List? _newImageBytes;
  String? _newImageName;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.currentStoreInfo['denominacion'],
    );
    _addressController = TextEditingController(
      text: widget.currentStoreInfo['direccion'],
    );
    _locationController = TextEditingController(
      text: widget.currentStoreInfo['ubicacion'],
    );
    _phoneController = TextEditingController(
      text: widget.currentStoreInfo['phone']?.toString(),
    );
    _imageUrl = widget.currentStoreInfo['imagen_url'];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _newImageBytes = bytes;
          _newImageName = image.name;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar imagen: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_imageUrl == null && _newImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar una imagen para la tienda'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? finalImageUrl = _imageUrl;

      // Subir nueva imagen si existe
      if (_newImageBytes != null && _newImageName != null) {
        final uploadedUrl = await CarnavalService.uploadStoreImage(
          _newImageBytes!,
          _newImageName!,
        );
        if (uploadedUrl != null) {
          finalImageUrl = uploadedUrl;
        } else {
          throw Exception('No se pudo subir la imagen');
        }
      }

      // Actualizar datos
      final updateData = {
        'denominacion': _nameController.text.trim(),
        'direccion': _addressController.text.trim(),
        'ubicacion': _locationController.text.trim(),
        'phone': _phoneController.text.trim(),
        'imagen_url': finalImageUrl,
      };

      final success = await CarnavalService.updateStoreInfo(
        widget.storeId,
        updateData,
      );

      if (success) {
        if (mounted) {
          Navigator.pop(context, true); // Retornar true si se guardó
        }
      } else {
        throw Exception('No se pudieron guardar los cambios');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configurar Tienda'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Completa los datos faltantes para sincronizar con Carnaval App.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 20),

                // Imagen
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                        image:
                            _newImageBytes != null
                                ? DecorationImage(
                                  image: MemoryImage(_newImageBytes!),
                                  fit: BoxFit.cover,
                                )
                                : _imageUrl != null
                                ? DecorationImage(
                                  image: NetworkImage(_imageUrl!),
                                  fit: BoxFit.cover,
                                )
                                : null,
                      ),
                      child:
                          (_newImageBytes == null && _imageUrl == null)
                              ? const Icon(
                                Icons.add_a_photo,
                                size: 40,
                                color: Colors.grey,
                              )
                              : null,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Logo de la tienda *',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 20),

                // Campos
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la tienda *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Ubicación (Ciudad/Zona)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.map),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono de contacto',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child:
              _isLoading
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Text('Guardar'),
        ),
      ],
    );
  }
}
