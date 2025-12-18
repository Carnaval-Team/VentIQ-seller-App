import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';

class ProductosZonaDestinoScreen extends StatefulWidget {
  final int idContrato;
  final String tituloContrato;
  final int? idZonaDestino;

  const ProductosZonaDestinoScreen({
    super.key,
    required this.idContrato,
    required this.tituloContrato,
    this.idZonaDestino,
  });

  @override
  State<ProductosZonaDestinoScreen> createState() => _ProductosZonaDestinoScreenState();
}

class _ProductosZonaDestinoScreenState extends State<ProductosZonaDestinoScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _stockFinalList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (widget.idZonaDestino == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      debugPrint('🔍 [DEBUG] Buscando stock directamente en zona: ${widget.idZonaDestino}');

      // Obtener todos los registros de inventario de la zona ordenados por ID desc
      final stockReal = await ConsignacionService.getStockEnZonaDestino(
        widget.idContrato, 
        widget.idZonaDestino!
      );
      
      // Filtrar para quedarnos solo con el ÚLTIMO registro de cada producto/presentación
      final Map<String, Map<String, dynamic>> ultimosRegistros = {};
      
      for (var item in stockReal) {
        final idProd = item['id_producto'];
        final idPres = item['id_presentacion'] ?? 0;
        final key = '$idProd-$idPres';

        if (!ultimosRegistros.containsKey(key)) {
          ultimosRegistros[key] = item;
        }
      }

      final finalItems = ultimosRegistros.values.toList();
      
      // Ordenar alfabéticamente por denominación
      finalItems.sort((a, b) {
        final denA = (a['app_dat_producto']?['denominacion'] ?? '').toString().toLowerCase();
        final denB = (b['app_dat_producto']?['denominacion'] ?? '').toString().toLowerCase();
        return denA.compareTo(denB);
      });

      setState(() {
        _stockFinalList = finalItems;
        _isLoading = false;
      });

      debugPrint('✅ [DEBUG] Stock final procesado: ${_stockFinalList.length} productos/presentaciones');
    } catch (e) {
      debugPrint('❌ Error cargando stock de inventario: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stock en Zona de Recepción'),
            Text(
              widget.tituloContrato,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: widget.idZonaDestino == null
            ? _buildNoZoneState()
            : _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _stockFinalList.isEmpty
                    ? _buildEmptyState()
                    : _buildStockList(),
      ),
    );
  }

  Widget _buildNoZoneState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 80, color: Colors.orange[400]),
            const SizedBox(height: 16),
            const Text(
              'Zona no configurada',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Este contrato no tiene asignada una zona de recepción. Por favor, configure el layout del almacén para este contrato.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'Zona vacía',
                style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'No se encontraron productos físicos en esta zona de recepción.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStockList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _stockFinalList.length,
      itemBuilder: (context, index) {
        final item = _stockFinalList[index];
        final prod = item['app_dat_producto'];
        final stock = (item['cantidad_final'] as num).toDouble();
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2, color: AppColors.primary),
            ),
            title: Text(
              prod['denominacion'] ?? 'Producto Desconocido',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('SKU: ${prod['sku'] ?? 'N/A'}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  stock.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: stock > 0 ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                const Text(
                  'Disponible',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
