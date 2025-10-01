import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/warehouse_service.dart';

enum LocationSelectorType {
  single, // Para recepción, extracción, ajuste
  dual, // Para transferencias (origen y destino)
}

class LocationSelectorWidget extends StatefulWidget {
  final LocationSelectorType type;
  final String title;
  final String? subtitle;
  final WarehouseZone? selectedLocation;
  final WarehouseZone? selectedSourceLocation;
  final WarehouseZone? selectedDestinationLocation;
  final Function(WarehouseZone?)? onLocationChanged;
  final Function(WarehouseZone?)? onSourceLocationChanged;
  final Function(WarehouseZone?)? onDestinationLocationChanged;
  final bool showLocationInfo;
  final bool isRequired;
  final String? validationMessage;

  const LocationSelectorWidget({
    Key? key,
    required this.type,
    required this.title,
    this.subtitle,
    this.selectedLocation,
    this.selectedSourceLocation,
    this.selectedDestinationLocation,
    this.onLocationChanged,
    this.onSourceLocationChanged,
    this.onDestinationLocationChanged,
    this.showLocationInfo = true,
    this.isRequired = true,
    this.validationMessage,
  }) : super(key: key);

  @override
  State<LocationSelectorWidget> createState() => _LocationSelectorWidgetState();
}

class _LocationSelectorWidgetState extends State<LocationSelectorWidget> {
  List<Warehouse> _warehouses = [];
  List<WarehouseZone> _allLocations = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final warehouseService = WarehouseService();
      final warehouses = await warehouseService.listWarehouses();

      // Flatten all zones from all warehouses
      List<WarehouseZone> allLocations = [];
      for (final warehouse in warehouses) {
        for (final zone in warehouse.zones) {
          final zoneWithWarehouse = WarehouseZone(
            id: zone.id, // ← ID único
            warehouseId: warehouse.id,
            name: zone.name,
            code: zone.code,
            type: zone.type,
            conditions: zone.conditions,
            capacity: zone.capacity,
            currentOccupancy: zone.currentOccupancy,
            locations: zone.locations,
            conditionCodes: zone.conditionCodes,
          );
          allLocations.add(zoneWithWarehouse);
        }
      }

      setState(() {
        _warehouses = warehouses;
        _allLocations = allLocations;
        _isLoading = false;
      });

      // ✅ AGREGAR ESTAS LÍNEAS:
      // Reset selected locations to avoid ID conflicts
      if (widget.onLocationChanged != null) {
        widget.onLocationChanged!(null);
      }
      if (widget.onSourceLocationChanged != null) {
        widget.onSourceLocationChanged!(null);
      }
      if (widget.onDestinationLocationChanged != null) {
        widget.onDestinationLocationChanged!(null);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar ubicaciones: $e';
        _isLoading = false;
      });
    }
  }

  String _getWarehouseName(String warehouseId) {
    final warehouse = _warehouses.firstWhere(
      (w) => w.id == warehouseId,
      orElse:
          () => Warehouse(
            id: warehouseId,
            name: 'Almacén desconocido',
            description: 'Almacén no encontrado',
            address: '',
            city: '',
            country: '',
            type: 'desconocido',
            createdAt: DateTime.now(),
            zones: [],
            denominacion: 'Almacén desconocido',
            direccion: '',
          ),
    );
    return warehouse.name;
  }

  Widget _buildLocationDropdown({
    required String label,
    required WarehouseZone? selectedLocation,
    required Function(WarehouseZone?) onChanged,
    String? hint,
    List<WarehouseZone>? excludeLocations,
  }) {
    // Filter locations if needed (for dual mode to avoid same source/destination)
    List<WarehouseZone> availableLocations = _allLocations;
    if (excludeLocations != null && excludeLocations.isNotEmpty) {
      availableLocations =
          _allLocations
              .where(
                (location) =>
                    !excludeLocations.any(
                      (excluded) => excluded.id == location.id,
                    ),
              )
              .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  selectedLocation != null
                      ? AppColors.primary
                      : AppColors.border,
              width: selectedLocation != null ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedLocation?.id,
              hint: Text(
                hint ?? 'Seleccionar ubicación...',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              isExpanded: true,
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    'Sin seleccionar',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                ...availableLocations.map((location) {
                  final warehouseName = _getWarehouseName(location.warehouseId);
                  return DropdownMenuItem<String>(
                    value: location.id,
                    child: Text(
                      '$warehouseName - ${location.name}${location.code.isNotEmpty ? ' (${location.code})' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              ],
              onChanged: (String? selectedId) {
                if (selectedId == null) {
                  onChanged(null);
                } else {
                  final selectedZone = availableLocations.firstWhere(
                    (zone) => zone.id == selectedId,
                  );
                  onChanged(selectedZone);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationInfo(WarehouseZone location) {
    final warehouseName = _getWarehouseName(location.warehouseId);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ubicación seleccionada',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildInfoRow('Almacén', warehouseName),
          _buildInfoRow('Zona', location.name),
          if (location.code.isNotEmpty) _buildInfoRow('Código', location.code),
          if (location.type.isNotEmpty) _buildInfoRow('Tipo', location.type),
          if (location.capacity != null && location.capacity! > 0)
            _buildInfoRow('Capacidad', '${location.capacity} unidades'),
          if (location.currentOccupancy != null &&
              location.currentOccupancy! > 0)
            _buildInfoRow(
              'Ocupación actual',
              '${location.currentOccupancy} unidades',
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationMessage() {
    if (!widget.isRequired || widget.validationMessage == null)
      return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.validationMessage!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.type == LocationSelectorType.dual
                        ? Icons.swap_horiz
                        : Icons.location_on,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Content
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadWarehouses,
                      child: Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else if (_isLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Cargando ubicaciones...',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else if (widget.type == LocationSelectorType.single)
              // Single location selector
              Column(
                children: [
                  _buildLocationDropdown(
                    label: 'Ubicación',
                    selectedLocation: widget.selectedLocation,
                    onChanged: widget.onLocationChanged ?? (location) {},
                  ),
                  _buildValidationMessage(),
                  if (widget.showLocationInfo &&
                      widget.selectedLocation != null)
                    _buildLocationInfo(widget.selectedLocation!),
                ],
              )
            else
              // Dual location selector (for transfers)
              Column(
                children: [
                  // Source location
                  _buildLocationDropdown(
                    label: 'PASO 1: Ubicación de Origen',
                    selectedLocation: widget.selectedSourceLocation,
                    onChanged: widget.onSourceLocationChanged ?? (location) {},
                    hint: 'Seleccionar zona de origen...',
                  ),

                  const SizedBox(height: 20),

                  // Destination location
                  _buildLocationDropdown(
                    label: 'PASO 2: Ubicación de Destino',
                    selectedLocation: widget.selectedDestinationLocation,
                    onChanged:
                        widget.onDestinationLocationChanged ?? (location) {},
                    hint: 'Seleccionar zona de destino...',
                    excludeLocations:
                        widget.selectedSourceLocation != null
                            ? [widget.selectedSourceLocation!]
                            : null,
                  ),

                  _buildValidationMessage(),

                  // Show info for both locations
                  if (widget.showLocationInfo) ...[
                    if (widget.selectedSourceLocation != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.output, color: Colors.orange, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Origen: ${_getWarehouseName(widget.selectedSourceLocation!.warehouseId)} - ${widget.selectedSourceLocation!.name}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (widget.selectedDestinationLocation != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.input, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Destino: ${_getWarehouseName(widget.selectedDestinationLocation!.warehouseId)} - ${widget.selectedDestinationLocation!.name}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
