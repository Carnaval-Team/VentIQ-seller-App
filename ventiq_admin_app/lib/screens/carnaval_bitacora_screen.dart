import 'package:flutter/material.dart';
import '../services/carnaval_service.dart';
import '../widgets/bitacora_tile.dart';

/// BITÁCORA DE CAPITÁN
///
/// Vista completa de todo lo que se ha tocado en las líneas de las órdenes de
/// Carnaval: quién subió una cantidad, quién la bajó, quién borró una línea,
/// cuándo, por qué y si el movimiento llegó al inventario de Inventtia.
///
/// Lee `carnavalapp.v_bitacora_capitan`, que alimenta el trigger
/// `trg_orderdetails_ajustar_erp`. La tabla de fondo es append-only, así que
/// nadie puede borrar su rastro desde ninguna app.
///
/// Solo la abre la tienda principal (misma comprobación que para asignar o
/// cancelar órdenes), porque muestra movimientos de todos los proveedores.
class CarnavalBitacoraScreen extends StatefulWidget {
  /// `null` = tienda principal, ve todo. Con valor, se acota a ese proveedor.
  final int? proveedorFilter;

  const CarnavalBitacoraScreen({Key? key, this.proveedorFilter})
      : super(key: key);

  @override
  State<CarnavalBitacoraScreen> createState() => _CarnavalBitacoraScreenState();
}

class _CarnavalBitacoraScreenState extends State<CarnavalBitacoraScreen> {
  static const _pageSize = 30;

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;

  List<Map<String, dynamic>> _rows = [];

  // Filtros
  String? _accion;
  bool _soloSinAplicar = false;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int? _orderId;
  String? _buscarQuien;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _currentPage = 0;
      _hasMore = true;
    });

    final rows = await CarnavalService.getBitacora(
      page: 0,
      pageSize: _pageSize,
      proveedorFilter: widget.proveedorFilter,
      accion: _accion,
      soloSinAplicar: _soloSinAplicar,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      orderId: _orderId,
      buscarQuien: _buscarQuien,
    );

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _isLoading = false;
      _hasMore = rows.length == _pageSize;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    setState(() => _isLoadingMore = true);

    final next = _currentPage + 1;
    final rows = await CarnavalService.getBitacora(
      page: next,
      pageSize: _pageSize,
      proveedorFilter: widget.proveedorFilter,
      accion: _accion,
      soloSinAplicar: _soloSinAplicar,
      dateFrom: _dateFrom,
      dateTo: _dateTo,
      orderId: _orderId,
      buscarQuien: _buscarQuien,
    );

    if (!mounted) return;
    setState(() {
      _rows.addAll(rows);
      _currentPage = next;
      _isLoadingMore = false;
      _hasMore = rows.length == _pageSize;
    });
  }

  /// La caja de búsqueda acepta un número (id de orden) o un nombre.
  void _onSearch() {
    final text = _searchController.text.trim();
    if (text.isEmpty) {
      _orderId = null;
      _buscarQuien = null;
    } else {
      final asId = int.tryParse(text);
      _orderId = asId;
      _buscarQuien = asId == null ? text : null;
    }
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
      _load();
    }
  }

  String get _rangeLabel {
    if (_dateFrom == null || _dateTo == null) return 'Todas las fechas';
    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '${f(_dateFrom!)} - ${f(_dateTo!)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bitácora de capitán'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _onSearch(),
              // Para que aparezca/desaparezca la X de limpiar.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por # de orden o por nombre...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch();
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // Filtros
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(_rangeLabel),
                  onPressed: _pickRange,
                ),
                if (_dateFrom != null) ...[
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 16),
                    label: const Text('Quitar fecha'),
                    onPressed: () {
                      setState(() {
                        _dateFrom = null;
                        _dateTo = null;
                      });
                      _load();
                    },
                  ),
                ],
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Todo'),
                  selected: _accion == null,
                  onSelected: (_) {
                    setState(() => _accion = null);
                    _load();
                  },
                ),
                for (final a in BitacoraTile.acciones) ...[
                  const SizedBox(width: 6),
                  FilterChip(
                    avatar: Icon(
                      BitacoraTile.iconoDeAccion(a['valor']),
                      size: 16,
                      color: BitacoraTile.colorDeAccion(a['valor']),
                    ),
                    label: Text(a['texto']!),
                    selected: _accion == a['valor'],
                    onSelected: (sel) {
                      setState(() => _accion = sel ? a['valor'] : null);
                      _load();
                    },
                  ),
                ],
                const SizedBox(width: 6),
                FilterChip(
                  avatar: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange.shade800,
                  ),
                  label: const Text('Sin ajustar inventario'),
                  selected: _soloSinAplicar,
                  onSelected: (sel) {
                    setState(() => _soloSinAplicar = sel);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= _rows.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            return BitacoraTile(
                              row: _rows[i],
                              showOrderId: true,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final filtrando = _accion != null ||
        _soloSinAplicar ||
        _dateFrom != null ||
        _orderId != null ||
        _buscarQuien != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              filtrando
                  ? 'No hay movimientos con esos filtros'
                  : 'Todavía no hay movimientos registrados',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
            if (!filtrando) ...[
              const SizedBox(height: 8),
              Text(
                'Aquí aparece cada vez que alguien cambia una cantidad o '
                'elimina un producto de una orden.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
