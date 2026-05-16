import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/movimiento_models.dart';
import '../models/store.dart';
import '../services/movimientos_service.dart';
import '../services/store_service.dart';
import '../widgets/app_drawer.dart';

class MovimientosScreen extends StatefulWidget {
  const MovimientosScreen({super.key});

  @override
  State<MovimientosScreen> createState() => _MovimientosScreenState();
}

class _MovimientosScreenState extends State<MovimientosScreen> {
  static const _refreshSeconds = 10;

  final _inventarioListKey = GlobalKey<AnimatedListState>();
  final _operacionesListKey = GlobalKey<AnimatedListState>();

  List<Store> _stores = [];
  Store? _selectedStore;

  // Listas “vivas” (lo que muestra la UI con AnimatedList)
  final List<InventarioMovimiento> _inventarioUI = [];
  final List<OperacionTR> _operacionesUI = [];

  Timer? _timer;
  Timer? _clockTimer;
  bool _loadingStores = true;
  bool _loadingData = false;
  DateTime _now = DateTime.now();
  int _inventarioTotal = 0;
  int _operacionesTotal = 0;

  // Flash highlight tracking (items recently moved/inserted).
  // Inventario: 'up' subió de posición, 'down' bajó, 'new' nuevo.
  final Map<String, String> _flashInv = {};
  final Set<int> _flashOps = {};

  void _flashInvKey(String key, String dir) {
    _flashInv[key] = dir;
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      if (_flashInv[key] == dir) {
        setState(() => _flashInv.remove(key));
      }
    });
  }

  void _flashOpKey(int id) {
    _flashOps.add(id);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _flashOps.remove(id));
    });
  }

  @override
  void initState() {
    super.initState();
    _loadStores();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStores() async {
    setState(() => _loadingStores = true);
    final stores = await StoreService.getAllStores();
    if (!mounted) return;
    setState(() {
      _stores = stores;
      _loadingStores = false;
      if (stores.isNotEmpty) {
        _selectedStore = stores.first;
      }
    });
    if (_selectedStore != null) {
      await _refreshAll(initial: true);
      _startAutoRefresh();
    }
  }

  void _startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: _refreshSeconds),
      (_) => _refreshAll(),
    );
  }

  Future<void> _onStoreChanged(Store? s) async {
    if (s == null || s.id == _selectedStore?.id) return;
    setState(() {
      _selectedStore = s;
      // Limpiar listas animadas
      for (int i = _inventarioUI.length - 1; i >= 0; i--) {
        final removed = _inventarioUI.removeAt(i);
        _inventarioListKey.currentState?.removeItem(
          i,
          (ctx, anim) => _buildInventarioRow(removed, anim, removing: true),
          duration: const Duration(milliseconds: 200),
        );
      }
      for (int i = _operacionesUI.length - 1; i >= 0; i--) {
        final removed = _operacionesUI.removeAt(i);
        _operacionesListKey.currentState?.removeItem(
          i,
          (ctx, anim) => _buildOperacionRow(removed, anim, removing: true),
          duration: const Duration(milliseconds: 200),
        );
      }
    });
    await _refreshAll(initial: true);
    _startAutoRefresh();
  }

  Future<void> _refreshAll({bool initial = false}) async {
    if (_selectedStore == null) return;
    if (_loadingData) return;
    setState(() => _loadingData = true);
    try {
      final results = await Future.wait([
        MovimientosService.getInventarioTiempoReal(
          idTienda: _selectedStore!.id,
        ),
        MovimientosService.getOperacionesTiempoReal(
          idTienda: _selectedStore!.id,
        ),
      ]);
      final inv = results[0] as List<InventarioMovimiento>;
      final ops = results[1] as List<OperacionTR>;
      if (!mounted) return;
      // Ordenar inventario por fecha DESC (lo de más movimiento primero)
      inv.sort((a, b) => b.ultimaFecha.compareTo(a.ultimaFecha));
      ops.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _diffApplyInventario(inv);
      _diffApplyOperaciones(ops);

      setState(() {
        _inventarioTotal = inv.isEmpty ? 0 : inv.first.totalCount;
        _operacionesTotal = ops.isEmpty ? 0 : ops.first.totalCount;
      });
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  // ---- Diff/animación tipo tabla de posiciones para inventario ----
  void _diffApplyInventario(List<InventarioMovimiento> nuevos) {
    final state = _inventarioListKey.currentState;
    final viejas = List<InventarioMovimiento>.from(_inventarioUI);
    final nuevasMap = {for (final i in nuevos) i.clave: i};

    // 1) remover las que ya no están
    for (int i = viejas.length - 1; i >= 0; i--) {
      final v = viejas[i];
      if (!nuevasMap.containsKey(v.clave)) {
        final removedItem = _inventarioUI.removeAt(i);
        state?.removeItem(
          i,
          (ctx, anim) => _buildInventarioRow(removedItem, anim, removing: true),
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    // 2) recorrer en orden destino: si cambió de posición → remove+insert
    for (int i = 0; i < nuevos.length; i++) {
      final n = nuevos[i];
      final currentIdx =
          _inventarioUI.indexWhere((x) => x.clave == n.clave);
      if (currentIdx == -1) {
        _inventarioUI.insert(i, n);
        state?.insertItem(
          i,
          duration: const Duration(milliseconds: 500),
        );
        _flashInvKey(n.clave, 'new');
      } else if (currentIdx != i) {
        // Mover: remove + insert con animación (leaderboard style)
        final moved = _inventarioUI.removeAt(currentIdx);
        final wentUp = i < currentIdx;
        state?.removeItem(
          currentIdx,
          (ctx, anim) => _buildInventarioRow(
            moved,
            anim,
            removing: true,
            slideFromBottom: wentUp,
          ),
          duration: const Duration(milliseconds: 350),
        );
        _inventarioUI.insert(i, n);
        state?.insertItem(
          i,
          duration: const Duration(milliseconds: 550),
        );
        _flashInvKey(n.clave, wentUp ? 'up' : 'down');
      } else {
        // Misma posición pero pudo cambiar cantidad → actualizar en sitio
        if (_inventarioUI[i].cantidadFinal != n.cantidadFinal ||
            _inventarioUI[i].variacion != n.variacion) {
          _inventarioUI[i] = n;
          _flashInvKey(n.clave, n.cantidadFinal > _inventarioUI[i].cantidadFinal ? 'up' : 'down');
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _diffApplyOperaciones(List<OperacionTR> nuevos) {
    final state = _operacionesListKey.currentState;
    final viejas = List<OperacionTR>.from(_operacionesUI);
    final nuevasMap = {for (final i in nuevos) i.clave: i};

    for (int i = viejas.length - 1; i >= 0; i--) {
      final v = viejas[i];
      if (!nuevasMap.containsKey(v.clave)) {
        final removedItem = _operacionesUI.removeAt(i);
        state?.removeItem(
          i,
          (ctx, anim) =>
              _buildOperacionRow(removedItem, anim, removing: true),
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    for (int i = 0; i < nuevos.length; i++) {
      final n = nuevos[i];
      final currentIdx =
          _operacionesUI.indexWhere((x) => x.clave == n.clave);
      if (currentIdx == -1) {
        _operacionesUI.insert(i, n);
        state?.insertItem(
          i,
          duration: const Duration(milliseconds: 600),
        );
        _flashOpKey(n.idOperacion);
      } else if (currentIdx != i) {
        final moved = _operacionesUI.removeAt(currentIdx);
        state?.removeItem(
          currentIdx,
          (ctx, anim) => _buildOperacionRow(moved, anim, removing: true),
          duration: const Duration(milliseconds: 300),
        );
        _operacionesUI.insert(i, n);
        state?.insertItem(
          i,
          duration: const Duration(milliseconds: 600),
        );
      } else {
        _operacionesUI[i] = n;
      }
    }
    if (mounted) setState(() {});
  }

  // ============== UI ==============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Movimientos en tiempo real'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),
        actions: [
          if (_loadingData)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refrescar ahora',
            icon: const Icon(Icons.refresh),
            onPressed: _loadingData ? null : () => _refreshAll(),
          ),
        ],
      ),
      body: _loadingStores
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeaderBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (ctx, c) {
                      final wide = c.maxWidth > 900;
                      if (wide) {
                        return Row(
                          children: [
                            Expanded(flex: 6, child: _buildInventarioPanel()),
                            const VerticalDivider(width: 1),
                            Expanded(flex: 5, child: _buildOperacionesPanel()),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Expanded(child: _buildInventarioPanel()),
                          const Divider(height: 1),
                          Expanded(child: _buildOperacionesPanel()),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderBar() {
    final df = DateFormat('EEEE d MMMM yyyy', 'es_ES');
    final tf = DateFormat('HH:mm:ss');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.store, color: AppColors.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 320,
            child: DropdownButtonFormField<Store>(
              value: _selectedStore,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tienda',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: _stores
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s.denominacion,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _onStoreChanged,
            ),
          ),
          const Spacer(),
          _LiveBadge(active: !_loadingData),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                df.format(_now),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                tf.format(_now),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInventarioPanel() {
    // Agrupar por almacén
    final Map<String, List<InventarioMovimiento>> porAlmacen = {};
    for (final m in _inventarioUI) {
      porAlmacen.putIfAbsent(m.almacenNombre, () => []).add(m);
    }

    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(
            icon: Icons.inventory_2,
            title: 'Inventario en tiempo real',
            subtitle: 'Total productos: $_inventarioTotal',
          ),
          Expanded(
            child: _inventarioUI.isEmpty
                ? const Center(
                    child: Text(
                      'Sin movimientos de inventario hoy',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : AnimatedList(
                    key: _inventarioListKey,
                    initialItemCount: _inventarioUI.length,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemBuilder: (ctx, index, anim) {
                      if (index >= _inventarioUI.length) {
                        return const SizedBox.shrink();
                      }
                      final item = _inventarioUI[index];
                      // Cabecera de grupo cuando cambia el almacén
                      final mostrarHeader = index == 0 ||
                          _inventarioUI[index - 1].almacenNombre !=
                              item.almacenNombre;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (mostrarHeader)
                            _almacenHeader(item.almacenNombre),
                          _buildInventarioRow(item, anim, position: index + 1),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _almacenHeader(String nombre) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.warehouse, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            nombre.isEmpty ? 'Almacén' : nombre,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventarioRow(
    InventarioMovimiento m,
    Animation<double> anim, {
    bool removing = false,
    int? position,
    bool slideFromBottom = true,
  }) {
    final isSubio = m.subio;
    final isBajo = m.bajo;
    final color = isSubio
        ? AppColors.success
        : isBajo
            ? AppColors.error
            : AppColors.textHint;
    final icon = isSubio
        ? Icons.arrow_upward
        : isBajo
            ? Icons.arrow_downward
            : Icons.remove;

    final flashDir = _flashInv[m.clave];
    final flashColor = flashDir == 'up' || flashDir == 'new'
        ? AppColors.success.withOpacity(0.18)
        : flashDir == 'down'
            ? AppColors.error.withOpacity(0.18)
            : null;

    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: flashColor,
        borderRadius: BorderRadius.circular(10),
        border: flashColor != null
            ? Border.all(
                color: (flashDir == 'down'
                        ? AppColors.error
                        : AppColors.success)
                    .withOpacity(0.45),
                width: 1.2,
              )
            : null,
      ),
      child: Card(
      key: ValueKey('inv-${m.clave}'),
      margin: EdgeInsets.zero,
      elevation: flashColor != null ? 4 : 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: removing ? null : () => _mostrarHistorial(m),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (position != null)
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    '$position',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.productoNombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${m.sku.isEmpty ? "-" : m.sku}  •  ${m.zonaNombre}',
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
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmt(m.cantidadFinal),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    isSubio
                        ? '+${_fmt(m.variacion.abs())}'
                        : isBajo
                            ? '-${_fmt(m.variacion.abs())}'
                            : '0',
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );

    // Leaderboard style: filas que suben entran desde abajo,
    // las que bajan salen hacia abajo. Las nuevas/eliminadas
    // dependen de `slideFromBottom`.
    final beginOffset = slideFromBottom
        ? const Offset(0, 0.6)
        : const Offset(0, -0.6);

    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
      axisAlignment: -1,
      child: FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          ),
          child: row,
        ),
      ),
    );
  }

  Widget _buildOperacionesPanel() {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader(
            icon: Icons.receipt_long,
            title: 'Operaciones del día',
            subtitle: 'Total: $_operacionesTotal',
          ),
          Expanded(
            child: _operacionesUI.isEmpty
                ? const Center(
                    child: Text(
                      'Sin operaciones hoy',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : AnimatedList(
                    key: _operacionesListKey,
                    initialItemCount: _operacionesUI.length,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemBuilder: (ctx, index, anim) {
                      if (index >= _operacionesUI.length) {
                        return const SizedBox.shrink();
                      }
                      return _buildOperacionRow(
                        _operacionesUI[index],
                        anim,
                        position: index + 1,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperacionRow(
    OperacionTR op,
    Animation<double> anim, {
    bool removing = false,
    int? position,
  }) {
    final tipoColor = _colorPorTipo(op.tipoOperacion);
    final tf = DateFormat('HH:mm:ss');
    final isNew = _flashOps.contains(op.idOperacion);

    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: isNew ? tipoColor.withOpacity(0.10) : null,
        borderRadius: BorderRadius.circular(10),
        border: isNew
            ? Border.all(color: tipoColor.withOpacity(0.55), width: 1.4)
            : null,
        boxShadow: isNew
            ? [
                BoxShadow(
                  color: tipoColor.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Card(
      key: ValueKey('op-${op.idOperacion}'),
      margin: EdgeInsets.zero,
      elevation: isNew ? 4 : 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            if (position != null)
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  '$position',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 36,
              decoration: BoxDecoration(
                color: tipoColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        op.tipoOperacion,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: tipoColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${op.idOperacion}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${op.usuarioNombre}  •  ${op.estadoNombre}',
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
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  op.total > 0
                      ? '\$${op.total.toStringAsFixed(2)}'
                      : '${op.cantidadItems} items',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  tf.format(op.createdAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );

    // Estilo notificación: entra deslizándose desde la derecha,
    // con un pequeño rebote y escala. Tipos removidos salen igual.
    final curved = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
      axisAlignment: -1,
      child: FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.05, 0),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: row,
          ),
        ),
      ),
    );
  }

  Widget _panelHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorPorTipo(String tipo) {
    final t = tipo.toLowerCase();
    if (t.contains('venta')) return AppColors.success;
    if (t.contains('extraccion') || t.contains('extracción')) {
      return AppColors.warning;
    }
    if (t.contains('recepcion') || t.contains('recepción')) {
      return AppColors.info;
    }
    if (t.contains('transferencia')) return AppColors.secondary;
    return AppColors.textSecondary;
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  Future<void> _mostrarHistorial(InventarioMovimiento m) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return _HistorialDialog(
          producto: m,
          idTienda: _selectedStore!.id,
        );
      },
    );
  }
}

class _LiveBadge extends StatefulWidget {
  final bool active;
  const _LiveBadge({required this.active});

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _ctrl,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'EN VIVO • cada 10s',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.error,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorialDialog extends StatefulWidget {
  final InventarioMovimiento producto;
  final int idTienda;
  const _HistorialDialog({required this.producto, required this.idTienda});

  @override
  State<_HistorialDialog> createState() => _HistorialDialogState();
}

class _HistorialDialogState extends State<_HistorialDialog> {
  late Future<List<HistorialProductoDia>> _future;

  @override
  void initState() {
    super.initState();
    _future = MovimientosService.getHistorialProductoDia(
      idTienda: widget.idTienda,
      idProducto: widget.producto.idProducto,
      idUbicacion: widget.producto.idUbicacion,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tf = DateFormat('HH:mm:ss');
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.producto.productoNombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'SKU: ${widget.producto.sku} • ${widget.producto.zonaNombre}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<HistorialProductoDia>>(
                future: _future,
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('Sin movimientos hoy'),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final h = list[i];
                      final isSubio = h.direccion == 'subio';
                      final isBajo = h.direccion == 'bajo';
                      final color = isSubio
                          ? AppColors.success
                          : isBajo
                              ? AppColors.error
                              : AppColors.textHint;
                      final icon = isSubio
                          ? Icons.arrow_upward
                          : isBajo
                              ? Icons.arrow_downward
                              : Icons.remove;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: color.withOpacity(0.15),
                          child: Icon(icon, size: 16, color: color),
                        ),
                        title: Text(
                          'Inicial: ${h.cantidadInicial}  →  Final: ${h.cantidadFinal}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${h.almacenNombre} • ${h.zonaNombre}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isSubio
                                  ? '+${h.variacion.abs()}'
                                  : isBajo
                                      ? '-${h.variacion.abs()}'
                                      : '0',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              tf.format(h.fecha.toLocal()),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
