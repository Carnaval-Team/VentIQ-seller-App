import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../config/app_colors.dart';
import '../services/catalogo_service.dart';
import '../services/user_preferences_service.dart';

class CatalogoProductosScreen extends StatefulWidget {
  const CatalogoProductosScreen({super.key});

  @override
  State<CatalogoProductosScreen> createState() =>
      _CatalogoProductosScreenState();
}

class _CatalogoProductosScreenState extends State<CatalogoProductosScreen> {
  final CatalogoService _catalogoService = CatalogoService();
  final UserPreferencesService _userPrefs = UserPreferencesService();

  List<Map<String, dynamic>> _productos = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _idTienda;
  FiltroStockCatalogo _stockFilter = FiltroStockCatalogo.todos;
  FiltroPublicacionCatalogo _publicationFilter =
      FiltroPublicacionCatalogo.todos;
  bool _isUpdating = false;
  String? _loadError;
  int _processed = 0;
  int _batchTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      if (!mounted) return;
      setState(() => _idTienda = idTienda);

      final productos = await _catalogoService.obtenerProductosCatalogo(
        idTienda,
      );
      if (mounted) {
        setState(() {
          _productos = productos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando productos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProductos => filtrarProductosCatalogo(
    _productos,
    busqueda: _searchQuery,
    stock: _stockFilter,
    publicacion: _publicationFilter,
  );

  Future<void> _updateFiltered(bool publish) async {
    if (_isUpdating || _idTienda == null) return;
    final selected = List<Map<String, dynamic>>.of(_filteredProductos);
    final pending = selected
        .where((p) => (p['mostrar_en_catalogo'] == true) != publish)
        .toList();
    if (pending.isEmpty) return;
    setState(() {
      _isUpdating = true;
      _processed = 0;
      _batchTotal = pending.length;
    });
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(publish ? 'Activar productos' : 'Desactivar productos'),
          content: Text(
            'Se seleccionaron los ${selected.length} productos del resultado filtrado. '
            'Se ${publish ? 'activarán' : 'desactivarán'} ${pending.length}; los demás ya tienen ese estado. '
            '${publish ? 'Los productos que no cumplan los requisitos no se publicarán.' : 'Dejarán de mostrarse en el catálogo.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final failures = <String>[];
      var successes = 0;
      for (final product in pending) {
        try {
          final result = await _catalogoService.actualizarMostrarEnCatalogo(
            (product['id'] as num).toInt(),
            _idTienda!,
            publish,
          );
          if (result['success'] == true) {
            product['mostrar_en_catalogo'] = publish;
            successes++;
          } else {
            failures.add(
              '${product['denominacion']}: ${result['message'] ?? 'No actualizado'}',
            );
          }
        } catch (e) {
          failures.add('${product['denominacion']}: $e');
        }
        if (mounted) setState(() => _processed++);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resultado de la actualización'),
          content: SingleChildScrollView(
            child: Text(
              '$successes actualizados; ${failures.length} no actualizados.'
              '${failures.isEmpty ? '' : '\n\n${failures.take(10).join('\n')}'}'
              '${failures.length > 10 ? '\nY ${failures.length - 10} errores más.' : ''}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _toggleMostrarEnCatalogo(Map<String, dynamic> producto) async {
    if (_idTienda == null || _isUpdating) return;
    setState(() {
      _isUpdating = true;
      _batchTotal = 0;
    });

    final idProducto = producto['id'] as int;
    final mostrarActual = producto['mostrar_en_catalogo'] as bool? ?? false;
    final nuevoValor = !mostrarActual;

    try {
      final result = await _catalogoService.actualizarMostrarEnCatalogo(
        idProducto,
        _idTienda!,
        nuevoValor,
      );

      if (result['success'] == true) {
        if (mounted) {
          setState(() {
            final index = _productos.indexWhere((p) => p['id'] == idProducto);
            if (index != -1) {
              _productos[index]['mostrar_en_catalogo'] = nuevoValor;
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                nuevoValor
                    ? '✅ Producto publicado en catálogo'
                    : '✅ Producto removido del catálogo',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _mostrarDetallesProducto(Map<String, dynamic> producto) {
    final faltantes = _catalogoService.obtenerRequisitosFaltantes(producto);
    final esValido = faltantes.isEmpty;

    // Controladores para edición
    final denominacionController = TextEditingController(
      text: producto['denominacion'] ?? '',
    );
    final precioController = TextEditingController(
      text: producto['precio_venta']?.toString() ?? '',
    );
    bool enEdicion = false;
    File? imagenSeleccionada;
    final imagePicker = ImagePicker();

    Future<void> _seleccionarImagen() async {
      try {
        final pickedFile = await imagePicker.pickImage(
          source: ImageSource.gallery,
        );
        if (pickedFile != null) {
          imagenSeleccionada = File(pickedFile.path);
        }
      } catch (e) {
        print('Error seleccionando imagen: $e');
      }
    }

    Future<void> _guardarCambios(BuildContext context) async {
      try {
        final idProducto = producto['id'] as int;
        final denominacion = denominacionController.text.trim();
        final precioText = precioController.text.trim();
        final precio = precioText.isNotEmpty
            ? double.tryParse(precioText)
            : null;

        // Validar que al menos un campo se haya modificado
        if (denominacion.isEmpty &&
            precio == null &&
            imagenSeleccionada == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor modifica al menos un campo'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        // Mostrar indicador de carga
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );

        // Actualizar producto
        await _catalogoService.actualizarProducto(
          idProducto: idProducto,
          denominacion: denominacion.isNotEmpty ? denominacion : null,
          precio: precio,
          imagen: imagenSeleccionada,
        );

        if (mounted) {
          Navigator.pop(context); // Cerrar indicador de carga
          Navigator.pop(context); // Cerrar diálogo de detalles

          // Recargar datos
          await _loadData();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Producto actualizado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Cerrar indicador de carga
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Detalles del Producto'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Imagen con botón de editar
                Stack(
                  children: [
                    if (producto['imagen'] != null &&
                        (producto['imagen'] as String).isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: NetworkImage(producto['imagen'] as String),
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade200,
                        ),
                        child: const Icon(Icons.image_not_supported, size: 48),
                      ),
                    if (enEdicion)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: FloatingActionButton.small(
                          onPressed: () async {
                            await _seleccionarImagen();
                            setState(() {});
                          },
                          backgroundColor: Colors.blue,
                          child: const Icon(Icons.camera_alt, size: 18),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Denominación
                Text(
                  'Denominación',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (enEdicion)
                  TextField(
                    controller: denominacionController,
                    decoration: InputDecoration(
                      hintText: 'Nombre del producto',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  )
                else
                  Text(
                    producto['denominacion'] ?? 'No configurada',
                    style: TextStyle(
                      color: (producto['tiene_denominacion'] == true)
                          ? Colors.black
                          : Colors.red,
                    ),
                  ),
                const SizedBox(height: 12),

                // SKU (solo lectura)
                Text(
                  'SKU',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(producto['sku'] ?? 'N/A'),
                const SizedBox(height: 12),

                // Precio con aclaración
                Text(
                  'Precio Base del Sistema',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Este es el precio base del producto en todo el sistema',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                if (enEdicion)
                  TextField(
                    controller: precioController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Precio',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  )
                else
                  Text(
                    producto['precio_venta'] != null
                        ? '\$${producto['precio_venta']}'
                        : 'No configurado',
                    style: TextStyle(
                      color: (producto['tiene_precio'] == true)
                          ? Colors.black
                          : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 12),

                // Presentación
                Text(
                  'Presentación',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  (producto['tiene_presentacion'] == true)
                      ? '✅ Configurada'
                      : '❌ No configurada',
                  style: TextStyle(
                    color: (producto['tiene_presentacion'] == true)
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                const SizedBox(height: 16),

                // Estado de validación
                if (!esValido)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠️ Requisitos faltantes:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...faltantes.map((req) => Text('• $req')),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(color: Colors.green.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '✅ Producto válido para catálogo',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (enEdicion)
              TextButton(
                onPressed: () {
                  setState(() => enEdicion = false);
                  denominacionController.dispose();
                  precioController.dispose();
                },
                child: const Text('Cancelar'),
              ),
            if (enEdicion)
              ElevatedButton(
                onPressed: () async {
                  await _guardarCambios(context);
                  denominacionController.dispose();
                  precioController.dispose();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Guardar'),
              ),
            if (!enEdicion)
              TextButton(
                onPressed: () {
                  setState(() => enEdicion = true);
                },
                child: const Text('Editar'),
              ),
            TextButton(
              onPressed: () {
                denominacionController.dispose();
                precioController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProductos;
    return PopScope(
      canPop: !_isUpdating,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestionar Catálogo'),
          backgroundColor: AppColors.primary,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'Notificaciones WAPI',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: _isUpdating
                  ? null
                  : () => Navigator.pushNamed(context, '/wapi-notifications'),
            ),
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _isUpdating || _isLoading ? null : _loadData,
            ),
          ],
        ),
        bottomNavigationBar: _isLoading || _loadError != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isUpdating && _batchTotal > 0) ...[
                        LinearProgressIndicator(
                          value: _processed / _batchTotal,
                        ),
                        const SizedBox(height: 8),
                        Text('Procesados: $_processed de $_batchTotal'),
                      ] else
                        Text(
                          '${filtered.length} productos seleccionados (todos los filtrados)',
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                _isUpdating ||
                                    !filtered.any(
                                      (p) => p['mostrar_en_catalogo'] != true,
                                    )
                                ? null
                                : () => _updateFiltered(true),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Activar todos'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                _isUpdating ||
                                    !filtered.any(
                                      (p) => p['mostrar_en_catalogo'] == true,
                                    )
                                ? null
                                : () => _updateFiltered(false),
                            icon: const Icon(Icons.visibility_off_outlined),
                            label: const Text('Desactivar todos'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No se pudo cargar el catálogo: $_loadError'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadData,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : AbsorbPointer(
                absorbing: _isUpdating,
                child: Column(
                  children: [
                    // Barra de búsqueda
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                        decoration: InputDecoration(
                          hintText: 'Buscar producto...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        leading: const Icon(Icons.filter_list),
                        title: Text(
                          'Filtros${_stockFilter != FiltroStockCatalogo.todos || _publicationFilter != FiltroPublicacionCatalogo.todos ? ' activos' : ''}',
                        ),
                        children: [
                          DropdownButtonFormField<FiltroStockCatalogo>(
                            key: ValueKey(_stockFilter),
                            initialValue: _stockFilter,
                            decoration: const InputDecoration(
                              labelText: 'Stock físico de la tienda',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: FiltroStockCatalogo.todos,
                                child: Text('Todos'),
                              ),
                              DropdownMenuItem(
                                value: FiltroStockCatalogo.conStock,
                                child: Text('Con stock (> 0)'),
                              ),
                              DropdownMenuItem(
                                value: FiltroStockCatalogo.sinStock,
                                child: Text('Sin stock (≤ 0)'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _stockFilter = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<FiltroPublicacionCatalogo>(
                            key: ValueKey(_publicationFilter),
                            initialValue: _publicationFilter,
                            decoration: const InputDecoration(
                              labelText: 'Estado en catálogo',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: FiltroPublicacionCatalogo.todos,
                                child: Text('Todos'),
                              ),
                              DropdownMenuItem(
                                value: FiltroPublicacionCatalogo.publicados,
                                child: Text('Publicados'),
                              ),
                              DropdownMenuItem(
                                value: FiltroPublicacionCatalogo.noPublicados,
                                child: Text('No publicados'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _publicationFilter = value);
                              }
                            },
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _stockFilter = FiltroStockCatalogo.todos;
                              _publicationFilter =
                                  FiltroPublicacionCatalogo.todos;
                            }),
                            child: const Text('Limpiar filtros'),
                          ),
                        ],
                      ),
                    ),
                    // Resumen
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total: ${_filteredProductos.length}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'En catálogo: ${_filteredProductos.where((p) => p['mostrar_en_catalogo'] == true).length}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Lista de productos
                    Expanded(
                      child: _filteredProductos.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shopping_bag_outlined,
                                    size: 64,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No hay productos',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _filteredProductos.length,
                              itemBuilder: (context, index) {
                                final producto = _filteredProductos[index];
                                final esValido =
                                    producto['es_valido_catalogo'] == true;
                                final mostrarEnCatalogo =
                                    producto['mostrar_en_catalogo'] == true;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.grey.shade200,
                                        image:
                                            (producto['imagen'] != null &&
                                                (producto['imagen'] as String)
                                                    .isNotEmpty)
                                            ? DecorationImage(
                                                image: NetworkImage(
                                                  producto['imagen'] as String,
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child:
                                          (producto['imagen'] == null ||
                                              (producto['imagen'] as String)
                                                  .isEmpty)
                                          ? const Icon(
                                              Icons.image_not_supported,
                                              size: 24,
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      producto['denominacion'] ?? 'Sin nombre',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'SKU: ${producto['sku'] ?? 'N/A'}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        Text(
                                          '\$${producto['precio_venta'] ?? 'N/A'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green,
                                          ),
                                        ),
                                        Text(
                                          'Stock: ${producto['stock_disponible']} unidades base',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        if (!esValido)
                                          Text(
                                            '⚠️ Incompleto',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.red.shade600,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Switch(
                                          value: mostrarEnCatalogo,
                                          onChanged:
                                              !_isUpdating &&
                                                  (esValido ||
                                                      mostrarEnCatalogo)
                                              ? (_) => _toggleMostrarEnCatalogo(
                                                  producto,
                                                )
                                              : null,
                                          activeColor: Colors.green,
                                        ),
                                      ],
                                    ),
                                    onTap: () =>
                                        _mostrarDetallesProducto(producto),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
