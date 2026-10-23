import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/analytics/inventory_metrics.dart';
import '../services/analytics_service.dart';
import '../widgets/lote_expiry_widgets.dart';

/// Lista operativa de productos por vencer / vencidos.
class CaducidadesScreen extends StatefulWidget {
  final String? initialTab; // 'expiring' | 'expired' | 'all'

  const CaducidadesScreen({super.key, this.initialTab});

  @override
  State<CaducidadesScreen> createState() => _CaducidadesScreenState();
}

class _CaducidadesScreenState extends State<CaducidadesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<StockAlert> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = switch (widget.initialTab) {
      'expired' => 1,
      'all' => 2,
      _ => 0,
    };
    _tabs = TabController(length: 3, vsync: this, initialIndex: initial);
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
      final all = await AnalyticsService.getStockAlerts();
      final caducidad = all
          .where((a) => a.alertType == 'expiring' || a.alertType == 'expired')
          .toList()
        ..sort((a, b) {
          final fa = a.fechaVencimiento ?? DateTime(9999);
          final fb = b.fechaVencimiento ?? DateTime(9999);
          return fa.compareTo(fb);
        });
      if (!mounted) return;
      setState(() {
        _alerts = caducidad;
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

  List<StockAlert> _filtered(String type) {
    if (type == 'all') return _alerts;
    return _alerts.where((a) => a.alertType == type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caducidades'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              text:
                  'Por vencer (${_filtered('expiring').length})',
            ),
            Tab(text: 'Vencidos (${_filtered('expired').length})'),
            Tab(text: 'Todos (${_alerts.length})'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _list('expiring'),
                    _list('expired'),
                    _list('all'),
                  ],
                ),
    );
  }

  Widget _list(String type) {
    final items = _filtered(type);
    if (items.isEmpty) {
      return Center(
        child: Text(
          type == 'expired'
              ? 'No hay productos vencidos con stock'
              : type == 'expiring'
                  ? 'No hay productos por vencer'
                  : 'Sin alertas de caducidad',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final a = items[index];
        final estado = a.alertType == 'expired' ? 'expired' : 'expiring';
        final fecha = a.fechaVencimiento;
        final fechaTxt = fecha == null
            ? '—'
            : '${fecha.day.toString().padLeft(2, '0')}/'
                '${fecha.month.toString().padLeft(2, '0')}/'
                '${fecha.year}';

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: loteEstadoColor(estado).withOpacity(0.15),
              child: Icon(
                a.alertType == 'expired'
                    ? Icons.event_busy
                    : Icons.schedule,
                color: loteEstadoColor(estado),
              ),
            ),
            title: Text(
              a.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  a.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (a.codigoLote != null && a.codigoLote!.isNotEmpty)
                      Text(
                        'Lote ${a.codigoLote}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    Text('Vence $fechaTxt', style: const TextStyle(fontSize: 12)),
                    Text(
                      'Stock: ${a.currentStock.toStringAsFixed(a.currentStock == a.currentStock.roundToDouble() ? 0 : 2)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    LoteEstadoChip(estado: estado),
                  ],
                ),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
