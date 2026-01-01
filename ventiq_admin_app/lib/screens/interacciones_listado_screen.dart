import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/interacciones_service.dart';

class InteraccionesListadoScreen extends StatefulWidget {
  final int idTienda;
  final String tipoInteraccion; // 'tienda' o 'productos'

  const InteraccionesListadoScreen({
    super.key,
    required this.idTienda,
    required this.tipoInteraccion,
  });

  @override
  State<InteraccionesListadoScreen> createState() => _InteraccionesListadoScreenState();
}

class _InteraccionesListadoScreenState extends State<InteraccionesListadoScreen> {
  final InteraccionesService _interaccionesService = InteraccionesService();

  late PageController _pageController;
  int _currentPage = 1;
  int _pageSize = 10;
  bool _isLoading = false;

  List<Map<String, dynamic>> _interacciones = [];
  int _totalInteracciones = 0;
  int _totalPages = 1;

  // Para filtro de productos
  List<Map<String, dynamic>> _productos = [];
  int? _productoSeleccionado;
  bool _mostrarFiltroProducto = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadData();
    if (widget.tipoInteraccion == 'productos') {
      _loadProductos();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      late Map<String, dynamic> result;

      if (widget.tipoInteraccion == 'tienda') {
        result = await _interaccionesService.getInteraccionesTiendaPaginado(
          widget.idTienda,
          page: _currentPage,
          pageSize: _pageSize,
        );
      } else if (widget.tipoInteraccion == 'productos') {
        if (_productoSeleccionado != null) {
          result = await _interaccionesService.getRatingsProductoPaginado(
            _productoSeleccionado!,
            page: _currentPage,
            pageSize: _pageSize,
          );
        } else {
          result = await _interaccionesService.getInteraccionesProductosPaginado(
            widget.idTienda,
            page: _currentPage,
            pageSize: _pageSize,
          );
        }
      }

      if (mounted) {
        setState(() {
          _interacciones = List<Map<String, dynamic>>.from(result['data'] ?? []);
          _totalInteracciones = result['total'] ?? 0;
          _totalPages = result['totalPages'] ?? 1;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando datos: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadProductos() async {
    try {
      final productos = await _interaccionesService.getProductosTiendaParaFiltro(widget.idTienda);
      if (mounted) {
        setState(() => _productos = productos);
      }
    } catch (e) {
      print('❌ Error cargando productos: $e');
    }
  }

  void _cambiarProductoFiltro(int? idProducto) {
    setState(() {
      _productoSeleccionado = idProducto;
      _currentPage = 1;
    });
    _loadData();
  }

  void _irAPagina(int pagina) {
    if (pagina >= 1 && pagina <= _totalPages) {
      setState(() => _currentPage = pagina);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.tipoInteraccion == 'tienda'
        ? 'Interacciones de la Tienda'
        : 'Interacciones de Productos';

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filtro de productos (solo si es tipo productos)
          if (widget.tipoInteraccion == 'productos') _buildFiltroProducto(),

          // Contenido
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _interacciones.isEmpty
                    ? const Center(
                        child: Text('No hay interacciones'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _interacciones.length,
                        itemBuilder: (context, index) {
                          final interaccion = _interacciones[index];
                          return _buildTarjetaInteraccion(interaccion);
                        },
                      ),
          ),

          // Paginación
          if (_totalPages > 1) _buildPaginacion(),
        ],
      ),
    );
  }

  Widget _buildFiltroProducto() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primary.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filtrar por Producto',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              IconButton(
                icon: Icon(
                  _mostrarFiltroProducto ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _mostrarFiltroProducto = !_mostrarFiltroProducto);
                },
              ),
            ],
          ),
          if (_mostrarFiltroProducto) ...[
            const SizedBox(height: 12),
            DropdownButton<int?>(
              isExpanded: true,
              value: _productoSeleccionado,
              hint: const Text('Seleccionar producto...'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todos los productos'),
                ),
                ..._productos.map((producto) {
                  final id = (producto['id'] as num).toInt();
                  final denominacion = producto['denominacion'] as String;
                  final promedio = (producto['promedio_rating'] as num).toDouble();
                  final cantidad = (producto['cantidad_ratings'] as num).toInt();

                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Text(
                      '$denominacion (⭐ ${promedio.toStringAsFixed(1)} - $cantidad)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              ],
              onChanged: _cambiarProductoFiltro,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTarjetaInteraccion(Map<String, dynamic> interaccion) {
    final rating = (interaccion['rating'] as num).toDouble();
    final comentario = interaccion['comentario'] as String?;
    final fecha = interaccion['created_at'] as String?;
    final denominacion = interaccion['denominacion'] as String?;

    Color getRatingColor(double rating) {
      if (rating >= 4) return Colors.green;
      if (rating == 3) return Colors.orange;
      return Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (denominacion != null)
                        Text(
                          denominacion,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: getRatingColor(rating).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '⭐ ${rating.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: getRatingColor(rating),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),

            // Comentario
            if (comentario != null && comentario.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  comentario,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],

            // Fecha
            if (fecha != null) ...[
              const SizedBox(height: 12),
              Text(
                _formatearFecha(fecha),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaginacion() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(
            color: Colors.grey[300]!,
          ),
        ),
      ),
      child: Column(
        children: [
          // Información de página
          Text(
            'Página $_currentPage de $_totalPages ($_totalInteracciones total)',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),

          // Botones de navegación
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Botón anterior
              ElevatedButton.icon(
                onPressed: _currentPage > 1 ? () => _irAPagina(_currentPage - 1) : null,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Anterior'),
              ),
              const SizedBox(width: 12),

              // Números de página
              ..._buildBotonesPagina(),

              const SizedBox(width: 12),

              // Botón siguiente
              ElevatedButton.icon(
                onPressed: _currentPage < _totalPages ? () => _irAPagina(_currentPage + 1) : null,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Siguiente'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBotonesPagina() {
    final botones = <Widget>[];
    final inicio = (_currentPage - 2).clamp(1, _totalPages);
    final fin = (_currentPage + 2).clamp(1, _totalPages);

    if (inicio > 1) {
      botones.add(
        TextButton(
          onPressed: () => _irAPagina(1),
          child: const Text('1'),
        ),
      );
      if (inicio > 2) {
        botones.add(const Text('...'));
      }
    }

    for (int i = inicio; i <= fin; i++) {
      if (i == _currentPage) {
        botones.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$i',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      } else {
        botones.add(
          TextButton(
            onPressed: () => _irAPagina(i),
            child: Text('$i'),
          ),
        );
      }
    }

    if (fin < _totalPages) {
      if (fin < _totalPages - 1) {
        botones.add(const Text('...'));
      }
      botones.add(
        TextButton(
          onPressed: () => _irAPagina(_totalPages),
          child: Text('$_totalPages'),
        ),
      );
    }

    return botones;
  }

  String _formatearFecha(String fecha) {
    try {
      final dateTime = DateTime.parse(fecha);
      final ahora = DateTime.now();
      final diferencia = ahora.difference(dateTime);

      if (diferencia.inDays == 0) {
        if (diferencia.inHours == 0) {
          return 'Hace ${diferencia.inMinutes} minutos';
        }
        return 'Hace ${diferencia.inHours} horas';
      } else if (diferencia.inDays == 1) {
        return 'Ayer';
      } else if (diferencia.inDays < 7) {
        return 'Hace ${diferencia.inDays} días';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return fecha;
    }
  }
}
