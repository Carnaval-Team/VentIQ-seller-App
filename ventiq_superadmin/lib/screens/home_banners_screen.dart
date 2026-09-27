import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_colors.dart';
import '../models/home_banner.dart';
import '../services/auth_service.dart';
import '../services/home_banners_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';

class HomeBannersScreen extends StatefulWidget {
  const HomeBannersScreen({super.key});

  @override
  State<HomeBannersScreen> createState() => _HomeBannersScreenState();
}

class _HomeBannersScreenState extends State<HomeBannersScreen> {
  List<HomeBanner> _banners = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  Future<void> _loadBanners() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final banners = await HomeBannersService.listBanners();
      if (mounted) {
        setState(() {
          _banners = banners;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al cargar banners: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleActivo(HomeBanner banner) async {
    final nuevo = banner.copyWith(activo: !banner.activo);
    try {
      await HomeBannersService.upsertBanner(
        id: nuevo.id,
        imageUrl: nuevo.imageUrl,
        link: nuevo.link,
        descripcion: nuevo.descripcion,
        orden: nuevo.orden,
        activo: nuevo.activo,
      );
      await _loadBanners();
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error al cambiar estado: $e', isError: true);
      }
    }
  }

  Future<void> _deleteBanner(HomeBanner banner) async {
    final action = await showDialog<_DeleteAction>(
      context: context,
      builder: (context) => _DeleteBannerDialog(
        allowHardDelete: AuthService.hasFullAccess(),
      ),
    );

    if (action == null || !mounted) return;

    try {
      await HomeBannersService.deleteBanner(
        banner.id!,
        hard: action == _DeleteAction.hard,
      );
      if (mounted) {
        _showSnackBar(
          action == _DeleteAction.hard
              ? 'Banner eliminado permanentemente'
              : 'Banner desactivado',
        );
      }
      await _loadBanners();
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error al eliminar: $e', isError: true);
      }
    }
  }

  void _showFormDialog({HomeBanner? banner}) {
    showDialog(
      context: context,
      builder: (context) => _BannerFormDialog(
        banner: banner,
        onSaved: (_) => _loadBanners(),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = AuthService.canWrite();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Banners de inicio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loadBanners,
          ),
          if (canWrite)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Nuevo banner',
              onPressed: () => _showFormDialog(),
            ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _buildBody(),
      floatingActionButton: canWrite
          ? FloatingActionButton(
              onPressed: () => _showFormDialog(),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadBanners,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_banners.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              'No hay banners configurados',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Presiona el botón + para crear el primero',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
      itemCount: _banners.length,
      itemBuilder: (context, index) {
        final banner = _banners[index];
        return _BannerCard(
          banner: banner,
          onEdit: AuthService.canWrite()
              ? () => _showFormDialog(banner: banner)
              : null,
          onToggle: AuthService.canWrite()
              ? () => _toggleActivo(banner)
              : null,
          onDelete: AuthService.canWrite()
              ? () => _deleteBanner(banner)
              : null,
        );
      },
    );
  }
}

class _BannerCard extends StatelessWidget {
  final HomeBanner banner;
  final VoidCallback? onEdit;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  const _BannerCard({
    required this.banner,
    this.onEdit,
    this.onToggle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenWidth);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showImagePreview(context, banner.imageUrl),
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: Image.network(
                banner.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: AppColors.textHint),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildInfoSection()),
                      _buildActions(context),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoSection(),
                      const SizedBox(height: 12),
                      _buildActions(context),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                banner.descripcion?.isNotEmpty == true
                    ? banner.descripcion!
                    : 'Banner #${banner.id}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: banner.activo
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.textSecondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                banner.activo ? 'ACTIVO' : 'INACTIVO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: banner.activo
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (banner.link?.isNotEmpty == true)
          Row(
            children: [
              Icon(Icons.link,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  banner.link!,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.format_list_numbered,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Orden: ${banner.orden}',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onToggle != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Activo',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              Switch(
                value: banner.activo,
                onChanged: (_) => onToggle!(),
                activeThumbColor: AppColors.success,
              ),
            ],
          ),
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Editar',
            onPressed: onEdit,
          ),
        if (onDelete != null)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            tooltip: 'Eliminar',
            onPressed: onDelete,
          ),
      ],
    );
  }

  void _showImagePreview(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.network(url),
        ),
      ),
    );
  }
}

class _BannerFormDialog extends StatefulWidget {
  final HomeBanner? banner;
  final ValueChanged<HomeBanner>? onSaved;

  const _BannerFormDialog({this.banner, this.onSaved});

  @override
  State<_BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends State<_BannerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();

  late final TextEditingController _linkController;
  late final TextEditingController _descripcionController;
  late final TextEditingController _ordenController;

  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _activo = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _linkController = TextEditingController(text: widget.banner?.link ?? '');
    _descripcionController =
        TextEditingController(text: widget.banner?.descripcion ?? '');
    _ordenController = TextEditingController(
      text: widget.banner?.orden.toString() ?? '0',
    );
    _activo = widget.banner?.activo ?? true;
  }

  @override
  void dispose() {
    _linkController.dispose();
    _descripcionController.dispose();
    _ordenController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      ImageSource? source;

      if (PlatformUtils.isWeb) {
        source = ImageSource.gallery;
      } else {
        source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt),
                    title: const Text('Cámara'),
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library),
                    title: const Text('Galería'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      if (source == null) return;

      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1400,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (mounted) {
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = image.name;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error al seleccionar imagen: $e', isError: true);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final isNew = widget.banner?.id == null;
    if (isNew && _selectedImageBytes == null) {
      _showSnackBar('Debes seleccionar una imagen', isError: true);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      String? imageUrl;
      if (_selectedImageBytes != null) {
        imageUrl = await HomeBannersService.uploadImage(
          _selectedImageBytes!,
          fileName: _selectedImageName,
        );
      }

      final orden = int.tryParse(_ordenController.text) ?? 0;

      final saved = await HomeBannersService.upsertBanner(
        id: widget.banner?.id,
        imageUrl: imageUrl ?? widget.banner?.imageUrl,
        link: _linkController.text.isEmpty ? null : _linkController.text,
        descripcion: _descripcionController.text.isEmpty
            ? null
            : _descripcionController.text,
        orden: orden,
        activo: _activo,
      );

      if (mounted) {
        widget.onSaved?.call(saved);
        Navigator.pop(context);
        _showSnackBar(
          isNew ? 'Banner creado' : 'Banner actualizado',
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error al guardar: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.banner != null;
    final hasImage = _selectedImageBytes != null ||
        (widget.banner?.imageUrl.isNotEmpty == true);

    return AlertDialog(
      title: Text(isEditing ? 'Editar banner' : 'Nuevo banner'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasImage) ...[
                  AspectRatio(
                    aspectRatio: 16 / 7,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _selectedImageBytes != null
                          ? Image.memory(
                              _selectedImageBytes!,
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                              widget.banner!.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                color: AppColors.surfaceVariant,
                                child: const Center(
                                  child: Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image),
                  label: Text(
                    hasImage ? 'Cambiar imagen' : 'Seleccionar imagen',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    hintText: 'Ej. Ofertas de la semana',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _linkController,
                  decoration: const InputDecoration(
                    labelText: 'Link',
                    hintText: 'Ej. /search?categoryId=14',
                    border: OutlineInputBorder(),
                    helperText:
                        'Puede ser una ruta interna (/search?...) o https://...',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ordenController,
                  decoration: const InputDecoration(
                    labelText: 'Orden',
                    hintText: '0',
                    border: OutlineInputBorder(),
                    helperText: 'Menor valor = aparece primero',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresa un orden';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Debe ser un número entero';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Activo'),
                  subtitle: const Text('Visible en el carrusel de inicio'),
                  value: _activo,
                  activeThumbColor: AppColors.success,
                  onChanged: (value) => setState(() => _activo = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _save,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}

enum _DeleteAction { soft, hard }

class _DeleteBannerDialog extends StatelessWidget {
  final bool allowHardDelete;

  const _DeleteBannerDialog({required this.allowHardDelete});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Eliminar banner'),
      content: const Text(
        'Elige una acción. Desactivar lo oculta de la app; eliminarlo borra el registro permanentemente.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _DeleteAction.soft),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
          ),
          child: const Text('Desactivar'),
        ),
        if (allowHardDelete)
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _DeleteAction.hard),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar definitivamente'),
          ),
      ],
    );
  }
}
