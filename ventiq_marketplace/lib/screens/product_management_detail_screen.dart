import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../services/store_management_service.dart';
import '../widgets/supabase_image.dart';

class ProductManagementDetailScreen extends StatefulWidget {
  final int productId;
  final int storeId;
  final bool storeAllowsCatalog;

  const ProductManagementDetailScreen({
    super.key,
    required this.productId,
    required this.storeId,
    required this.storeAllowsCatalog,
  });

  @override
  State<ProductManagementDetailScreen> createState() =>
      _ProductManagementDetailScreenState();
}

class _ProductManagementDetailScreenState
    extends State<ProductManagementDetailScreen> {
  final _storeService = StoreManagementService();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final SupabaseClient _supabase = Supabase.instance.client;

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  String? _imageUrl;

  num _currentQuantity = 0;
  int? _basePresentationId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  num? _parseNum(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final categoriesRaw = await _storeService.getCatalogCategories();
      final detail = await _storeService.getProductManagementDetail(
        productId: widget.productId,
      );

      final product = Map<String, dynamic>.from(detail['product'] as Map);

      final name = (product['denominacion'] ?? '').toString();
      final image = (product['imagen'] ?? '').toString().trim();

      final categoryIdRaw = product['id_categoria'];
      final categoryId = categoryIdRaw is int
          ? categoryIdRaw
          : (categoryIdRaw is num ? categoryIdRaw.toInt() : null);

      final price = (detail['precio_venta_cup'] is num)
          ? (detail['precio_venta_cup'] as num)
          : null;

      final qty = (detail['cantidad_final'] is num)
          ? (detail['cantidad_final'] as num)
          : 0;

      final basePresRaw = detail['base_presentacion_id'];
      final basePres = basePresRaw is int
          ? basePresRaw
          : (basePresRaw is num ? basePresRaw.toInt() : null);

      // Deduplicar categorías por id y validar selección
      final Map<int, Map<String, dynamic>> uniqueById = {};
      for (final c in categoriesRaw) {
        final idRaw = c['id'];
        final id = idRaw is int ? idRaw : (idRaw is num ? idRaw.toInt() : null);
        if (id != null && !uniqueById.containsKey(id)) {
          uniqueById[id] = Map<String, dynamic>.from(c);
        }
      }
      final categories = uniqueById.values.toList();
      final hasSelected =
          categoryId != null && uniqueById.containsKey(categoryId);
      final safeCategoryId = hasSelected ? categoryId : null;

      if (!mounted) return;

      setState(() {
        _categories = categories;
        _selectedCategoryId = safeCategoryId;
        _imageUrl = image.isNotEmpty ? image : null;
        _currentQuantity = qty;
        _basePresentationId = basePres;

        _nameController.text = name;
        _priceController.text = price == null ? '' : price.toString();
        _qtyController.text = qty.toString();

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando producto: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _pickImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.paddingM),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Tomar foto'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Elegir de galería'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;
    await _pickAndUploadImage(source);
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      setState(() => _isUploadingImage = true);

      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1400,
        imageQuality: 82,
      );

      if (file == null) {
        if (mounted) setState(() => _isUploadingImage = false);
        return;
      }

      final bytes = await file.readAsBytes();
      final url = await _uploadProductImage(bytes);

      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _isUploadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error subiendo imagen: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<String> _uploadProductImage(Uint8List bytes) async {
    final fileName =
        'product_${widget.storeId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _supabase.storage
        .from('images_back')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return _supabase.storage.from('images_back').getPublicUrl(fileName);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameController.text.trim();
    final price = _parseNum(_priceController.text);
    final qty = _parseNum(_qtyController.text);

    if (_imageUrl == null || _imageUrl!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La imagen es obligatoria'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precio inválido'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    if (qty == null || qty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cantidad inválida'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    final categoryId = _selectedCategoryId;
    if (categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una categoría'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _storeService.updateProductBasicInfo(
        productId: widget.productId,
        name: name,
      );

      await _storeService.updateProductImage(
        productId: widget.productId,
        imageUrl: _imageUrl!.trim(),
      );

      await _storeService.updateProductCategory(
        productId: widget.productId,
        storeId: widget.storeId,
        categoryId: categoryId,
      );

      await _storeService.upsertProductPriceForToday(
        productId: widget.productId,
        priceCup: price,
      );

      final basePres =
          _basePresentationId ??
          await _storeService.ensureBasePresentationId(
            productId: widget.productId,
          );

      await _storeService.insertInventorySnapshot(
        productId: widget.productId,
        basePresentationId: basePres,
        currentQuantity: _currentQuantity,
        newQuantity: qty,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Producto actualizado'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error actualizando: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar producto')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.paddingM),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.storeAllowsCatalog)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lock_outline,
                              color: AppTheme.warningColor,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'La tienda no está activa en el catálogo. La visibilidad del producto quedará deshabilitada.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!widget.storeAllowsCatalog) const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'El nombre es obligatorio';
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Nombre del producto',
                        prefixIcon: Icon(Icons.shopping_bag_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      items: _categories.map((c) {
                        final idRaw = c['id'];
                        final id = idRaw is int
                            ? idRaw
                            : (idRaw is num ? idRaw.toInt() : 0);
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            (c['denominacion'] ?? 'Categoría').toString(),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                      validator: (v) =>
                          v == null ? 'Selecciona una categoría' : null,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildImageCard(),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceController,
                      validator: (v) {
                        final value = _parseNum(v ?? '');
                        if (value == null || value <= 0) {
                          return 'Precio válido (ej: 10.50)';
                        }
                        return null;
                      },
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Precio (CUP)',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _qtyController,
                      validator: (v) {
                        final value = _parseNum(v ?? '');
                        if (value == null) return 'Cantidad válida';
                        if (value < 0) return 'No puede ser negativa';
                        return null;
                      },
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad actual',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isSaving || _isUploadingImage ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Guardar cambios',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildImageCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.image_outlined, color: AppTheme.primaryColor),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Foto del producto',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: _isUploadingImage ? null : _pickImageSource,
                child: Text(_imageUrl == null ? 'Subir' : 'Cambiar'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _isUploadingImage
                  ? Container(
                      color: Colors.white,
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : (_imageUrl != null && _imageUrl!.isNotEmpty)
                  ? SupabaseImage(
                      imageUrl: _imageUrl!,
                      width: double.infinity,
                      height: 170,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: Colors.white,
                      child: const Center(
                        child: Icon(Icons.image_outlined, size: 42),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
