import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../models/fondo_inversion.dart';
import '../services/fondo_inversion_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/fdi_inversores_section.dart';
import '../widgets/fdi_liquidacion_detalle_dialog.dart';

/// Vista principal del Fondo de Inversión (solo gerente).
/// Tabs: Saldos · Movimientos · Liquidaciones · Transferencias ·
/// Inversiones · Configuración.
class FondoInversionScreen extends StatefulWidget {
  const FondoInversionScreen({super.key});

  @override
  State<FondoInversionScreen> createState() => _FondoInversionScreenState();
}

class _FondoInversionScreenState extends State<FondoInversionScreen>
    with SingleTickerProviderStateMixin {
  final _service = FondoInversionService();
  final _fmt = NumberFormat('#,##0.00');
  late final TabController _tabs;

  int? _idTienda;
  bool _loading = true;
  String? _error;

  FdiSaldosResult _saldos = const FdiSaldosResult([], {});
  List<FdiMovimiento> _movimientos = [];
  List<FdiLiquidacion> _liquidaciones = [];
  List<FdiTransferencia> _transferencias = [];
  List<FdiInversion> _inversiones = [];
  List<FdiConcepto> _conceptos = [];
  List<FdiCuenta> _cuentas = [];
  List<Map<String, dynamic>> _medios = [];
  List<String> _monedas = [];
  int _diasAlerta = 15;
  bool _soloRevision = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      // Reconstruye el FAB al cambiar de tab (Transferir / Inversión).
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _idTienda ??= await UserPreferencesService().getIdTienda();
      final id = _idTienda;
      if (id == null) throw Exception('Sin tienda asignada');
      final r = await Future.wait([
        _service.saldos(id),
        _service.movimientos(id),
        _service.listLiquidaciones(id),
        _service.listTransferencias(id),
        _service.listInversiones(id, soloRevision: _soloRevision),
        _service.listConceptos(id),
        _service.listCuentas(id),
        _service.listMediosPago(),
        _service.listMonedas(),
        _service.getDiasAlertaRevision(id),
      ]);
      if (!mounted) return;
      setState(() {
        _saldos = r[0] as FdiSaldosResult;
        _movimientos = r[1] as List<FdiMovimiento>;
        _liquidaciones = r[2] as List<FdiLiquidacion>;
        _transferencias = r[3] as List<FdiTransferencia>;
        _inversiones = r[4] as List<FdiInversion>;
        _conceptos = r[5] as List<FdiConcepto>;
        _cuentas = r[6] as List<FdiCuenta>;
        _medios = r[7] as List<Map<String, dynamic>>;
        _monedas = r[8] as List<String>;
        _diasAlerta = r[9] as int;
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

  String _conceptoDe(int idCuenta) {
    final c = _cuentas.where((x) => x.id == idCuenta).firstOrNull;
    return _conceptos
            .where((x) => x.id == c?.idConcepto)
            .firstOrNull
            ?.denominacion ??
        '';
  }

  String _cuentaNombre(int id) =>
      _cuentas.where((x) => x.id == id).firstOrNull?.nombre ?? '#$id';

  String _medioNombre(int? id) =>
      _medios
          .where((m) => (m['id'] as num?)?.toInt() == id)
          .firstOrNull?['denominacion']
          ?.toString() ??
      (id?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Fondo de Inversión',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Saldos'),
            Tab(text: 'Movimientos'),
            Tab(text: 'Liquidaciones'),
            Tab(text: 'Transferencias'),
            Tab(text: 'Inversiones'),
            Tab(text: 'Config'),
          ],
        ),
      ),
      drawer: const AdminDrawer(),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? LayoutBuilder(
                      builder: (ctx, c) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight),
                          child: Center(child: Text('Error: $_error')),
                        ),
                      ),
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _tabSaldos(),
                        _tabMovimientos(),
                        _tabLiquidaciones(),
                        _tabTransferencias(),
                        _tabInversiones(),
                        _tabConfig(),
                      ],
                    ),
            ),
      floatingActionButton: _fab(),
    );
  }

  Widget? _fab() {
    final i = _tabs.index;
    if (i == 3) {
      return FloatingActionButton.extended(
        onPressed: _nuevaTransferencia,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Transferir'),
      );
    }
    if (i == 4) {
      return FloatingActionButton.extended(
        onPressed: _nuevaInversion,
        icon: const Icon(Icons.add),
        label: const Text('Inversión'),
      );
    }
    return null;
  }

  // ==========================================================================
  // SALDOS
  // ==========================================================================

  Widget _tabSaldos() {
    final totales = _saldos.totalesPorMoneda.entries.toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text(
                  'Totales: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...totales.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      '${_fmt.format(e.value)} ${e.key}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _dialogoMonto('ingreso_manual'),
                icon: const Icon(Icons.add),
                label: const Text('Ingreso manual'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _dialogoMonto('ajuste'),
                icon: const Icon(Icons.tune),
                label: const Text('Ajuste positivo'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final s in _saldos.saldos)
          ListTile(
            dense: true,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text('${s.concepto} · ${s.cuenta}'),
            subtitle: Text('${s.medioPago} · ${s.moneda}'),
            trailing: Text(
              _fmt.format(s.saldo),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        if (_saldos.saldos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Sin saldos todavía')),
          ),
      ],
    );
  }

  Future<void> _dialogoMonto(String tipo) async {
    FdiCuenta? cuenta;
    int? medio = _medios.isNotEmpty
        ? (_medios.first['id'] as num).toInt()
        : null;
    String moneda = _monedas.isNotEmpty ? _monedas.first : 'CUP';
    final montoCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    final idem = _service.newIdempotencyKey();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tipo == 'ajuste' ? 'Ajuste positivo' : 'Ingreso manual'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<FdiCuenta>(
                initialValue: cuenta,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cuenta'),
                items: [
                  for (final c in _cuentas.where((c) => c.activo))
                    DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${_conceptoDe(c.id)} · ${c.nombre}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setD(() => cuenta = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: medio,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Medio'),
                      items: [
                        for (final m in _medios)
                          DropdownMenuItem(
                            value: (m['id'] as num).toInt(),
                            child: Text(
                              m['denominacion']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setD(() => medio = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: moneda,
                      decoration: const InputDecoration(labelText: 'Moneda'),
                      items: [
                        for (final mo in _monedas)
                          DropdownMenuItem(value: mo, child: Text(mo)),
                      ],
                      onChanged: (v) => setD(() => moneda = v ?? moneda),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Monto'),
              ),
              TextField(
                controller: motivoCtrl,
                decoration: InputDecoration(
                  labelText: tipo == 'ajuste'
                      ? 'Motivo (obligatorio)'
                      : 'Motivo',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final monto = double.tryParse(
                  montoCtrl.text.replaceAll(',', '.'),
                );
                if (cuenta == null ||
                    medio == null ||
                    monto == null ||
                    monto <= 0) {
                  return;
                }
                try {
                  if (tipo == 'ajuste') {
                    await _service.ajuste(
                      idTienda: _idTienda!,
                      idCuenta: cuenta!.id,
                      idMedioPago: medio!,
                      moneda: moneda,
                      monto: monto,
                      motivo: motivoCtrl.text,
                      idempotencyKey: idem,
                    );
                  } else {
                    await _service.ingresoManual(
                      idTienda: _idTienda!,
                      idCuenta: cuenta!.id,
                      idMedioPago: medio!,
                      moneda: moneda,
                      monto: monto,
                      motivo: motivoCtrl.text,
                      idempotencyKey: idem,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  // ==========================================================================
  // MOVIMIENTOS
  // ==========================================================================

  Widget _tabMovimientos() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: _movimientos.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = _movimientos[i];
        final neg = m.monto < 0;
        return ListTile(
          dense: true,
          title: Text('${m.tipo} · ${m.concepto} · ${m.cuenta}'),
          subtitle: Text(
            '${m.medioPago} · ${m.moneda}'
            '${m.observacion != null ? ' · ${m.observacion}' : ''}\n'
            '${m.createdAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(m.createdAt!) : ''}',
          ),
          isThreeLine: true,
          trailing: Text(
            '${neg ? '' : '+'}${_fmt.format(m.monto)}',
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
  // LIQUIDACIONES
  // ==========================================================================

  /// Mini-estadística de una liquidación: etiqueta pequeña secundaria
  /// encima del monto, que es lo que realmente importa. Sin ellipsis:
  /// los montos pueden ser grandes y deben leerse completos.
  Widget _liqStat(String label, double valor, String moneda, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          '${_fmt.format(valor)} $moneda',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _tabLiquidaciones() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: _liquidaciones.length,
      itemBuilder: (_, i) {
        final l = _liquidaciones[i];
        // Agregados por moneda: vendido, para inversión y ganancia de socios.
        final porMoneda = <String, List<double>>{};
        for (final d in l.detalle) {
          final moneda = d['moneda']?.toString() ?? '';
          final v = porMoneda.putIfAbsent(moneda, () => [0, 0, 0]);
          v[0] += (d['monto_vendido'] as num?)?.toDouble() ?? 0;
          v[1] += (d['monto_inversion'] as num?)?.toDouble() ?? 0;
          v[2] += (d['monto_ganancia_retirada'] as num?)?.toDouble() ?? 0;
        }
        return Card(
          child: InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => FdiLiquidacionDetalleDialog(
                liquidacion: l,
                cargarRepartos: () async {
                  final rows = await _service.historialInversores(
                    _idTienda!,
                    desde: l.fechaDesde,
                    hasta: l.fechaHasta,
                  );
                  return rows
                      .where((r) => r['id_liquidacion'] == l.id)
                      .toList();
                },
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat('dd/MM/yy').format(l.fechaDesde)} – '
                    '${DateFormat('dd/MM/yy').format(l.fechaHasta)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final e in porMoneda.entries)
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        _liqStat(
                          'Vendido',
                          e.value[0],
                          e.key,
                          AppColors.textPrimary,
                        ),
                        _liqStat(
                          'Inversión',
                          e.value[1],
                          e.key,
                          AppColors.primary,
                        ),
                        _liqStat(
                          'Socios',
                          e.value[2],
                          e.key,
                          AppColors.success,
                        ),
                      ],
                    ),
                  if (porMoneda.isEmpty)
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        _liqStat(
                          'Vendido',
                          l.ventaTotal,
                          'CUP',
                          AppColors.textPrimary,
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '#${l.id} · ${l.conceptoDestino} · ${l.cuentaDestino} · '
                    '${l.cantidadOrdenes} órdenes',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (l.diferenciaGanancia != null && l.diferenciaGanancia != 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Diferencia de ganancia: '
                        '${_fmt.format(l.diferenciaGanancia!)} CUP'
                        '${l.confirmadaConDiferencia ? ' (confirmada)' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // TRANSFERENCIAS
  // ==========================================================================

  Widget _tabTransferencias() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      itemCount: _transferencias.length,
      itemBuilder: (_, i) {
        final t = _transferencias[i];
        return Card(
          child: ListTile(
            title: Text(
              '${_cuentaNombre(t.idCuentaOrigen)} → ${_cuentaNombre(t.idCuentaDestino)}',
            ),
            subtitle: Text(
              'Salieron ${_fmt.format(t.montoTotalOrigen)} ${t.monedaOrigen}'
              ' (base ${_fmt.format(t.montoBaseOrigen)} + comisión ${_fmt.format(t.montoComision)})'
              ' · Llegaron ${_fmt.format(t.montoDestino)} ${t.monedaDestino}'
              '${t.observacion != null ? '\n${t.observacion}' : ''}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Corregir (transferencia inversa al 0%)',
              onPressed: () => _nuevaTransferencia(corregir: t),
            ),
          ),
        );
      },
    );
  }

  Future<void> _nuevaTransferencia({FdiTransferencia? corregir}) async {
    FdiCuenta? cOri;
    FdiCuenta? cDes;
    int? mOri, mDes;
    String? moOri, moDes;
    final montoCtrl = TextEditingController();
    final tasaCtrl = TextEditingController(text: '1');
    final pctCtrl = TextEditingController(text: corregir != null ? '0' : '0');
    final obsCtrl = TextEditingController(
      text: corregir != null ? 'Corrección de #${corregir.id}' : '',
    );
    final idem = _service.newIdempotencyKey();

    if (corregir != null) {
      cOri = _cuentas
          .where((c) => c.id == corregir.idCuentaDestino)
          .firstOrNull;
      cDes = _cuentas.where((c) => c.id == corregir.idCuentaOrigen).firstOrNull;
      mDes = corregir.idMedioPagoOrigen;
      moDes = corregir.monedaOrigen;
      mOri = corregir.idMedioPagoDestino;
      moOri = corregir.monedaDestino;
      montoCtrl.text = corregir.montoBaseOrigen.toStringAsFixed(2);
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final montoD =
              double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
          final tasa = double.tryParse(tasaCtrl.text.replaceAll(',', '.')) ?? 1;
          final pct = double.tryParse(pctCtrl.text.replaceAll(',', '.')) ?? 0;
          final base = montoD * tasa;
          final comi = base * pct / 100;

          // Disponibilidad real del fondo (saldo por cuenta+medio+moneda).
          final saldos = _saldos.saldos;
          double? disp(int? idCta, int? medio, String? moneda) {
            if (idCta == null || medio == null || moneda == null) return null;
            return saldos
                .where(
                  (s) =>
                      s.idCuenta == idCta &&
                      s.idMedioPago == medio &&
                      s.moneda == moneda,
                )
                .firstOrNull
                ?.saldo;
          }

          // Origen en cascada: solo opciones con saldo > 0.
          final cuentasOrigen = [
            for (final c in _cuentas)
              if (saldos.any((s) => s.idCuenta == c.id && s.saldo > 0) ||
                  c.id == cOri?.id)
                c,
          ];
          final mediosOrigen = <int, Map<String, dynamic>>{
            for (final s in saldos)
              if (cOri != null &&
                  s.idCuenta == cOri!.id &&
                  s.idMedioPago != null &&
                  s.saldo > 0)
                s.idMedioPago!: {
                  'id': s.idMedioPago!,
                  'denominacion': s.medioPago,
                },
          }.values.toList();
          final monedasOrigen = <String>{
            for (final s in saldos)
              if (cOri != null &&
                  mOri != null &&
                  s.idCuenta == cOri!.id &&
                  s.idMedioPago == mOri &&
                  s.saldo > 0)
                s.moneda,
          }.toList();
          final dispOri = disp(cOri?.id, mOri, moOri);
          final dispDes = disp(cDes?.id, mDes, moDes);

          Widget disponibleText(String label, double? v, String? moneda) {
            if (v == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$label disponible: ${_fmt.format(v)} ${moneda ?? ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: v > 0 ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }

          Widget cuentaDrop(
            String label,
            FdiCuenta? v,
            List<FdiCuenta> opciones,
            ValueChanged<FdiCuenta?> onC,
          ) => DropdownButtonFormField<FdiCuenta>(
            initialValue: v,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              for (final c in opciones)
                DropdownMenuItem(
                  value: c,
                  child: Text(
                    '${_conceptoDe(c.id)} · ${c.nombre}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onC,
          );
          Widget medioDrop(
            String label,
            int? v,
            List<Map<String, dynamic>> opciones,
            ValueChanged<int?> onC,
          ) => DropdownButtonFormField<int>(
            initialValue: v,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              for (final m in opciones)
                DropdownMenuItem(
                  value: (m['id'] as num).toInt(),
                  child: Text(m['denominacion']?.toString() ?? ''),
                ),
            ],
            onChanged: onC,
          );
          Widget monedaDrop(
            String label,
            String? v,
            List<String> opciones,
            ValueChanged<String?> onC,
          ) => DropdownButtonFormField<String>(
            initialValue: v,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: [
              for (final mo in opciones)
                DropdownMenuItem(value: mo, child: Text(mo)),
            ],
            onChanged: onC,
          );
          return AlertDialog(
            title: Text(
              corregir != null
                  ? 'Corregir transferencia #${corregir.id}'
                  : 'Nueva transferencia',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  cuentaDrop(
                    'Cuenta origen',
                    cOri,
                    cuentasOrigen,
                    (v) => setD(() {
                      cOri = v;
                      mOri = null;
                      moOri = null;
                    }),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: medioDrop(
                          'Medio origen',
                          mOri,
                          mediosOrigen,
                          (v) => setD(() {
                            mOri = v;
                            moOri = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: monedaDrop(
                          'Moneda origen',
                          moOri,
                          monedasOrigen,
                          (v) => setD(() => moOri = v),
                        ),
                      ),
                    ],
                  ),
                  disponibleText('Origen', dispOri, moOri),
                  cuentaDrop(
                    'Cuenta destino',
                    cDes,
                    _cuentas,
                    (v) => setD(() => cDes = v),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: medioDrop(
                          'Medio destino',
                          mDes,
                          _medios,
                          (v) => setD(() => mDes = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: monedaDrop(
                          'Moneda destino',
                          moDes,
                          _monedas,
                          (v) => setD(() => moDes = v),
                        ),
                      ),
                    ],
                  ),
                  disponibleText('Destino', dispDes, moDes),
                  TextField(
                    controller: montoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Monto que llega (moneda destino)',
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tasaCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Tasa (destino→origen)',
                          ),
                          onChanged: (_) => setD(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: pctCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: '% costo',
                          ),
                          onChanged: (_) => setD(() {}),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: obsCtrl,
                    decoration: const InputDecoration(labelText: 'Observación'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sale: ${_fmt.format(base + comi)} ${moOri ?? ''} '
                    '(base ${_fmt.format(base)} + com. ${_fmt.format(comi)})\n'
                    'Llega: ${_fmt.format(montoD)} ${moDes ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  if (cOri == null ||
                      cDes == null ||
                      mOri == null ||
                      mDes == null ||
                      moOri == null ||
                      moDes == null ||
                      montoD <= 0) {
                    return;
                  }
                  try {
                    await _service.transferir(
                      idTienda: _idTienda!,
                      idCuentaOrigen: cOri!.id,
                      idMedioPagoOrigen: mOri!,
                      monedaOrigen: moOri!,
                      idCuentaDestino: cDes!.id,
                      idMedioPagoDestino: mDes!,
                      monedaDestino: moDes!,
                      montoDestino: montoD,
                      tasa: tasa,
                      porcentajeCosto: pct,
                      idTransferenciaCorregida: corregir?.id,
                      observacion: obsCtrl.text,
                      idempotencyKey: idem,
                    );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text('Transferir'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) _load();
  }

  // ==========================================================================
  // INVERSIONES
  // ==========================================================================

  Widget _tabInversiones() {
    return Column(
      children: [
        SwitchListTile(
          dense: true,
          title: const Text('Solo en revisión'),
          value: _soloRevision,
          onChanged: (v) async {
            setState(() => _soloRevision = v);
            _load();
          },
        ),
        Expanded(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
            itemCount: _inversiones.length,
            itemBuilder: (_, i) {
              final inv = _inversiones[i];
              final avance = inv.montoTotalRef > 0
                  ? inv.montoRecibidoRef / inv.montoTotalRef
                  : 0.0;
              return Card(
                child: ListTile(
                  leading: Icon(
                    inv.enRevision
                        ? Icons.warning_amber
                        : Icons.savings_outlined,
                    color: inv.enRevision ? AppColors.warning : null,
                  ),
                  title: Text(inv.identificador),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${inv.estado}${inv.estadoManual ? ' (manual)' : ''}'
                        ' · ${_fmt.format(inv.montoRecibidoRef)} / ${_fmt.format(inv.montoTotalRef)} ${inv.monedaReferencia}',
                      ),
                      LinearProgressIndicator(value: avance.clamp(0.0, 1.0)),
                      if (inv.enRevision)
                        Text(
                          'En revisión (${inv.motivoRevision ?? ''})'
                          '${inv.montoFaltanteRef != null ? ' · faltante ${_fmt.format(inv.montoFaltanteRef!)}' : ''}',
                          style: const TextStyle(color: AppColors.error),
                        ),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () => _detalleInversion(inv),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _detalleInversion(FdiInversion inv) async {
    Map<String, dynamic>? det;
    try {
      det = await _service.detalleInversion(inv.id);
    } catch (_) {}
    if (!mounted) return;
    final fuentes = (det?['fuentes'] as List?) ?? [];
    final recepciones = (det?['recepciones'] as List?) ?? [];
    final historial = (det?['historial'] as List?) ?? [];
    final notaCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Inversión ${inv.identificador}'),
          content: SizedBox(
            width: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Estado: ${inv.estado} · Total ${_fmt.format(inv.montoTotalRef)} '
                  '· Recibido ${_fmt.format(inv.montoRecibidoRef)} ${inv.monedaReferencia}',
                ),
                const Divider(),
                const Text(
                  'Fuentes',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final f in fuentes)
                  Text(
                    '- ${f['concepto']} · ${f['cuenta']} · ${f['medio_pago']} · '
                    '${_fmt.format((f['monto'] as num?)?.toDouble() ?? 0)} ${f['moneda']}'
                    ' (ref ${_fmt.format((f['monto_ref'] as num?)?.toDouble() ?? 0)})',
                  ),
                const Divider(),
                const Text(
                  'Recepciones',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final r in recepciones)
                  Text(
                    '- Op #${r['id_operacion']} · '
                    '${_fmt.format((r['monto_recepcion'] as num?)?.toDouble() ?? 0)} ${r['moneda_recepcion']}'
                    ' (ref ${_fmt.format((r['monto_ref'] as num?)?.toDouble() ?? 0)})',
                  ),
                const Divider(),
                const Text(
                  'Historial',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final h in historial)
                  Text(
                    '- ${h['estado_anterior'] ?? '—'} → ${h['estado_nuevo']} '
                    '(${h['origen']}) ${h['motivo'] ?? ''}',
                  ),
                if (inv.enRevision) ...[
                  const Divider(),
                  TextField(
                    controller: notaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nota de resolución de revisión',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (inv.enRevision)
              TextButton(
                onPressed: () async {
                  try {
                    await _service.resolverRevision(
                      idInversion: inv.id,
                      nota: notaCtrl.text,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text('Resolver revisión'),
              ),
            TextButton(
              onPressed: () => _cambiarEstado(inv, ctx),
              child: const Text('Cambiar estado'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cambiarEstado(FdiInversion inv, BuildContext parentCtx) async {
    String estado = inv.estado;
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Cambiar estado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: estado,
                items: const [
                  DropdownMenuItem(
                    value: 'pendiente',
                    child: Text('Pendiente'),
                  ),
                  DropdownMenuItem(value: 'parcial', child: Text('Parcial')),
                  DropdownMenuItem(
                    value: 'completado',
                    child: Text('Completado'),
                  ),
                ],
                onChanged: (v) => setD(() => estado = v ?? estado),
              ),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(labelText: 'Motivo'),
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
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await _service.cambiarEstadoInversion(
          idInversion: inv.id,
          estado: estado,
          motivo: motivoCtrl.text,
        );
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _nuevaInversion() async {
    final idCtrl = TextEditingController();
    final detCtrl = TextEditingController();
    String monedaRef = _monedas.isNotEmpty ? _monedas.first : 'CUP';
    final fuentes = <Map<String, dynamic>>[];
    final idem = _service.newIdempotencyKey();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final totalRef = fuentes.fold<double>(
            0,
            (s, f) => s + (f['monto'] * f['tasa_a_ref']),
          );
          return AlertDialog(
            title: const Text('Nueva inversión'),
            content: SizedBox(
              width: 560,
              child: ListView(
                shrinkWrap: true,
                children: [
                  TextField(
                    controller: idCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Identificador *',
                    ),
                  ),
                  TextField(
                    controller: detCtrl,
                    decoration: const InputDecoration(labelText: 'Detalles'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: monedaRef,
                    decoration: const InputDecoration(
                      labelText: 'Moneda de referencia',
                    ),
                    items: [
                      for (final m in _monedas)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setD(() => monedaRef = v ?? monedaRef),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Fuentes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final f = await _dialogoFuente(monedaRef);
                          if (f != null) setD(() => fuentes.add(f));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar'),
                      ),
                    ],
                  ),
                  for (var i = 0; i < fuentes.length; i++)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${_cuentaNombre(fuentes[i]['id_cuenta'])} · '
                        '${_medioNombre(fuentes[i]['id_medio_pago'])}',
                      ),
                      subtitle: Text(
                        '${_fmt.format(fuentes[i]['monto'])} ${fuentes[i]['moneda']} → ref '
                        '${_fmt.format(fuentes[i]['monto'] * fuentes[i]['tasa_a_ref'])}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setD(() => fuentes.removeAt(i)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Total ref: ${_fmt.format(totalRef)} $monedaRef',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  if (idCtrl.text.trim().isEmpty || fuentes.isEmpty) return;
                  try {
                    await _service.crearInversion(
                      idTienda: _idTienda!,
                      identificador: idCtrl.text.trim(),
                      detalles: detCtrl.text,
                      monedaReferencia: monedaRef,
                      fuentes: fuentes,
                      idempotencyKey: idem,
                    );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text('Crear'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) _load();
  }

  Future<Map<String, dynamic>?> _dialogoFuente(String monedaRef) async {
    FdiCuenta? cuenta;
    int? medio;
    String moneda = monedaRef;
    final montoCtrl = TextEditingController();
    final tasaCtrl = TextEditingController(text: '1');
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Fuente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<FdiCuenta>(
                initialValue: cuenta,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cuenta'),
                items: [
                  for (final c in _cuentas.where((c) => c.activo))
                    DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${_conceptoDe(c.id)} · ${c.nombre}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setD(() => cuenta = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: medio,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Medio'),
                      items: [
                        for (final m in _medios)
                          DropdownMenuItem(
                            value: (m['id'] as num).toInt(),
                            child: Text(m['denominacion']?.toString() ?? ''),
                          ),
                      ],
                      onChanged: (v) => setD(() => medio = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: moneda,
                      decoration: const InputDecoration(labelText: 'Moneda'),
                      items: [
                        for (final mo in _monedas)
                          DropdownMenuItem(value: mo, child: Text(mo)),
                      ],
                      onChanged: (v) => setD(() => moneda = v ?? moneda),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Monto'),
              ),
              if (moneda != monedaRef)
                TextField(
                  controller: tasaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tasa a moneda ref',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final monto = double.tryParse(
                  montoCtrl.text.replaceAll(',', '.'),
                );
                final tasa =
                    double.tryParse(tasaCtrl.text.replaceAll(',', '.')) ?? 1;
                if (cuenta == null ||
                    medio == null ||
                    monto == null ||
                    monto <= 0) {
                  return;
                }
                Navigator.pop(ctx, {
                  'id_cuenta': cuenta!.id,
                  'id_medio_pago': medio!,
                  'moneda': moneda,
                  'monto': monto,
                  'tasa_a_ref': moneda == monedaRef ? 1.0 : tasa,
                });
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // CONFIG
  // ==========================================================================

  Widget _tabConfig() {
    final ctrl = TextEditingController(text: '$_diasAlerta');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Días sin completarse para marcar una inversión como vencida '
          '(revisión automática al consultar)',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Días',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () async {
                final d = int.tryParse(ctrl.text);
                if (d == null || d <= 0) return;
                await _service.setDiasAlertaRevision(_idTienda!, d);
                _load();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
        const Divider(height: 32),
        _estructuraSection(),
        const Divider(height: 32),
        if (_idTienda != null) FdiInversoresSection(idTienda: _idTienda!),
      ],
    );
  }

  // ==========================================================================
  // Estructura: conceptos y cuentas (gestionadas por el gerente)
  // ==========================================================================

  Widget _estructuraSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Conceptos y cuentas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _dialogoConcepto,
              icon: const Icon(Icons.add),
              label: const Text('Concepto'),
            ),
          ],
        ),
        const Text(
          'La estructura la gestiona el dueño aquí. No se puede eliminar '
          'nada que ya tenga saldos o movimientos.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        for (final concepto in _conceptos) ...[
          Card(
            child: ExpansionTile(
              initiallyExpanded: false,
              title: Text(
                concepto.denominacion + (concepto.activo ? '' : ' (inactivo)'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: concepto.descripcion != null
                  ? Text(concepto.descripcion!)
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _dialogoConcepto(concepto: concepto),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _confirmarEliminarConcepto(concepto),
                  ),
                ],
              ),
              children: [
                for (final c in _cuentas.where(
                  (x) => x.idConcepto == concepto.id,
                ))
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 20,
                    ),
                    title: Text(c.nombre + (c.activo ? '' : ' (inactiva)')),
                    subtitle: c.descripcion != null
                        ? Text(c.descripcion!)
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _dialogoCuenta(
                            cuenta: c,
                            idConcepto: concepto.id,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _confirmarEliminarCuenta(c),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _dialogoCuenta(idConcepto: concepto.id),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar cuenta'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _dialogoConcepto({FdiConcepto? concepto}) async {
    final denomCtrl = TextEditingController(text: concepto?.denominacion ?? '');
    final descCtrl = TextEditingController(text: concepto?.descripcion ?? '');
    var activo = concepto?.activo ?? true;
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
        await _service.crearConcepto(
          _idTienda!,
          denominacion: denomCtrl.text.trim(),
          descripcion: descCtrl.text.trim().isEmpty
              ? null
              : descCtrl.text.trim(),
        );
      } else {
        await _service.actualizarConcepto(
          concepto.id,
          denominacion: denomCtrl.text.trim(),
          descripcion: descCtrl.text.trim(),
          activo: activo,
        );
      }
      _load();
    } catch (e) {
      _snackError(e);
    }
  }

  Future<void> _dialogoCuenta({FdiCuenta? cuenta, int? idConcepto}) async {
    final nombreCtrl = TextEditingController(text: cuenta?.nombre ?? '');
    final descCtrl = TextEditingController(text: cuenta?.descripcion ?? '');
    int? conceptoSel =
        idConcepto ??
        cuenta?.idConcepto ??
        (_conceptos.isNotEmpty ? _conceptos.first.id : null);
    var activo = cuenta?.activo ?? true;
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
                initialValue:
                    _conceptos
                        .where((c) => c.activo)
                        .any((c) => c.id == conceptoSel)
                    ? conceptoSel
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Concepto *'),
                items: [
                  for (final co in _conceptos.where((c) => c.activo))
                    DropdownMenuItem(
                      value: co.id,
                      child: Text(co.denominacion),
                    ),
                ],
                onChanged: (v) => setD(() => conceptoSel = v),
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
    if (conceptoSel == null || nombreCtrl.text.trim().isEmpty) return;
    try {
      if (cuenta == null) {
        await _service.crearCuenta(
          _idTienda!,
          idConcepto: conceptoSel!,
          nombre: nombreCtrl.text.trim(),
          descripcion: descCtrl.text.trim().isEmpty
              ? null
              : descCtrl.text.trim(),
        );
      } else {
        await _service.actualizarCuenta(
          cuenta.id,
          nombre: nombreCtrl.text.trim(),
          descripcion: descCtrl.text.trim(),
          activo: activo,
        );
      }
      _load();
    } catch (e) {
      _snackError(e);
    }
  }

  Future<void> _confirmarEliminarConcepto(FdiConcepto concepto) async {
    final tieneCuentas = _cuentas.any((c) => c.idConcepto == concepto.id);
    if (tieneCuentas) {
      _snackError(
        'No se puede eliminar: el concepto tiene cuentas. '
        'Elimínalas o desactívalo.',
      );
      return;
    }
    final ok = await _confirmDialog(
      'Eliminar concepto "${concepto.denominacion}"?',
    );
    if (ok != true) return;
    try {
      await _service.eliminarConcepto(concepto.id);
      _load();
    } catch (e) {
      _snackError(e);
    }
  }

  Future<void> _confirmarEliminarCuenta(FdiCuenta cuenta) async {
    if (await _service.cuentaTieneMovimientos(cuenta.id)) {
      _snackError(
        'No se puede eliminar: la cuenta tiene movimientos. '
        'Desactívala en su lugar.',
      );
      return;
    }
    final ok = await _confirmDialog('Eliminar cuenta "${cuenta.nombre}"?');
    if (ok != true) return;
    try {
      await _service.eliminarCuenta(cuenta.id);
      _load();
    } catch (e) {
      _snackError(e);
    }
  }

  Future<bool?> _confirmDialog(String texto) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirmar'),
      content: Text(texto),
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

  void _snackError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
    );
  }
}
