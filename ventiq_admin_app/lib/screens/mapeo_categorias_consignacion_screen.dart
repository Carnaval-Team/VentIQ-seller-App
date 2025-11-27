import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_categoria_service.dart';

class MapeoCategoriesConsignacionScreen extends StatefulWidget {
  const MapeoCategoriesConsignacionScreen({Key? key}) : super(key: key);

  @override
  State<MapeoCategoriesConsignacionScreen> createState() =>
      _MapeoCategoriesConsignacionScreenState();
}

class _MapeoCategoriesConsignacionScreenState
    extends State<MapeoCategoriesConsignacionScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _productosSinMapeo = [];
  List<Map<String, dynamic>> _categorias = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final productos =
          await ConsignacionCategoriaService.getProductosSinMapeo();
      final categorias =
          await ConsignacionCategoriaService.getCategoriasTienda();

      if (mounted) {
        setState(() {
          _productosSinMapeo = productos;
          _categorias = categorias;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error cargando datos: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _asignarCategoria(
    int idProductoConsignacion,
    int idCategoria,
    int? idSubcategoria,
  ) async {
    final success = await ConsignacionCategoriaService.asignarCategoriaProducto(
      idProductoConsignacion: idProductoConsignacion,
      idCategoria: idCategoria,
      idSubcategoria: idSubcategoria,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Categoría asignada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error al asignar categoría'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _mostrarDialogoAsignacion(Map<String, dynamic> producto) {
    int? categoriaSeleccionada;
    int? subcategoriaSeleccionada;
    List<Map<String, dynamic>> subcategorias = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Asignar Categoría'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Producto: ${producto['denominacion_producto']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'De: ${producto['tienda_origen']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Categoría origen: ${producto['categoria_origen'] ?? 'N/A'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Selecciona categoría en tu tienda:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: categoriaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Categoría *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: _categorias.map((cat) {
                    return DropdownMenuItem<int>(
                      value: cat['id'],
                      child: Text(cat['denominacion']),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    setDialogState(() {
                      categoriaSeleccionada = value;
                      subcategoriaSeleccionada = null;
                    });

                    if (value != null) {
                      final subs = await ConsignacionCategoriaService
                          .getSubcategorias(value);
                      setDialogState(() {
                        subcategorias = subs;
                      });
                    }
                  },
                ),
                if (subcategorias.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Subcategoría (opcional):',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: subcategoriaSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Subcategoría',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.subdirectory_arrow_right),
                    ),
                    items: subcategorias.map((subcat) {
                      return DropdownMenuItem<int>(
                        value: subcat['id'],
                        child: Text(subcat['denominacion']),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        subcategoriaSeleccionada = value;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: categoriaSeleccionada == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      _asignarCategoria(
                        producto['id_producto_consignacion'],
                        categoriaSeleccionada!,
                        subcategoriaSeleccionada,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Asignar'),
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
        title: const Text('Mapear Categorías de Consignación'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _productosSinMapeo.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Todos los productos están mapeados',
                        style: TextStyle(
                            fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Puedes vender todos los productos de consignación',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _productosSinMapeo.length,
                    itemBuilder: (context, index) {
                      final producto = _productosSinMapeo[index];
                      return _buildProductoCard(producto);
                    },
                  ),
                ),
    );
  }

  Widget _buildProductoCard(Map<String, dynamic> producto) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2,
                    color: Colors.orange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        producto['denominacion_producto'],
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'SKU: ${producto['sku_producto'] ?? 'N/A'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    'De:',
                    producto['tienda_origen'],
                  ),
                  const SizedBox(height: 6),
                  _buildDetailRow(
                    'Categoría origen:',
                    producto['categoria_origen'] ?? 'N/A',
                  ),
                  if (producto['subcategoria_origen'] != null) ...[
                    const SizedBox(height: 6),
                    _buildDetailRow(
                      'Subcategoría origen:',
                      producto['subcategoria_origen'],
                    ),
                  ],
                  const SizedBox(height: 6),
                  _buildDetailRow(
                    'Disponible:',
                    '${producto['cantidad_disponible'].toInt()} unidades',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _mostrarDialogoAsignacion(producto),
                icon: const Icon(Icons.link),
                label: const Text('Asignar Categoría'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
