import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../services/store_data_service.dart';

class StoreDetailScreen extends StatefulWidget {
  final int storeId;

  const StoreDetailScreen({
    super.key,
    required this.storeId,
  });

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  final StoreDataService _storeDataService = StoreDataService();
  
  Map<String, dynamic>? _storeData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStoreData();
  }

  Future<void> _loadStoreData() async {
    try {
      final data = await _storeDataService.getStoreData(widget.storeId);
      if (mounted) {
        setState(() {
          _storeData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    }
  }

  Widget _buildMapPreview() {
    final lat = (_storeData?['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (_storeData?['longitude'] as num?)?.toDouble() ?? 0.0;

    return FlutterMap(
      options: MapOptions(
        center: LatLng(lat, lng),
        zoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'VentIQAdmin/1.6.0 (+https://ventiq.com; contact: support@ventiq.com)',
          tileSize: 256,
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(
                Uri.parse('https://openstreetmap.org/copyright'),
              ),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(lat, lng),
              width: 40,
              height: 40,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Detalle de Tienda'),
          backgroundColor: AppColors.primary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_storeData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Detalle de Tienda'),
          backgroundColor: AppColors.primary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No se pudo cargar la información de la tienda',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    final hasCoordinates = _storeData!['latitude'] != null && _storeData!['longitude'] != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Tienda'),
        backgroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Foto de la tienda
                if (_storeData!['imagen_url'] != null && (_storeData!['imagen_url'] as String).isNotEmpty)
                  Card(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _storeData!['imagen_url'],
                        height: 250,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 250,
                            color: Colors.grey.shade200,
                            child: Center(
                              child: Icon(Icons.image_not_supported, 
                                size: 48, 
                                color: Colors.grey.shade400),
                            ),
                          );
                        },
                      ),
                    ),
                  )
                else
                  Card(
                    child: Container(
                      height: 250,
                      color: Colors.grey.shade200,
                      child: Center(
                        child: Icon(Icons.image, 
                          size: 48, 
                          color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Información básica
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información de la Tienda',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          'Nombre',
                          _storeData!['denominacion'] ?? 'No especificado',
                          Icons.store,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Dirección',
                          _storeData!['direccion'] ?? 'No especificada',
                          Icons.location_on,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Teléfono',
                          _storeData!['phone'] ?? 'No especificado',
                          Icons.phone,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Ubicación geográfica
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ubicación Geográfica',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          'País',
                          _storeData!['nombre_pais'] ?? 'No especificado',
                          Icons.public,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Provincia/Estado',
                          _storeData!['nombre_estado'] ?? 'No especificado',
                          Icons.location_on,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Coordenadas',
                          _storeData!['latitude'] != null && _storeData!['longitude'] != null
                              ? '${_storeData!['latitude']}, ${_storeData!['longitude']}'
                              : 'No especificadas',
                          Icons.map,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Mapa
                if (hasCoordinates)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ubicación en Mapa',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              height: 350,
                              child: _buildMapPreview(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
