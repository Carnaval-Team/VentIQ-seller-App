import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../services/catalog_qr_print_service.dart';
import '../services/store_management_service.dart';
import '../services/user_preferences_service.dart';
import '../services/user_session_service.dart';
import '../services/whapi_service.dart';
import '../widgets/supabase_image.dart';
import 'create_product_screen.dart';
import 'product_management_detail_screen.dart';
import 'store_location_picker_screen.dart';

class StoreManagementScreen extends StatefulWidget {
  const StoreManagementScreen({super.key});

  @override
  State<StoreManagementScreen> createState() => _StoreManagementScreenState();
}

class _StoreManagementScreenState extends State<StoreManagementScreen> {
  final _sessionService = UserSessionService();
  final _storeService = StoreManagementService();
  final _userPrefs = UserPreferencesService();
  final _whapiService = WhapiService();
  final _picker = ImagePicker();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _stores = [];
  int _selectedStoreIndex = 0;

  bool _isProductsLoading = false;
  String? _productsErrorMessage;
  List<Map<String, dynamic>> _products = [];

  bool _isSubscriptionLoading = false;
  String? _subscriptionErrorMessage;
  Map<String, dynamic>? _subscriptionCatalog;

  // Selección múltiple de productos
  bool _isMultiSelectMode = false;
  final Set<int> _selectedProductIds = {};

  final _createFormKey = GlobalKey<FormState>();
  final _editFormKey = GlobalKey<FormState>();
  final _denominacionController = TextEditingController();
  final _direccionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _paisController = TextEditingController();
  final _estadoController = TextEditingController();
  final _nombrePaisController = TextEditingController();
  final _nombreEstadoController = TextEditingController();

  LatLng? _selectedLocation;
  String? _imageUrl;
  bool _isUploadingImage = false;
  TimeOfDay _horaApertura = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _horaCierre = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  String _getCatalogUrlForStore(int storeId) {
    return 'https://inventtia-catalogo.netlify.app/open.html?${Uri(queryParameters: {'storeId': storeId.toString()}).query}';
  }

  String _buildWhatsappMessage(Map<String, dynamic> product) {
    final store = (_stores.isNotEmpty && _selectedStoreIndex < _stores.length)
        ? _stores[_selectedStoreIndex]
        : null;

    final storeName = (store?['denominacion'] ?? 'Tu tienda').toString();
    final storePhone = (store?['phone'] ?? '').toString();
    final storeIdRaw = store?['id'];
    final storeId = storeIdRaw is int
        ? storeIdRaw
        : (storeIdRaw is num ? storeIdRaw.toInt() : null);

    final catalogUrl = storeId == null ? null : _getCatalogUrlForStore(storeId);

    final nombre = (product['denominacion'] ?? 'Producto destacado').toString();
    final precioNum = product['precio_venta_cup'];
    final precio = precioNum is num
        ? '${precioNum.toStringAsFixed(2)} CUP'
        : 'Pregunta por el precio';
    final stockNum = product['stock'];
    final stock = stockNum is num ? stockNum.toString() : 'Disponible';

    final buffer = StringBuffer()
      ..writeln('🔥 Oferta especial en $storeName')
      ..writeln('🛍️ $nombre')
      ..writeln('💰 Precio: $precio')
      ..writeln('📦 Stock: $stock');

    if (catalogUrl != null && catalogUrl.trim().isNotEmpty) {
      buffer.writeln('🛒 Ver catálogo: $catalogUrl');
    }
    if (storePhone.trim().isNotEmpty) {
      buffer.writeln('📲 Pedidos por WhatsApp: $storePhone');
    }

    buffer.writeln('✨ ¡Responde este mensaje y te atendemos al instante!');
    return buffer.toString();
  }

  String? _getFirstImageUrl(Map<String, dynamic> product) {
    final url = (product['imagen'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    return url;
  }

  Future<void> _shareProductOnWhatsapp(Map<String, dynamic> product) async {
    try {
      final group = await _resolveWhatsappGroup();
      if (group == null) return;
      await _sendProductToWhatsappGroup(product, groupId: group['group_id']!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enviado a ${group['name'] ?? 'grupo de WhatsApp'}'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar el producto: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _shareMultipleOnWhatsapp(
    List<Map<String, dynamic>> products,
  ) async {
    final group = await _resolveWhatsappGroup();
    if (group == null) return;

    final failures = <String>[];
    for (final product in products) {
      try {
        await _sendProductToWhatsappGroup(product, groupId: group['group_id']!);
      } catch (_) {
        failures.add((product['denominacion'] ?? 'Producto').toString());
      }
    }

    if (!mounted) return;
    if (failures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Productos enviados a ${group['name'] ?? 'WhatsApp'}'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fallaron ${failures.length} envíos. Revisa la conexión o el grupo.',
          ),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _sendProductToWhatsappGroup(
    Map<String, dynamic> product, {
    required String groupId,
  }) async {
    final message = _buildWhatsappMessage(product);
    final imageUrl = _getFirstImageUrl(product);
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      await _whapiService.sendImageMessage(
        to: groupId,
        caption: message,
        mediaUrl: imageUrl,
      );
    } else {
      await _whapiService.sendTextMessage(to: groupId, body: message);
    }
  }

  Future<Map<String, String>?> _resolveWhatsappGroup() async {
    final storeId = _getSelectedStoreId();
    if (storeId == null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una tienda para compartir'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return null;
    }

    final savedGroup = await _userPrefs.getWhatsappGroupForStore(storeId);
    if (savedGroup != null) {
      final useSaved = await _showSavedGroupDialog(savedGroup);
      if (useSaved == true) return savedGroup;
      if (useSaved == false) {
        return await _showGroupPicker(storeId: storeId);
      }
      return null;
    }

    return await _showGroupPicker(storeId: storeId);
  }

  Future<bool?> _showSavedGroupDialog(Map<String, String> group) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Grupo de WhatsApp guardado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group['name'] ?? 'Grupo WhatsApp',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                group['group_id'] ?? '',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cambiar grupo'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Usar guardado'),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, String>?> _showGroupPicker({required int storeId}) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Selecciona el grupo de WhatsApp'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Registrar con enlace de invitación'),
                subtitle: const Text('Obligatorio para nuevos grupos'),
                onTap: () => Navigator.of(context).pop('invite'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.groups_2_outlined),
                title: const Text('Elegir de mis grupos'),
                subtitle: const Text('Usa un grupo existente del WhatsApp'),
                onTap: () => Navigator.of(context).pop('list'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (action == 'invite') {
      return await _showInviteGroupDialog(storeId: storeId);
    }
    if (action == 'list') {
      return await _showGroupListDialog(storeId: storeId);
    }
    return null;
  }

  Future<Map<String, String>?> _showInviteGroupDialog({
    required int storeId,
  }) async {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        final inviteController = TextEditingController();
        final nameController = TextEditingController();
        String? errorText;
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Registrar grupo por invitación'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: inviteController,
                      decoration: InputDecoration(
                        labelText: 'Enlace de invitación',
                        hintText: 'https://chat.whatsapp.com/...',
                        prefixIcon: const Icon(Icons.link_outlined),
                        errorText: errorText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre para guardar (opcional)',
                        prefixIcon: Icon(Icons.bookmark_outline),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Este enlace es obligatorio para registrar el grupo en el sistema.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final inviteRaw = inviteController.text.trim();
                          final inviteCode = _extractInviteCode(inviteRaw);
                          if (inviteCode == null || inviteCode.isEmpty) {
                            setStateDialog(() {
                              errorText =
                                  'Ingresa un enlace válido de invitación';
                            });
                            return;
                          }
                          setStateDialog(() {
                            errorText = null;
                            isSubmitting = true;
                          });
                          try {
                            final groupId = await _whapiService
                                .acceptGroupInvite(inviteCode);
                            final groupName = nameController.text.trim().isEmpty
                                ? 'Grupo WhatsApp'
                                : nameController.text.trim();
                            await _userPrefs.saveWhatsappGroupForStore(
                              storeId: storeId,
                              groupId: groupId,
                              name: groupName,
                              inviteCode: inviteCode,
                            );
                            if (!context.mounted) return;
                            Navigator.of(context).pop({
                              'group_id': groupId,
                              'name': groupName,
                              'invite_code': inviteCode,
                            });
                          } catch (e) {
                            setStateDialog(() {
                              errorText = e.toString();
                              isSubmitting = false;
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Registrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>?> _showGroupListDialog({
    required int storeId,
  }) async {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        Map<String, String>? selectedGroup;
        Future<List<Map<String, dynamic>>>? groupsFuture;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            groupsFuture ??= _whapiService.getGroups(count: 100);
            return AlertDialog(
              title: const Text('Selecciona un grupo'),
              content: SizedBox(
                width: double.maxFinite,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: groupsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No se pudieron cargar los grupos: ${snapshot.error}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () {
                              setStateDialog(() {
                                groupsFuture = _whapiService.getGroups(
                                  count: 100,
                                );
                              });
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      );
                    }

                    final groups = snapshot.data ?? [];
                    if (groups.isEmpty) {
                      return const Text(
                        'No se encontraron grupos en tu WhatsApp.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        final groupId = group['id']?.toString() ?? '';
                        final groupName =
                            group['name']?.toString() ?? 'Grupo WhatsApp';
                        final inviteCode = group['invite_code']?.toString();
                        return RadioListTile<String>(
                          title: Text(groupName),
                          subtitle: Text(groupId),
                          value: groupId,
                          groupValue: selectedGroup?['group_id'],
                          onChanged: (value) {
                            if (value == null) return;
                            setStateDialog(() {
                              selectedGroup = {
                                'group_id': groupId,
                                'name': groupName,
                                if (inviteCode != null &&
                                    inviteCode.trim().isNotEmpty)
                                  'invite_code': inviteCode,
                              };
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: selectedGroup == null
                      ? null
                      : () async {
                          final group = selectedGroup!;
                          await _userPrefs.saveWhatsappGroupForStore(
                            storeId: storeId,
                            groupId: group['group_id']!,
                            name: group['name'] ?? 'Grupo WhatsApp',
                            inviteCode: group['invite_code'],
                          );
                          if (!context.mounted) return;
                          Navigator.of(context).pop(group);
                        },
                  child: const Text('Usar grupo'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String? _extractInviteCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }
    return trimmed;
  }

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) _selectedProductIds.clear();
    });
  }

  void _toggleSelectProduct(int productId) {
    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
      } else {
        _selectedProductIds.add(productId);
      }
    });
  }

  Future<void> _shareSelectedProducts() async {
    final products = _products.where((p) {
      final idRaw = p['id'];
      final pid = idRaw is int ? idRaw : (idRaw is num ? idRaw.toInt() : null);
      return pid != null && _selectedProductIds.contains(pid);
    }).toList();
    if (products.isEmpty) return;

    await _shareMultipleOnWhatsapp(products);
  }

  @override
  void dispose() {
    _denominacionController.dispose();
    _direccionController.dispose();
    _phoneController.dispose();
    _paisController.dispose();
    _estadoController.dispose();
    _nombrePaisController.dispose();
    _nombreEstadoController.dispose();
    _whapiService.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    final selectedStoreIdBefore = _getSelectedStoreId();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uuid = await _sessionService.getUserId();
      if (uuid == null) {
        setState(() {
          _isLoading = false;
          _stores = [];
        });
        return;
      }

      final storeIds = await _storeService.getManagedStoreIds(uuid: uuid);
      final stores = await _storeService.getStoresByIds(storeIds);

      var newSelectedIndex = 0;
      if (selectedStoreIdBefore != null) {
        final idx = stores.indexWhere((s) {
          final id = s['id'];
          final sid = id is int ? id : (id is num ? id.toInt() : null);
          return sid == selectedStoreIdBefore;
        });
        if (idx >= 0) newSelectedIndex = idx;
      }

      setState(() {
        _stores = stores;
        _selectedStoreIndex = newSelectedIndex;
        _isLoading = false;
      });

      await _loadProductsForSelectedStore();
      await _loadSubscriptionForSelectedStore();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error cargando tu tienda: $e';
      });
    }
  }

  Future<void> _loadSubscriptionForSelectedStore() async {
    final storeId = _getSelectedStoreId();
    if (storeId == null) {
      if (!mounted) return;
      setState(() {
        _isSubscriptionLoading = false;
        _subscriptionErrorMessage = null;
        _subscriptionCatalog = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubscriptionLoading = true;
      _subscriptionErrorMessage = null;
      _subscriptionCatalog = null;
    });

    try {
      final response = await _supabase
          .from('app_dat_suscripcion_catalogo')
          .select('id, created_at, tiempo_suscripcion, vencido')
          .eq('id_tienda', storeId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _isSubscriptionLoading = false;
        _subscriptionCatalog = response == null
            ? null
            : Map<String, dynamic>.from(response as Map);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubscriptionLoading = false;
        _subscriptionErrorMessage = 'Error cargando suscripción: $e';
        _subscriptionCatalog = null;
      });
    }
  }

  void _fillStoreFormFromData(Map<String, dynamic> store) {
    _denominacionController.text = (store['denominacion'] ?? '').toString();
    _direccionController.text = (store['direccion'] ?? '').toString();
    _phoneController.text = (store['phone'] ?? '').toString();

    _paisController.text = (store['pais'] ?? '').toString();
    _estadoController.text = (store['estado'] ?? '').toString();
    _nombrePaisController.text = (store['nombre_pais'] ?? '').toString();
    _nombreEstadoController.text = (store['nombre_estado'] ?? '').toString();

    final ubicacion = (store['ubicacion'] ?? '').toString();
    if (ubicacion.contains(',')) {
      final parts = ubicacion.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          _selectedLocation = LatLng(lat, lng);
        }
      }
    }

    final imageUrl = (store['imagen_url'] ?? '').toString().trim();
    _imageUrl = imageUrl.isEmpty ? null : imageUrl;

    final horaAperturaStr = (store['hora_apertura'] ?? '').toString();
    final horaCierreStr = (store['hora_cierre'] ?? '').toString();

    TimeOfDay? parseTime(String v) {
      final parts = v.split(':');
      if (parts.length < 2) return null;
      final hh = int.tryParse(parts[0]);
      final mm = int.tryParse(parts[1]);
      if (hh == null || mm == null) return null;
      return TimeOfDay(hour: hh, minute: mm);
    }

    final open = parseTime(horaAperturaStr);
    final close = parseTime(horaCierreStr);
    if (open != null) _horaApertura = open;
    if (close != null) _horaCierre = close;
  }

  Future<void> _updateStore({required int storeId}) async {
    if (!(_editFormKey.currentState?.validate() ?? false)) return;

    if (_selectedLocation == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la ubicación en el mapa'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    if (_imageUrl == null || _imageUrl!.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sube una imagen para la tienda'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final lat = _selectedLocation!.latitude;
      final lng = _selectedLocation!.longitude;
      final ubicacion = '${lat.toStringAsFixed(7)},${lng.toStringAsFixed(7)}';

      await _storeService.updateStore(
        storeId: storeId,
        denominacion: _denominacionController.text.trim(),
        direccion: _direccionController.text.trim(),
        ubicacion: ubicacion,
        imagenUrl: _imageUrl!.trim(),
        phone: _phoneController.text.trim(),
        pais: _paisController.text.trim(),
        estado: _estadoController.text.trim(),
        nombrePais: _nombrePaisController.text.trim(),
        nombreEstado: _nombreEstadoController.text.trim(),
        horaApertura: _formatTime(_horaApertura),
        horaCierre: _formatTime(_horaCierre),
        latitude: lat,
        longitude: lng,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tienda actualizada correctamente'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      await _loadStores();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error actualizando tienda: $e';
      });
    }
  }

  Future<void> _openEditStoreSheet({
    required Map<String, dynamic> store,
  }) async {
    final storeIdRaw = store['id'];
    final int? storeId = storeIdRaw is int
        ? storeIdRaw
        : (storeIdRaw is num ? storeIdRaw.toInt() : null);
    if (storeId == null) return;

    setState(() {
      _fillStoreFormFromData(store);
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isDark ? AppTheme.darkCardBackground : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: AppTheme.paddingM,
              right: AppTheme.paddingM,
              top: AppTheme.paddingM,
              bottom: bottomInset + AppTheme.paddingM,
            ),
            child: Form(
              key: _editFormKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Editar tienda',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _denominacionController,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'La denominación es obligatoria';
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Denominación',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _direccionController,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'La dirección es obligatoria';
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'El teléfono es obligatorio';
                        return null;
                      },
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono (WhatsApp)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildLocationCard(),
                    const SizedBox(height: 14),
                    _buildImageCard(),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _paisController,
                            maxLength: 2,
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.length != 2) {
                                return 'Código país (2 letras)';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'País (ISO)',
                              prefixIcon: Icon(Icons.flag_outlined),
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _estadoController,
                            maxLength: 10,
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'Código estado';
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'Estado (código)',
                              prefixIcon: Icon(Icons.map_outlined),
                              counterText: '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nombrePaisController,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Nombre del país';
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Nombre país',
                        prefixIcon: Icon(Icons.public_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nombreEstadoController,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Nombre del estado';
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Nombre estado',
                        prefixIcon: Icon(Icons.map_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildScheduleRow(),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isUploadingImage || _isLoading
                                ? null
                                : () => _updateStore(storeId: storeId),
                            style: FilledButton.styleFrom(
                              backgroundColor: accentColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Guardar',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int? _getSelectedStoreId() {
    if (_stores.isEmpty) return null;
    if (_selectedStoreIndex < 0 || _selectedStoreIndex >= _stores.length) {
      return null;
    }
    final store = _stores[_selectedStoreIndex];
    final id = store['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return null;
  }

  bool _isSelectedStoreValidated() {
    if (_stores.isEmpty) return false;
    if (_selectedStoreIndex < 0 || _selectedStoreIndex >= _stores.length) {
      return false;
    }
    return _stores[_selectedStoreIndex]['validada'] == true;
  }

  bool _isSelectedStoreVisibleInCatalog() {
    if (_stores.isEmpty) return false;
    if (_selectedStoreIndex < 0 || _selectedStoreIndex >= _stores.length) {
      return false;
    }
    return _stores[_selectedStoreIndex]['mostrar_en_catalogo'] == true;
  }

  bool _isSelectedStoreEffectivelyActive() {
    return _isSelectedStoreValidated() && _isSelectedStoreVisibleInCatalog();
  }

  Future<void> _loadProductsForSelectedStore() async {
    final storeId = _getSelectedStoreId();
    if (storeId == null) {
      if (!mounted) return;
      setState(() {
        _products = [];
        _isProductsLoading = false;
        _productsErrorMessage = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isProductsLoading = true;
        _productsErrorMessage = null;
      });
    }

    try {
      final products = await _storeService.getStoreProductsOverview(
        storeId: storeId,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _isProductsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _products = [];
        _isProductsLoading = false;
        _productsErrorMessage = 'Error cargando productos: $e';
      });
    }
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) =>
            StoreLocationPickerScreen(initialLocation: _selectedLocation),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedLocation = result;
    });

    await _tryFillFromCoordinates(result);
  }

  Future<void> _tryFillFromCoordinates(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isEmpty) return;

      final p = placemarks.first;

      final iso = (p.isoCountryCode ?? '').trim();
      final country = (p.country ?? '').trim();
      final admin = (p.administrativeArea ?? '').trim();

      final street = (p.street ?? '').trim();
      final subLocality = (p.subLocality ?? '').trim();
      final locality = (p.locality ?? '').trim();
      final subAdmin = (p.subAdministrativeArea ?? '').trim();

      final addressParts = <String>[
        if (street.isNotEmpty) street,
        if (subLocality.isNotEmpty) subLocality,
        if (locality.isNotEmpty) locality,
        if (subAdmin.isNotEmpty) subAdmin,
        if (admin.isNotEmpty) admin,
        if (country.isNotEmpty) country,
      ];
      final address = addressParts.join(', ');

      if (_direccionController.text.trim().isEmpty && address.isNotEmpty) {
        _direccionController.text = address;
      }

      if (_paisController.text.trim().isEmpty && iso.length == 2) {
        _paisController.text = iso;
      }
      if (_nombrePaisController.text.trim().isEmpty && country.isNotEmpty) {
        _nombrePaisController.text = country;
      }
      if (_nombreEstadoController.text.trim().isEmpty && admin.isNotEmpty) {
        _nombreEstadoController.text = admin;
      }
    } catch (_) {}
  }

  String _formatTime(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  Future<void> _pickTime({required bool isOpen}) async {
    final initial = isOpen ? _horaApertura : _horaCierre;
    final picked = await showTimePicker(context: context, initialTime: initial);

    if (picked == null || !mounted) return;

    setState(() {
      if (isOpen) {
        _horaApertura = picked;
      } else {
        _horaCierre = picked;
      }
    });
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
      final url = await _uploadStoreImage(bytes);

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

  Future<String> _uploadStoreImage(Uint8List bytes) async {
    final fileName = 'store_${DateTime.now().millisecondsSinceEpoch}.jpg';

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

  Future<void> _createStore() async {
    if (!(_createFormKey.currentState?.validate() ?? false)) return;

    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la ubicación en el mapa'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    if (_imageUrl == null || _imageUrl!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sube una imagen para la tienda'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    final uuid = await _sessionService.getUserId();
    if (uuid == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final lat = _selectedLocation!.latitude;
      final lng = _selectedLocation!.longitude;
      final ubicacion = '${lat.toStringAsFixed(7)},${lng.toStringAsFixed(7)}';

      final tienda = await _storeService.createStore(
        denominacion: _denominacionController.text.trim(),
        direccion: _direccionController.text.trim(),
        ubicacion: ubicacion,
        imagenUrl: _imageUrl!.trim(),
        phone: _phoneController.text.trim(),
        pais: _paisController.text.trim(),
        estado: _estadoController.text.trim(),
        nombrePais: _nombrePaisController.text.trim(),
        nombreEstado: _nombreEstadoController.text.trim(),
        horaApertura: _formatTime(_horaApertura),
        horaCierre: _formatTime(_horaCierre),
        latitude: lat,
        longitude: lng,
      );

      int? storeIdInt;
      final storeId = tienda['id'];
      if (storeId is int) {
        storeIdInt = storeId;
      } else if (storeId is num) {
        storeIdInt = storeId.toInt();
      }

      if (storeIdInt != null) {
        await _storeService.ensureGerenteLink(uuid: uuid, storeId: storeIdInt);
        await _storeService.createDefaultSubscription(storeIdInt, uuid);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tienda creada. Queda en validación.'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      await _loadStores();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error creando tienda: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mi tienda'),
          backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.paddingL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store_mall_directory_outlined, size: 56, color: textSecondary),
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondary),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _loadStores,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                  ),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_stores.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Administrar mi tienda'),
          backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: _buildCreateStore(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: _buildStoreSelector(),
          backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.primaryColor,
          foregroundColor: Colors.white,
          bottom: TabBar(
            labelColor: isDark ? AppTheme.darkAccentColor : Colors.white,
            unselectedLabelColor: isDark ? AppTheme.darkTextSecondary : const Color(0xCCFFFFFF),
            indicatorColor: isDark ? AppTheme.darkAccentColor : Colors.white,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Tienda'),
              Tab(text: 'Productos'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildStoreTab(), _buildProductsTab()]),
      ),
    );
  }

  Widget _buildStoreSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_stores.length <= 1) {
      return Text((_stores.first['denominacion'] ?? 'Mi tienda').toString());
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: _selectedStoreIndex,
        dropdownColor: isDark ? AppTheme.darkCardBackground : AppTheme.primaryColor,
        iconEnabledColor: Colors.white,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        items: List.generate(_stores.length, (idx) {
          final store = _stores[idx];
          return DropdownMenuItem<int>(
            value: idx,
            child: Text((store['denominacion'] ?? 'Tienda').toString()),
          );
        }),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _selectedStoreIndex = v);
          _loadProductsForSelectedStore();
          _loadSubscriptionForSelectedStore();
        },
      ),
    );
  }

  Widget _buildStoreTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppTheme.getCardColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);
    final dividerColor = AppTheme.getDividerColor(context);

    final store = _stores[_selectedStoreIndex];

    final storeIdRaw = store['id'];
    final int? storeId = storeIdRaw is int
        ? storeIdRaw
        : (storeIdRaw is num ? storeIdRaw.toInt() : null);

    final imageUrl = (store['imagen_url'] ?? '').toString().trim();
    final denominacion = (store['denominacion'] ?? 'Tienda').toString();
    final direccion = (store['direccion'] ?? '').toString();
    final phone = (store['phone'] ?? '').toString();
    final pais = (store['nombre_pais'] ?? store['pais'] ?? '').toString();
    final estado = (store['nombre_estado'] ?? store['estado'] ?? '').toString();
    final horaApertura = (store['hora_apertura'] ?? '').toString();
    final horaCierre = (store['hora_cierre'] ?? '').toString();
    final isValidated = store['validada'] == true;
    final isVisibleInCatalog = store['mostrar_en_catalogo'] == true;
    final effectiveVisible = isValidated && isVisibleInCatalog;
    final catalogUrl = storeId == null
        ? null
        : 'https://inventtia-catalogo.netlify.app/open.html?${Uri(queryParameters: {'storeId': storeId.toString()}).query}';

    return RefreshIndicator(
      onRefresh: _loadStores,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTheme.paddingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    child: SizedBox(
                      height: 190,
                      child: imageUrl.isNotEmpty
                          ? SupabaseImage(
                              imageUrl: imageUrl,
                              width: double.infinity,
                              height: 190,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.store_rounded, size: 48),
                              ),
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.paddingM),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                denominacion,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _openEditStoreSheet(store: store),
                              icon: Icon(Icons.edit_outlined, color: accentColor),
                              tooltip: 'Editar',
                            ),
                            _buildValidationChip(isValidated),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (direccion.isNotEmpty)
                          _infoRow(
                            icon: Icons.location_on_outlined,
                            text: direccion,
                          ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _infoRow(icon: Icons.phone_outlined, text: phone),
                        ],
                        if (pais.isNotEmpty || estado.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _infoRow(
                            icon: Icons.public,
                            text: [
                              if (estado.isNotEmpty) estado,
                              if (pais.isNotEmpty) pais,
                            ].join(' · '),
                          ),
                        ],
                        if (horaApertura.isNotEmpty ||
                            horaCierre.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _infoRow(
                            icon: Icons.schedule,
                            text: 'Horario: $horaApertura - $horaCierre',
                          ),
                        ],
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: dividerColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                effectiveVisible
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: effectiveVisible
                                    ? accentColor
                                    : textSecondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  !isValidated
                                      ? 'Visibilidad bloqueada (en validación)'
                                      : (effectiveVisible
                                            ? 'Visible en el catálogo'
                                            : 'Oculta en el catálogo'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                              Switch(
                                value: isVisibleInCatalog,
                                onChanged: (!isValidated || storeId == null)
                                    ? null
                                    : (value) async {
                                        try {
                                          await _storeService
                                              .updateMostrarEnCatalogo(
                                                storeId: storeId,
                                                mostrarEnCatalogo: value,
                                              );
                                          if (!mounted) return;
                                          setState(() {
                                            final updated =
                                                Map<String, dynamic>.from(
                                                  store,
                                                );
                                            updated['mostrar_en_catalogo'] =
                                                value;
                                            _stores[_selectedStoreIndex] =
                                                updated;
                                          });
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'No se pudo actualizar visibilidad: $e',
                                              ),
                                              backgroundColor:
                                                  AppTheme.errorColor,
                                            ),
                                          );
                                        }
                                      },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isValidated
                                ? AppTheme.successColor.withOpacity(isDark ? 0.15 : 0.08)
                                : AppTheme.warningColor.withOpacity(isDark ? 0.15 : 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isValidated
                                    ? Icons.check_circle_outline
                                    : Icons.hourglass_bottom_rounded,
                                color: isValidated
                                    ? AppTheme.successColor
                                    : AppTheme.warningColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isValidated
                                      ? 'Tu tienda fue validada. Puedes decidir si mostrarla en el catálogo.'
                                      : 'Tu tienda está en validación. Mientras tanto no aparecerá en el catálogo y no podrás cambiar su visibilidad.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildSubscriptionCard(isDark: isDark, textPrimary: textPrimary, cardColor: cardColor, dividerColor: dividerColor),
                        const SizedBox(height: 12),
                        _buildCatalogQrCard(
                          catalogUrl: catalogUrl,
                          storeName: denominacion,
                          isStoreEffectivelyActive: effectiveVisible,
                          isDark: isDark,
                          textPrimary: textPrimary,
                          cardColor: cardColor,
                          dividerColor: dividerColor,
                          accentColor: accentColor,
                        ),
                      ],
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

  Widget _buildSubscriptionCard({
    required bool isDark,
    required Color textPrimary,
    required Color cardColor,
    required Color dividerColor,
  }) {
    final sub = _subscriptionCatalog;

    if (_isSubscriptionLoading) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dividerColor),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Cargando suscripción del catálogo...',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_subscriptionErrorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.errorColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _subscriptionErrorMessage!,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ),
            IconButton(
              onPressed: _loadSubscriptionForSelectedStore,
              icon: const Icon(Icons.refresh),
              tooltip: 'Reintentar',
            ),
          ],
        ),
      );
    }

    if (sub == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dividerColor),
        ),
        child: Row(
          children: [
            Icon(Icons.subscriptions_outlined, color: AppTheme.getTextSecondaryColor(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Suscripción del catálogo: no se ha creado aún.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final tiempoSuscripcion = (sub['tiempo_suscripcion'] is num)
        ? (sub['tiempo_suscripcion'] as num).toDouble()
        : 0.0;
    final createdAtRaw = sub['created_at']?.toString();
    final createdAt = createdAtRaw == null
        ? null
        : DateTime.tryParse(createdAtRaw);
    final now = DateTime.now();
    final elapsedDays = createdAt == null
        ? 0.0
        : now.difference(createdAt).inSeconds / (60 * 60 * 24);
    final remainingDays = math.max(0.0, tiempoSuscripcion - elapsedDays);
    final isExpired = (sub['vencido'] == true) || remainingDays <= 0.0;

    final statusColor = isExpired
        ? AppTheme.warningColor
        : AppTheme.successColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.subscriptions_outlined, color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suscripción del catálogo',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isExpired
                      ? 'Tiempo disponible: 0 días'
                      : 'Tiempo disponible: ${remainingDays.toStringAsFixed(1)} días',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogQrCard({
    required String? catalogUrl,
    required String storeName,
    required bool isStoreEffectivelyActive,
    required bool isDark,
    required Color textPrimary,
    required Color cardColor,
    required Color dividerColor,
    required Color accentColor,
  }) {
    final canShowQr = catalogUrl != null && catalogUrl.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'QR del catálogo',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: canShowQr
                    ? () {
                        final url = catalogUrl.trim();
                        showDialog<void>(
                          context: context,
                          builder: (context) {
                            return Dialog(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'QR del catálogo',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        storeName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Center(
                                        child: QrImageView(
                                          data: url,
                                          size: 280,
                                          backgroundColor: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SelectableText(
                                        url,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: const Text('Cerrar'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: FilledButton(
                                              onPressed: () async {
                                                await Clipboard.setData(
                                                  ClipboardData(text: url),
                                                );
                                                if (!context.mounted) return;
                                                Navigator.of(context).pop();
                                                ScaffoldMessenger.of(
                                                  this.context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Enlace copiado',
                                                    ),
                                                    backgroundColor:
                                                        AppTheme.successColor,
                                                  ),
                                                );
                                              },
                                              child: const Text(
                                                'Copiar enlace',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }
                    : null,
                icon: const Icon(Icons.open_in_full_rounded),
                tooltip: 'Ampliar',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!isStoreEffectivelyActive)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withOpacity(isDark ? 0.15 : 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.warningColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tu tienda no está activa en el catálogo. El QR abrirá el enlace, pero puede que la tienda no sea visible para los clientes.',
                      style: TextStyle(
                        color: textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (canShowQr)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSurfaceColor : AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: dividerColor),
                  ),
                  child: QrImageView(
                    data: catalogUrl,
                    size: 120,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Escanéalo para abrir tu tienda en el catálogo.',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: catalogUrl),
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Enlace copiado'),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copiar enlace'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          final uri = Uri.tryParse(catalogUrl);
                          if (uri == null) return;
                          try {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Abrir catálogo'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await CatalogQrPrintService().printQr(
                            title: storeName,
                            data: catalogUrl,
                          );
                          if (!mounted) return;
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Impresión disponible solo en web',
                                ),
                                backgroundColor: AppTheme.warningColor,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Imprimir QR'),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Text(
              'Selecciona una tienda para generar el QR.',
              style: TextStyle(
                color: AppTheme.getTextSecondaryColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppTheme.getCardColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);
    final dividerColor = AppTheme.getDividerColor(context);

    final storeId = _getSelectedStoreId();
    final isStoreValidated = _isSelectedStoreValidated();
    final isStoreEffectiveActive = _isSelectedStoreEffectivelyActive();

    if (storeId == null) {
      return Center(child: Text('No hay tienda seleccionada', style: TextStyle(color: textPrimary)));
    }

    if (_productsErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.paddingL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 56, color: textSecondary),
              const SizedBox(height: 10),
              Text(
                _productsErrorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _loadProductsForSelectedStore,
                style: FilledButton.styleFrom(backgroundColor: accentColor),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadStores();
        await _loadProductsForSelectedStore();
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppTheme.paddingM),
        itemCount: _products.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isStoreValidated
                        ? AppTheme.successColor.withOpacity(isDark ? 0.15 : 0.08)
                        : AppTheme.warningColor.withOpacity(isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isStoreValidated
                            ? Icons.check_circle_outline
                            : Icons.hourglass_bottom_rounded,
                        color: isStoreValidated
                            ? AppTheme.successColor
                            : AppTheme.warningColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isStoreValidated
                              ? (isStoreEffectiveActive
                                    ? 'Tu tienda está activa en el catálogo.'
                                    : 'Tu tienda está validada pero no está visible en el catálogo. Activa la tienda primero para mostrar productos.')
                              : 'Tu tienda está en validación. Mientras tanto los productos no podrán mostrarse en el catálogo.',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isProductsLoading
                            ? null
                            : () async {
                                final created = await Navigator.of(context)
                                    .push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => CreateProductScreen(
                                          storeId: storeId,
                                          storeAllowsCatalog:
                                              isStoreEffectiveActive,
                                        ),
                                      ),
                                    );

                                if (created == true && mounted) {
                                  await _loadProductsForSelectedStore();
                                }
                              },
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text(
                          'Nuevo producto',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: _isMultiSelectMode
                          ? 'Cancelar selección múltiple'
                          : 'Seleccionar múltiples para compartir',
                      onPressed: _toggleMultiSelect,
                      icon: Icon(
                        _isMultiSelectMode
                            ? Icons.checklist_rtl
                            : Icons.library_add_check,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Compartir seleccionados',
                      onPressed:
                          !_isMultiSelectMode ||
                              _selectedProductIds.isEmpty ||
                              _isProductsLoading
                          ? null
                          : _shareSelectedProducts,
                      icon: const Icon(Icons.campaign),
                    ),
                  ],
                ),
                if (_isMultiSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Row(
                      children: [
                        Chip(
                          label: Text(
                            '${_selectedProductIds.length} seleccionados',
                            style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                          ),
                          avatar: const Icon(
                            Icons.check_circle,
                            color: AppTheme.successColor,
                            size: 18,
                          ),
                          backgroundColor: AppTheme.successColor.withOpacity(
                            isDark ? 0.2 : 0.12,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                if (_isProductsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!_isProductsLoading && _products.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: dividerColor),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 44, color: textSecondary),
                        const SizedBox(height: 10),
                        Text(
                          'Aún no tienes productos.',
                          style: TextStyle(fontWeight: FontWeight.w800, color: textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Crea tu primer producto para empezar a vender en el catálogo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textSecondary),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }

          final product = _products[index - 1];

          final idRaw = product['id'];
          final productId = idRaw is int
              ? idRaw
              : (idRaw is num ? idRaw.toInt() : null);
          final nombre = (product['denominacion'] ?? 'Producto').toString();
          final imagen = (product['imagen'] ?? '').toString().trim();
          final stock = (product['stock'] is num)
              ? (product['stock'] as num)
              : 0;
          final precio = (product['precio_venta_cup'] is num)
              ? (product['precio_venta_cup'] as num)
              : null;

          final isProductVisible = product['mostrar_en_catalogo'] == true;
          final canToggleVisibility =
              isStoreEffectiveActive && productId != null;
          final isSelected =
              productId != null &&
              _isMultiSelectMode &&
              _selectedProductIds.contains(productId);

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              onTap: productId == null
                  ? null
                  : () async {
                      if (_isMultiSelectMode) {
                        _toggleSelectProduct(productId);
                        return;
                      }
                      final updated = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ProductManagementDetailScreen(
                            productId: productId,
                            storeId: storeId,
                            storeAllowsCatalog: isStoreEffectiveActive,
                          ),
                        ),
                      );

                      if (updated == true && mounted) {
                        await _loadProductsForSelectedStore();
                      }
                    },
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  if (_isMultiSelectMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Checkbox(
                        value: isSelected,
                        onChanged: productId == null
                            ? null
                            : (_) => _toggleSelectProduct(productId),
                      ),
                    ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: imagen.isNotEmpty
                          ? SupabaseImage(
                              imageUrl: imagen,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: isDark ? AppTheme.darkSurfaceColor : Colors.grey[200],
                              child: Icon(Icons.image_outlined, color: textSecondary),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Stock: ${stock.toString()}',
                          style: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          precio == null
                              ? 'Precio: --'
                              : 'Precio: ${precio.toStringAsFixed(2)} CUP',
                          style: TextStyle(
                            color: textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Compartir en WhatsApp',
                    onPressed: () async {
                      await _shareProductOnWhatsapp(product);
                    },
                    icon: Icon(Icons.campaign_outlined, color: accentColor),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: isProductVisible && isStoreEffectiveActive,
                    onChanged: !canToggleVisibility
                        ? null
                        : (value) async {
                            try {
                              await _storeService
                                  .updateProductMostrarEnCatalogo(
                                    productId: productId,
                                    mostrarEnCatalogo: value,
                                  );
                              if (!mounted) return;
                              setState(() {
                                final updated = Map<String, dynamic>.from(
                                  _products[index - 1],
                                );
                                updated['mostrar_en_catalogo'] = value;
                                _products[index - 1] = updated;
                              });
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'No se pudo actualizar el producto: $e',
                                  ),
                                  backgroundColor: AppTheme.errorColor,
                                ),
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildValidationChip(bool isValidated) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isValidated
            ? AppTheme.successColor.withOpacity(isDark ? 0.2 : 0.12)
            : AppTheme.warningColor.withOpacity(isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isValidated ? 'Validada' : 'En validación',
        style: TextStyle(
          color: isValidated ? AppTheme.successColor : AppTheme.warningColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _infoRow({required IconData icon, required String text}) {
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateStore() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppTheme.getCardColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      child: Form(
        key: _createFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.paddingM),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Crea tu tienda',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warningColor.withOpacity(isDark ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'En validación',
                          style: TextStyle(
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _denominacionController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'La denominación es obligatoria';
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Denominación',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _direccionController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'La dirección es obligatoria';
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Dirección',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'El teléfono es obligatorio';
                      return null;
                    },
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (WhatsApp)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildLocationCard(),
                  const SizedBox(height: 14),
                  _buildImageCard(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _paisController,
                          maxLength: 2,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.length != 2) {
                              return 'Código país (2 letras)';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'País (ISO)',
                            prefixIcon: Icon(Icons.flag_outlined),
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _estadoController,
                          maxLength: 10,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return 'Código estado';
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Estado (código)',
                            prefixIcon: Icon(Icons.map_outlined),
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nombrePaisController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Nombre del país';
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Nombre país',
                      prefixIcon: Icon(Icons.public_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nombreEstadoController,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Nombre del estado';
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Nombre estado',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildScheduleRow(),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isUploadingImage || _isLoading
                        ? null
                        : _createStore,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Crear tienda',
                      style: TextStyle(fontWeight: FontWeight.w800),
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

  Widget _buildLocationCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final dividerColor = AppTheme.getDividerColor(context);

    final text = _selectedLocation == null
        ? 'Seleccionar en mapa'
        : '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}';

    return InkWell(
      onTap: _pickLocation,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurfaceColor : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dividerColor),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              color: accentColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: textPrimary),
          ],
        ),
      ),
    );
  }

  Widget _buildImageCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final dividerColor = AppTheme.getDividerColor(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, color: accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Foto de la tienda',
                  style: TextStyle(fontWeight: FontWeight.w800, color: textPrimary),
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
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _isUploadingImage
                  ? Container(
                      color: isDark ? AppTheme.darkCardBackground : Colors.white,
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : (_imageUrl != null && _imageUrl!.isNotEmpty)
                  ? SupabaseImage(
                      imageUrl: _imageUrl!,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: isDark ? AppTheme.darkCardBackground : Colors.white,
                      child: Center(
                        child: Icon(Icons.storefront_outlined, size: 42, color: textSecondary),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final dividerColor = AppTheme.getDividerColor(context);

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _pickTime(isOpen: true),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: accentColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Apertura: ${_horaApertura.format(context)}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => _pickTime(isOpen: false),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceColor : AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: accentColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cierre: ${_horaCierre.format(context)}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
