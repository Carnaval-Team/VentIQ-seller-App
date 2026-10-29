import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';
import '../services/marketplace_product_service.dart';

/// Modo del selector:
///  - manual: el padre lo abre con push y, al "Continuar",
///    retorna un [WapiProductSelection] vía Navigator.pop.
///  - schedule: idéntico, pero el texto del botón cambia.
enum WapiProductSelectorMode { manual, schedule }

/// Lo que el selector devuelve al padre al confirmar.
///
/// Antes sólo devolvía `List<int>`, así que la decisión "sólo disponibles"
/// (el usuario descarta los agotados) se perdía al cerrar la pantalla y
/// nunca llegaba al backend. Ahora viaja junto a los ids.
class WapiProductSelection {
  final List<int> ids;

  /// Si es `true`, la programación/envío debe re-filtrar en el backend y
  /// descartar los productos que estén agotados en el momento del envío.
  final bool soloDisponibles;

  const WapiProductSelection({
    required this.ids,
    this.soloDisponibles = false,
  });
}

/// Selector multi-select de productos para difundir por WhatsApp.
///
/// Datos vienen del RPC paginado `get_productos_marketplace`. Sólo se
/// muestran productos con imagen (WAPI requiere URL pública).
class WapiProductSelectorScreen extends StatefulWidget {
  final int idTienda;
  final WapiProductSelectorMode mode;
  final Set<int> initialSelected;

  /// Preferencia "solo disponibles" con la que abre la pantalla.
  ///
  /// `null` = el padre no opina (envío manual): se reusa la última decisión
  /// guardada en caché para esta tienda/modo. Un valor explícito (editar una
  /// programación) manda sobre la caché.
  final bool? initialSoloDisponibles;

  const WapiProductSelectorScreen({
    super.key,
    required this.idTienda,
    this.mode = WapiProductSelectorMode.manual,
    this.initialSelected = const {},
    this.initialSoloDisponibles,
  });

  @override
  State<WapiProductSelectorScreen> createState() =>
      _WapiProductSelectorScreenState();
}

class _WapiProductSelectorScreenState extends State<WapiProductSelectorScreen> {
  static const int _pageSize = 20;
  static const String _prefsPrefix = 'wapi_product_selection';

  final Set<int> _selected = {};
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<MarketplaceProduct> _items = [];
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String _query = '';
  Timer? _debounce;
  /// Filtro local (no toca el RPC): oculta del listado los productos
  /// sin stock. No altera la selección ya hecha.
  bool _hideSinStock = false;

  /// Decisión del usuario: enviar sólo productos con stock. A diferencia de
  /// [_hideSinStock] (puramente visual) esta preferencia SÍ viaja al backend,
  /// que re-filtra con el stock del momento del envío.
  bool _soloDisponibles = false;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
    _soloDisponibles = widget.initialSoloDisponibles ?? false;
    _scrollCtrl.addListener(_onScroll);
    // Si el padre no pasó selección previa, recuperamos la última guardada
    // en cache para esta tienda/modo.
    if (widget.initialSelected.isEmpty) _restoreCachedSelection();
    _restoreCachedSoloDisponibles();
    _reload();
  }

  /// Clave de cache: separada por tienda y por modo (manual vs programado),
  /// así "enviar ahora" y los programados no se pisan entre sí.
  String get _prefsKey =>
      '${_prefsPrefix}_${widget.idTienda}_${widget.mode.name}';

  /// Clave aparte para la preferencia "solo disponibles": se guarda aunque no
  /// haya ids seleccionados.
  String get _prefsKeySoloDisponibles => '${_prefsKey}_solo_disponibles';

  Future<void> _restoreCachedSoloDisponibles() async {
    // El padre tiene la última palabra (p. ej. la programación ya guardada).
    if (widget.initialSoloDisponibles != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_prefsKeySoloDisponibles);
      if (v == null || !mounted) return;
      setState(() => _soloDisponibles = v);
    } catch (_) {
      // cache best-effort
    }
  }

  Future<void> _restoreCachedSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey);
      if (raw == null || raw.isEmpty || !mounted) return;
      final ids = raw
          .map((e) => int.tryParse(e))
          .whereType<int>()
          .toSet();
      if (ids.isEmpty) return;
      setState(() => _selected.addAll(ids));
    } catch (_) {
      // cache es best-effort: si falla, se abre sin preselección
    }
  }

  Future<void> _persistSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selected.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setStringList(
          _prefsKey,
          _selected.map((e) => e.toString()).toList(),
        );
      }
    } catch (_) {
      // ignorar
    }
  }

  Future<void> _persistSoloDisponibles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeySoloDisponibles, _soloDisponibles);
    } catch (_) {
      // ignorar
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loadingInitial = true;
      _error = null;
      _items.clear();
      _hasMore = true;
    });
    try {
      final page = await MarketplaceProductService.getProductos(
        idTienda: widget.idTienda,
        limit: 999,
        offset: 0,
        search: _query,
        soloDisponibles: false,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loadingInitial) return;
    setState(() => _loadingMore = true);
    try {
      final page = await MarketplaceProductService.getProductos(
        idTienda: widget.idTienda,
        limit: 999,
        offset: _items.length,
        search: _query,
        soloDisponibles: false,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando más: $e')),
      );
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = v.trim();
      if (q == _query) return;
      _query = q;
      _reload();
    });
  }

  bool _canSend(MarketplaceProduct p) =>
      p.imagen.isNotEmpty &&
      p.denominacion.isNotEmpty &&
      p.precioVenta > 0;

  /// Productos publicables ya cargados en memoria, aplicando el filtro
  /// local de "ocultar no disponibles". Es puramente visual: NO recarga
  /// del RPC, sólo filtra `_items`.
  List<MarketplaceProduct> get _visibleItems => _items
      .where(_canSend)
      .where((p) => !_hideSinStock || _tieneStock(p))
      .toList();

  bool _tieneStock(MarketplaceProduct p) =>
      p.tieneStock && p.stockDisponible > 0;

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Seleccionar productos'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loadingInitial
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _reload)
              : Column(
                  children: [
                    _buildHeader(_visibleItems),
                    Expanded(
                      child: _visibleItems.isEmpty
                          ? _EmptyView(
                              message: _hideSinStock
                                  ? 'Ningún producto con stock disponible.\n'
                                      'Usa "Mostrar no disponibles" para ver el resto.'
                                  : null,
                            )
                          : RefreshIndicator(
                              onRefresh: _reload,
                              child: isWeb
                                  ? _buildGrid(_visibleItems)
                                  : _buildList(_visibleItems),
                            ),
                    ),
                    _buildBottomBar(),
                  ],
                ),
    );
  }

  /// Todos los publicables cargados, ignorando el filtro visual. Las acciones
  /// de selección masiva operan sobre esto para que "ocultar no disponibles"
  /// no deje productos sin stock marcados fuera de la vista.
  List<MarketplaceProduct> get _publicables =>
      _items.where(_canSend).toList();

  Widget _buildHeader(List<MarketplaceProduct> filtered) {
    final todos = _publicables;
    final allSelectedVisible = filtered.isNotEmpty &&
        filtered.every((p) => _selected.contains(p.idProducto));
    final disponibles = todos.where(_tieneStock).toList();
    final sinStockCount = todos.length - disponibles.length;
    final narrow = MediaQuery.of(context).size.width < 700;

    void onSoloDisponibles() {
      setState(() {
        // Alterna el filtro. Al activarlo marca únicamente los que tienen
        // stock > 0 y desmarca los sin stock (incluso si están ocultos).
        _soloDisponibles = !_soloDisponibles;
        if (_soloDisponibles) {
          for (final p in todos) {
            if (_tieneStock(p)) {
              _selected.add(p.idProducto);
            } else {
              _selected.remove(p.idProducto);
            }
          }
        }
      });
      _persistSelection();
      _persistSoloDisponibles();
    }

    void onToggleTodos() {
      setState(() {
        for (final p in filtered) {
          if (allSelectedVisible) {
            _selected.remove(p.idProducto);
          } else {
            _selected.add(p.idProducto);
          }
        }
      });
      _persistSelection();
    }

    // Sólo filtra en memoria — no se vuelve a llamar al RPC.
    void onToggleHide() =>
        setState(() => _hideSinStock = !_hideSinStock);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar producto…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                    ),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${filtered.length} mostrado(s) • '
                  '${disponibles.length} con stock'
                  '${_soloDisponibles ? ' • sólo disponibles' : ''}'
                  '${_hideSinStock && sinStockCount > 0 ? ' • $sinStockCount oculto(s)' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              _HeaderAction(
                icon: _hideSinStock
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                label: _hideSinStock
                    ? 'Mostrar no disponibles'
                    : 'Ocultar no disponibles',
                color: _hideSinStock
                    ? AppColors.warning
                    : AppColors.textSecondary,
                iconOnly: narrow,
                onPressed: sinStockCount == 0 ? null : onToggleHide,
              ),
              const SizedBox(width: 2),
              // Alterna "solo disponibles". Activo = el backend re-filtrará
              // por stock al enviar (la preferencia viaja con la selección).
              _HeaderAction(
                icon: _soloDisponibles
                    ? Icons.inventory_2
                    : Icons.inventory_2_outlined,
                label: 'Solo disponibles',
                tooltip: _soloDisponibles
                    ? 'Activado: los productos agotados no se enviarán. '
                        'Toca para incluir también los agotados.'
                    : 'Marcar y enviar sólo los productos con stock. '
                        'Se omite en el envío todo lo que esté agotado.',
                color: _soloDisponibles
                    ? AppColors.success
                    : AppColors.textSecondary,
                iconOnly: narrow,
                onPressed: disponibles.isEmpty && !_soloDisponibles
                    ? null
                    : onSoloDisponibles,
              ),
              const SizedBox(width: 2),
              _HeaderAction(
                icon: allSelectedVisible ? Icons.deselect : Icons.select_all,
                label: allSelectedVisible
                    ? 'Deseleccionar todo'
                    : 'Seleccionar todo',
                iconOnly: narrow,
                onPressed: filtered.isEmpty ? null : onToggleTodos,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<MarketplaceProduct> items) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: items.length + (_loadingMore || _hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= items.length) return _buildLoaderTile();
        return _ProductTile(
          product: items[i],
          selected: _selected.contains(items[i].idProducto),
          onTap: () => _toggle(items[i]),
        );
      },
    );
  }

  Widget _buildGrid(List<MarketplaceProduct> items) {
    return GridView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 150,
      ),
      itemCount: items.length + (_loadingMore || _hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= items.length) return _buildLoaderTile();
        return _ProductTile(
          product: items[i],
          selected: _selected.contains(items[i].idProducto),
          onTap: () => _toggle(items[i]),
        );
      },
    );
  }

  Widget _buildLoaderTile() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );

  void _toggle(MarketplaceProduct p) {
    setState(() {
      if (_selected.contains(p.idProducto)) {
        _selected.remove(p.idProducto);
      } else {
        _selected.add(p.idProducto);
      }
    });
    _persistSelection();
  }

  /// Si entre los seleccionados hay productos sin stock, pedir confirmación
  /// antes de devolver la lista al padre. "Revisar" cancela y deja al usuario
  /// en el picker para ajustar; "Continuar" envía igual (salvo que el filtro
  /// "solo disponibles" esté activo: entonces el backend los descarta).
  Future<void> _confirmAndPop() async {
    await _persistSelection();
    await _persistSoloDisponibles();
    if (!mounted) return;
    final sinStock = _items
        .where((p) =>
            _selected.contains(p.idProducto) &&
            (!p.tieneStock || p.stockDisponible <= 0))
        .toList();

    if (sinStock.isEmpty) {
      Navigator.of(context).pop(_resultado());
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning),
            SizedBox(width: 8),
            Expanded(child: Text('Productos sin stock')),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _soloDisponibles
                    ? 'Los siguientes ${sinStock.length} producto(s) no tienen '
                        'stock y tienes activado "Solo disponibles": se '
                        'omitirán al enviar. La programación guardará el '
                        'filtro, así que tampoco se enviarán si siguen '
                        'agotados cuando toque el envío.'
                    : 'Los siguientes ${sinStock.length} producto(s) no tienen '
                        'stock disponible. Aún puedes difundirlos, pero los '
                        'destinatarios verán "Sin stock" en el mensaje.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: sinStock
                        .map((p) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('• ',
                                      style: TextStyle(
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.bold)),
                                  Expanded(
                                    child: Text(
                                      p.denominacion,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'revisar'),
            child: const Text('Revisar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              _soloDisponibles ? 'Continuar sin ellos' : 'Continuar igual',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'continuar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'continuar') {
      Navigator.of(context).pop(_resultado());
    }
    // En "revisar" no hacemos nada — el usuario sigue en el picker.
  }

  WapiProductSelection _resultado() => WapiProductSelection(
        ids: _selected.toList(),
        soloDisponibles: _soloDisponibles,
      );

  /// Seleccionados que el backend descartaría al enviar por estar agotados.
  int get _sinStockSeleccionados => _items
      .where((p) => _selected.contains(p.idProducto) && !_tieneStock(p))
      .length;

  Widget _buildBottomBar() {
    final label = widget.mode == WapiProductSelectorMode.manual
        ? 'Continuar (${_selected.length})'
        : 'Guardar selección (${_selected.length})';
    final omitidos = _soloDisponibles ? _sinStockSeleccionados : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selected.isEmpty
                  ? 'Selecciona al menos un producto para continuar'
                  : omitidos > 0
                      ? '${_selected.length} producto(s) listos • '
                          '$omitidos sin stock se omitirán'
                      : _soloDisponibles
                          ? '${_selected.length} producto(s) • '
                              'sólo con stock disponible'
                          : '${_selected.length} producto(s) listos',
              style: TextStyle(
                color: _selected.isEmpty
                    ? AppColors.textSecondary
                    : omitidos > 0
                        ? AppColors.warning
                        : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.arrow_forward),
            label: Text(label),
            onPressed: _selected.isEmpty ? null : _confirmAndPop,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón compacto de la barra de acciones del header. En pantallas
/// estrechas colapsa a sólo icono (con tooltip) para no desbordar.
class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Texto del tooltip cuando el label visible se queda corto (p. ej. el
  /// estado del filtro "solo disponibles"). Si es `null` se usa [label].
  final String? tooltip;
  final Color? color;
  final bool iconOnly;
  final VoidCallback? onPressed;

  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.iconOnly,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tip = tooltip ?? label;
    if (iconOnly) {
      return IconButton(
        icon: Icon(icon, size: 20),
        color: color,
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 34),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      );
    }
    return Tooltip(
      message: tip,
      child: TextButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: color,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final MarketplaceProduct product;
  final bool selected;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  String _formatStock(double s) {
    if (s % 1 == 0) return s.toStringAsFixed(0);
    return s.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final sinStock = !product.tieneStock || product.stockDisponible <= 0;
    final stockText = sinStock
        ? 'Sin stock'
        : '${_formatStock(product.stockDisponible)} disp.';
    final borderColor = selected
        ? AppColors.primary
        : sinStock
            ? AppColors.warning
            : AppColors.border;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: sinStock ? AppColors.warning.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: product.imagen.isNotEmpty
                          ? Image.network(
                              product.imagen,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.broken_image,
                                    color: AppColors.textLight),
                              ),
                            )
                          : Container(
                              color: AppColors.surfaceVariant,
                              child: const Icon(
                                  Icons.image_not_supported_outlined),
                            ),
                    ),
                  ),
                  if (sinStock)
                    Positioned(
                      top: 2,
                      left: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.denominacion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '\$${product.precioVenta.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (product.categoriaNombre.isNotEmpty)
                          Flexible(
                            child: Text(
                              product.categoriaNombre,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textLight),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          sinStock
                              ? Icons.warning_amber_rounded
                              : Icons.inventory_2_outlined,
                          size: 13,
                          color: sinStock
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          stockText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: sinStock
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: sinStock
                                ? AppColors.warning
                                : AppColors.textSecondary,
                          ),
                        ),
                        if (product.ubicacion != null &&
                            product.ubicacion!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.place_outlined,
                              size: 13, color: AppColors.textLight),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              product.ubicacion!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textLight,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String? message;
  const _EmptyView({this.message});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 64, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(
              message ??
                  'No hay productos publicables.\n'
                      'Asegúrate de que tienen foto y precio.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 56, color: AppColors.error),
            const SizedBox(height: 10),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
