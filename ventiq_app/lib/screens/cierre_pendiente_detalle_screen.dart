import 'package:flutter/material.dart';

import '../services/offline_database_service.dart';
import '../services/user_preferences_service.dart';

/// Detalle de un cierre de turno guardado localmente (pendiente de sync).
///
/// Muestra todo lo persistido en almacenamiento: apertura, cuadre, observaciones,
/// inventario contado, ventas y egresos de ese turno.
class CierrePendienteDetalleScreen extends StatefulWidget {
  final String? localTurnoId;

  const CierrePendienteDetalleScreen({super.key, this.localTurnoId});

  @override
  State<CierrePendienteDetalleScreen> createState() =>
      _CierrePendienteDetalleScreenState();
}

class _CierrePendienteDetalleScreenState
    extends State<CierrePendienteDetalleScreen> {
  static const _blue = Color(0xFF4A90E2);
  static const _ink = Color(0xFF1F2937);

  final _prefs = UserPreferencesService();
  final _offlineDb = OfflineDatabaseService();

  bool _loading = true;
  String? _error;
  String? _selectedId;
  List<Map<String, dynamic>> _closedTurnos = [];
  Map<String, dynamic>? _turno;
  Map<String, dynamic> _cuadre = {};
  List<Map<String, dynamic>> _ventas = [];
  List<Map<String, dynamic>> _egresos = [];
  Map<int, String> _nombresProducto = {};

  @override
  void initState() {
    super.initState();
    _selectedId = widget.localTurnoId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final closed = await _prefs.getClosedPendingOfflineTurnos();
      closed.sort((a, b) {
        final fa = a['fecha_cierre']?.toString() ?? '';
        final fb = b['fecha_cierre']?.toString() ?? '';
        return fa.compareTo(fb);
      });

      Map<String, dynamic>? turno;
      final requested = _selectedId ?? widget.localTurnoId;
      if (requested != null && requested.isNotEmpty) {
        turno = await _prefs.getOfflineTurnoByLocalId(requested);
      }
      turno ??= closed.isNotEmpty ? closed.last : null;

      if (turno == null) {
        if (!mounted) return;
        setState(() {
          _closedTurnos = closed;
          _turno = null;
          _loading = false;
        });
        return;
      }

      final localId = turno['local_id']?.toString();
      final cuadre = await _prefs.getOfflineTurnoCuadre(turno);
      final orders = await _prefs.getPendingOrders();
      final ventas =
          orders.where((o) {
            if (localId == null || localId.isEmpty) return false;
            return o['local_turno_id']?.toString() == localId;
          }).toList()
            ..sort((a, b) {
              final fa =
                  a['fecha_creacion']?.toString() ??
                  a['created_offline_at']?.toString() ??
                  '';
              final fb =
                  b['fecha_creacion']?.toString() ??
                  b['created_offline_at']?.toString() ??
                  '';
              return fb.compareTo(fa);
            });

      final egresosAll = await _prefs.getEgresosOffline();
      final egresos =
          egresosAll.where((e) {
            if (localId == null || localId.isEmpty) return false;
            return e['local_turno_id']?.toString() == localId;
          }).toList();

      final ids = <int>{};
      final cierre = turno['cierre'] is Map
          ? Map<String, dynamic>.from(turno['cierre'] as Map)
          : <String, dynamic>{};
      final apertura = turno['apertura'] is Map
          ? Map<String, dynamic>.from(turno['apertura'] as Map)
          : <String, dynamic>{};
      for (final raw in [
        ..._asMapList(cierre['productos']),
        ..._asMapList(apertura['productos']),
      ]) {
        final id = _asInt(raw['id_producto'] ?? raw['id']);
        if (id != null) ids.add(id);
      }

      final nombres = <int, String>{};
      for (final id in ids) {
        try {
          final p = await _offlineDb.getProductById(id);
          final name = p?['denominacion']?.toString() ??
              p?['nombre']?.toString();
          if (name != null && name.isNotEmpty) nombres[id] = name;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _closedTurnos = closed;
        _turno = turno;
        _cuadre = cuadre;
        _ventas = ventas;
        _egresos = egresos;
        _nombresProducto = nombres;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  String _money(dynamic value) {
    final n = (value is num) ? value.toDouble() : double.tryParse('$value') ?? 0;
    return '\$${n.toStringAsFixed(2)}';
  }

  String _qty(dynamic value) {
    final n = (value is num) ? value.toDouble() : double.tryParse('$value');
    if (n == null) return '—';
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  String _fecha(dynamic raw) {
    if (raw == null || '$raw'.isEmpty) return '—';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _productoNombre(Map<String, dynamic> row) {
    final named = row['denominacion']?.toString() ??
        row['nombre']?.toString() ??
        row['nombre_producto']?.toString();
    if (named != null && named.isNotEmpty) return named;
    final id = _asInt(row['id_producto'] ?? row['id']);
    if (id != null && _nombresProducto.containsKey(id)) {
      return _nombresProducto[id]!;
    }
    return id == null ? 'Producto' : 'Producto #$id';
  }

  Future<void> _openTurno(String localId) async {
    _selectedId = localId;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Cierre guardado'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _centeredMessage('No se pudo cargar el cierre.\n$_error')
              : _turno == null
                  ? _centeredMessage(
                      'No hay un cierre de turno guardado pendiente de sincronizar.',
                    )
                  : _buildBody(),
    );
  }

  Widget _centeredMessage(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700], fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final turno = _turno!;
    final apertura = turno['apertura'] is Map
        ? Map<String, dynamic>.from(turno['apertura'] as Map)
        : <String, dynamic>{};
    final cierre = turno['cierre'] is Map
        ? Map<String, dynamic>.from(turno['cierre'] as Map)
        : <String, dynamic>{};
    final productosCierre = _asMapList(cierre['productos']);
    final productosApertura = _asMapList(apertura['productos']);
    final observaciones = (cierre['observaciones'] ??
            _cuadre['observaciones'] ??
            apertura['observaciones'])
        ?.toString();
    final diff = (_cuadre['diferencia'] as num?)?.toDouble() ?? 0;
    final otherClosed = _closedTurnos
        .where(
          (t) => t['local_id']?.toString() != turno['local_id']?.toString(),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _bannerPendiente(),
        if (otherClosed.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Otros cierres pendientes',
                  style: TextStyle(fontWeight: FontWeight.w600, color: _ink),
                ),
                const SizedBox(height: 8),
                for (final t in otherClosed.reversed)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('TPV ${t['id_tpv'] ?? '—'}'),
                    subtitle: Text(_fecha(t['fecha_cierre'])),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final id = t['local_id']?.toString();
                      if (id != null) _openTurno(id);
                    },
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(Icons.lock_clock, 'Turno'),
              const SizedBox(height: 12),
              _kv('TPV', '${turno['id_tpv'] ?? apertura['id_tpv'] ?? '—'}'),
              _kv('Apertura', _fecha(turno['fecha_apertura'] ?? apertura['fecha_apertura'])),
              _kv('Cierre', _fecha(turno['fecha_cierre'] ?? cierre['fecha_cierre'])),
              _kv(
                'Efectivo inicial',
                _money(
                  _cuadre['efectivo_inicial'] ?? apertura['efectivo_inicial'],
                ),
              ),
              _kv('Inventario', (cierre['maneja_inventario'] ?? apertura['maneja_inventario']) == true ? 'Sí' : 'No'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(Icons.account_balance_wallet_outlined, 'Cuadre de caja'),
              const SizedBox(height: 12),
              _kv('Ventas totales', _money(_cuadre['ventas_totales'])),
              _kv('Efectivo en ventas', _money(_cuadre['total_efectivo'])),
              _kv('Transferencias', _money(_cuadre['total_transferencias'])),
              _kv('Egresos efectivo', _money(_cuadre['egresos_efectivo'])),
              _kv('Egresos digitales', _money(_cuadre['egresos_digitales'])),
              _kv('Egresos totales', _money(_cuadre['egresos_totales'])),
              const Divider(height: 20),
              _kv('Efectivo esperado', _money(_cuadre['efectivo_esperado'])),
              _kv('Efectivo final', _money(_cuadre['efectivo_final'] ?? cierre['efectivo_final'])),
              _kv(
                'Diferencia',
                _money(diff),
                valueColor: diff.abs() < 0.01
                    ? Colors.green[700]
                    : (diff < 0 ? Colors.red[700] : Colors.orange[800]),
                emphasize: true,
              ),
              const Divider(height: 20),
              _kv('Operaciones', '${_cuadre['operaciones_totales'] ?? _ventas.length}'),
              _kv('Productos vendidos', '${_cuadre['productos_vendidos'] ?? '—'}'),
              _kv('Ticket promedio', _money(_cuadre['ticket_promedio'])),
            ],
          ),
        ),
        if (observaciones != null && observaciones.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(Icons.notes, 'Observaciones'),
                const SizedBox(height: 8),
                Text(
                  observaciones.trim(),
                  style: const TextStyle(color: _ink, height: 1.35),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _listCard(
          icon: Icons.inventory_2_outlined,
          title: 'Inventario al cierre',
          empty: 'No se guardó conteo de inventario en este cierre.',
          count: productosCierre.length,
          children: [
            for (final p in productosCierre)
              _kv(_productoNombre(p), _qty(p['cantidad'])),
          ],
        ),
        const SizedBox(height: 12),
        _listCard(
          icon: Icons.receipt_long_outlined,
          title: 'Ventas del turno',
          empty: 'No hay ventas guardadas de este turno.',
          count: _ventas.length,
          children: [
            for (final venta in _ventas) _ventaTile(venta),
          ],
        ),
        const SizedBox(height: 12),
        _listCard(
          icon: Icons.money_off_outlined,
          title: 'Egresos',
          empty: 'No hay egresos guardados de este turno.',
          count: _egresos.length,
          children: [
            for (final e in _egresos)
              _kv(
                (e['motivo_entrega'] ?? e['motivo'] ?? 'Egreso').toString(),
                '${_money(e['monto_entrega'] ?? e['monto'])}'
                '${e['es_digital'] == true ? ' · digital' : ' · efectivo'}',
              ),
          ],
        ),
        if (productosApertura.isNotEmpty) ...[
          const SizedBox(height: 12),
          _listCard(
            icon: Icons.storefront_outlined,
            title: 'Inventario de apertura',
            empty: '',
            count: productosApertura.length,
            children: [
              for (final p in productosApertura)
                _kv(_productoNombre(p), _qty(p['cantidad'])),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: _card(
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'Datos técnicos guardados',
                style: TextStyle(fontWeight: FontWeight.w600, color: _ink),
              ),
              children: [
                _kv('local_id', turno['local_id']?.toString() ?? '—'),
                _kv('status', turno['status']?.toString() ?? '—'),
                _kv('server_id', '${turno['server_id_turno'] ?? '—'}'),
                _kv(
                  'uuid apertura',
                  '${turno['client_uuid_apertura'] ?? apertura['client_uuid'] ?? '—'}',
                ),
                _kv(
                  'uuid cierre',
                  '${turno['client_uuid_cierre'] ?? cierre['client_uuid'] ?? '—'}',
                ),
                _kv('id cierre local', '${cierre['id'] ?? '—'}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bannerPendiente() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_upload_outlined, color: _blue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este cierre quedó guardado en el dispositivo y aún no se sincroniza con el servidor.',
              style: TextStyle(color: _ink, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ventaTile(Map<String, dynamic> venta) {
    final items = _asMapList(venta['items']);
    final desglose = _asMapList(venta['desglose_pagos']);
    final synced = venta['synced'] == true;
    final pagos = desglose.isEmpty
        ? ''
        : desglose
            .map((p) {
              final name = p['denominacion']?.toString() ??
                  'Medio ${p['id_medio_pago'] ?? ''}';
              return '$name ${_money(p['monto'])}';
            })
            .join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  venta['id']?.toString() ?? 'Venta',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: _ink),
                ),
              ),
              Text(
                _money(venta['total']),
                style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_fecha(venta['fecha_creacion'] ?? venta['created_offline_at'])}'
            ' · ${venta['estado'] ?? (synced ? 'sincronizada' : 'pendiente')}'
            '${synced ? ' · sync' : ' · sin sync'}',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          if (pagos.isNotEmpty)
            Text(pagos, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          if (items.isNotEmpty)
            Text(
              items
                  .map((i) => '${_qty(i['cantidad'])} × ${_productoNombre(i)}')
                  .join(', '),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }

  Widget _listCard({
    required IconData icon,
    required String title,
    required String empty,
    required int count,
    required List<Widget> children,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(icon, count > 0 ? '$title ($count)' : title),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Text(empty, style: TextStyle(color: Colors.grey[600]))
          else
            ...children,
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _blue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: child,
    );
  }

  Widget _kv(
    String label,
    String value, {
    Color? valueColor,
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey[700])),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? _ink,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
