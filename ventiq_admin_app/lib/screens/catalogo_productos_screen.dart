import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../config/app_colors.dart';
import '../services/catalogo_service.dart';
import '../services/user_preferences_service.dart';

class CatalogoProductosScreen extends StatefulWidget {
  const CatalogoProductosScreen({super.key});

  @override
  State<CatalogoProductosScreen> createState() => _CatalogoProductosScreenState();
}

class _CatalogoProductosScreenState extends State<CatalogoProductosScreen> {
  final CatalogoService _catalogoService = CatalogoService();
  final UserPreferencesService _userPrefs = UserPreferencesService();

  List<Map<String, dynamic>> _productos = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _idTienda;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      setState(() => _idTienda = idTienda);

      final productos = await _catalogoService.obtenerProductosCatalogo(idTienda);
      if (mounted) {
        setState(() {
          _productos = productos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando productos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredProductos {
    if (_searchQuery.isEmpty) return _productos;
    return _productos
        .where((p) {
          final denominacion = (p['denominacion'] as String?)?.toLowerCase() ?? '';
          final sku = (p['sku'] as String?)?.toLowerCase() ?? '';
          final query = _searchQuery.toLowerCase();
          return denominacion.contains(query) || sku.contains(query);
        })
        .toList();
  }

  Future<void> _toggleMostrarEnCatalogo(Map<String, dynamic> producto) async {
    if (_idTienda == null) return;

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
              content: Text(nuevoValor ? '✅ Producto publicado en catálogo' : '✅ Producto removido del catálogo'),
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
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        final pickedFile = await imagePicker.pickImage(source: ImageSource.gallery);
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
        final precio = precioText.isNotEmpty ? double.tryParse(precioText) : null;

        // Validar que al menos un campo se haya modificado
        if (denominacion.isEmpty && precio == null && imagenSeleccionada == null) {
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
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
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
            SnackBar(
              content: Text('❌ Error: $e'),
              backgroundColor: Colors.red,
            ),
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
                    if (producto['imagen'] != null && (producto['imagen'] as String).isNotEmpty)
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                if (enEdicion)
                  TextField(
                    controller: denominacionController,
                    decoration: InputDecoration(
                      hintText: 'Nombre del producto',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                else
                  Text(
                    producto['denominacion'] ?? 'No configurada',
                    style: TextStyle(
                      color: (producto['tiene_denominacion'] == true) ? Colors.black : Colors.red,
                    ),
                  ),
                const SizedBox(height: 12),

                // SKU (solo lectura)
                Text(
                  'SKU',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(producto['sku'] ?? 'N/A'),
                const SizedBox(height: 12),

                // Precio con aclaración
                Text(
                  'Precio Base del Sistema',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: 'Precio',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                else
                  Text(
                    producto['precio_venta'] != null ? '\$${producto['precio_venta']}' : 'No configurado',
                    style: TextStyle(
                      color: (producto['tiene_precio'] == true) ? Colors.black : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 12),

                // Presentación
                Text(
                  'Presentación',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(
                  (producto['tiene_presentacion'] == true) ? '✅ Configurada' : '❌ No configurada',
                  style: TextStyle(
                    color: (producto['tiene_presentacion'] == true) ? Colors.green : Colors.red,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar Catálogo'),
        backgroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
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
                              Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                'No hay productos',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredProductos.length,
                          itemBuilder: (context, index) {
                            final producto = _filteredProductos[index];
                            final esValido = producto['es_valido_catalogo'] == true;
                            final mostrarEnCatalogo = producto['mostrar_en_catalogo'] == true;

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.grey.shade200,
                                    image: (producto['imagen'] != null && (producto['imagen'] as String).isNotEmpty)
                                        ? DecorationImage(
                                            image: NetworkImage(producto['imagen'] as String),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: (producto['imagen'] == null || (producto['imagen'] as String).isEmpty)
                                      ? const Icon(Icons.image_not_supported, size: 24)
                                      : null,
                                ),
                                title: Text(
                                  producto['denominacion'] ?? 'Sin nombre',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Switch(
                                      value: mostrarEnCatalogo,
                                      onChanged: esValido
                                          ? (_) => _toggleMostrarEnCatalogo(producto)
                                          : null,
                                      activeColor: Colors.green,
                                    ),
                                  ],
                                ),
                                onTap: () => _mostrarDetallesProducto(producto),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
