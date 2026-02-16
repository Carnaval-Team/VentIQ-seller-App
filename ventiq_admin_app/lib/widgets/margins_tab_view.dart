import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/margin_service.dart';

class MarginsTabView extends StatefulWidget {
  const MarginsTabView({super.key});

  @override
  State<MarginsTabView> createState() => _MarginsTabViewState();
}

class _MarginsTabViewState extends State<MarginsTabView> {
  List<Map<String, dynamic>> _margenes = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMargenes();
  }

  Future<void> _loadMargenes() async {
    setState(() => _isLoading = true);
    try {
      final margenes = await MarginService.getMargenesComerciales();
      if (mounted) {
        setState(() {
          _margenes = margenes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando márgenes: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredMargenes {
    if (_searchQuery.isEmpty) return _margenes;
    final q = _searchQuery.toLowerCase();
    return _margenes.where((m) {
      final nombre = (m['producto_denominacion'] ?? '').toString().toLowerCase();
      final sku = (m['producto_sku'] ?? '').toString().toLowerCase();
      return nombre.contains(q) || sku.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header con búsqueda y botón agregar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por producto...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showCreateDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        // Info banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Los márgenes configurados se verifican al completar recepciones. '
                    'Si el margen no se cumple, el precio de venta se ajusta automáticamente. '
                    'El monto fijo se expresa en CUP.',
                    style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Lista
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredMargenes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.trending_up, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No hay márgenes configurados'
                                : 'No se encontraron resultados',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Presione "Nuevo" para agregar un margen',
                              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                            ),
                          ],
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMargenes,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        itemCount: _filteredMargenes.length,
                        itemBuilder: (context, index) => _buildMargenCard(_filteredMargenes[index]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildMargenCard(Map<String, dynamic> margen) {
    final tipoMargen = margen['tipo_margen'] as int? ?? 1;
    final margenDeseado = (margen['margen_deseado'] as num?)?.toDouble() ?? 0;
    final precioVenta = (margen['precio_venta_cup'] as num?)?.toDouble();
    final precioPromedio = (margen['precio_promedio_usd'] as num?)?.toDouble();
    final fechaDesde = margen['fecha_desde']?.toString() ?? '';
    final fechaHasta = margen['fecha_hasta']?.toString();
    final esPorcentaje = tipoMargen == 1;

    // Verificar si el margen está vigente
    final hoy = DateTime.now();
    final desde = DateTime.tryParse(fechaDesde);
    final hasta = fechaHasta != null ? DateTime.tryParse(fechaHasta) : null;
    final vigente = desde != null &&
        !desde.isAfter(hoy) &&
        (hasta == null || !hasta.isBefore(hoy));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: vigente ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: producto + acciones
            Row(
              children: [
                // Imagen del producto
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: margen['producto_imagen'] != null &&
                          (margen['producto_imagen'] as String).isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            margen['producto_imagen'],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.inventory_2, color: Colors.grey[400], size: 20),
                          ),
                        )
                      : Icon(Icons.inventory_2, color: Colors.grey[400], size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        margen['producto_denominacion'] ?? 'Producto',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (margen['producto_sku'] != null)
                        Text(
                          'SKU: ${margen['producto_sku']}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
                // Badge vigente
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: vigente
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: vigente
                          ? Colors.green.withOpacity(0.5)
                          : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    vigente ? 'Vigente' : 'No vigente',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: vigente ? Colors.green[700] : Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (action) {
                    if (action == 'edit') _showEditDialog(margen);
                    if (action == 'delete') _showDeleteDialog(margen);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Editar')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),

            // Detalles del margen
            Row(
              children: [
                // Margen
                Expanded(
                  child: _buildDetailChip(
                    icon: Icons.trending_up,
                    label: 'Margen',
                    value: esPorcentaje
                        ? '${margenDeseado.toStringAsFixed(1)}%'
                        : '${margenDeseado.toStringAsFixed(2)} CUP',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                // Tipo
                Expanded(
                  child: _buildDetailChip(
                    icon: esPorcentaje ? Icons.percent : Icons.attach_money,
                    label: 'Tipo',
                    value: esPorcentaje ? 'Porcentaje' : 'Monto fijo (CUP)',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Precio venta actual
                Expanded(
                  child: _buildDetailChip(
                    icon: Icons.sell,
                    label: 'Precio venta',
                    value: precioVenta != null
                        ? '${precioVenta.toStringAsFixed(2)} CUP'
                        : 'Sin precio',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                // Costo promedio
                Expanded(
                  child: _buildDetailChip(
                    icon: Icons.analytics,
                    label: 'Costo prom.',
                    value: precioPromedio != null
                        ? '\$${precioPromedio.toStringAsFixed(2)} USD'
                        : 'Sin costo',
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Fechas
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  'Desde: ${_formatDate(fechaDesde)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                if (fechaHasta != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Hasta: ${_formatDate(fechaHasta)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ] else ...[
                  const SizedBox(width: 12),
                  Text(
                    'Sin fecha fin',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400], fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                Text(
                  value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  // =====================================================
  // DIALOGO CREAR MARGEN
  // =====================================================
  void _showCreateDialog() {
    final margenController = TextEditingController();
    int tipoMargen = 1; // 1=%, 2=monto fijo
    DateTime fechaDesde = DateTime.now();
    DateTime? fechaHasta;
    Map<String, dynamic>? productoSeleccionado;
    List<Map<String, dynamic>> resultadosBusqueda = [];
    final searchController = TextEditingController();
    bool buscando = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.trending_up, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Nuevo Margen'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Buscar producto
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Buscar producto',
                      hintText: 'Nombre, SKU o descripción...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: buscando
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {
                                      resultadosBusqueda = [];
                                      productoSeleccionado = null;
                                    });
                                  },
                                )
                              : null,
                    ),
                    onChanged: (query) async {
                      if (query.length < 2) {
                        setDialogState(() => resultadosBusqueda = []);
                        return;
                      }
                      setDialogState(() => buscando = true);
                      final results = await MarginService.buscarProductos(query);
                      setDialogState(() {
                        resultadosBusqueda = results;
                        buscando = false;
                      });
                    },
                  ),

                  // Resultados de búsqueda
                  if (resultadosBusqueda.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: resultadosBusqueda.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (_, i) {
                          final prod = resultadosBusqueda[i];
                          final nombre = prod['denominacion'] ?? '';
                          final sku = prod['sku']?.toString() ?? '';
                          final descripcion = prod['descripcion']?.toString() ?? '';
                          final imagen = prod['imagen']?.toString() ?? '';
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                productoSeleccionado = prod;
                                searchController.text = nombre;
                                resultadosBusqueda = [];
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Row(
                                children: [
                                  // Imagen del producto
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: imagen.isNotEmpty
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: Image.network(
                                              imagen,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(Icons.inventory_2, color: Colors.grey[400], size: 20),
                                            ),
                                          )
                                        : Icon(Icons.inventory_2, color: Colors.grey[400], size: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  // Info del producto
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nombre,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (sku.isNotEmpty)
                                          Text(
                                            'SKU: $sku',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                          ),
                                        if (descripcion.isNotEmpty)
                                          Text(
                                            descripcion,
                                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  if (resultadosBusqueda.isEmpty && searchController.text.length >= 2 && !buscando && productoSeleccionado == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No se encontraron productos para "${searchController.text}"',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
                      ),
                    ),

                  // Producto seleccionado
                  if (productoSeleccionado != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          // Imagen del producto seleccionado
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: (productoSeleccionado!['imagen'] != null &&
                                    (productoSeleccionado!['imagen'] as String).isNotEmpty)
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      productoSeleccionado!['imagen'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                                    ),
                                  )
                                : Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  productoSeleccionado!['denominacion'] ?? '',
                                  style: TextStyle(fontSize: 13, color: Colors.green[700], fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (productoSeleccionado!['sku'] != null &&
                                    (productoSeleccionado!['sku'] as String).isNotEmpty)
                                  Text(
                                    'SKU: ${productoSeleccionado!['sku']}',
                                    style: TextStyle(fontSize: 11, color: Colors.green[600]),
                                  ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setDialogState(() {
                              productoSeleccionado = null;
                              searchController.clear();
                            }),
                            child: Icon(Icons.close, size: 18, color: Colors.green[700]),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Tipo de margen
                  const Text('Tipo de margen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Porcentaje %'), icon: Icon(Icons.percent, size: 16)),
                      ButtonSegment(value: 2, label: Text('Monto fijo CUP'), icon: Icon(Icons.attach_money, size: 16)),
                    ],
                    selected: {tipoMargen},
                    onSelectionChanged: (v) => setDialogState(() => tipoMargen = v.first),
                  ),

                  const SizedBox(height: 16),

                  // Valor del margen
                  TextField(
                    controller: margenController,
                    decoration: InputDecoration(
                      labelText: tipoMargen == 1 ? 'Margen deseado (%)' : 'Margen deseado (CUP)',
                      hintText: tipoMargen == 1 ? 'Ej: 30' : 'Ej: 500',
                      border: const OutlineInputBorder(),
                      suffixText: tipoMargen == 1 ? '%' : 'CUP',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),

                  if (tipoMargen == 2) ...[
                    const SizedBox(height: 4),
                    Text(
                      'El monto se expresa en CUP (pesos cubanos)',
                      style: TextStyle(fontSize: 11, color: Colors.orange[700], fontStyle: FontStyle.italic),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Fecha desde
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.calendar_today, size: 20),
                    title: const Text('Fecha desde', style: TextStyle(fontSize: 13)),
                    subtitle: Text(_formatDate(fechaDesde.toIso8601String()), style: const TextStyle(fontSize: 12)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fechaDesde,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setDialogState(() => fechaDesde = picked);
                    },
                  ),

                  // Fecha hasta
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.event, size: 20),
                    title: const Text('Fecha hasta (opcional)', style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      fechaHasta != null ? _formatDate(fechaHasta!.toIso8601String()) : 'Sin fecha fin',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: fechaHasta != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setDialogState(() => fechaHasta = null),
                          )
                        : null,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fechaHasta ?? fechaDesde,
                        firstDate: fechaDesde,
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setDialogState(() => fechaHasta = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (productoSeleccionado == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Seleccione un producto'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                final margenVal = double.tryParse(margenController.text);
                if (margenVal == null || margenVal <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ingrese un margen válido'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                try {
                  await MarginService.crearMargen(
                    idProducto: productoSeleccionado!['id'],
                    margenDeseado: margenVal,
                    tipoMargen: tipoMargen,
                    fechaDesde: fechaDesde,
                    fechaHasta: fechaHasta,
                  );
                  if (mounted) Navigator.pop(context);
                  _loadMargenes();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Margen creado exitosamente'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // DIALOGO EDITAR MARGEN
  // =====================================================
  void _showEditDialog(Map<String, dynamic> margen) {
    final margenController = TextEditingController(
      text: (margen['margen_deseado'] as num?)?.toString() ?? '',
    );
    int tipoMargen = margen['tipo_margen'] as int? ?? 1;
    DateTime fechaDesde = DateTime.tryParse(margen['fecha_desde']?.toString() ?? '') ?? DateTime.now();
    DateTime? fechaHasta = margen['fecha_hasta'] != null
        ? DateTime.tryParse(margen['fecha_hasta'].toString())
        : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Editar Margen'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Producto (solo lectura)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2, color: Colors.grey[600], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            margen['producto_denominacion'] ?? 'Producto',
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tipo de margen
                  const Text('Tipo de margen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Porcentaje %'), icon: Icon(Icons.percent, size: 16)),
                      ButtonSegment(value: 2, label: Text('Monto fijo CUP'), icon: Icon(Icons.attach_money, size: 16)),
                    ],
                    selected: {tipoMargen},
                    onSelectionChanged: (v) => setDialogState(() => tipoMargen = v.first),
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: margenController,
                    decoration: InputDecoration(
                      labelText: tipoMargen == 1 ? 'Margen deseado (%)' : 'Margen deseado (CUP)',
                      border: const OutlineInputBorder(),
                      suffixText: tipoMargen == 1 ? '%' : 'CUP',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),

                  if (tipoMargen == 2) ...[
                    const SizedBox(height: 4),
                    Text(
                      'El monto se expresa en CUP (pesos cubanos)',
                      style: TextStyle(fontSize: 11, color: Colors.orange[700], fontStyle: FontStyle.italic),
                    ),
                  ],

                  const SizedBox(height: 16),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.calendar_today, size: 20),
                    title: const Text('Fecha desde', style: TextStyle(fontSize: 13)),
                    subtitle: Text(_formatDate(fechaDesde.toIso8601String()), style: const TextStyle(fontSize: 12)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fechaDesde,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setDialogState(() => fechaDesde = picked);
                    },
                  ),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.event, size: 20),
                    title: const Text('Fecha hasta (opcional)', style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      fechaHasta != null ? _formatDate(fechaHasta!.toIso8601String()) : 'Sin fecha fin',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: fechaHasta != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setDialogState(() => fechaHasta = null),
                          )
                        : null,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fechaHasta ?? fechaDesde,
                        firstDate: fechaDesde,
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setDialogState(() => fechaHasta = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final margenVal = double.tryParse(margenController.text);
                if (margenVal == null || margenVal <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ingrese un margen válido'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                try {
                  await MarginService.actualizarMargen(
                    idMargen: margen['id'],
                    margenDeseado: margenVal,
                    tipoMargen: tipoMargen,
                    fechaDesde: fechaDesde,
                    fechaHasta: fechaHasta,
                    limpiarFechaHasta: fechaHasta == null,
                  );
                  if (mounted) Navigator.pop(context);
                  _loadMargenes();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Margen actualizado'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // DIALOGO ELIMINAR MARGEN
  // =====================================================
  void _showDeleteDialog(Map<String, dynamic> margen) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Eliminar Margen'),
          ],
        ),
        content: Text(
          '¿Está seguro de eliminar el margen de "${margen['producto_denominacion']}"?\n\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await MarginService.eliminarMargen(margen['id']);
                if (mounted) Navigator.pop(context);
                _loadMargenes();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Margen eliminado'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
