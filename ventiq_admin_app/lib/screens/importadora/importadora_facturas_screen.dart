import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/importadora_factura.dart';
import '../../services/importadora_facturas_service.dart';
import '../../services/image_picker_service.dart';
import 'estados_factura_screen.dart';

class ImportadoraFacturasScreen extends StatefulWidget {
  const ImportadoraFacturasScreen({super.key});

  @override
  State<ImportadoraFacturasScreen> createState() =>
      _ImportadoraFacturasScreenState();
}

class _ImportadoraFacturasScreenState extends State<ImportadoraFacturasScreen>
    with SingleTickerProviderStateMixin {
  final ImportadoraFacturasService _service = ImportadoraFacturasService();
  late TabController _tabController;

  double _saldoDisponible = 0.0;
  List<RecargaSaldo> _recargas = [];
  List<HistorialSaldo> _historialSaldo = [];
  List<ImportadoraFactura> _facturas = [];
  List<EstadoFactura> _estados = [];

  bool _isLoadingSaldo = true;
  bool _isLoadingFacturas = true;

  final _currencyFmt = NumberFormat.currency(locale: 'es', symbol: '\$');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0) {
          _loadSaldoData();
        } else {
          _loadFacturasData();
        }
      }
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    await Future.wait([_loadSaldoData(), _loadFacturasData()]);
  }

  Future<void> _loadSaldoData() async {
    setState(() => _isLoadingSaldo = true);
    try {
      final results = await Future.wait([
        _service.getSaldoDisponible(),
        _service.getRecargas(),
        _service.getHistorialSaldo(),
      ]);
      setState(() {
        _saldoDisponible = results[0] as double;
        _recargas = results[1] as List<RecargaSaldo>;
        _historialSaldo = results[2] as List<HistorialSaldo>;
        _isLoadingSaldo = false;
      });
    } catch (e) {
      setState(() => _isLoadingSaldo = false);
      _showError('Error cargando saldo: $e');
    }
  }

  Future<void> _loadFacturasData() async {
    setState(() => _isLoadingFacturas = true);
    try {
      final results = await Future.wait([
        _service.getFacturas(),
        _service.getEstados(),
      ]);
      setState(() {
        _facturas = results[0] as List<ImportadoraFactura>;
        _estados = results[1] as List<EstadoFactura>;
        _isLoadingFacturas = false;
      });
    } catch (e) {
      setState(() => _isLoadingFacturas = false);
      _showError('Error cargando facturas: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.success),
    );
  }

  // ==================== DIALOGO RECARGA ====================

  void _showRecargaDialog() {
    final montoCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: const Text('Recargar Saldo'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: montoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Monto *',
                            prefixText: '\$ ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Fecha de Pago *',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today),
                            ),
                            child: Text(_dateFmt.format(selectedDate)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: obsCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Observación',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final monto = double.tryParse(montoCtrl.text) ?? 0;
                        if (monto <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Ingrese un monto válido'),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        try {
                          await _service.agregarRecarga(
                            monto: monto,
                            fechaPago: selectedDate,
                            observacion:
                                obsCtrl.text.trim().isEmpty
                                    ? null
                                    : obsCtrl.text.trim(),
                          );
                          await _loadSaldoData();
                          _showSuccess(
                            'Recarga de ${_currencyFmt.format(monto)} registrada',
                          );
                        } catch (e) {
                          _showError('Error: $e');
                        }
                      },
                      child: const Text('Recargar'),
                    ),
                  ],
                ),
          ),
    );
  }

  // ==================== DIALOGO HISTORIAL SALDO ====================

  void _showHistorialSaldoDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            expand: false,
            builder:
                (ctx, scrollCtrl) => Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history, color: Colors.white),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Historial de Saldo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child:
                          _historialSaldo.isEmpty
                              ? const Center(
                                child: Text('Sin historial de movimientos'),
                              )
                              : ListView.separated(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.all(16),
                                itemCount: _historialSaldo.length,
                                separatorBuilder:
                                    (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, i) {
                                  final h = _historialSaldo[i];
                                  final isIngreso = h.diferencia > 0;
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          isIngreso
                                              ? AppColors.success.withOpacity(
                                                0.15,
                                              )
                                              : AppColors.error.withOpacity(
                                                0.15,
                                              ),
                                      child: Icon(
                                        isIngreso
                                            ? Icons.arrow_upward
                                            : Icons.arrow_downward,
                                        color:
                                            isIngreso
                                                ? AppColors.success
                                                : AppColors.error,
                                      ),
                                    ),
                                    title: Text(
                                      h.referencia ?? h.tipoOperacion,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${_dateFmt.format(h.createdAt)}  •  Anterior: ${_currencyFmt.format(h.montoAnterior)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${isIngreso ? '+' : ''}${_currencyFmt.format(h.diferencia)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color:
                                                isIngreso
                                                    ? AppColors.success
                                                    : AppColors.error,
                                          ),
                                        ),
                                        Text(
                                          _currencyFmt.format(h.montoNuevo),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                    ),
                  ],
                ),
          ),
    );
  }

  // ==================== DIALOGO NUEVA FACTURA ====================

  void _showNuevaFacturaDialog() {
    if (_estados.isEmpty) {
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Sin estados configurados'),
              content: const Text(
                'Debe configurar al menos un estado en el nomenclador antes de crear facturas.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EstadosFacturaScreen(),
                      ),
                    ).then((_) => _loadFacturasData());
                  },
                  child: const Text('Ir a Estados'),
                ),
              ],
            ),
      );
      return;
    }

    final numFacturaCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    Uint8List? fotoBytes;
    String? fotoNombre;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: const Text('Nueva Factura'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.account_balance_wallet,
                                color: AppColors.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Saldo disponible: ${_currencyFmt.format(_saldoDisponible)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: numFacturaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Número de Factura *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: valorCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor *',
                            prefixText: '\$ ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Fecha de Procesamiento *',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today),
                            ),
                            child: Text(_dateFmt.format(selectedDate)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // ---- AVISO ORIENTACIÓN ----
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.screen_rotation,
                                  color: Colors.blue.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tome la foto en modo horizontal (apaisado) para que la factura sea completamente visible.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade800),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // ---- SELECTOR DE FOTO ----
                        InkWell(
                          onTap: () async {
                            final bytes = await ImagePickerService.pickImage();
                            if (bytes != null) {
                              setDialogState(() {
                                fotoBytes = bytes;
                                fotoNombre = 'factura_${DateTime.now().millisecondsSinceEpoch}.jpg';
                              });
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            height: fotoBytes != null ? 160 : 52,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: fotoBytes != null
                                    ? AppColors.primary
                                    : Colors.grey.shade400,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: fotoBytes != null
                                  ? null
                                  : Colors.grey.shade50,
                            ),
                            child: fotoBytes != null
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(7),
                                        child: Image.memory(
                                          fotoBytes!,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            GestureDetector(
                                              onTap: () => _verFotoDesdeBytes(fotoBytes!),
                                              child: Container(
                                                margin: const EdgeInsets.only(right: 4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.zoom_in,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => setDialogState(() {
                                                fotoBytes = null;
                                                fotoNombre = null;
                                              }),
                                              child: Container(
                                                decoration: const BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.add_a_photo_outlined,
                                          color: Colors.grey),
                                      SizedBox(width: 8),
                                      Text(
                                        'Adjuntar foto de factura (opcional)',
                                        style: TextStyle(
                                            color: Colors.grey, fontSize: 13),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'El valor se descontará del saldo disponible. El estado inicial será el primero del nomenclador.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final numFactura = numFacturaCtrl.text.trim();
                        final valor = double.tryParse(valorCtrl.text) ?? 0;
                        if (numFactura.isEmpty || valor <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Complete los campos obligatorios',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        try {
                          String? fotoUrl;
                          if (fotoBytes != null && fotoNombre != null) {
                            fotoUrl = await _service.uploadFacturaFoto(
                              fotoBytes!,
                              fotoNombre!,
                            );
                          }
                          await _service.crearFactura(
                            numeroFactura: numFactura,
                            valor: valor,
                            fechaProcesamiento: selectedDate,
                            fotoUrl: fotoUrl,
                          );
                          await _loadAllData();
                          _showSuccess('Factura #$numFactura creada');
                        } catch (e) {
                          _showError('$e');
                        }
                      },
                      child: const Text('Crear Factura'),
                    ),
                  ],
                ),
          ),
    );
  }

  // ==================== DIALOGO CAMBIO DE ESTADO ====================

  void _showCambioEstadoDialog(ImportadoraFactura factura) {
    int selectedEstadoId = factura.idEstado;

    showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: Text('Cambiar Estado - Factura #${factura.numeroFactura}'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children:
                        _estados
                            .where((e) => e.activo)
                            .map(
                              (estado) => RadioListTile<int>(
                                title: Text(estado.denominacion),
                                value: estado.id,
                                groupValue: selectedEstadoId,
                                activeColor: AppColors.primary,
                                onChanged:
                                    (v) => setDialogState(
                                      () => selectedEstadoId = v!,
                                    ),
                              ),
                            )
                            .toList(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed:
                          selectedEstadoId == factura.idEstado
                              ? null
                              : () async {
                                Navigator.pop(ctx);
                                try {
                                  await _service.cambiarEstadoFactura(
                                    idFactura: factura.id!,
                                    idEstadoAnterior: factura.idEstado,
                                    idEstadoNuevo: selectedEstadoId,
                                  );
                                  await _loadFacturasData();
                                  _showSuccess('Estado actualizado');
                                } catch (e) {
                                  _showError('Error: $e');
                                }
                              },
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
          ),
    );
  }

  // ==================== DIALOGO HISTORIAL DE ESTADOS ====================

  void _showHistorialEstadosDialog(ImportadoraFactura factura) async {
    showDialog(
      context: context,
      builder:
          (ctx) => FutureBuilder<List<HistorialEstadoFactura>>(
            future: _service.getHistorialEstadoFactura(factura.id!),
            builder: (ctx, snap) {
              return AlertDialog(
                title: Text('Historial - Factura #${factura.numeroFactura}'),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child:
                      snap.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator())
                          : snap.hasError
                          ? Text('Error: ${snap.error}')
                          : snap.data!.isEmpty
                          ? const Center(
                            child: Text('Sin historial de cambios'),
                          )
                          : ListView.separated(
                            itemCount: snap.data!.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final h = snap.data![i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.swap_horiz,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                title: Text(
                                  '${h.denominacionAnterior ?? 'N/A'} → ${h.denominacionNuevo ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _dateFmt.format(h.createdAt),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    if (h.observacion != null)
                                      Text(
                                        h.observacion!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar'),
                  ),
                ],
              );
            },
          ),
    );
  }

  // ==================== BUILD ====================

  Color _hexToColor(String? hex) {
    try {
      final h = (hex ?? '#2196F3').replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagos a Importadora'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Estados de Factura',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EstadosFacturaScreen(),
                ),
              ).then((_) => _loadFacturasData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
            tooltip: 'Actualizar',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Saldo'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Facturas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSaldoTab(), _buildFacturasTab()],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildFAB() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        if (_tabController.index == 0) {
          return FloatingActionButton.extended(
            onPressed: _showRecargaDialog,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Recargar Saldo'),
          );
        } else {
          return FloatingActionButton.extended(
            onPressed: _showNuevaFacturaDialog,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Nueva Factura'),
          );
        }
      },
    );
  }

  // ==================== TAB SALDO ====================

  Widget _buildSaldoTab() {
    if (_isLoadingSaldo) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSaldoData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSaldoCard(),
            const SizedBox(height: 20),
            _buildRecargasSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSaldoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Saldo Disponible',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showHistorialSaldoDialog,
                  icon: const Icon(
                    Icons.history,
                    color: Colors.white70,
                    size: 16,
                  ),
                  label: const Text(
                    'Historial',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _currencyFmt.format(_saldoDisponible),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildSaldoStat(
                  'Recargas',
                  _recargas.length.toString(),
                  Icons.arrow_upward,
                ),
                const SizedBox(width: 24),
                _buildSaldoStat(
                  'Total recargado',
                  _currencyFmt.format(
                    _recargas.fold(0.0, (sum, r) => sum + r.monto),
                  ),
                  Icons.payments,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaldoStat(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white54, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRecargasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Historial de Recargas',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_recargas.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.payments_outlined, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'Sin recargas registradas',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recargas.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final recarga = _recargas[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.success.withOpacity(0.15),
                    child: const Icon(
                      Icons.arrow_upward,
                      color: AppColors.success,
                    ),
                  ),
                  title: Text(
                    _currencyFmt.format(recarga.monto),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fecha de pago: ${_dateFmt.format(recarga.fechaPago)}',
                      ),
                      if (recarga.observacion != null)
                        Text(
                          recarga.observacion!,
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  trailing: Text(
                    _dateFmt.format(recarga.createdAt),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 80),
      ],
    );
  }

  // ==================== TAB FACTURAS ====================

  Widget _buildFacturasTab() {
    if (_isLoadingFacturas) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFacturasData,
      color: AppColors.primary,
      child:
          _facturas.isEmpty
              ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sin facturas registradas',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Presione el botón + para agregar una factura',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
              : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: _facturas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _buildFacturaCard(_facturas[i]),
              ),
    );
  }

  void _verFotoDesdeBytes(Uint8List bytes) {
    _mostrarVisorFoto(
      imageWidget: Image.memory(bytes, fit: BoxFit.contain),
    );
  }

  void _verFotoFactura(String url) {
    _mostrarVisorFoto(
      imageWidget: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: Colors.white)),
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white, size: 64),
        ),
      ),
    );
  }

  void _mostrarVisorFoto({required Widget imageWidget}) {
    final transformCtrl = TransformationController();
    int rotacion = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setViewState) => Dialog(
          backgroundColor: Colors.black87,
          insetPadding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- BARRA DE HERRAMIENTAS ----
              Container(
                color: Colors.black54,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_in,
                        color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    const Text('Pellizca para hacer zoom',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 11)),
                    const Spacer(),
                    // Zoom +
                    IconButton(
                      tooltip: 'Acercar',
                      icon: const Icon(Icons.add_circle_outline,
                          color: Colors.white),
                      onPressed: () {
                        final current = transformCtrl.value;
                        final scale = current.getMaxScaleOnAxis();
                        if (scale < 5.0) {
                          transformCtrl.value = current.clone()
                            ..scale(1.3);
                        }
                      },
                    ),
                    // Zoom -
                    IconButton(
                      tooltip: 'Alejar',
                      icon: const Icon(Icons.remove_circle_outline,
                          color: Colors.white),
                      onPressed: () {
                        final current = transformCtrl.value;
                        final scale = current.getMaxScaleOnAxis();
                        if (scale > 0.5) {
                          transformCtrl.value = current.clone()
                            ..scale(0.75);
                        }
                      },
                    ),
                    // Reset zoom
                    IconButton(
                      tooltip: 'Restablecer',
                      icon: const Icon(Icons.fit_screen, color: Colors.white),
                      onPressed: () {
                        transformCtrl.value = Matrix4.identity();
                      },
                    ),
                    // Rotar 90°
                    IconButton(
                      tooltip: 'Rotar 90°',
                      icon: const Icon(Icons.rotate_right, color: Colors.white),
                      onPressed: () {
                        setViewState(() => rotacion = (rotacion + 1) % 4);
                      },
                    ),
                    // Cerrar
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // ---- IMAGEN ----
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                  maxWidth: MediaQuery.of(ctx).size.width,
                ),
                child: InteractiveViewer(
                  transformationController: transformCtrl,
                  minScale: 0.5,
                  maxScale: 6.0,
                  child: RotatedBox(
                    quarterTurns: rotacion,
                    child: imageWidget,
                  ),
                ),
              ),
              // ---- PIE ----
              Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Center(
                  child: Text(
                    'Doble tap para zoom rápido  •  Arrastra para mover',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFacturaCard(ImportadoraFactura factura) {
    final estadoColor = _hexToColor(factura.colorEstado);
    final tieneFoto = factura.fotoUrl != null && factura.fotoUrl!.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Factura #${factura.numeroFactura}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Procesamiento: ${_dateFmt.format(factura.fechaProcesamiento)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tieneFoto)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _verFotoFactura(factura.fotoUrl!),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          factura.fotoUrl!,
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.image_not_supported_outlined,
                            size: 42,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: estadoColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: estadoColor.withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    factura.denominacionEstado ?? 'Sin estado',
                    style: TextStyle(
                      color: estadoColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.attach_money,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  _currencyFmt.format(factura.valor),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                if (tieneFoto)
                  TextButton.icon(
                    onPressed: () => _verFotoFactura(factura.fotoUrl!),
                    icon: const Icon(Icons.receipt, size: 16),
                    label: const Text('Ver Foto', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                TextButton.icon(
                  onPressed:
                      () => _showHistorialEstadosDialog(factura),
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Historial', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: () => _showCambioEstadoDialog(factura),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text(
                    'Estado',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
