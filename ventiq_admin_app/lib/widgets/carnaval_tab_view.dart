import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_service.dart';
import '../services/store_service.dart';
import '../services/tpv_service.dart';
import '../services/store_config_service.dart';
import 'store_config_dialog.dart';
import 'product_sync_sheet.dart';
import 'product_sales_dialog.dart';

class CarnavalTabView extends StatefulWidget {
  const CarnavalTabView({super.key});

  @override
  State<CarnavalTabView> createState() => _CarnavalTabViewState();
}

class _CarnavalTabViewState extends State<CarnavalTabView> {
  bool _isLoading = true;
  bool _isSynced = false;
  int? _storeId;
  int? _carnavalStoreId;
  Map<String, dynamic>? _storeInfo;
  Map<String, dynamic>? _carnavalProviderInfo;
  int _syncedProductsCount = 0;
  Map<String, List<Map<String, dynamic>>> _syncedProducts = {};
  List<Map<String, dynamic>> _tpvs = [];
  Map<String, dynamic>? _assignedTpvConfig;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Obtener ID de la tienda actual
      _storeId = await StoreService.getCurrentStoreId();

      if (_storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      // Verificar si está sincronizada con Carnaval
      _isSynced = await CarnavalService.isStoreSyncedWithCarnaval(_storeId!);

      // Obtener información de la tienda
      _storeInfo = await CarnavalService.getStoreInfo(_storeId!);

      if (_isSynced) {
        // Obtener ID de Carnaval
        _carnavalStoreId = await CarnavalService.getCarnavalStoreId(_storeId!);

        if (_carnavalStoreId != null) {
          // Obtener información del proveedor en Carnaval
          _carnavalProviderInfo = await CarnavalService.getCarnavalProviderInfo(
            _carnavalStoreId!,
          );

          // Obtener cantidad de productos sincronizados
          _syncedProductsCount = await CarnavalService.getSyncedProductsCount(
            _carnavalStoreId!,
          );

          // Obtener productos sincronizados agrupados con ubicación
          _syncedProducts = await CarnavalService.getSyncedProductsWithLocation(
            _carnavalStoreId!,
          );

          // Cargar TPVs y configuración de asignación
          _tpvs = await TpvService.getTpvsByStore();
          _assignedTpvConfig =
              await StoreConfigService.getTpvTrabajadorEncargadoCarnaval(
                _storeId!,
              );
        }
      }
    } catch (e) {
      print('❌ Error al cargar datos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _syncWithCarnaval() async {
    // Mostrar diálogo de confirmación
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Sincronizar con Carnaval App'),
            content: const Text(
              '¿Deseas que tu tienda esté disponible para vender en Carnaval App?\n\n'
              'Se verificará que la tienda tenga todos los datos necesarios.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );

    if (confirm != true || _storeId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Validar datos de la tienda
      final validation = await CarnavalService.validateStoreData(_storeId!);

      if (validation['isValid'] != true) {
        final missingFields = validation['missingFields'] as List;

        if (mounted) {
          final shouldConfig = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Datos incompletos'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'La tienda no tiene todos los datos necesarios para sincronizar con Carnaval App:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...missingFields.map(
                        (field) => Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 8,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(field.toString())),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Por favor, completa estos datos antes de sincronizar.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text('Configurar'),
                    ),
                  ],
                ),
          );

          if (shouldConfig == true && mounted) {
            final configResult = await showDialog<bool>(
              context: context,
              builder:
                  (context) => StoreConfigDialog(
                    storeId: _storeId!,
                    currentStoreInfo:
                        validation['storeInfo'] as Map<String, dynamic>,
                  ),
            );

            if (configResult == true) {
              // Recargar datos y reintentar sincronización
              await _loadData();
              if (mounted) {
                _syncWithCarnaval();
              }
            }
          }
        }
        return;
      }

      // Crear proveedor en Carnaval
      await CarnavalService.createCarnavalProvider(_storeId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Tienda sincronizada con Carnaval App exitosamente',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Recargar datos
      await _loadData();
    } catch (e) {
      print('❌ Error al sincronizar con Carnaval: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al sincronizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unsyncFromCarnaval() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Desincronizar de Carnaval App'),
            content: const Text(
              '¿Estás seguro de que deseas desincronizar tu tienda de Carnaval App?\n\n'
              'Esto no eliminará el proveedor en Carnaval, solo desvinculará la tienda.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Desincronizar'),
              ),
            ],
          ),
    );

    if (confirm != true || _storeId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await CarnavalService.unsyncStoreFromCarnaval(_storeId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Tienda desincronizada de Carnaval App'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      await _loadData();
    } catch (e) {
      print('❌ Error al desincronizar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al desincronizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Compacto con Estado
          _buildCompactHeader(),

          const SizedBox(height: 16),

          // Información de la Tienda Compacta
          if (_storeInfo != null) _buildCompactStoreInfo(),

          // Sección de Asignación de TPV (Nueva funcionalidad)
          if (_isSynced) ...[
            const SizedBox(height: 16),
            _buildTpvAssignmentSection(),
          ],

          // Lista de Productos Sincronizados
          if (_isSynced && _carnavalStoreId != null) ...[
            const SizedBox(height: 16),
            _buildSyncedProductsList(),
          ],

          // Botón de configuración adicional si está sincronizado
          if (_isSynced) ...[const SizedBox(height: 16), _buildQuickActions()],
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              _isSynced
                  ? [Colors.green.shade700, Colors.green.shade500]
                  : [Colors.orange.shade700, Colors.orange.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_isSynced ? Colors.green : Colors.orange).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isSynced ? Icons.check_circle_outline : Icons.storefront,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isSynced
                          ? 'Tienda Sincronizada'
                          : 'Venta en Carnaval App',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSynced
                          ? 'Tu tienda está visible para los clientes'
                          : 'Sincroniza para comenzar a vender online',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isSynced) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _syncWithCarnaval,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.orange.shade700,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Sincronizar Ahora',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactStoreInfo() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagen de la tienda
                Hero(
                  tag: 'store_image',
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey.shade100,
                      image:
                          _storeInfo!['imagen_url'] != null
                              ? DecorationImage(
                                image: NetworkImage(_storeInfo!['imagen_url']),
                                fit: BoxFit.cover,
                              )
                              : null,
                    ),
                    child:
                        _storeInfo!['imagen_url'] == null
                            ? Icon(
                              Icons.store,
                              color: Colors.grey.shade400,
                              size: 40,
                            )
                            : null,
                  ),
                ),
                const SizedBox(width: 16),
                // Información
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _storeInfo!['denominacion'] ?? 'Sin Nombre',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isSynced)
                            GestureDetector(
                              onTap: () async {
                                final result = await showDialog<bool>(
                                  context: context,
                                  builder:
                                      (context) => StoreConfigDialog(
                                        storeId: _storeId!,
                                        currentStoreInfo: _storeInfo!,
                                      ),
                                );
                                if (result == true) {
                                  _loadData();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (_storeInfo!['ubicacion'] != null)
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 12,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _storeInfo!['ubicacion'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      // Badge de productos
                      if (_isSynced)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 12,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_syncedProductsCount productos',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncedProductsList() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Productos Sincronizados',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: () async {
                final result = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder:
                      (context) => ProductSyncSheet(
                        storeId: _storeId!,
                        carnavalStoreId: _carnavalStoreId!,
                      ),
                );
                if (result == true) {
                  _loadData();
                }
              },
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_syncedProducts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 40,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  'No hay productos sincronizados',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          ..._syncedProducts.entries.map((entry) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                leading:
                    entry.value.isNotEmpty && entry.value.first['image'] != null
                        ? CircleAvatar(
                          backgroundImage: NetworkImage(
                            entry.value.first['image'],
                          ),
                          radius: 16,
                        )
                        : const Icon(Icons.category),
                title: Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                children:
                    entry.value.map((product) {
                      final isActive = product['status'] == true;
                      return Opacity(
                        opacity: isActive ? 1.0 : 0.5,
                        child: ListTile(
                          onTap: () async {
                            // Debug: verificar datos antes de abrir el diálogo
                            print('🔍 Abriendo ProductSalesDialog:');
                            print('  - storeId: $_storeId');
                            print('  - product id: ${product['id']}');
                            print(
                              '  - localProductId (id_producto): ${product['id_producto']}',
                            );
                            print('  - product keys: ${product.keys.toList()}');

                            final result = await showDialog<bool>(
                              context: context,
                              builder:
                                  (context) => ProductSalesDialog(
                                    product: product,
                                    storeId: _storeId,
                                    localProductId: product['id_producto'],
                                  ),
                            );
                            // Si el producto cambió de estado, recargar datos
                            if (result == true) {
                              _loadData();
                            }
                          },
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image:
                                  product['image'] != null
                                      ? DecorationImage(
                                        image: NetworkImage(product['image']),
                                        fit: BoxFit.cover,
                                        colorFilter:
                                            isActive
                                                ? null
                                                : ColorFilter.mode(
                                                  Colors.grey,
                                                  BlendMode.saturation,
                                                ),
                                      )
                                      : null,
                            ),
                          ),
                          title: Text(
                            '${product['name']} (ID: ${product['id']})',
                            style: TextStyle(
                              color: isActive ? null : Colors.grey,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Precio: \$${product['price']} | Stock: ${product['stock']}',
                                style: TextStyle(
                                  color: isActive ? null : Colors.grey,
                                ),
                              ),
                              if (product['almacen'] != null &&
                                  product['ubicacion'] != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 12,
                                      color:
                                          isActive
                                              ? Colors.grey.shade600
                                              : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '${product['almacen']} - ${product['ubicacion']}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color:
                                              isActive
                                                  ? Colors.grey.shade600
                                                  : Colors.grey,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: Icon(
                            isActive
                                ? Icons.check_circle
                                : Icons.visibility_off,
                            color: isActive ? Colors.green : Colors.grey,
                            size: 16,
                          ),
                        ),
                      );
                    }).toList(),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTpvAssignmentSection() {
    final hasAssignment = _assignedTpvConfig != null;
    final tpvName = _assignedTpvConfig?['tpv_name'] ?? 'No asignado';
    final workerName = _assignedTpvConfig?['worker_name'] ?? '';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Gestión de Ventas Carnaval',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _showTpvAssignmentDialog,
                  icon: Icon(
                    hasAssignment ? Icons.edit : Icons.add_circle_outline,
                    size: 18,
                  ),
                  label: Text(hasAssignment ? 'Cambiar' : 'Asignar'),
                ),
              ],
            ),
            if (hasAssignment) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.point_of_sale,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tpvName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          if (workerName.isNotEmpty)
                            Text(
                              'Vendedor: $workerName',
                              style: TextStyle(
                                color: Colors.blue.shade800,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Las ventas no se asignarán a un TPV específico.',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showTpvAssignmentDialog() async {
    // Preparar lista plana de opciones (TPV + Vendedor)
    final List<Map<String, dynamic>> options = [];

    for (var tpv in _tpvs) {
      var vendedoresData = tpv['vendedor'];
      List<dynamic> vendedores = [];

      if (vendedoresData is List) {
        vendedores = vendedoresData;
      } else if (vendedoresData != null) {
        vendedores = [vendedoresData];
      }

      if (vendedores.isEmpty) {
        // Opción de TPV sin vendedor (opcional, si se permite)
        // Por ahora solo añadimos si hay vendedor, o mostramos mensaje
        continue;
      }

      for (var vendedor in vendedores) {
        if (vendedor is Map<String, dynamic>) {
          options.add({
            'tpv': tpv,
            'vendedor': vendedor,
            'trabajador': vendedor['trabajador'],
          });
        }
      }
    }

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay TPVs con vendedores disponibles'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Asignar TPV para Carnaval'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Selecciona el TPV y vendedor que gestionará las ventas de Carnaval App:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder:
                          (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final tpv = option['tpv'];
                        final trabajador = option['trabajador'];
                        final workerName =
                            trabajador != null
                                ? '${trabajador['nombres']} ${trabajador['apellidos']}'
                                : 'Sin datos de trabajador';

                        return ListTile(
                          title: Text(
                            tpv['denominacion'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('Vendedor: $workerName'),
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade50,
                            child: const Icon(
                              Icons.person_outline,
                              color: Colors.blue,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Colors.grey,
                          ),
                          onTap: () {
                            Navigator.pop(context, option);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
    );

    if (result != null) {
      await _assignTpv(result);
    }
  }

  Future<void> _assignTpv(Map<String, dynamic> selection) async {
    setState(() => _isLoading = true);
    try {
      final tpv = selection['tpv'];
      final vendedor = selection['vendedor'];
      final trabajador = selection['trabajador'];

      if (vendedor == null || trabajador == null) {
        throw Exception('Datos de vendedor incompletos');
      }

      final workerName = '${trabajador['nombres']} ${trabajador['apellidos']}';

      final configData = {
        'tpv_id': tpv['id'],
        'tpv_name': tpv['denominacion'],
        'app_dat_vendedor_uuid': vendedor['uuid'],
        'worker_name': workerName,
        'worker_data': trabajador,
      };

      await StoreConfigService.updateTpvTrabajadorEncargadoCarnaval(
        _storeId!,
        configData,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ TPV asignado correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadData();
    } catch (e) {
      print('❌ Error asignando TPV: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al asignar TPV: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _unsyncFromCarnaval,
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Desvincular Tienda'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: BorderSide(color: Colors.red.shade200),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
