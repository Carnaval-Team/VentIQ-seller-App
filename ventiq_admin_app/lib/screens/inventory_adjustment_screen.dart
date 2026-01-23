import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/inventory.dart'; // Contains InventoryProduct, InventoryResponse, etc.
import '../services/inventory_service.dart';
import '../services/warehouse_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/product_selector_widget.dart';
import '../services/product_search_service.dart';

class InventoryAdjustmentScreen extends StatefulWidget {
  final int operationType; // 3 para faltante (sumar), 4 para exceso (restar)
  final String adjustmentType; // 'shortage' o 'excess'

  const InventoryAdjustmentScreen({
    super.key,
    required this.operationType,
    required this.adjustmentType,
  });

  @override
  State<InventoryAdjustmentScreen> createState() => _InventoryAdjustmentScreenState();
}

class _InventoryAdjustmentScreenState extends State<InventoryAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newQuantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _observationsController = TextEditingController();


  Map<String, dynamic>? _selectedProduct;
  
  List<Map<String, dynamic>> _warehousesWithZones = [];
  Map<String, dynamic>? _selectedZone;
  
  List<Map<String, dynamic>> _presentations = [];
  Map<String, dynamic>? _selectedPresentation;
  
  double? _currentStock;
  
  bool _isLoading = false;
  bool _isLoadingZones = false;
  bool _isLoadingPresentations = false;
  bool _isLoadingStock = false;

  @override
  void initState() {
    super.initState();
    // Load zones first, then products will be filtered by selected zone
    _loadInitialZones();
  }

  Future<void> _loadInitialZones() async {
    setState(() => _isLoadingZones = true);
    try {
      // Obtener todos los almacenes/zonas disponibles
      final warehouses = await WarehouseService().listWarehousesOK();
      
      // Convertir almacenes a formato de zonas para el dropdown
      final warehousesWithZones = warehouses.map((warehouse) => {
        'id': int.tryParse(warehouse.id) ?? 0,
        'name': warehouse.name,
        'denominacion': warehouse.denominacion ?? warehouse.name,
        'direccion': warehouse.direccion ?? warehouse.address,
        'zones': warehouse.zones.map((zone) => {
          'id': int.tryParse(zone.id) ?? 0,
          'denominacion': zone.name ?? zone.name,
          'code': zone.code ?? '',
        }).toList(),
      }).toList();
      
      setState(() {
        _warehousesWithZones = warehousesWithZones;
        _isLoadingZones = false;
      });
    } catch (e) {
      setState(() => _isLoadingZones = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar zonas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _newQuantityController.dispose();
    _reasonController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  Future<void> _loadPresentationsForZone() async {
    if (_selectedProduct == null || _selectedZone == null) return;
    
    setState(() => _isLoadingPresentations = true);
    try {
      // Obtener presentaciones del producto que están presentes en la zona seleccionada
      final productId = int.tryParse((_selectedProduct!['id_producto'] ?? _selectedProduct!['id'])?.toString() ?? '0');
      final zoneId = _selectedZone!['id'] as int;
      
      // Primero obtener todas las presentaciones del producto (sin filtrar por zona)
      final allPresentationsResponse = await InventoryService.getInventoryProducts(
        idProducto: productId,
        mostrarSinStock: false, // Solo mostrar presentaciones con stock
        limite: 100,
      );
      
      // Luego verificar cuáles están disponibles en la zona específica
      final zoneSpecificResponse = await InventoryService.getInventoryProducts(
        idProducto: productId,
        idUbicacion: zoneId,
        mostrarSinStock: false,
        limite: 100,
      );
      
      // Extraer presentaciones únicas de todos los productos de inventario
      final Map<String, Map<String, dynamic>> uniquePresentations = {};
      
      // Primero agregar todas las presentaciones disponibles del producto
      for (final product in allPresentationsResponse.products) {
        String presentationKey;
        if (product.idPresentacion != null) {
          presentationKey = product.idPresentacion.toString();
          uniquePresentations[presentationKey] = {
            'id': product.idPresentacion!,
            'name': product.presentacion,
            'denominacion': product.presentacion,
            'codigo': product.idPresentacion.toString(),
            'stock_disponible': 0.0, // Inicializar en 0
            'available_in_zone': false,
          };
        } else {
          // Handle products without specific presentation
          presentationKey = 'null';
          uniquePresentations[presentationKey] = {
            'id': null,
            'name': 'Sin presentación',
            'denominacion': 'Sin presentación',
            'codigo': 'SIN_PRES',
            'stock_disponible': 0.0,
            'available_in_zone': false,
          };
        }
      }
      
      // Luego actualizar con el stock específico de la zona seleccionada
      for (final product in zoneSpecificResponse.products) {
        String presentationKey = product.idPresentacion?.toString() ?? 'null';
        if (uniquePresentations.containsKey(presentationKey)) {
          uniquePresentations[presentationKey]!['stock_disponible'] = product.cantidadFinal;
          uniquePresentations[presentationKey]!['available_in_zone'] = true;
        }
      }
      
      final presentations = uniquePresentations.values.toList();
      
      setState(() {
        _presentations = presentations;
        _isLoadingPresentations = false;
        
        // Auto-seleccionar si solo hay una presentación disponible
        if (presentations.length == 1) {
          _selectedPresentation = presentations.first;
          // Cargar stock para la presentación seleccionada automáticamente
          _loadCurrentStock();
        } else {
          // Reset selección si hay múltiples opciones
          _selectedPresentation = null;
          _currentStock = null;
        }
      });
      
      // Mostrar mensaje informativo sobre las presentaciones encontradas
      if (mounted) {
        final presentationsInZone = presentations.where((p) => p['available_in_zone'] == true).length;
        final message = presentations.isEmpty 
            ? 'No hay presentaciones disponibles para este producto'
            : presentationsInZone == 0
                ? 'Se encontraron ${presentations.length} presentación(es) del producto, pero ninguna tiene stock en la zona seleccionada'
                : presentations.length == 1
                    ? 'Se seleccionó automáticamente la única presentación disponible: ${presentations.first['name']}'
                    : 'Se encontraron ${presentations.length} presentación(es), ${presentationsInZone} con stock en esta zona';
                
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: presentations.isEmpty ? Colors.red : 
                           presentationsInZone == 0 ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoadingPresentations = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar presentaciones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadCurrentStock() async {
    if (_selectedProduct == null || _selectedZone == null || 
        _selectedPresentation == null) {
      return;
    }

    setState(() => _isLoadingStock = true);
    try {
      // Obtener stock específico usando el servicio de inventario real
      final productId = int.tryParse((_selectedProduct!['id_producto'] ?? _selectedProduct!['id'])?.toString() ?? '0');
      final zoneId = _selectedZone!['id'] as int;
      final presentationId = _selectedPresentation!['id'] as int?;
      
      if (productId == null || productId == 0) {
        throw Exception('ID de producto inválido');
      }
      
      // Usar el servicio de inventario para obtener stock específico
      final inventoryResponse = await InventoryService.getInventoryProducts(
        idProducto: productId,
        idUbicacion: zoneId,
        idPresentacion: presentationId,
        mostrarSinStock: true,
        limite: 1,
      );
      
      double stock = 0.0;
      if (inventoryResponse.products.isNotEmpty) {
        stock = inventoryResponse.products.first.cantidadFinal ?? 0.0;
      }
      
      setState(() {
        _currentStock = stock;
        _isLoadingStock = false;
      });
    } catch (e) {
      setState(() => _isLoadingStock = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar stock: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _selectProduct(Map<String, dynamic> product) {
    if (_selectedZone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar una zona primero'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _selectedProduct = product;
      // Reset dependent selections
      _selectedPresentation = null;
      _currentStock = null;
    });
    
    // PASO 3: Cargar presentaciones para la combinación zona-producto
    _loadPresentationsForZone();
  }

  void _clearProductSelection() {
  setState(() {
    _selectedProduct = null;
    _selectedZone = null;
    _selectedPresentation = null;
    _currentStock = null;
    _newQuantityController.clear();
    _reasonController.clear();
    _observationsController.clear();
    _warehousesWithZones.clear();
    _presentations.clear();
  });
}

  void _onZoneSelected(Map<String, dynamic> zone) {
    setState(() {
      _selectedZone = zone;
      // Reset dependent selections cuando cambia la zona
      _selectedProduct = null;
      _selectedPresentation = null;
      _currentStock = null;
      _presentations.clear();
    });
  }

  Future<void> _submitAdjustment() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, completa todos los campos requeridos'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que se haya seleccionado un producto
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un producto'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que se haya seleccionado una zona
    if (_selectedZone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar una zona'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que se haya seleccionado una presentación
    if (_selectedPresentation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar una presentación'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que se haya ingresado una nueva cantidad
    final nuevaCantidadText = _newQuantityController.text.trim();
    if (nuevaCantidadText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe ingresar la nueva cantidad'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final nuevaCantidad = double.tryParse(nuevaCantidadText);
    if (nuevaCantidad == null || nuevaCantidad < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La nueva cantidad debe ser un número válido mayor o igual a cero'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que se haya ingresado un motivo
    final motivo = _reasonController.text.trim();
    if (motivo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe ingresar el motivo del ajuste'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que se haya ingresado observaciones
    final observaciones = _observationsController.text.trim();
    if (observaciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe ingresar observaciones del ajuste'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que el stock actual esté disponible
    if (_currentStock == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se ha cargado el stock actual. Seleccione nuevamente la presentación.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validar que la nueva cantidad sea diferente del stock actual
    final stockActual = _currentStock!;
    if (nuevaCantidad == stockActual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La nueva cantidad debe ser diferente del stock actual'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Calcular la diferencia y validar que sea significativa
    final diferencia = nuevaCantidad - stockActual;
    if (diferencia.abs() < 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La diferencia debe ser mayor a 0.01 unidades'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Mostrar confirmación para ajustes grandes
    if (diferencia.abs() > stockActual * 0.5 && stockActual > 0) {
      final confirmacion = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Ajuste Grande'),
          content: Text(
            'Está ajustando ${diferencia > 0 ? 'aumentando' : 'disminuyendo'} '
            'el stock en ${diferencia.abs().toStringAsFixed(2)} unidades '
            '(${(diferencia.abs() / stockActual * 100).toStringAsFixed(1)}% del stock actual).\n\n'
            '¿Está seguro de continuar?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      
      if (confirmacion != true) return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('🔄 INICIO: Preparando datos para ajuste de inventario...');
      
      // Obtener UUID del usuario
      final userUuid = await UserPreferencesService().getUserId();
      if (userUuid == null || userUuid.isEmpty) {
        throw Exception('No se pudo obtener el UUID del usuario');
      }

      // Preparar datos del ajuste
      final ajusteData = {
        'idProducto': _selectedProduct!['id_producto'] ?? _selectedProduct!['id'],
        'idUbicacion': _selectedZone!['id'],
        'idPresentacion': _selectedPresentation!['id'],
        'cantidadAnterior': _currentStock ?? 0.0,
        'cantidadNueva': nuevaCantidad,
        'motivo': motivo,
        'observaciones': observaciones,
        'uuid': userUuid,
        'idTipoOperacion': widget.operationType,
      };

      print('📦 Datos del ajuste preparados:');
      print('   - Producto: ${_selectedProduct!['denominacion']} (ID: ${_selectedProduct!['id_producto'] ?? _selectedProduct!['id']})');
      print('   - Zona: ${_selectedZone!['denominacion']} (ID: ${_selectedZone!['id']})');
      print('   - Presentación: ${_selectedPresentation!['denominacion']} (ID: ${_selectedPresentation!['id']})');
      print('   - Stock actual: ${_currentStock ?? 0.0} → Nueva cantidad: $nuevaCantidad');
      print('   - Diferencia: ${nuevaCantidad - (_currentStock ?? 0.0)}');
      print('   - Motivo: $motivo');
      print('   - Observaciones: $observaciones');
      print('   - Tipo de operación: ${widget.operationType}');
      print('   - Usuario UUID: $userUuid');

      // Llamar al servicio para insertar el ajuste
      print('🔄 Llamando a InventoryService.insertInventoryAdjustment...');
      
      // Convert string IDs to integers
      final productId = int.tryParse((_selectedProduct!['id_producto'] ?? _selectedProduct!['id'])?.toString() ?? '0');
      final zoneId = int.tryParse(_selectedZone!['id']?.toString() ?? '0');
      final presentationId = int.tryParse(_selectedPresentation!['id']?.toString() ?? '0');
      
      if (productId == null || zoneId == null || presentationId == null) {
        throw Exception('Error: IDs inválidos para el ajuste de inventario');
      }
      
      final result = await InventoryService.insertInventoryAdjustment(
        idProducto: productId,
        idUbicacion: zoneId,
        idPresentacion: presentationId,
        cantidadAnterior: _currentStock ?? 0.0,
        cantidadNueva: nuevaCantidad,
        motivo: motivo,
        observaciones: observaciones,
        uuid: userUuid,
        idTipoOperacion: widget.operationType,
      );

      print('📦 Resultado del servicio: $result');

      if (result['status'] == 'success') {
        print('✅ ÉXITO: Ajuste de inventario registrado correctamente');
        print('📊 Detalles del ajuste:');
        print('   - ID Operación: ${result['id_operacion']}');
        print('   - ID Ajuste: ${result['id_ajuste']}');
        print('   - Diferencia aplicada: ${result['diferencia']}');

        // Mostrar mensaje de éxito al usuario
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ajuste registrado exitosamente\n'
              'Operación ID: ${result['id_operacion']}\n'
              'Diferencia: ${result['diferencia']}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // Limpiar formulario
        _resetForm();
        
        // Opcional: Navegar de regreso
        Navigator.of(context).pop();
      } else {
        // Error en el procesamiento
        final errorMessage = result['message'] ?? 'Error desconocido al registrar el ajuste';
        print('❌ Error en el ajuste: $errorMessage');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorMessage'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ ERROR CRÍTICO en _submitAdjustment: $e');
      print('📍 StackTrace: $stackTrace');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error crítico: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _resetForm() {
    setState(() {
      _selectedProduct = null;
      _selectedZone = null;
      _selectedPresentation = null;
      _currentStock = 0.0;
      _newQuantityController.clear();
      _reasonController.clear();
      _observationsController.clear();
      _warehousesWithZones.clear();
      _presentations.clear();
    });
    print('🔄 Formulario reiniciado');
  }

  @override
  Widget build(BuildContext context) {
    final isExcess = widget.adjustmentType == 'excess';
    final title = isExcess ? 'Ajuste por Exceso' : 'Ajuste por Faltante';
    final subtitle = isExcess ? 'Reducir inventario por sobrante' : 'Aumentar inventario por faltante';
    final color = isExcess ? const Color(0xFFFF6B35) : const Color(0xFFFF8C42);
    final icon = isExcess ? Icons.trending_up : Icons.trending_down;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: color,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: color.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // PASO 1: Selección de Zona (PRIMERO)
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _selectedZone != null ? Colors.green : Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '1',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Selección de Zona',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _selectedZone != null ? Colors.green : null,
                    ),
                  ),
                  if (_selectedZone != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Tree view for warehouses and zones
              if (_isLoadingZones)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_warehousesWithZones.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'No hay zonas disponibles',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: _warehousesWithZones.map((warehouse) {
                      return ExpansionTile(
                        leading: const Icon(Icons.warehouse, color: Colors.blue),
                        title: Text(
                          warehouse['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          '${warehouse['zones'].length} zona(s) disponible(s)',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        children: (warehouse['zones'] as List<Map<String, dynamic>>)
                            .map<Widget>((zone) {
                          final isSelected = _selectedZone != null && 
                                           _selectedZone!['id'] == zone['id'];
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.only(left: 72, right: 16),
                            leading: Icon(
                              Icons.location_on,
                              color: isSelected ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                            title: Text(
                              zone['denominacion'],
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.green : null,
                              ),
                            ),
                            subtitle: zone['code'].isNotEmpty 
                                ? Text('Código: ${zone['code']}')
                                : null,
                            trailing: isSelected 
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            selected: isSelected,
                            onTap: () => _onZoneSelected(zone),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),

              // Validation message for zone selection
              if (_selectedZone == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '⚠️ Debe seleccionar una zona para continuar',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // PASO 2: Selección de Producto (SEGUNDO - Solo activo si hay zona)
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _selectedProduct != null 
                          ? Colors.green 
                          : _selectedZone != null 
                              ? Colors.blue 
                              : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '2',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Selección de Producto',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _selectedProduct != null 
                          ? Colors.green 
                          : _selectedZone != null 
                              ? null 
                              : Colors.grey,
                    ),
                  ),
                  if (_selectedProduct != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              if (_selectedZone == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Seleccione una zona primero para buscar productos',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: 200,
                  child: ProductSelectorWidget(
                    searchType: ProductSearchType.withStock,
                    locationId: _selectedZone!['id'],
                    requireInventory: true,
                    searchHint: 'Buscar productos en ${_selectedZone!['denominacion']}...',
                    onProductSelected: _selectProduct,
                  ),
                ),

              const SizedBox(height: 24),

              // Presentation selection
              Text(
                'Selección de Presentación',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<int>( // Especificamos que el tipo de valor es int
                decoration: const InputDecoration(
                  labelText: 'Presentación *',
                  border: OutlineInputBorder(),
                  hintText: 'Seleccione una presentación',
                ),
                // 1. EL VALOR AHORA ES SOLO EL ID
                value: _selectedPresentation?['id'], // Usamos el ID del mapa, que puede ser null

                // 2. LOS ITEMS SIGUEN USANDO EL ID
                items: _presentations.map((presentation) {
                  return DropdownMenuItem<int>( // El tipo del item también es int
                    value: presentation['id'], // El valor del item es el ID (entero)
                    child: Text(
                      presentation['name'] ?? 'Sin nombre',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),

                // 3. EL ONCHANGED RECIBE EL ID (ENTERO)
                onChanged: _presentations.isEmpty ? null : (int? newId) {
                  if (newId == null) return;

                  // Buscamos el mapa completo en nuestra lista original usando el ID recibido
                  final selectedMap = _presentations.firstWhere(
                        (p) => p['id'] == newId,
                    orElse: () => {}, // Devolvemos un mapa vacío si no se encuentra
                  );

                  setState(() {
                    // Asignamos el mapa completo a _selectedPresentation
                    _selectedPresentation = selectedMap.isNotEmpty ? selectedMap : null;
                    // Cargamos el stock para la nueva presentación seleccionada
                    _loadCurrentStock();
                  });
                },

                // 4. LA VALIDACIÓN COMPRUEBA EL ID
                validator: (value) {
                  // El valor aquí es el ID
                  if (value == null) {
                    return 'Debe seleccionar una presentación';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Current stock
              Text(
                'Stock Actual',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _currentStock != null && _currentStock! > 0 
                      ? Colors.green.shade50 
                      : Colors.orange.shade50,
                  border: Border.all(
                    color: _currentStock != null && _currentStock! > 0 
                        ? Colors.green.shade300 
                        : Colors.orange.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _currentStock != null && _currentStock! > 0 
                          ? Icons.inventory 
                          : Icons.warning,
                      color: _currentStock != null && _currentStock! > 0 
                          ? Colors.green.shade700 
                          : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isLoadingStock 
                                ? 'Cargando stock...' 
                                : _currentStock != null 
                                    ? 'Stock disponible: ${_currentStock!.toStringAsFixed(2)} unidades'
                                    : 'Stock no disponible',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _currentStock != null && _currentStock! > 0 
                                  ? Colors.green.shade700 
                                  : Colors.orange.shade700,
                            ),
                          ),
                          if (_currentStock != null && _currentStock! == 0)
                            Text(
                              'No hay stock disponible para esta combinación',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_isLoadingStock)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Quantity
              Text(
                'Nueva Cantidad en Inventario',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _newQuantityController,
                decoration: const InputDecoration(
                  labelText: 'Nueva Cantidad *',
                  hintText: 'Ingrese la nueva cantidad total',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory),
                  suffixText: 'unidades',
                  helperText: 'Cantidad final que debe quedar en inventario',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'La nueva cantidad es requerida';
                  }
                  final quantity = double.tryParse(value);
                  if (quantity == null || quantity < 0) {
                    return 'Ingrese una cantidad válida mayor o igual a cero';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Reason
              Text(
                'Motivo del Ajuste',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  hintText: 'Ej: Conteo físico, Merma, Error de registro',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El motivo es requerido';
                  }
                  if (value.trim().length < 5) {
                    return 'El motivo debe tener al menos 5 caracteres';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Observations
              Text(
                'Observaciones',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _observationsController,
                decoration: const InputDecoration(
                  labelText: 'Observaciones adicionales',
                  hintText: 'Información adicional sobre el ajuste (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 32),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitAdjustment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Procesando...'),
                          ],
                        )
                      : Text(
                          'Registrar ${isExcess ? 'Ajuste por Exceso' : 'Ajuste por Faltante'}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
              break;
            case 1:
              Navigator.pushNamed(context, '/products');
              break;
            case 2:
              Navigator.pushNamed(context, '/inventory');
              break;
            case 3:
              Navigator.pushNamed(context, '/settings');
              break;
          }
        },
      ),
    );
  }
}
