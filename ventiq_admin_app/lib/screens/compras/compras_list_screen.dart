import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/compra.dart';
import '../../models/supplier.dart';
import '../../services/compra_service.dart';
import '../../services/supplier_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/admin_drawer.dart';
import 'compra_detail_screen.dart';
import 'compra_form_screen.dart';
import 'compras_widgets.dart';

/// Listado del módulo Compras (`fn_fdi_compra_listar`).
class ComprasListScreen extends StatefulWidget {
  const ComprasListScreen({super.key});

  @override
  State<ComprasListScreen> createState() => _ComprasListScreenState();
}

class _ComprasListScreenState extends State<ComprasListScreen> {
  final _service = CompraService();
  final _textoCtrl = TextEditingController();
  Timer? _debounce;

  int? _idTienda;
  bool _cargando = true;
  String? _error;
  List<CompraResumen> _compras = const [];
  List<Supplier> _proveedores = const [];

  String? _estado;
  int? _idProveedor;
  DateTimeRange? _rango;

  @override
  void initState() {
    super.initState();
    _cargarProveedores();
    _cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textoCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  // Datos
  // ==========================================================================

  Future<void> _cargarProveedores() async {
    try {
      final proveedores = await SupplierService.getAllSuppliers(
        activeOnly: false,
      );
      if (!mounted) return;
      setState(() => _proveedores = proveedores);
    } catch (_) {
      // El filtro por proveedor queda vacío; el listado no depende de esto.
      if (!mounted) return;
      setState(() => _proveedores = const []);
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      _idTienda ??= await UserPreferencesService().getIdTienda();
      final idTienda = _idTienda;
      if (idTienda == null) {
        throw Exception('No se pudo determinar la tienda del usuario.');
      }
      final texto = _textoCtrl.text.trim();
      final filas = await _service.listar(
        idTienda: idTienda,
        estado: _estado,
        idProveedor: _idProveedor,
        desde: _rango?.start,
        hasta: _rango?.end,
        texto: texto.isEmpty ? null : texto,
      );
      if (!mounted) return;
      setState(() {
        _compras = filas;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mensajeDe(e);
        _cargando = false;
      });
    }
  }

  void _programarRecarga() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _cargar);
  }

  String _mensajeDe(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '');
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  // ==========================================================================
  // Filtros
  // ==========================================================================

  int get _filtrosActivos {
    var n = 0;
    if (_estado != null) n++;
    if (_idProveedor != null) n++;
    if (_rango != null) n++;
    if (_textoCtrl.text.trim().isNotEmpty) n++;
    return n;
  }

  void _limpiarFiltros() {
    _debounce?.cancel();
    _textoCtrl.clear();
    setState(() {
      _estado = null;
      _idProveedor = null;
      _rango = null;
    });
    _cargar();
  }

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(ahora.year - 4),
      lastDate: DateTime(ahora.year + 2),
      initialDateRange: _rango,
      helpText: 'Fecha de factura',
      saveText: 'Aplicar',
    );
    if (rango == null || !mounted) return;
    setState(() => _rango = rango);
    _cargar();
  }

  List<Widget> _chipsFiltros({required bool conQuitar}) {
    final chips = <Widget>[];
    if (_estado != null) {
      chips.add(
        _chipFiltro(
          'Estado: ${CompraEstado.etiquetaDe(_estado)}',
          conQuitar
              ? () {
                  setState(() => _estado = null);
                  _cargar();
                }
              : null,
        ),
      );
    }
    if (_idProveedor != null) {
      final nombre = _proveedores
          .where((p) => p.id == _idProveedor)
          .map((p) => p.denominacion)
          .firstOrNull;
      chips.add(
        _chipFiltro(
          'Proveedor: ${nombre ?? '#$_idProveedor'}',
          conQuitar
              ? () {
                  setState(() => _idProveedor = null);
                  _cargar();
                }
              : null,
        ),
      );
    }
    if (_rango != null) {
      chips.add(
        _chipFiltro(
          '${formatearFecha(_rango!.start)} – ${formatearFecha(_rango!.end)}',
          conQuitar
              ? () {
                  setState(() => _rango = null);
                  _cargar();
                }
              : null,
        ),
      );
    }
    final texto = _textoCtrl.text.trim();
    if (texto.isNotEmpty) {
      chips.add(
        _chipFiltro(
          'Texto: “$texto”',
          conQuitar
              ? () {
                  _textoCtrl.clear();
                  _cargar();
                }
              : null,
        ),
      );
    }
    return chips;
  }

  Widget _chipFiltro(String etiqueta, VoidCallback? onDelete) {
    return Chip(
      label: Text(etiqueta, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: AppColors.surfaceVariant,
      side: const BorderSide(color: AppColors.border),
      onDeleted: onDelete,
      deleteIcon: onDelete == null ? null : const Icon(Icons.close, size: 14),
    );
  }

  // ==========================================================================
  // Navegación
  // ==========================================================================

  Future<void> _nuevaCompra() async {
    final creada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CompraFormScreen()),
    );
    if (creada == true && mounted) _cargar();
  }

  Future<void> _abrirDetalle(CompraResumen compra) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CompraDetailScreen(idCompra: compra.id),
      ),
    );
    // El detalle puede editar o cancelar; al volver siempre se relee
    // (una sola consulta) para no mostrar cifras viejas.
    if (mounted) _cargar();
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Compras',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      drawer: const AdminDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevaCompra,
        icon: const Icon(Icons.add),
        label: const Text('Nueva compra'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tamano = comprasTamanoDe(constraints.maxWidth);
          final conPanel = constraints.maxWidth > comprasAnchoPanelLateral;

          if (conPanel) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _barraFiltros(tamano),
                      Expanded(child: _area(tamano)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 340,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                    child: SingleChildScrollView(child: _panelResumen()),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              _barraFiltros(tamano),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _bandaTotales(tamano == ComprasTamano.compacto ? 2 : 4),
              ),
              Expanded(child: _area(tamano)),
            ],
          );
        },
      ),
    );
  }

  // ==========================================================================
  // Barra de filtros
  // ==========================================================================

  Widget _barraFiltros(ComprasTamano tamano) {
    if (tamano == ComprasTamano.compacto) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textoCtrl,
                textInputAction: TextInputAction.search,
                onChanged: (_) => _programarRecarga(),
                onSubmitted: (_) => _cargar(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar factura o proveedor...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _hojaFiltros(),
              icon: const Icon(Icons.filter_list, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.border),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              label: Text(
                _filtrosActivos > 0 ? 'Filtros ($_filtrosActivos)' : 'Filtros',
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: 190, child: _dropdownEstado()),
              SizedBox(width: 230, child: _dropdownProveedor()),
              _botonRango(),
              SizedBox(
                width: 250,
                child: TextField(
                  controller: _textoCtrl,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => _programarRecarga(),
                  onSubmitted: (_) => _cargar(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Número de factura o proveedor',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _filtrosActivos == 0 ? null : _limpiarFiltros,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('Limpiar'),
              ),
            ],
          ),
          if (_filtrosActivos > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _chipsFiltros(conQuitar: true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dropdownEstado({VoidCallback? alCambiar}) {
    return DropdownButtonFormField<String?>(
      initialValue: _estado,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Estado',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
        ...CompraEstado.values.map(
          (e) => DropdownMenuItem<String?>(
            value: e.codigo,
            child: Row(
              children: [
                Icon(
                  iconoEstadoCompra(e.codigo),
                  size: 14,
                  color: colorEstadoCompra(e.codigo),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(e.etiqueta, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ],
      onChanged: (valor) {
        setState(() => _estado = valor);
        _cargar();
        alCambiar?.call();
      },
    );
  }

  Widget _dropdownProveedor({VoidCallback? alCambiar}) {
    final ids = _proveedores.map((p) => p.id).toSet();
    final valor = ids.contains(_idProveedor) ? _idProveedor : null;
    return DropdownButtonFormField<int?>(
      initialValue: valor,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Proveedor',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
        ..._proveedores.map(
          (p) => DropdownMenuItem<int?>(
            value: p.id,
            child: Text(p.denominacion, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (valor) {
        setState(() => _idProveedor = valor);
        _cargar();
        alCambiar?.call();
      },
    );
  }

  Widget _botonRango({VoidCallback? alCambiar}) {
    return Tooltip(
      message:
          'Filtra por fecha de factura: las compras sin fecha de factura '
          'quedan fuera del rango.',
      child: OutlinedButton.icon(
        onPressed: () async {
          await _elegirRango();
          alCambiar?.call();
        },
        icon: const Icon(Icons.date_range, size: 18),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
        label: Text(
          _rango == null
              ? 'Fecha de factura'
              : '${formatearFecha(_rango!.start)} – ${formatearFecha(_rango!.end)}',
        ),
      ),
    );
  }

  Future<void> _hojaFiltros() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Filtros',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _limpiarFiltros();
                            setSheetState(() {});
                          },
                          child: const Text('Limpiar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _dropdownEstado(alCambiar: () => setSheetState(() {})),
                    const SizedBox(height: 12),
                    _dropdownProveedor(alCambiar: () => setSheetState(() {})),
                    const SizedBox(height: 12),
                    _botonRango(alCambiar: () => setSheetState(() {})),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Ver resultados'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // Cifras
  // ==========================================================================

  Map<String, TotalesCompra> _totalesPorMoneda() {
    final mapa = <String, TotalesCompra>{};
    for (final fila in _compras) {
      final moneda = fila.monedaTotal.trim().isEmpty
          ? '—'
          : fila.monedaTotal.trim();
      final previo = mapa[moneda] ?? TotalesCompra.cero;
      mapa[moneda] = TotalesCompra(
        mercancia: redondear2(previo.mercancia + fila.totalMercancia),
        ajustes: redondear2(previo.ajustes + fila.totalAjustes),
        financiado: redondear2(previo.financiado + fila.totalFinanciado),
        aterrizado: redondear2(previo.aterrizado + fila.costoAterrizado),
      );
    }
    return mapa;
  }

  Widget _bandaTotales(int columnas) {
    final porMoneda = _totalesPorMoneda();
    if (porMoneda.isEmpty) return const SizedBox.shrink();
    if (porMoneda.length == 1) {
      final e = porMoneda.entries.first;
      return bandaTotalesCompra(
        totales: e.value,
        moneda: e.key,
        columnas: columnas,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in porMoneda.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    e.key,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Financiado ${formatearImporte(e.value.financiado)} · '
                    'Aterrizado ${formatearImporte(e.value.aterrizado)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Text(
          'Hay compras en varias monedas: sus importes no se suman.',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _panelResumen() {
    final porMoneda = _totalesPorMoneda();
    return panelCompras(
      children: [
        const Text(
          'Resumen del filtro',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (porMoneda.isEmpty)
          textoMetaCompras('Sin compras para sumar.')
        else if (porMoneda.length == 1)
          bloqueTotalesCompra(
            totales: porMoneda.entries.first.value,
            moneda: porMoneda.entries.first.key,
            helperAterrizado:
                'Incluye los ajustes con origen de pago de la wallet de importadora.',
          )
        else
          _bandaTotales(2),
        const Divider(height: 24, color: AppColors.border),
        Row(
          children: [
            const Icon(
              Icons.receipt_long,
              size: 16,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _compras.length == 1
                    ? '1 compra listada'
                    : '${_compras.length} compras listadas',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (_filtrosActivos > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _chipsFiltros(conQuitar: true),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _limpiarFiltros,
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Limpiar filtros'),
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================================================
  // Contenido
  // ==========================================================================

  Widget _area(ComprasTamano tamano) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _vistaError();
    }
    if (_compras.isEmpty) {
      return _vistaVacia();
    }
    if (tamano == ComprasTamano.compacto) {
      return _listaTarjetas();
    }
    return _tabla(tamano);
  }

  Widget _vistaError() {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 56, color: Colors.red[300]),
                  const SizedBox(height: 12),
                  const Text(
                    'No se pudieron cargar las compras',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _error ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _cargar,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                      if (_filtrosActivos > 0)
                        OutlinedButton(
                          onPressed: _limpiarFiltros,
                          child: const Text('Limpiar filtros'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _vistaVacia() {
    final conFiltros = _filtrosActivos > 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              conFiltros ? Icons.search_off : Icons.shopping_cart_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              conFiltros
                  ? 'Ninguna compra coincide con los filtros'
                  : 'Todavía no hay compras registradas',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              conFiltros
                  ? 'Prueba con otro estado, proveedor o rango de fechas.'
                  : 'Registra la primera compra para empezar a controlar el costo real.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            if (conFiltros)
              OutlinedButton(
                onPressed: _limpiarFiltros,
                child: const Text('Limpiar filtros'),
              )
            else
              ElevatedButton.icon(
                onPressed: _nuevaCompra,
                icon: const Icon(Icons.add),
                label: const Text('Nueva compra'),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // Tabla (tablet y PC)
  // ==========================================================================

  // Flex de las columnas de PC. Cabecera y filas comparten estos valores.
  static const int _fNum = 6;
  static const int _fProv = 20;
  static const int _fFact = 11;
  static const int _fFecha = 9;
  static const int _fMoneda = 6;
  static const int _fMerc = 11;
  static const int _fAjustes = 10;
  static const int _fFin = 11;
  static const int _fAter = 11;
  static const int _fEstado = 13;

  Widget _tabla(ComprasTamano tamano) {
    final pc = tamano == ComprasTamano.expandido;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: pc ? _cabeceraPc() : _cabeceraTablet(),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _cargar,
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: _compras.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final compra = _compras[index];
                    return InkWell(
                      onTap: () => _abrirDetalle(compra),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: pc ? _filaPc(compra) : _filaTablet(compra),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celda(
    String texto, {
    bool derecha = false,
    bool negrita = false,
    Color? color,
    int? maxLineas,
  }) {
    return Text(
      texto,
      textAlign: derecha ? TextAlign.right : TextAlign.left,
      maxLines: maxLineas ?? 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: negrita ? FontWeight.w600 : FontWeight.w400,
        color: color ?? AppColors.textPrimary,
      ),
    );
  }

  Widget _cabeceraPc() {
    const estilo = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 0.2,
    );
    Widget h(String t, int flex, {bool derecha = false}) => Expanded(
      flex: flex,
      child: Text(
        t,
        textAlign: derecha ? TextAlign.right : TextAlign.left,
        style: estilo,
      ),
    );
    return Row(
      children: [
        h('#', _fNum),
        h('Proveedor', _fProv),
        h('Factura', _fFact),
        h('Fecha', _fFecha),
        h('Moneda', _fMoneda),
        h('Mercancía', _fMerc, derecha: true),
        h('Ajustes', _fAjustes, derecha: true),
        h('Financiado', _fFin, derecha: true),
        h('Aterrizado', _fAter, derecha: true),
        h('Estado', _fEstado),
      ],
    );
  }

  Widget _filaPc(CompraResumen c) {
    return Row(
      children: [
        Expanded(
          flex: _fNum,
          child: _celda('#${c.numeroCompra}', negrita: true),
        ),
        Expanded(
          flex: _fProv,
          child: _celda(c.proveedor.isEmpty ? '—' : c.proveedor),
        ),
        Expanded(
          flex: _fFact,
          child: _celda(
            (c.numeroFactura ?? '').trim().isEmpty ? '—' : c.numeroFactura!,
          ),
        ),
        Expanded(flex: _fFecha, child: _celda(formatearFecha(c.fechaFactura))),
        Expanded(
          flex: _fMoneda,
          child: _celda(c.monedaTotal.isEmpty ? '—' : c.monedaTotal),
        ),
        Expanded(
          flex: _fMerc,
          child: _celda(formatearImporte(c.totalMercancia), derecha: true),
        ),
        Expanded(
          flex: _fAjustes,
          child: _celda(formatearImporte(c.totalAjustes), derecha: true),
        ),
        Expanded(
          flex: _fFin,
          child: _celda(
            formatearImporte(c.totalFinanciado),
            derecha: true,
            negrita: true,
          ),
        ),
        Expanded(
          flex: _fAter,
          child: _celda(
            formatearImporte(c.costoAterrizado),
            derecha: true,
            negrita: true,
          ),
        ),
        Expanded(
          flex: _fEstado,
          child: Align(
            alignment: Alignment.centerLeft,
            child: chipEstadoCompra(c.estado, denso: true),
          ),
        ),
      ],
    );
  }

  Widget _cabeceraTablet() {
    const estilo = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 0.2,
    );
    Widget h(String t, int flex, {bool derecha = false}) => Expanded(
      flex: flex,
      child: Text(
        t,
        textAlign: derecha ? TextAlign.right : TextAlign.left,
        style: estilo,
      ),
    );
    return Row(
      children: [
        h('Proveedor', 32),
        h('Mercancía', 15, derecha: true),
        h('Financiado', 15, derecha: true),
        h('Aterrizado', 15, derecha: true),
        h('Estado', 18),
      ],
    );
  }

  Widget _filaTablet(CompraResumen c) {
    final factura = (c.numeroFactura ?? '').trim();
    final meta = [
      if (c.monedaTotal.isNotEmpty) c.monedaTotal,
      if (factura.isNotEmpty) 'Factura $factura',
      formatearFecha(c.fechaFactura),
    ].join(' · ');
    return Row(
      children: [
        Expanded(
          flex: 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.proveedor.isEmpty ? '—' : c.proveedor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${c.lineas} ${c.lineas == 1 ? 'línea' : 'líneas'} · $meta',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 15,
          child: _celda(formatearImporte(c.totalMercancia), derecha: true),
        ),
        Expanded(
          flex: 15,
          child: _celda(
            formatearImporte(c.totalFinanciado),
            derecha: true,
            negrita: true,
          ),
        ),
        Expanded(
          flex: 15,
          child: _celda(
            formatearImporte(c.costoAterrizado),
            derecha: true,
            negrita: true,
          ),
        ),
        Expanded(
          flex: 18,
          child: Align(
            alignment: Alignment.centerLeft,
            child: chipEstadoCompra(c.estado, denso: true),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // Tarjetas (móvil)
  // ==========================================================================

  Widget _listaTarjetas() {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _compras.length,
        itemBuilder: (context, index) => _tarjeta(_compras[index]),
      ),
    );
  }

  Widget _tarjeta(CompraResumen c) {
    final factura = (c.numeroFactura ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _abrirDetalle(c),
          child: panelCompras(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      c.proveedor.isEmpty ? '—' : c.proveedor,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatearImporte(c.costoAterrizado),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text(
                        'aterrizado',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      factura.isEmpty
                          ? 'Sin factura · ${formatearFecha(c.fechaFactura)}'
                          : 'Factura $factura · ${formatearFecha(c.fechaFactura)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  chipEstadoCompra(c.estado, denso: true),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mercancía ${formatearImporte(c.totalMercancia)} ${c.monedaTotal}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Financiado ${formatearImporte(c.totalFinanciado)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  '${c.lineas} ${c.lineas == 1 ? 'línea' : 'líneas'}',
                  if (c.totalAjustes != 0)
                    'Ajustes ${formatearImporte(c.totalAjustes)}',
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
