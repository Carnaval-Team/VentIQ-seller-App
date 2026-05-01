import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/inventory_service.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/conversion_info_widget.dart';
import '../widgets/product_selector_widget.dart';
import '../widgets/location_selector_widget.dart';
import '../services/product_search_service.dart';
import '../utils/presentation_converter.dart';

class InventoryExtractionWebScreen extends StatefulWidget {
  const InventoryExtractionWebScreen({super.key});

  @override
  State<InventoryExtractionWebScreen> createState() =>
      _InventoryExtractionWebScreenState();
}

class _InventoryExtractionWebScreenState
    extends State<InventoryExtractionWebScreen> {
  final _formKey = GlobalKey<FormState>();
  final _autorizadoPorController = TextEditingController();
  final _observacionesController = TextEditingController();

  static String _lastAutorizadoPor = '';
  static String _lastObservaciones = '';

  final List<Map<String, dynamic>> _selectedProducts = [];
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  WarehouseZone? _selectedSourceLocation;
  bool _isLoading = false;
  bool _isLoadingMotivos = true;

  static const Color _accent = AppColors.warning;

  @override
  void initState() {
    super.initState();
    _loadMotivoOptions();
    _autorizadoPorController.text = _lastAutorizadoPor;
    _observacionesController.text = _lastObservaciones;
  }

  @override
  void dispose() {
    _autorizadoPorController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _loadMotivoOptions() async {
    setState(() => _isLoadingMotivos = true);
    try {
      _motivoOptions = await InventoryService.getMotivoExtraccionOptions();
    } catch (e) {
      debugPrint('Error loading motivo options: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMotivos = false);
    }
  }

  void _savePersistedValues() {
    _lastAutorizadoPor = _autorizadoPorController.text;
    _lastObservaciones = _observacionesController.text;
  }

  void _addProductToExtraction(Map<String, dynamic> product) {
    if (_selectedSourceLocation == null) {
      _showSnack('Debe seleccionar una zona primero', AppColors.warning);
      return;
    }

    final productWithId = Map<String, dynamic>.from(product);
    if (productWithId['id'] == null && productWithId['id_producto'] != null) {
      productWithId['id'] = productWithId['id_producto'];
    }

    showDialog(
      context: context,
      builder: (context) => _ProductQuantityWebDialog(
        product: productWithId,
        sourceLocation: _selectedSourceLocation,
        onProductAdded: (productData) {
          setState(() => _selectedProducts.add(productData));
        },
      ),
    );
  }

  void _removeProductFromExtraction(int index) {
    setState(() => _selectedProducts.removeAt(index));
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _showExtractionConfirmation() async {
    if (_selectedSourceLocation == null) {
      _showSnack('Debe seleccionar una zona de origen', AppColors.error);
      return;
    }
    if (_selectedProducts.isEmpty) {
      _showSnack('Debe seleccionar al menos un producto', AppColors.error);
      return;
    }
    if (_selectedMotivo == null) {
      _showSnack('Debe seleccionar un motivo', AppColors.error);
      return;
    }
    if (_autorizadoPorController.text.trim().isEmpty) {
      _showSnack('Debe indicar quién autoriza la extracción', AppColors.error);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: _accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Confirmar Extracción',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _summaryRow(
                  Icons.location_on_outlined,
                  'Zona de origen',
                  _selectedSourceLocation?.name ?? 'No seleccionada',
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  Icons.assignment_outlined,
                  'Motivo',
                  _selectedMotivo?['denominacion'] ?? 'No seleccionado',
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  Icons.person_outline_rounded,
                  'Autorizado por',
                  _autorizadoPorController.text.trim().isEmpty
                      ? 'No especificado'
                      : _autorizadoPorController.text.trim(),
                ),
                const SizedBox(height: 16),
                Text(
                  'Productos a extraer (${_selectedProducts.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Column(
                      children: _selectedProducts.map((p) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['denominacion'] ??
                                          p['nombre_producto'] ??
                                          'Sin nombre',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if ((p['presentacion'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(
                                        '${p['presentacion']}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'x ${p['cantidad']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _accent,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Confirmar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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

    if (confirmed == true) {
      _submitExtraction();
    }
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitExtraction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    _savePersistedValues();

    try {
      final userPrefs = UserPreferencesService();
      final userUuid = await userPrefs.getUserId();
      final userData = await userPrefs.getUserData();
      final idTienda = userData['idTienda'] as int?;

      if (userUuid == null || idTienda == null) {
        throw Exception('No se encontró información del usuario o tienda');
      }

      final productos = _selectedProducts.map((product) {
        final idPresentacion = product['id_presentacion'];
        return {
          'id_producto': product['id_producto'],
          'id_variante': product['id_variante'],
          'id_opcion_variante': product['id_opcion_variante'],
          'id_ubicacion': product['id_ubicacion'],
          'id_presentacion': idPresentacion ?? 1,
          'cantidad': product['cantidad'],
          'precio_unitario': product['precio_unitario'],
          'sku_producto': product['sku_producto'],
          'sku_ubicacion': product['sku_ubicacion'],
        };
      }).toList();

      final result = await InventoryService.insertCompleteExtraction(
        autorizadoPor: _autorizadoPorController.text.trim(),
        estadoInicial: 1,
        idMotivoOperacion: _selectedMotivo!['id'],
        idTienda: idTienda,
        observaciones: _observacionesController.text.trim(),
        productos: productos,
        uuid: userUuid,
      );

      if (result['status'] != 'success') {
        throw Exception(result['message'] ?? 'Error desconocido');
      }

      final operationId = result['id_operacion'];
      if (operationId != null) {
        try {
          await InventoryService.completeOperation(
            idOperacion: operationId,
            comentario:
                'Extracción completada automáticamente - ${_observacionesController.text.trim()}',
            uuid: userUuid,
          );
        } catch (e) {
          debugPrint('⚠️ Error al completar operación: $e');
        }
      }

      if (mounted) {
        _showSnack('Extracción registrada exitosamente', AppColors.success);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error al registrar extracción: $e', AppColors.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =====================================================
  // BUILD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Extracción de Productos',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: (_isLoading || _selectedProducts.isEmpty)
                  ? null
                  : _showExtractionConfirmation,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accent,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_isLoading
                  ? 'Procesando...'
                  : 'Procesar (${_selectedProducts.length})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _accent,
                disabledBackgroundColor: Colors.white70,
                disabledForegroundColor: _accent,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
        ],
      ),
      endDrawer: const AdminDrawer(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderBanner(),
                  const SizedBox(height: 20),
                  _buildDetailsCard(),
                  const SizedBox(height: 20),
                  _buildLocationCard(),
                  const SizedBox(height: 20),
                  _buildProductSearchCard(),
                  const SizedBox(height: 20),
                  _buildSelectedProductsCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.outbox_rounded,
              color: _accent,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registro de Extracción',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Documenta la salida de productos del inventario indicando motivo, '
                  'autorización y zona de origen.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return _buildWebCard(
      title: 'Detalles de la Extracción',
      subtitle: 'Motivo, autorización y observaciones',
      icon: Icons.assignment_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoadingMotivos)
            _buildLoadingPlaceholder('Cargando motivos...')
          else
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedMotivo,
              isExpanded: true,
              decoration: _inputDecoration(
                label: 'Motivo *',
                hint: 'Selecciona el motivo de la extracción',
                prefixIcon: Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
              ),
              items: _motivoOptions.map((m) {
                return DropdownMenuItem(
                  value: m,
                  child: Text(
                    m['denominacion'] ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (m) => setState(() => _selectedMotivo = m),
              validator: (v) => v == null ? 'Campo requerido' : null,
            ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _autorizadoPorController,
            decoration: _inputDecoration(
              label: 'Autorizado por *',
              hint: 'Nombre del responsable',
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: Colors.grey.shade500,
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _observacionesController,
            decoration: _inputDecoration(
              label: 'Observaciones',
              hint: 'Información adicional (opcional)',
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return _buildWebCard(
      title: 'Zona de Origen',
      subtitle: _selectedSourceLocation != null
          ? 'Zona desde donde se extraerán los productos'
          : 'Selecciona la zona de origen',
      icon: Icons.warehouse_outlined,
      iconColor: AppColors.info,
      child: Theme(
        // Suprimir headers/labels duplicados internos del widget para integrar mejor
        data: Theme.of(context),
        child: LocationSelectorWidget(
          type: LocationSelectorType.single,
          title: 'Seleccionar Zona',
          subtitle: 'Desde donde se extraerán los productos',
          selectedLocation: _selectedSourceLocation,
          onLocationChanged: (location) {
            setState(() {
              _selectedSourceLocation = location;
              _selectedProducts.clear();
            });
          },
          validationMessage: _selectedSourceLocation == null
              ? 'Debe seleccionar una zona'
              : null,
        ),
      ),
    );
  }

  Widget _buildProductSearchCard() {
    final isEnabled = _selectedSourceLocation != null;
    return _buildWebCard(
      title: 'Agregar Productos',
      subtitle: isEnabled
          ? 'Buscando en ${_selectedSourceLocation!.name}'
          : 'Selecciona una zona primero',
      icon: Icons.search_rounded,
      child: !isEnabled
          ? _buildEmptyState(
              icon: Icons.warehouse_outlined,
              title: 'Sin zona seleccionada',
              description:
                  'Selecciona una zona en el panel anterior para buscar productos disponibles.',
            )
          : Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                height: 360,
                child: ProductSelectorWidget(
                  key: ValueKey(
                      'extraction_selector_${_selectedSourceLocation!.id}'),
                  searchType: ProductSearchType.withStock,
                  requireInventory: true,
                  locationId: int.tryParse(_selectedSourceLocation!.id),
                  searchHint:
                      'Buscar productos en ${_selectedSourceLocation!.name}...',
                  onProductSelected: _addProductToExtraction,
                ),
              ),
            ),
    );
  }

  Widget _buildSelectedProductsCard() {
    return _buildWebCard(
      title: 'Productos Seleccionados',
      subtitle: _selectedProducts.isEmpty
          ? 'Aún no has agregado productos'
          : '${_selectedProducts.length} producto(s) listos para extraer',
      icon: Icons.inventory_2_outlined,
      iconColor: _accent,
      trailing: _selectedProducts.isNotEmpty
          ? TextButton.icon(
              onPressed: () => setState(_selectedProducts.clear),
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Limpiar'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12),
              ),
            )
          : null,
      child: _selectedProducts.isEmpty
          ? _buildEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Sin productos',
              description:
                  'Agrega productos buscándolos arriba para preparar la extracción.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRowsHeader(),
                ..._selectedProducts.asMap().entries.map((e) {
                  return _buildRow(e.key, e.value);
                }),
                const SizedBox(height: 12),
                ConversionInfoWidget(
                  conversions: _selectedProducts,
                  showDetails: true,
                ),
              ],
            ),
    );
  }

  Widget _buildRowsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              'Producto / Presentación',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              'Zona',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              'Cantidad',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildRow(int index, Map<String, dynamic> product) {
    final isLast = index == _selectedProducts.length - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : const Color(0xFFFAFBFC),
        border: Border(
          left: BorderSide(color: Colors.grey.shade200),
          right: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(10))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['denominacion'] ??
                      product['nombre_producto'] ??
                      'Sin nombre',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((product['presentacion'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    product['presentacion'].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if ((product['variante'] ?? '').toString().isNotEmpty)
                  Text(
                    'Variante: ${product['variante']}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              product['zona_nombre']?.toString() ?? '—',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              '${product['cantidad']}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppColors.error,
              tooltip: 'Eliminar',
              onPressed: () => _removeProductFromExtraction(index),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SHARED HELPERS
  // =====================================================
  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      labelStyle: TextStyle(
        fontSize: 14,
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  Widget _buildWebCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
    Color? iconColor,
    Widget? trailing,
  }) {
    final Color accentColor = iconColor ?? AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Container(height: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingPlaceholder(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// PRODUCT QUANTITY DIALOG (WEB)
// =====================================================
class _ProductQuantityWebDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final WarehouseZone? sourceLocation;
  final Function(Map<String, dynamic>) onProductAdded;

  const _ProductQuantityWebDialog({
    required this.product,
    required this.onProductAdded,
    this.sourceLocation,
  });

  @override
  State<_ProductQuantityWebDialog> createState() =>
      _ProductQuantityWebDialogState();
}

class _ProductQuantityWebDialogState
    extends State<_ProductQuantityWebDialog> {
  final _quantityController = TextEditingController();
  Map<String, dynamic>? _selectedVariant;
  List<Map<String, dynamic>> _availableVariants = [];
  bool _isLoadingVariants = false;
  double _maxAvailableStock = 0.0;

  Map<String, dynamic>? _selectedPresentation;
  List<Map<String, dynamic>> _availablePresentations = [];
  bool _isLoadingPresentations = false;

  static const Color _accent = AppColors.warning;

  @override
  void initState() {
    super.initState();
    _loadLocationSpecificVariants();
    _loadAvailablePresentations();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadLocationSpecificVariants() async {
    if (widget.sourceLocation == null) return;
    final sourceLayoutId = int.tryParse(widget.sourceLocation!.id);
    if (sourceLayoutId == null) return;

    setState(() => _isLoadingVariants = true);
    try {
      final rawId = widget.product['id'] ?? widget.product['id_producto'];
      if (rawId == null) {
        setState(() => _isLoadingVariants = false);
        return;
      }
      final productId = rawId is int ? rawId : int.parse(rawId.toString());

      final variants = await InventoryService.getProductVariantsInLocation(
        idProducto: productId,
        idLayout: sourceLayoutId,
      );

      setState(() {
        _availableVariants = variants;
        if (variants.isNotEmpty) {
          _selectedVariant = variants.first;
          _maxAvailableStock =
              _selectedVariant!['stock_disponible']?.toDouble() ?? 0.0;
        }
        _isLoadingVariants = false;
      });
    } catch (e) {
      setState(() => _isLoadingVariants = false);
      final fallbackStock =
          (widget.product['stock_disponible'] as num?)?.toDouble() ?? 0.0;
      _availableVariants = [
        {
          'id_variante': null,
          'variante': 'Estándar',
          'id_presentacion': null,
          'presentacion': 'Unidad',
          'stock_disponible': fallbackStock,
        },
      ];
      _selectedVariant = _availableVariants.first;
      _maxAvailableStock = fallbackStock;
    }
  }

  Future<void> _loadAvailablePresentations() async {
    if (widget.sourceLocation == null) return;
    final sourceLayoutId = int.tryParse(widget.sourceLocation!.id);
    if (sourceLayoutId == null) return;

    setState(() => _isLoadingPresentations = true);
    try {
      final rawId = widget.product['id'] ?? widget.product['id_producto'];
      if (rawId == null) {
        setState(() => _isLoadingPresentations = false);
        return;
      }
      final productId = rawId is int ? rawId : int.parse(rawId.toString());

      final presentations =
          await InventoryService.getProductPresentationsInZone(
        idProducto: productId,
        idLayout: sourceLayoutId,
      );

      setState(() {
        _availablePresentations = presentations;
        if (presentations.isNotEmpty) {
          _selectedPresentation = presentations.first;
        } else {
          final stockFromVariant =
              _selectedVariant?['stock_disponible']?.toDouble() ??
                  _maxAvailableStock;
          _availablePresentations = [
            {
              'id': widget.product['id_presentacion'] ?? 1,
              'denominacion': widget.product['presentacion'] ?? 'Unidad',
              'cantidad': 1.0,
              'stock_disponible': stockFromVariant,
            },
          ];
          _selectedPresentation = _availablePresentations.first;
        }
        _isLoadingPresentations = false;
      });
    } catch (e) {
      setState(() => _isLoadingPresentations = false);
      final stockFromVariant =
          _selectedVariant?['stock_disponible']?.toDouble() ??
              _maxAvailableStock;
      _availablePresentations = [
        {
          'id': widget.product['id_presentacion'],
          'denominacion': widget.product['presentacion'] ?? 'Unidad',
          'cantidad': 1.0,
          'stock_disponible': stockFromVariant,
        },
      ];
      _selectedPresentation = _availablePresentations.first;
    }
  }

  Future<void> _submit() async {
    final quantity = double.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese una cantidad válida')),
      );
      return;
    }
    if (quantity > _maxAvailableStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad excede stock disponible')),
      );
      return;
    }

    try {
      final baseProductData = {
        'id_producto': widget.product['id'],
        'id_variante': widget.product['id_variante'],
        'id_opcion_variante': widget.product['id_opcion_variante'],
        'id_ubicacion': widget.sourceLocation != null
            ? int.tryParse(widget.sourceLocation!.id)
            : null,
        'precio_unitario':
            (widget.product['precio_venta'] as num?)?.toDouble() ?? 0.0,
        'sku_producto': widget.product['sku'] ?? '',
        'sku_ubicacion': widget.product['ubicacion'] ?? '',
        'denominacion': widget.product['denominacion'] ??
            widget.product['nombre_producto'] ??
            '',
        'variante': widget.product['variante'] ?? '',
        'opcionVariante': widget.product['opcion_variante'] ?? '',
        'zona_nombre': widget.sourceLocation?.name ?? 'Sin zona',
      };

      final processedProductData =
          await PresentationConverter.processProductForExtraction(
        productId: widget.product['id'].toString(),
        selectedPresentation: _selectedPresentation,
        cantidad: quantity,
        baseProductData: baseProductData,
      );

      widget.onProductAdded(processedProductData);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error procesando producto: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productName = widget.product['denominacion'] ??
        widget.product['nombre_producto'] ??
        'Extraer Producto';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      productName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kvRow('SKU', widget.product['sku']?.toString() ?? 'N/A'),
                          const SizedBox(height: 8),
                          _kvRow(
                            'Stock disponible',
                            _maxAvailableStock.toStringAsFixed(1),
                            valueColor: _maxAvailableStock > 0
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          if ((widget.product['presentacion'] ?? '')
                              .toString()
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _kvRow('Presentación base',
                                widget.product['presentacion'].toString()),
                          ],
                        ],
                      ),
                    ),
                    if (widget.product['es_elaborado'] == true) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFB45309), size: 18),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Producto elaborado: se extraerán ingredientes automáticamente.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFFB45309),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    // Presentation
                    if (_isLoadingPresentations)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_availablePresentations.isNotEmpty) ...[
                      const Text(
                        'Presentación a extraer',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        value: _selectedPresentation,
                        isExpanded: true,
                        decoration: _dialogInput(
                          label: 'Presentación',
                          prefixIcon: Icon(
                            Icons.category_outlined,
                            size: 18,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        items: _availablePresentations.map((p) {
                          final label =
                              '${p['denominacion'] ?? 'Sin nombre'} - ${p['cantidad']}';
                          return DropdownMenuItem(
                            value: p,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() {
                          _selectedPresentation = v;
                          _quantityController.clear();
                        }),
                      ),
                      const SizedBox(height: 18),
                    ],
                    // Quantity
                    const Text(
                      'Cantidad a extraer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _quantityController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: _dialogInput(
                        label: 'Cantidad *',
                        hint: '0.00',
                        prefixIcon: Icon(
                          Icons.numbers_rounded,
                          size: 18,
                          color: Colors.grey.shade500,
                        ),
                        suffixText:
                            _selectedVariant?['presentacion_nombre']?.toString(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Actions
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _selectedVariant == null ? null : _submit,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Agregar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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

  Widget _kvRow(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _dialogInput({
    required String label,
    String? hint,
    String? suffixText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffixText,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }
}
