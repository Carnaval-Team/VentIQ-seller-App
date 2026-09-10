import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_colors.dart';
import '../../models/pago_proveedores.dart';
import '../../models/supplier.dart';
import '../../services/pago_proveedores_service.dart';
import '../../services/supplier_service.dart';
import '../../services/file_picker_service.dart';
import 'estados_factura_proveedores_screen.dart';
import 'monedas_proveedores_screen.dart';

class PagoProveedoresScreen extends StatefulWidget {
  const PagoProveedoresScreen({super.key});

  @override
  State<PagoProveedoresScreen> createState() => _PagoProveedoresScreenState();
}

class _PagoProveedoresScreenState extends State<PagoProveedoresScreen>
    with SingleTickerProviderStateMixin {
  final PagoProveedoresService _service = PagoProveedoresService();
  late TabController _tabController;

  List<Supplier> _proveedores = [];
  Supplier? _proveedorSeleccionado;
  ProveedorConfig? _proveedorConfig;
  bool _isLoadingProveedores = true;

  double _saldoDisponible = 0.0;
  List<RecargaSaldoProveedor> _recargas = [];
  List<HistorialSaldoProveedor> _historialSaldo = [];
  List<ProveedorFactura> _facturas = [];
  List<EstadoFacturaProveedor> _estados = [];

  bool _isLoadingSaldo = false;
  bool _isLoadingFacturas = false;

  // Filtro de fechas para el reporte de saldo
  DateTime? _reporteDesde;
  DateTime? _reporteHasta;

  final _dateFmt = DateFormat('dd/MM/yyyy');

  int? get _idProveedor => _proveedorSeleccionado?.id;

  String get _monedaSimbolo => _proveedorConfig?.monedaSimbolo ?? '\$';

  String get _monedaCodigo => _proveedorConfig?.monedaCodigo ?? 'USD';

  NumberFormat get _currencyFmt =>
      NumberFormat.currency(locale: 'es', symbol: '$_monedaSimbolo ');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _idProveedor != null) {
        if (_tabController.index == 0) {
          _loadSaldoData();
        } else {
          _loadFacturasData();
        }
      }
    });
    _loadProveedores();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProveedores() async {
    setState(() => _isLoadingProveedores = true);
    try {
      final proveedores = await SupplierService.getAllSuppliers();
      setState(() {
        _proveedores = proveedores.where((p) => p.isActive).toList();
        _isLoadingProveedores = false;
      });
    } catch (e) {
      setState(() => _isLoadingProveedores = false);
      _showError('Error cargando proveedores: $e');
    }
  }

  Future<void> _onProveedorChanged(Supplier? proveedor) async {
    setState(() {
      _proveedorSeleccionado = proveedor;
      _proveedorConfig = null;
      _saldoDisponible = 0;
      _recargas = [];
      _historialSaldo = [];
      _facturas = [];
    });
    if (proveedor == null) return;
    await _loadProveedorConfig();
    await _loadAllData();
  }

  Future<void> _loadProveedorConfig() async {
    final id = _idProveedor;
    if (id == null) return;
    try {
      final config = await _service.getProveedorConfig(id);
      setState(() => _proveedorConfig = config);
    } catch (e) {
      print('⚠️ Error cargando config proveedor: $e');
    }
  }

  Future<void> _loadAllData() async {
    if (_idProveedor == null) return;
    await Future.wait([_loadSaldoData(), _loadFacturasData()]);
  }

  Future<void> _loadSaldoData() async {
    final id = _idProveedor;
    if (id == null) return;
    setState(() => _isLoadingSaldo = true);
    try {
      final results = await Future.wait([
        _service.getSaldoDisponible(id),
        _service.getRecargas(id),
        _service.getHistorialSaldo(id),
      ]);
      setState(() {
        _saldoDisponible = results[0] as double;
        _recargas = results[1] as List<RecargaSaldoProveedor>;
        _historialSaldo = results[2] as List<HistorialSaldoProveedor>;
        _isLoadingSaldo = false;
      });
    } catch (e) {
      setState(() => _isLoadingSaldo = false);
      _showError('Error cargando saldo: $e');
    }
  }

  Future<void> _loadFacturasData() async {
    final id = _idProveedor;
    if (id == null) return;
    setState(() => _isLoadingFacturas = true);
    try {
      final results = await Future.wait([
        _service.getFacturas(id),
        _service.getEstados(),
      ]);
      setState(() {
        _facturas = results[0] as List<ProveedorFactura>;
        _estados = results[1] as List<EstadoFacturaProveedor>;
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

  Future<void> _confirmCancelarPago(HistorialSaldoProveedor h) async {
    if (!h.esRecarga) return;

    final idRecarga = _service.resolverRecargaId(h, _recargas);
    if (idRecarga == null) {
      _showError('No se pudo identificar el pago asociado a este movimiento');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pago'),
        content: Text(
          '¿Cancelar este pago de ${_currencyFmt.format(h.diferencia)}?\n\n'
          'El monto se descontará del saldo disponible y se eliminará del historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await _service.cancelarPagoRecarga(
        idProveedor: _idProveedor!,
        idRecarga: idRecarga,
        idHistorial: h.id,
      );
      await _loadSaldoData();
      _showSuccess(
        'Pago de ${_currencyFmt.format(h.diferencia)} cancelado. Saldo actualizado.',
      );
    } catch (e) {
      _showError('$e');
    }
  }

  Widget? _buildCancelarPagoButton(HistorialSaldoProveedor h) {
    if (!h.esRecarga) return null;
    return IconButton(
      tooltip: 'Cancelar pago',
      icon: Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 22),
      onPressed: () => _confirmCancelarPago(h),
    );
  }

  // ==================== DIALOGO RECARGA ====================

  void _showRecargaDialog() {
    if (_idProveedor == null) {
      _showError('Selecciona un proveedor primero');
      return;
    }
    final montoCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          var isLoading = false;
          var errorMessage = '';
          return AlertDialog(
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
                        lastDate: DateTime.now().add(const Duration(days: 365)),
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
                  if (errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorMessage,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
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
              _buildSubmitButton(
                isLoading: isLoading,
                label: 'Recargar',
                onPressed: () async {
                  final monto = double.tryParse(montoCtrl.text) ?? 0;
                  if (monto <= 0) {
                    setDialogState(
                      () => errorMessage = 'Ingrese un monto válido',
                    );
                    return;
                  }
                  setDialogState(() {
                    isLoading = true;
                    errorMessage = '';
                  });
                  try {
                    await _service.agregarRecarga(
                      idProveedor: _idProveedor!,
                      monto: monto,
                      fechaPago: selectedDate,
                      observacion: obsCtrl.text.trim().isEmpty
                          ? null
                          : obsCtrl.text.trim(),
                    );
                    await _loadSaldoData();
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showSuccess(
                      'Recarga de ${_currencyFmt.format(monto)} registrada',
                    );
                  } catch (e) {
                    setDialogState(() {
                      isLoading = false;
                      errorMessage = 'Error: $e';
                    });
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== GESTIÓN DE FOTOS (MÚLTIPLES PÁGINAS) ====================

  void _showGestionFotosDialog(ProveedorFactura factura) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final fotos = factura.fotos.toList()
            ..sort((a, b) => a.numeroPagina.compareTo(b.numeroPagina));

          return AlertDialog(
            title: Text('Fotos — Factura #${factura.numeroFactura}'),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fotos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sin fotos adjuntas',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: fotos.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final foto = fotos[i];
                          return Stack(
                            children: [
                              foto.isImage
                                  ? GestureDetector(
                                      onTap: () =>
                                          _verFotoFactura(foto.fotoUrl),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          foto.fotoUrl,
                                          height: 130,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                                height: 130,
                                                color: Colors.grey.shade200,
                                                child: const Icon(
                                                  Icons.broken_image,
                                                  color: Colors.grey,
                                                  size: 40,
                                                ),
                                              ),
                                        ),
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () =>
                                          _abrirArchivoUrl(foto.fotoUrl),
                                      child: Container(
                                        height: 70,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const SizedBox(width: 16),
                                            Icon(
                                              _iconForMime(foto.mimeType),
                                              color: AppColors.primary,
                                              size: 32,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    foto.displayName,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    foto.mimeType,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.open_in_new,
                                              color: Colors.grey,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                        ),
                                      ),
                                    ),
                              Positioned(
                                top: 6,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    foto.displayName.length > 20
                                        ? 'Arch. ${foto.numeroPagina}'
                                        : foto.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () async {
                                    final confirm = await showDialog<bool>(
                                      context: ctx,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Eliminar foto'),
                                        content: Text(
                                          '¿Eliminar la foto de la página ${foto.numeroPagina}?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancelar'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Eliminar'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      try {
                                        await _service.eliminarFotoFactura(
                                          foto.id!,
                                        );
                                        await _loadFacturasData();
                                        Navigator.pop(ctx);
                                        _showSuccess('Foto eliminada');
                                      } catch (e) {
                                        _showError('Error: $e');
                                      }
                                    }
                                  },
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const Divider(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: Text('Añadir archivo ${fotos.length + 1}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final picked = await FilePickerService.pickFile();
                      if (picked == null) return;
                      Navigator.pop(ctx);
                      try {
                        await _service.agregarFotoFactura(
                          idFactura: factura.id!,
                          bytes: picked.bytes,
                          fileName: picked.nombre,
                          numeroPagina: fotos.length + 1,
                          mimeType: picked.mimeType,
                          nombreArchivo: picked.nombre,
                        );
                        await _loadFacturasData();
                        _showSuccess('Archivo añadido (${picked.nombre})');
                      } catch (e) {
                        _showError('Error: $e');
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
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

  // ==================== DIALOGO HISTORIAL SALDO ====================

  void _showHistorialSaldoDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              child: _historialSaldo.isEmpty
                  ? const Center(child: Text('Sin historial de movimientos'))
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: _historialSaldo.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final h = _historialSaldo[i];
                        final isIngreso = h.diferencia > 0;
                        final cancelBtn = _buildCancelarPagoButton(h);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isIngreso
                                ? AppColors.success.withOpacity(0.15)
                                : AppColors.error.withOpacity(0.15),
                            child: Icon(
                              isIngreso
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: isIngreso
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
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (h.observacion != null &&
                                  h.observacion!.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.comment_outlined,
                                      size: 11,
                                      color: Colors.indigo,
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        h.observacion!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              Text(
                                '${_dateFmt.format(h.createdAt)}  •  Anterior: ${_currencyFmt.format(h.montoAnterior)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${isIngreso ? '+' : ''}${_currencyFmt.format(h.diferencia)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isIngreso
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
                              if (cancelBtn != null) cancelBtn,
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
    if (_idProveedor == null) {
      _showError('Selecciona un proveedor primero');
      return;
    }
    if (_estados.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
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
                    builder: (_) => const EstadosFacturaProveedoresScreen(),
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
    final List<({Uint8List bytes, String nombre, String mimeType})> fotos = [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          var isLoading = false;
          var errorMessage = '';
          return AlertDialog(
            title: const Text('Nueva Factura'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 360,
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
                        if (picked != null)
                          setDialogState(() => selectedDate = picked);
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
                    // ---- ARCHIVOS / FOTOS (múltiples páginas) ----
                    Row(
                      children: [
                        const Text(
                          'Archivos adjuntos',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await FilePickerService.pickFile();
                            if (picked != null) {
                              setDialogState(() {
                                fotos.add((
                                  bytes: picked.bytes,
                                  nombre: picked.nombre,
                                  mimeType: picked.mimeType,
                                ));
                              });
                            }
                          },
                          icon: const Icon(Icons.attach_file, size: 16),
                          label: Text('Adjuntar ${fotos.length + 1}'),
                        ),
                      ],
                    ),
                    if (fotos.isNotEmpty)
                      ...List.generate(fotos.length, (i) {
                        final f = fotos[i];
                        final esImagen = f.mimeType.startsWith('image/');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Stack(
                            children: [
                              esImagen
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        f.bytes,
                                        height: 100,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Container(
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const SizedBox(width: 12),
                                          Icon(
                                            _iconForMime(f.mimeType),
                                            color: AppColors.primary,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              f.nombre,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              Positioned(
                                top: 4,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () =>
                                      setDialogState(() => fotos.removeAt(i)),
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
                              ),
                            ],
                          ),
                        );
                      })
                    else
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade50,
                        ),
                        child: const Center(
                          child: Text(
                            'Sin archivos adjuntos (opcional)',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
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
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 6),
                          Expanded(
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
                    if (errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          errorMessage,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              _buildSubmitButton(
                isLoading: isLoading,
                label: 'Crear Factura',
                onPressed: () async {
                  final numFactura = numFacturaCtrl.text.trim();
                  final valor = double.tryParse(valorCtrl.text) ?? 0;
                  if (numFactura.isEmpty || valor <= 0) {
                    setDialogState(
                      () => errorMessage = 'Complete los campos obligatorios',
                    );
                    return;
                  }
                  setDialogState(() {
                    isLoading = true;
                    errorMessage = '';
                  });
                  try {
                    await _service.crearFactura(
                      idProveedor: _idProveedor!,
                      numeroFactura: numFactura,
                      valor: valor,
                      fechaProcesamiento: selectedDate,
                      fotosEntradas: fotos,
                    );
                    await _loadAllData();
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showSuccess(
                      'Factura #$numFactura creada con ${fotos.length} archivo(s)',
                    );
                  } catch (e) {
                    setDialogState(() {
                      isLoading = false;
                      errorMessage = '$e';
                    });
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== DIALOGO EDITAR FACTURA ====================

  void _showEditarFacturaDialog(ProveedorFactura factura) {
    final numCtrl = TextEditingController(text: factura.numeroFactura);
    final valorCtrl = TextEditingController(
      text: factura.valor.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Factura #${factura.numeroFactura}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
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
                        'Si cambia el valor, el saldo disponible se ajustará automáticamente.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: numCtrl,
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Guardar'),
            onPressed: () async {
              final nuevoNumero = numCtrl.text.trim();
              final nuevoValor = double.tryParse(valorCtrl.text) ?? 0;
              if (nuevoNumero.isEmpty || nuevoValor <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Complete los campos obligatorios'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await _service.actualizarDetallesFactura(
                  idProveedor: _idProveedor!,
                  idFactura: factura.id!,
                  numeroFacturaAnterior: factura.numeroFactura,
                  nuevoNumeroFactura: nuevoNumero,
                  valorAnterior: factura.valor,
                  nuevoValor: nuevoValor,
                );
                await _loadAllData();
                _showSuccess('Factura actualizada correctamente');
              } catch (e) {
                _showError('$e');
              }
            },
          ),
        ],
      ),
    );
  }

  // ==================== DIALOGO CAMBIO DE ESTADO ====================

  void _showCambioEstadoDialog(ProveedorFactura factura) {
    int selectedEstadoId = factura.idEstado;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Cambiar Estado - Factura #${factura.numeroFactura}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _estados
                .where((e) => e.activo)
                .map(
                  (estado) => RadioListTile<int>(
                    title: Text(estado.denominacion),
                    value: estado.id,
                    groupValue: selectedEstadoId,
                    activeColor: AppColors.primary,
                    onChanged: (v) =>
                        setDialogState(() => selectedEstadoId = v!),
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
              onPressed: selectedEstadoId == factura.idEstado
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

  void _showHistorialEstadosDialog(ProveedorFactura factura) async {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<List<HistorialEstadoFacturaProveedor>>(
        future: _service.getHistorialEstadoFactura(factura.id!),
        builder: (ctx, snap) {
          return AlertDialog(
            title: Text('Historial - Factura #${factura.numeroFactura}'),
            content: SizedBox(
              width: 360,
              height: 300,
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : snap.hasError
                  ? Text('Error: ${snap.error}')
                  : snap.data!.isEmpty
                  ? const Center(child: Text('Sin historial de cambios'))
                  : ListView.separated(
                      itemCount: snap.data!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
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

  IconData _iconForMime(String mime) {
    if (mime == 'application/pdf') return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('msword'))
      return Icons.description;
    if (mime.contains('excel') || mime.contains('spreadsheet'))
      return Icons.table_chart;
    if (mime.startsWith('image/')) return Icons.image;
    return Icons.insert_drive_file;
  }

  Future<void> _abrirArchivoUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showError('No se pudo abrir el archivo');
      }
    } catch (e) {
      if (mounted) _showError('Error al abrir: $e');
    }
  }

  Color _hexToColor(String? hex) {
    try {
      final h = (hex ?? '#2196F3').replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  Future<void> _showAsignarMonedaDialog() async {
    if (_idProveedor == null) {
      _showError('Selecciona un proveedor primero');
      return;
    }
    try {
      final monedas = await _service.getMonedas(soloActivas: true);
      if (!mounted) return;
      if (monedas.isEmpty) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sin monedas'),
            content: const Text(
              'No hay monedas activas. ¿Desea gestionar monedas ahora?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Gestionar monedas'),
              ),
            ],
          ),
        );
        if (go == true && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MonedasProveedoresScreen()),
          );
        }
        return;
      }

      int? selectedId = _proveedorConfig?.idMoneda ?? monedas.first.id;
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text('Moneda — ${_proveedorSeleccionado!.denominacion}'),
            content: DropdownButtonFormField<int>(
              value: selectedId,
              decoration: const InputDecoration(
                labelText: 'Moneda',
                border: OutlineInputBorder(),
              ),
              items: monedas
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        '${m.codigo} (${m.simbolo}) — ${m.denominacion}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setDialogState(() => selectedId = v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedId == null) return;
                  Navigator.pop(ctx);
                  try {
                    final config = await _service.setProveedorConfig(
                      idProveedor: _idProveedor!,
                      idMoneda: selectedId!,
                    );
                    setState(() => _proveedorConfig = config);
                    _showSuccess(
                      'Moneda ${_monedaCodigo} asignada al proveedor',
                    );
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
    } catch (e) {
      _showError('Error cargando monedas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pago a proveedores'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (value) async {
              if (value == 'estados') {
                await Navigator.pushNamed(context, '/pago-proveedores-estados');
                await _loadFacturasData();
              } else if (value == 'monedas') {
                await Navigator.pushNamed(context, '/pago-proveedores-monedas');
                await _loadProveedorConfig();
              } else if (value == 'asignar_moneda') {
                await _showAsignarMonedaDialog();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'estados',
                child: Row(
                  children: [
                    Icon(Icons.label_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Estados de factura'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'monedas',
                child: Row(
                  children: [
                    Icon(Icons.attach_money, size: 18),
                    SizedBox(width: 8),
                    Text('Gestionar monedas'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'asignar_moneda',
                child: Row(
                  children: [
                    Icon(Icons.currency_exchange, size: 18),
                    SizedBox(width: 8),
                    Text('Asignar moneda al proveedor'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadProveedores();
              if (_idProveedor != null) await _loadAllData();
            },
            tooltip: 'Actualizar',
          ),
        ],
        bottom: _idProveedor == null
            ? null
            : TabBar(
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
      body: Column(
        children: [
          _buildProveedorSelector(),
          Expanded(
            child: _idProveedor == null
                ? _buildSeleccionarProveedorEmpty()
                : TabBarView(
                    controller: _tabController,
                    children: [_buildSaldoTab(), _buildFacturasTab()],
                  ),
          ),
        ],
      ),
      floatingActionButton: _idProveedor == null ? null : _buildFAB(),
    );
  }

  Widget _buildProveedorSelector() {
    return Material(
      elevation: 1,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              value: _proveedorSeleccionado?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Proveedor',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.handshake_outlined),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              hint: Text(
                _isLoadingProveedores
                    ? 'Cargando proveedores...'
                    : 'Selecciona un proveedor',
              ),
              items: _proveedores
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.denominacion,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _isLoadingProveedores
                  ? null
                  : (id) {
                      Supplier? proveedor;
                      if (id != null) {
                        for (final p in _proveedores) {
                          if (p.id == id) {
                            proveedor = p;
                            break;
                          }
                        }
                      }
                      _onProveedorChanged(proveedor);
                    },
            ),
            if (_idProveedor != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.payments_outlined,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _proveedorConfig != null
                        ? 'Moneda: $_monedaCodigo ($_monedaSimbolo)'
                        : 'Moneda: USD (por defecto) — configure la moneda',
                    style: TextStyle(
                      fontSize: 13,
                      color: _proveedorConfig != null
                          ? Colors.grey[700]
                          : Colors.orange[800],
                      fontWeight: _proveedorConfig != null
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _showAsignarMonedaDialog,
                    child: Text(
                      _proveedorConfig != null ? 'Cambiar' : 'Configurar',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeleccionarProveedorEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.handshake_outlined, size: 72, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Selecciona un proveedor',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Elige un proveedor arriba para ver saldo y facturas',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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

  // ==================== REPORTE PDF ====================

  Future<void> _exportarReportePdf() async {
    final doc = pw.Document();
    final fechaFmt = DateFormat('dd/MM/yyyy');
    final moneyFmt = NumberFormat.currency(
      locale: 'es',
      symbol: '$_monedaSimbolo ',
    );
    final proveedorNombre = _proveedorSeleccionado?.denominacion ?? 'Proveedor';

    // Combinar movimientos del historial filtrados
    final movimientos = _historialFiltrado();

    final totalRecargas = movimientos
        .where((h) => h.diferencia > 0)
        .fold(0.0, (s, h) => s + h.diferencia);
    final totalDescuentos = movimientos
        .where((h) => h.diferencia < 0)
        .fold(0.0, (s, h) => s + h.diferencia.abs());

    final rangoTexto = (_reporteDesde != null || _reporteHasta != null)
        ? 'Del ${_reporteDesde != null ? fechaFmt.format(_reporteDesde!) : '—'} al ${_reporteHasta != null ? fechaFmt.format(_reporteHasta!) : '—'}'
        : 'Todos los movimientos';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Reporte de Saldo - $proveedorNombre ($_monedaCodigo)',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            rangoTexto,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          // Resumen
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text(
                      'Saldo Actual',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      moneyFmt.format(_saldoDisponible),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      'Total Recargas',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      moneyFmt.format(totalRecargas),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      'Total Descuentos',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      moneyFmt.format(totalDescuentos),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          // Tabla de movimientos
          pw.TableHelper.fromTextArray(
            headers: [
              'Fecha',
              'Tipo',
              'Referencia',
              'Monto Ant.',
              'Monto Nuevo',
              'Diferencia',
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            data: movimientos.map((h) {
              final esIngreso = h.diferencia > 0;
              return [
                fechaFmt.format(h.createdAt),
                esIngreso ? 'Recarga' : 'Descuento',
                h.referencia ?? '',
                moneyFmt.format(h.montoAnterior),
                moneyFmt.format(h.montoNuevo),
                '${esIngreso ? '+' : ''}${moneyFmt.format(h.diferencia)}',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name:
          'reporte_pago_proveedores_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  List<HistorialSaldoProveedor> _historialFiltrado() {
    return _historialSaldo.where((h) {
      if (_reporteDesde != null &&
          h.createdAt.isBefore(
            DateTime(
              _reporteDesde!.year,
              _reporteDesde!.month,
              _reporteDesde!.day,
            ),
          )) {
        return false;
      }
      if (_reporteHasta != null &&
          h.createdAt.isAfter(
            DateTime(
              _reporteHasta!.year,
              _reporteHasta!.month,
              _reporteHasta!.day,
              23,
              59,
              59,
            ),
          )) {
        return false;
      }
      return true;
    }).toList();
  }

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
            _buildReporteSection(),
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
                Text(
                  'Saldo Disponible ($_monedaCodigo)',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
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

  Widget _buildReporteSection() {
    final movimientos = _historialFiltrado();
    final totalRecargas = movimientos
        .where((h) => h.diferencia > 0)
        .fold(0.0, (s, h) => s + h.diferencia);
    final totalDescuentos = movimientos
        .where((h) => h.diferencia < 0)
        .fold(0.0, (s, h) => s + h.diferencia.abs());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- Cabecera con título y botón PDF ----
        Row(
          children: [
            const Text(
              'Reporte de Movimientos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _historialSaldo.isEmpty ? null : _exportarReportePdf,
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Exportar PDF', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ---- Filtro de fechas ----
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.filter_list,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Filtrar por fechas',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_reporteDesde != null || _reporteHasta != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _reporteDesde = null;
                          _reporteHasta = null;
                        }),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: Colors.grey,
                        ),
                        child: const Text(
                          'Limpiar',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _reporteDesde ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            helpText: 'Desde',
                          );
                          if (picked != null)
                            setState(() => _reporteDesde = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Desde',
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: Icon(Icons.calendar_today, size: 14),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            _reporteDesde != null
                                ? _dateFmt.format(_reporteDesde!)
                                : 'Todas',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _reporteHasta ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            helpText: 'Hasta',
                          );
                          if (picked != null)
                            setState(() => _reporteHasta = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Hasta',
                            border: OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: Icon(Icons.calendar_today, size: 14),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            _reporteHasta != null
                                ? _dateFmt.format(_reporteHasta!)
                                : 'Hoy',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // ---- Resumen de totales ----
        Row(
          children: [
            Expanded(
              child: Card(
                color: AppColors.success.withOpacity(0.08),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_upward,
                            size: 14,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Recargas',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currencyFmt.format(totalRecargas),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.arrow_downward,
                            size: 14,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Descuentos',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currencyFmt.format(totalDescuentos),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                          fontSize: 14,
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
        // ---- Lista de movimientos ----
        if (movimientos.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _historialSaldo.isEmpty
                        ? 'Sin movimientos registrados'
                        : 'Sin movimientos en el período seleccionado',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: movimientos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (ctx, i) {
              final h = movimientos[i];
              final esIngreso = h.diferencia > 0;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: esIngreso
                        ? AppColors.success.withOpacity(0.15)
                        : Colors.red.shade50,
                    child: Icon(
                      esIngreso ? Icons.arrow_upward : Icons.arrow_downward,
                      color: esIngreso
                          ? AppColors.success
                          : Colors.red.shade700,
                    ),
                  ),
                  trailing: _buildCancelarPagoButton(h),
                  title: Row(
                    children: [
                      Text(
                        '${esIngreso ? '+' : ''}${_currencyFmt.format(h.diferencia)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: esIngreso
                              ? AppColors.success
                              : Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: esIngreso
                              ? AppColors.success.withOpacity(0.1)
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          esIngreso ? 'Recarga' : 'Descuento',
                          style: TextStyle(
                            fontSize: 10,
                            color: esIngreso
                                ? AppColors.success
                                : Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (h.observacion != null && h.observacion!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.comment_outlined,
                                size: 12,
                                color: Colors.indigo,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  h.observacion!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (h.referencia != null)
                        Text(
                          h.referencia!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      Text(
                        '${_dateFmt.format(h.createdAt)}  •  Ant: ${_currencyFmt.format(h.montoAnterior)}  →  Nuevo: ${_currencyFmt.format(h.montoNuevo)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
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
      child: _facturas.isEmpty
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
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Presione el botón + para agregar una factura',
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
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

  void _verFotoFactura(String url) {
    _mostrarVisorFoto(
      imageWidget: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_in, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    const Text(
                      'Pellizca para hacer zoom',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const Spacer(),
                    // Zoom +
                    IconButton(
                      tooltip: 'Acercar',
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        final current = transformCtrl.value;
                        final scale = current.getMaxScaleOnAxis();
                        if (scale < 5.0) {
                          transformCtrl.value = current.clone()..scale(1.3);
                        }
                      },
                    ),
                    // Zoom -
                    IconButton(
                      tooltip: 'Alejar',
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        final current = transformCtrl.value;
                        final scale = current.getMaxScaleOnAxis();
                        if (scale > 0.5) {
                          transformCtrl.value = current.clone()..scale(0.75);
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
                  child: RotatedBox(quarterTurns: rotacion, child: imageWidget),
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

  Widget _buildFacturaCard(ProveedorFactura factura) {
    final estadoColor = _hexToColor(factura.colorEstado);

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
                if (factura.fotos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _showGestionFotosDialog(factura),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              factura.fotos.first.fotoUrl,
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
                          if (factura.fotos.length > 1)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${factura.fotos.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
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
                    border: Border.all(color: estadoColor.withOpacity(0.4)),
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
                TextButton.icon(
                  onPressed: () => _showGestionFotosDialog(factura),
                  icon: Icon(
                    factura.fotos.isNotEmpty
                        ? Icons.photo_library_outlined
                        : Icons.add_a_photo_outlined,
                    size: 16,
                  ),
                  label: Text(
                    factura.fotos.isNotEmpty
                        ? 'Fotos (${factura.fotos.length})'
                        : 'Añadir Foto',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: factura.fotos.isNotEmpty
                        ? AppColors.primary
                        : Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showHistorialEstadosDialog(factura),
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text(
                    'Historial',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: () => _showEditarFacturaDialog(factura),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  onPressed: () => _showCambioEstadoDialog(factura),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Estado', style: TextStyle(fontSize: 12)),
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

  ElevatedButton _buildSubmitButton({
    required bool isLoading,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}
