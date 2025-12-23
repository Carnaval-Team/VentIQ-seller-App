import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/interacciones_service.dart';
import '../services/user_preferences_service.dart';
import 'interacciones_listado_screen.dart';

class InteraccionesClientesScreen extends StatefulWidget {
  const InteraccionesClientesScreen({super.key});

  @override
  State<InteraccionesClientesScreen> createState() => _InteraccionesClientesScreenState();
}

class _InteraccionesClientesScreenState extends State<InteraccionesClientesScreen> {
  final InteraccionesService _interaccionesService = InteraccionesService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  int? _idTienda;
  bool _isLoading = true;

  // Datos de la tienda
  Map<String, dynamic>? _estadisticasTienda;
  Map<String, dynamic>? _estadisticasProductos;
  List<Map<String, dynamic>> _ultimasInteraccionesTienda = [];
  List<Map<String, dynamic>> _ultimasInteraccionesProductos = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      // Obtener ID de tienda
      _idTienda = await _userPreferencesService.getIdTienda();
      if (_idTienda == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No se encontró la tienda'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Cargar datos en paralelo
      final results = await Future.wait([
        _interaccionesService.getEstadisticasTiendaRating(_idTienda!),
        _interaccionesService.getEstadisticasProductosRating(_idTienda!),
        _interaccionesService.getUltimasInteraccionesTienda(_idTienda!),
        _interaccionesService.getUltimasInteraccionesProductos(_idTienda!),
      ]);

      if (mounted) {
        setState(() {
          _estadisticasTienda = results[0] as Map<String, dynamic>;
          _estadisticasProductos = results[1] as Map<String, dynamic>;
          _ultimasInteraccionesTienda = List<Map<String, dynamic>>.from(results[2] as List);
          _ultimasInteraccionesProductos = List<Map<String, dynamic>>.from(results[3] as List);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Interacciones'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Estadísticas de la tienda
                    _buildEstadisticasTienda(),
                    const SizedBox(height: 24),

                    // Estadísticas de productos
                    _buildEstadisticasProductos(),
                    const SizedBox(height: 24),

                    // Últimas interacciones de la tienda
                    _buildSeccionInteracciones(
                      titulo: 'Últimas Interacciones de la Tienda',
                      interacciones: _ultimasInteraccionesTienda,
                      tipoInteraccion: 'tienda',
                    ),
                    const SizedBox(height: 24),

                    // Últimas interacciones de productos
                    _buildSeccionInteracciones(
                      titulo: 'Últimas Interacciones de Productos',
                      interacciones: _ultimasInteraccionesProductos,
                      tipoInteraccion: 'productos',
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEstadisticasTienda() {
    if (_estadisticasTienda == null) {
      return const SizedBox.shrink();
    }

    final promedio = (_estadisticasTienda!['promedio_rating'] as num).toDouble();
    final cantidad = (_estadisticasTienda!['cantidad_ratings'] as num).toInt();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calificación de la Tienda',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      promedio.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const Text(
                      'Promedio',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '$cantidad',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const Text(
                      'Calificaciones',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDistribucionEstrellas(_estadisticasTienda!),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticasProductos() {
    if (_estadisticasProductos == null) {
      return const SizedBox.shrink();
    }

    final promedio = (_estadisticasProductos!['promedio_rating'] as num?)?.toDouble() ?? 0.0;
    final cantidad = (_estadisticasProductos!['cantidad_ratings'] as num?)?.toInt() ?? 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => InteraccionesListadoScreen(
              idTienda: _idTienda!,
              tipoInteraccion: 'productos',
            ),
          ),
        );
      },
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Calificación Promedio de Productos',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        promedio.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'Promedio',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        '$cantidad',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'Calificaciones',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDistribucionEstrellas(_estadisticasProductos!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDistribucionEstrellas(Map<String, dynamic> stats) {
    final total = (stats['cantidad_ratings'] as num?)?.toInt() ?? 0;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      children: [
        _buildBarraEstrella(5, (stats['cantidad_5_estrellas'] as num?)?.toInt() ?? 0, total),
        const SizedBox(height: 8),
        _buildBarraEstrella(4, (stats['cantidad_4_estrellas'] as num?)?.toInt() ?? 0, total),
        const SizedBox(height: 8),
        _buildBarraEstrella(3, (stats['cantidad_3_estrellas'] as num?)?.toInt() ?? 0, total),
        const SizedBox(height: 8),
        _buildBarraEstrella(2, (stats['cantidad_2_estrellas'] as num?)?.toInt() ?? 0, total),
        const SizedBox(height: 8),
        _buildBarraEstrella(1, (stats['cantidad_1_estrella'] as num?)?.toInt() ?? 0, total),
      ],
    );
  }

  Widget _buildBarraEstrella(int estrellas, int cantidad, int total) {
    final porcentaje = total > 0 ? (cantidad / total) : 0.0;
    
    Color getColor(int estrellas) {
      if (estrellas >= 4) return Colors.green;
      if (estrellas == 3) return Colors.orange;
      return Colors.red;
    }

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            '$estrellas ⭐',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: porcentaje,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                getColor(estrellas),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '$cantidad',
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionInteracciones({
    required String titulo,
    required List<Map<String, dynamic>> interacciones,
    required String tipoInteraccion,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        if (interacciones.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No hay interacciones',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => InteraccionesListadoScreen(
                    idTienda: _idTienda!,
                    tipoInteraccion: tipoInteraccion,
                  ),
                ),
              );
            },
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: interacciones.length,
              itemBuilder: (context, index) {
                final interaccion = interacciones[index];
                return _buildTarjetaInteraccion(interaccion, tipoInteraccion);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTarjetaInteraccion(Map<String, dynamic> interaccion, String tipo) {
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: getRatingColor(rating).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '⭐ ${rating.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: getRatingColor(rating),
                    ),
                  ),
                ),
              ],
            ),
            if (comentario != null && comentario.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                comentario,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (fecha != null) ...[
              const SizedBox(height: 8),
              Text(
                fecha,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
