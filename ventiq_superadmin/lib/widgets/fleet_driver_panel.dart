import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/fleet_models.dart';

class FleetDriverPanel extends StatefulWidget {
  final List<RepartidorFlota> repartidores;
  final RepartidorFlota? selected;
  final ValueChanged<RepartidorFlota> onDriverTap;
  final int pointsLimit;
  final ValueChanged<int> onPointsLimitChanged;
  final bool isLoadingRoute;

  const FleetDriverPanel({
    super.key,
    required this.repartidores,
    required this.selected,
    required this.onDriverTap,
    required this.pointsLimit,
    required this.onPointsLimitChanged,
    this.isLoadingRoute = false,
  });

  @override
  State<FleetDriverPanel> createState() => _FleetDriverPanelState();
}

class _FleetDriverPanelState extends State<FleetDriverPanel> {
  String _searchQuery = '';
  String _filtroEstado = 'todos';

  List<RepartidorFlota> get _filteredDrivers {
    var list = widget.repartidores;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((r) =>
              r.nombre.toLowerCase().contains(q) ||
              (r.telefono?.contains(q) ?? false))
          .toList();
    }

    if (_filtroEstado != 'todos') {
      final estado = EstadoRepartidor.values.firstWhere(
        (e) => e.name == _filtroEstado,
        orElse: () => EstadoRepartidor.activo,
      );
      list = list.where((r) => r.estado == estado).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final activos =
        widget.repartidores.where((r) => r.estado == EstadoRepartidor.activo).length;
    final estacionados = widget.repartidores
        .where((r) => r.estado == EstadoRepartidor.estacionado)
        .length;
    final inactivos = widget.repartidores
        .where((r) => r.estado == EstadoRepartidor.inactivo)
        .length;

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header con contadores
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Repartidores',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatChip(
                      activos.toString(),
                      'Activos',
                      const Color(0xFF4CAF50),
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      estacionados.toString(),
                      'Estac.',
                      const Color(0xFFFF9800),
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      inactivos.toString(),
                      'Inact.',
                      const Color(0xFFF44336),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Barra de búsqueda y filtros
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar chofer...',
                    prefixIcon:
                        const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildFilterChip('todos', 'Todos'),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _buildFilterChip('activo', 'Activos'),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _buildFilterChip('estacionado', 'Estac.'),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _buildFilterChip('inactivo', 'Inact.'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Selector de puntos del historial
                Row(
                  children: [
                    const Icon(Icons.timeline, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    const Text(
                      'Puntos ruta:',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    _buildPointsChip(50),
                    const SizedBox(width: 4),
                    _buildPointsChip(100),
                    const SizedBox(width: 4),
                    _buildPointsChip(500),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Lista de choferes
          Expanded(
            child: _filteredDrivers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_shipping_outlined,
                            size: 48, color: AppColors.textHint),
                        const SizedBox(height: 8),
                        Text(
                          'Sin repartidores',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredDrivers.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, index) {
                      final driver = _filteredDrivers[index];
                      final isSelected =
                          widget.selected != null && widget.selected!.id == driver.id;
                      return _buildDriverCard(driver, isSelected);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String count, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isActive = _filtroEstado == value;
    return GestureDetector(
      onTap: () => setState(() => _filtroEstado = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildPointsChip(int value) {
    final isActive = widget.pointsLimit == value;
    return GestureDetector(
      onTap: () => widget.onPointsLimitChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.secondary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          value.toString(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDriverCard(RepartidorFlota driver, bool isSelected) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: isSelected
            ? AppColors.primary.withOpacity(0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => widget.onDriverTap(driver),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.3)
                    : AppColors.divider,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: avatar + nombre + estado
                Row(
                  children: [
                    // Avatar con color de estado
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: driver.colorEstado.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: driver.colorEstado, width: 2),
                      ),
                      child: Icon(
                        driver.estadoIcon,
                        color: driver.colorEstado,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.nombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (driver.telefono != null)
                            Text(
                              driver.telefono!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Badge de estado
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: driver.colorEstado.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        driver.estadoLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: driver.colorEstado,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Info secundaria
                Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      driver.tiempoDesdeUltimaActualizacion,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    if (driver.ordenesAsignadas.isNotEmpty) ...[
                      Icon(Icons.shopping_bag,
                          size: 13, color: AppColors.secondary),
                      const SizedBox(width: 4),
                      Text(
                        '${driver.ordenesAsignadas.length} orden${driver.ordenesAsignadas.length > 1 ? 'es' : ''}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.secondary),
                      ),
                    ],
                  ],
                ),

                // Órdenes expandibles (solo si está seleccionado)
                if (isSelected && driver.ordenesAsignadas.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  ...driver.ordenesAsignadas.map((orden) => _buildOrdenTile(orden)),
                  if (widget.isLoadingRoute)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Cargando ruta...',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrdenTile(OrdenAsignada orden) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Orden #${orden.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '\$${orden.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (orden.direccion != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on,
                    size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    orden.direccion!,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (orden.detalles.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...orden.detalles.map((detalle) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${detalle.productoNombre} x${detalle.cantidad}',
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '\$${(detalle.precio * detalle.cantidad).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
