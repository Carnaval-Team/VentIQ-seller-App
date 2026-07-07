import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';

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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
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
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.tune, color: AppColors.primary),
                  tooltip: 'Ajustar cantidad',
                  onPressed: () => _showAjusteDialog(item, prod, stock),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAjusteDialog(
    Map<String, dynamic> item,
    Map<String, dynamic> prod,
    double stockActual,
  ) async {
    final cantidadModController = TextEditingController();
    final motivoController = TextEditingController();
    final observacionesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AjusteDialogContent(
        prod: prod,
        stockActual: stockActual,
        cantidadModController: cantidadModController,
        motivoController: motivoController,
        observacionesController: observacionesController,
        formKey: formKey,
        onConfirm: (esAdd, cantidadMod, motivo, obs) async {
          final cantidadNueva = esAdd
              ? stockActual + cantidadMod
              : stockActual - cantidadMod;
          await _ejecutarAjuste(
            ctx: ctx,
            item: item,
            stockActual: stockActual,
            cantidadNueva: cantidadNueva,
            motivo: motivo,
            observaciones: obs,
          );
        },
      ),
    );

    cantidadModController.dispose();
    motivoController.dispose();
    observacionesController.dispose();
  }

  Future<void> _ejecutarAjuste({
    required BuildContext ctx,
    required Map<String, dynamic> item,
    required double stockActual,
    required double cantidadNueva,
    required String motivo,
    required String observaciones,
  }) async {
    try {
      final userUuid = await UserPreferencesService().getUserId();
      if (userUuid == null || userUuid.isEmpty) {
        throw Exception('No se pudo obtener el usuario autenticado');
      }

      final idProducto = item['id_producto'] as int;
      final idPresentacion = item['id_presentacion'] as int?;
      final idUbicacion = widget.idZonaDestino!;

      // Tipo 3 = faltante (incremento), tipo 4 = exceso (decremento)
      final idTipoOperacion = cantidadNueva >= stockActual ? 3 : 4;

      final result = await InventoryService.insertInventoryAdjustment(
        idProducto: idProducto,
        idUbicacion: idUbicacion,
        idPresentacion: idPresentacion ?? 0,
        cantidadAnterior: stockActual,
        cantidadNueva: cantidadNueva,
        motivo: motivo,
        observaciones: observaciones.isNotEmpty
            ? observaciones
            : 'Ajuste de inventario en zona de consignación - ${widget.tituloContrato}',
        uuid: userUuid,
        idTipoOperacion: idTipoOperacion,
      );

      if (!mounted) return;

      if (result['status'] == 'success') {
        Navigator.of(ctx).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ajuste registrado. Diferencia: ${(cantidadNueva - stockActual) >= 0 ? '+' : ''}${(cantidadNueva - stockActual).toStringAsFixed(0)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${result['message'] ?? 'Error desconocido'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar ajuste: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo de ajuste: elige adicionar / restar y cantidad a modificar
// ─────────────────────────────────────────────────────────────────────────────
class _AjusteDialogContent extends StatefulWidget {
  final Map<String, dynamic> prod;
  final double stockActual;
  final TextEditingController cantidadModController;
  final TextEditingController motivoController;
  final TextEditingController observacionesController;
  final GlobalKey<FormState> formKey;
  final Future<void> Function(
    bool esAdicionar,
    double cantidadMod,
    String motivo,
    String observaciones,
  ) onConfirm;

  const _AjusteDialogContent({
    required this.prod,
    required this.stockActual,
    required this.cantidadModController,
    required this.motivoController,
    required this.observacionesController,
    required this.formKey,
    required this.onConfirm,
  });

  @override
  State<_AjusteDialogContent> createState() => _AjusteDialogContentState();
}

class _AjusteDialogContentState extends State<_AjusteDialogContent> {
  bool _esAdicionar = true;
  bool _isSubmitting = false;

  double get _cantidadMod =>
      double.tryParse(widget.cantidadModController.text.trim()) ?? 0.0;

  double get _cantidadResultante =>
      _esAdicionar
          ? widget.stockActual + _cantidadMod
          : widget.stockActual - _cantidadMod;

  @override
  void initState() {
    super.initState();
    widget.cantidadModController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.cantidadModController.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultante = _cantidadResultante;
    final resultanteNegativa = resultante < 0;
    final diferencia = resultante - widget.stockActual;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.tune, color: AppColors.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text('Ajuste de Inventario', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      content: Form(
        key: widget.formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.prod['denominacion'] ?? 'Producto',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                'SKU: ${widget.prod['sku'] ?? 'N/A'}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              // Chip de stock actual
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 15, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Stock actual: ${widget.stockActual.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Toggle Adicionar / Restar
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _esAdicionar = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _esAdicionar ? Colors.green[600] : Colors.grey[200],
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_circle_outline,
                              size: 18,
                              color: _esAdicionar ? Colors.white : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Adicionar',
                              style: TextStyle(
                                color: _esAdicionar ? Colors.white : Colors.grey[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _esAdicionar = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_esAdicionar ? Colors.red[600] : Colors.grey[200],
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                              color: !_esAdicionar ? Colors.white : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Restar',
                              style: TextStyle(
                                color: !_esAdicionar ? Colors.white : Colors.grey[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Campo cantidad a modificar
              TextFormField(
                controller: widget.cantidadModController,
                decoration: InputDecoration(
                  labelText: 'Cantidad a ${_esAdicionar ? 'adicionar' : 'restar'} *',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(
                    _esAdicionar ? Icons.add : Icons.remove,
                    color: _esAdicionar ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingrese la cantidad';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Ingrese una cantidad mayor a 0';
                  if (!_esAdicionar && n > widget.stockActual) {
                    return 'No puede restar más de ${widget.stockActual.toStringAsFixed(0)}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              // Preview de resultado
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: resultanteNegativa
                      ? Colors.red[50]
                      : (_esAdicionar ? Colors.green[50] : Colors.orange[50]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: resultanteNegativa
                        ? Colors.red[300]!
                        : (_esAdicionar ? Colors.green[300]! : Colors.orange[300]!),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Quedará en stock:',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                    Row(
                      children: [
                        if (_cantidadMod > 0)
                          Text(
                            '(${diferencia >= 0 ? '+' : ''}${diferencia.toStringAsFixed(0)})  ',
                            style: TextStyle(
                              fontSize: 12,
                              color: diferencia >= 0 ? Colors.green[700] : Colors.red[700],
                            ),
                          ),
                        Text(
                          resultante.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: resultanteNegativa
                                ? Colors.red[700]
                                : (_esAdicionar ? Colors.green[700] : Colors.orange[700]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: widget.motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_note),
                  hintText: 'Ej: Conteo físico, diferencia, etc.',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingrese el motivo';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: widget.observacionesController,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.comment_outlined),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        _isSubmitting
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Confirmar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (!widget.formKey.currentState!.validate()) return;
                  setState(() => _isSubmitting = true);
                  await widget.onConfirm(
                    _esAdicionar,
                    _cantidadMod,
                    widget.motivoController.text.trim(),
                    widget.observacionesController.text.trim(),
                  );
                  if (mounted) setState(() => _isSubmitting = false);
                },
              ),
      ],
    );
  }
}
