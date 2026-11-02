import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../models/store.dart';
import '../services/fondo_inversion_service.dart';
import '../services/store_service.dart';
import '../widgets/app_drawer.dart';

/// Gestión del Fondo de Inversión por tienda.
///
/// El superadmin administra la estructura (conceptos y cuentas) y consulta
/// paneles de solo lectura: saldos actuales, movimientos e inversiones en
/// revisión. Los movimientos de dinero los hace el gerente desde admin_app.
class FondoInversionScreen extends StatefulWidget {
  const FondoInversionScreen({super.key});

  @override
  State<FondoInversionScreen> createState() => _FondoInversionScreenState();
}

class _FondoInversionScreenState extends State<FondoInversionScreen>
    with SingleTickerProviderStateMixin {
  final _fmt = NumberFormat('#,##0.00');
  late final TabController _tabs;

  List<Store> _tiendas = [];
  Store? _tienda;
  bool _loading = false;
  bool _loadingTiendas = true;
  String? _error;

  List<Map<String, dynamic>> _conceptos = [];
  List<Map<String, dynamic>> _cuentas = [];
  Map<String, dynamic> _saldos = {};
  List<Map<String, dynamic>> _movimientos = [];
  List<Map<String, dynamic>> _inversiones = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _loadTiendas();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadTiendas() async {
    try {
      final tiendas = await StoreService.getAllStores();
      if (!mounted) return;
      setState(() {
        _tiendas = tiendas;
        _loadingTiendas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingTiendas = false;
      });
    }
  }

  Future<void> _load() async {
    final tienda = _tienda;
    if (tienda == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        FondoInversionService.listConceptos(tienda.id),
        FondoInversionService.listCuentas(tienda.id),
        FondoInversionService.saldos(tienda.id),
        FondoInversionService.movimientos(tienda.id),
        FondoInversionService.inversiones(tienda.id, soloRevision: true),
      ]);
      if (!mounted) return;
      setState(() {
        _conceptos = r[0] as List<Map<String, dynamic>>;
        _cuentas = r[1] as List<Map<String, dynamic>>;
        _saldos = r[2] as Map<String, dynamic>;
        _movimientos = r[3] as List<Map<String, dynamic>>;
        _inversiones = r[4] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _conceptoNombre(int id) => _conceptos
          .where((c) => (c['id'] as num).toInt() == id)
          .firstOrNull?['denominacion']
          ?.toString() ??
      '#$id';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Fondo de Inversión'),
        backgroundColor: AppColors.primary,
        bottom: _tienda == null
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(text: 'Conceptos'),
                  Tab(text: 'Cuentas'),
                  Tab(text: 'Saldos'),
                  Tab(text: 'Movimientos'),
                  Tab(text: 'En revisión'),
                ],
              ),
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          _selectorTienda(),
          Expanded(
            child: _tienda == null
                ? const Center(
                    child: Text('Selecciona una tienda para continuar'),
                  )
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text('Error: $_error'))
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              _tabConceptos(),
                              _tabCuentas(),
                              _tabSaldos(),
                              _tabMovimientos(),
                              _tabRevision(),
                            ],
                          ),
          ),
        ],
      ),
      floatingActionButton: _tienda == null
          ? null
          : _tabs.index == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _dialogoConcepto(),
                  icon: const Icon(Icons.add),
                  label: const Text('Concepto'),
                )
              : _tabs.index == 1
                  ? FloatingActionButton.extended(
                      onPressed: () => _dialogoCuenta(),
                      icon: const Icon(Icons.add),
                      label: const Text('Cuenta'),
                    )
                  : null,
    );
  }

  Widget _selectorTienda() {
    if (_loadingTiendas) {
      return const LinearProgressIndicator();
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: DropdownButtonFormField<Store>(
        initialValue: _tienda,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Tienda',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final t in _tiendas)
            DropdownMenuItem(
              value: t,
              child: Text(t.denominacion, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (t) {
          setState(() => _tienda = t);
          _load();
        },
      ),
    );
  }

  // ==========================================================================
  // CONCEPTOS
  // ==========================================================================

  Widget _tabConceptos() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _conceptos.length,
      itemBuilder: (_, i) {
        final c = _conceptos[i];
        final activo = c['activo'] == true;
        return Card(
          child: ListTile(
            leading: Icon(
              Icons.category_outlined,
              color: activo ? null : AppColors.textSecondary,
            ),
            title: Text('${c['denominacion']}'),
            subtitle: c['descripcion'] != null
                ? Text('${c['descripcion']}')
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!activo)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text('inactivo',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _dialogoConcepto(concepto: c),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _eliminar(
                    'concepto "${c['denominacion']}"',
                    () => FondoInversionService.eliminarConcepto(
                        (c['id'] as num).toInt()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _dialogoConcepto({Map<String, dynamic>? concepto}) async {
    final denomCtrl =
        TextEditingController(text: concepto?['denominacion']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: concepto?['descripcion']?.toString() ?? '');
    var activo = concepto?['activo'] != false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(concepto == null ? 'Nuevo concepto' : 'Editar concepto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: denomCtrl,
                decoration: const InputDecoration(labelText: 'Denominación *'),
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              if (concepto != null)
                SwitchListTile(
                  dense: true,
                  title: const Text('Activo'),
                  value: activo,
                  onChanged: (v) => setD(() => activo = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      if (concepto == null) {
        await FondoInversionService.crearConcepto(
          idTienda: _tienda!.id,
          denominacion: denomCtrl.text.trim(),
          descripcion: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        );
      } else {
        await FondoInversionService.actualizarConcepto(
          (concepto['id'] as num).toInt(),
          denominacion: denomCtrl.text.trim(),
          descripcion: descCtrl.text.trim(),
          activo: activo,
        );
      }
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  // ==========================================================================
  // CUENTAS
  // ==========================================================================

  Widget _tabCuentas() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _cuentas.length,
      itemBuilder: (_, i) {
        final c = _cuentas[i];
        final activo = c['activo'] == true;
        return Card(
          child: ListTile(
            leading: Icon(
              Icons.account_balance_wallet_outlined,
              color: activo ? null : AppColors.textSecondary,
            ),
            title: Text('${c['nombre']}'),
            subtitle: Text(
              _conceptoNombre((c['id_concepto'] as num).toInt()) +
                  (c['descripcion'] != null ? ' · ${c['descripcion']}' : '') +
                  (activo ? '' : ' · inactiva'),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _dialogoCuenta(cuenta: c),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _eliminar(
                    'cuenta "${c['nombre']}" (solo si no tiene saldos/movimientos)',
                    () => FondoInversionService.eliminarCuenta(
                        (c['id'] as num).toInt()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _dialogoCuenta({Map<String, dynamic>? cuenta}) async {
    final nombreCtrl =
        TextEditingController(text: cuenta?['nombre']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: cuenta?['descripcion']?.toString() ?? '');
    int? idConcepto = (cuenta?['id_concepto'] as num?)?.toInt() ??
        (_conceptos.isNotEmpty ? (_conceptos.first['id'] as num).toInt() : null);
    var activo = cuenta?['activo'] != false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(cuenta == null ? 'Nueva cuenta' : 'Editar cuenta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: idConcepto,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Concepto *'),
                items: [
                  for (final c in _conceptos.where((c) => c['activo'] == true))
                    DropdownMenuItem(
                      value: (c['id'] as num).toInt(),
                      child: Text('${c['denominacion']}'),
                    ),
                ],
                onChanged: (v) => setD(() => idConcepto = v),
              ),
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              if (cuenta != null)
                SwitchListTile(
                  dense: true,
                  title: const Text('Activo'),
                  value: activo,
                  onChanged: (v) => setD(() => activo = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      if (idConcepto == null || nombreCtrl.text.trim().isEmpty) return;
      if (cuenta == null) {
        await FondoInversionService.crearCuenta(
          idTienda: _tienda!.id,
          idConcepto: idConcepto!,
          nombre: nombreCtrl.text.trim(),
          descripcion:
              descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        );
      } else {
        await FondoInversionService.actualizarCuenta(
          (cuenta['id'] as num).toInt(),
          nombre: nombreCtrl.text.trim(),
          descripcion: descCtrl.text.trim(),
          activo: activo,
          idConcepto: idConcepto,
        );
      }
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  // ==========================================================================
  // SALDOS (solo lectura)
  // ==========================================================================

  Widget _tabSaldos() {
    final saldos = (_saldos['saldos'] as List?) ?? [];
    final totales = (_saldos['totales_por_moneda'] as Map?) ?? {};
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 16,
              children: [
                const Text('Totales:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                for (final e in totales.entries)
                  Text('${_fmt.format((e.value as num).toDouble())} ${e.key}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        for (final s in saldos)
          ListTile(
            dense: true,
            title: Text('${s['concepto']} · ${s['cuenta']}'),
            subtitle: Text('${s['medio_pago']} · ${s['moneda']}'),
            trailing: Text(
              _fmt.format((s['saldo'] as num?)?.toDouble() ?? 0),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        if (saldos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Sin saldos')),
          ),
      ],
    );
  }

  // ==========================================================================
  // MOVIMIENTOS (solo lectura)
  // ==========================================================================

  Widget _tabMovimientos() {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _movimientos.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = _movimientos[i];
        final monto = (m['monto'] as num?)?.toDouble() ?? 0;
        final neg = monto < 0;
        final fecha = m['created_at'] != null
            ? DateFormat('dd/MM/yy HH:mm')
                .format(DateTime.tryParse(m['created_at'].toString()) ?? DateTime.now())
            : '';
        return ListTile(
          dense: true,
          title: Text('${m['tipo']} · ${m['concepto']} · ${m['cuenta']}'),
          subtitle: Text(
              '${m['medio_pago']} · ${m['moneda']}'
              '${m['observacion'] != null ? ' · ${m['observacion']}' : ''}\n$fecha'),
          isThreeLine: true,
          trailing: Text(
            '${neg ? '' : '+'}${_fmt.format(monto)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: neg ? AppColors.error : AppColors.success,
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // INVERSIONES EN REVISIÓN (solo lectura)
  // ==========================================================================

  Widget _tabRevision() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _inversiones.length,
      itemBuilder: (_, i) {
        final inv = _inversiones[i];
        final total = (inv['monto_total_ref'] as num?)?.toDouble() ?? 0;
        final recibido = (inv['monto_recibido_ref'] as num?)?.toDouble() ?? 0;
        final vencimiento = inv['vencimiento']?.toString();
        return Card(
          child: ListTile(
            leading: const Icon(Icons.warning_amber, color: AppColors.warning),
            title: Text('${inv['identificador']}'),
            subtitle: Text(
              '${inv['estado']} · recibido ${_fmt.format(recibido)} / '
              '${_fmt.format(total)} ${inv['moneda_referencia']}\n'
              '${vencimiento != null ? 'Vencimiento: $vencimiento · ' : ''}'
              '${inv['motivo_revision_efectivo'] ?? inv['motivo_revision'] ?? ''}'
              '${inv['monto_faltante_ref'] != null ? ' · faltante ${_fmt.format((inv['monto_faltante_ref'] as num).toDouble())}' : ''}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  Future<void> _eliminar(String que, Future<void> Function() fn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar'),
        content: Text('¿Eliminar $que?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await fn();
      _load();
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
    );
  }
}
