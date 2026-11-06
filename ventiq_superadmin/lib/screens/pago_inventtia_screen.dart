import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/inventtia_payment_model.dart';
import '../services/inventtia_payment_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';
import 'pago_inventtia_resumen.dart';

class PagoInventtiaScreen extends StatefulWidget {
  const PagoInventtiaScreen({super.key});

  @override
  State<PagoInventtiaScreen> createState() => _PagoInventtiaScreenState();
}

class _PagoInventtiaScreenState extends State<PagoInventtiaScreen>
    with SingleTickerProviderStateMixin {
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  late DateTime _licenciaMes;
  late TabController _tabController;

  InventtiaPaymentModel? _paymentData;
  List<AgentPaymentSummary> _agentPayments = [];
  List<InventtiaAgent> _agents = [];
  List<Map<String, dynamic>> _proveedores = [];
  ExchangeRates? _exchangeRates;
  double _commissionPercentage = 1.0;
  bool _isLoading = false;
  String? _errorMessage;

  final NumberFormat _moneyFmt = NumberFormat('#,##0.00', 'es');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeDefaultDates();
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initializeDefaultDates() {
    final now = DateTime.now();
    // El día de pago se liquidan las ventas del mes cerrado y la licencia del mes en curso.
    _fechaInicio = DateTime(now.year, now.month - 1, 1);
    _fechaFin = DateTime(now.year, now.month, 0);
    _licenciaMes = DateTime(now.year, now.month, 1);
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        InventtiaPaymentService.getExchangeRates(),
        InventtiaPaymentService.getInventtiaPayments(_fechaInicio, _fechaFin),
        InventtiaPaymentService.getAgentPayments(_fechaInicio, _fechaFin),
        InventtiaPaymentService.getAgents(),
        InventtiaPaymentService.getProveedores(),
      ]);

      if (!mounted) return;
      final payment = results[1] as InventtiaPaymentModel;
      setState(() {
        _exchangeRates = results[0] as ExchangeRates;
        _paymentData = payment;
        _commissionPercentage = payment.commissionPercentage;
        _agentPayments = results[2] as List<AgentPaymentSummary>;
        _agents = results[3] as List<InventtiaAgent>;
        _proveedores = results[4] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showConfigDialog() async {
    final controller = TextEditingController(
      text: _commissionPercentage.toString(),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Configurar Comisión Inventtia'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '% Comisión sobre precio costo',
            suffixText: '%',
            border: OutlineInputBorder(),
            helperText: 'Ej: 1.0 = 1% del costo de las órdenes',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true) {
      final newPercentage =
          double.tryParse(controller.text) ?? _commissionPercentage;
      final ok =
          await InventtiaPaymentService.updateInventtiaCommissionPercentage(
        newPercentage,
      );
      if (ok && mounted) {
        setState(() => _commissionPercentage = newPercentage);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Porcentaje de comisión actualizado')),
        );
        _loadAll();
      }
    }
    controller.dispose();
  }

  void _setDateRange(String range) {
    final now = DateTime.now();
    setState(() {
      switch (range) {
        case 'week':
          _fechaInicio = now.subtract(const Duration(days: 7));
          _fechaFin = now;
          break;
        case 'previous':
          _fechaInicio = DateTime(now.year, now.month - 1, 1);
          _fechaFin = DateTime(now.year, now.month, 0);
          break;
        case 'month':
          _fechaInicio = DateTime(now.year, now.month, 1);
          _fechaFin = now;
          break;
        case '3months':
          _fechaInicio = DateTime(now.year, now.month - 3, 1);
          _fechaFin = now;
          break;
        case 'year':
          _fechaInicio = DateTime(now.year, 1, 1);
          _fechaFin = now;
          break;
      }
    });
    _loadAll();
  }

  Future<void> _openAgentForm({InventtiaAgent? agent}) async {
    final nombreCtrl = TextEditingController(text: agent?.nombre ?? '');
    final apellidosCtrl = TextEditingController(text: agent?.apellidos ?? '');
    final selected = <int>{...?(agent?.proveedorIds)};
    var activo = agent?.activo ?? true;

    if (_proveedores.isEmpty) {
      _proveedores = await InventtiaPaymentService.getProveedores();
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(agent == null ? 'Nuevo agente' : 'Editar agente'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apellidosCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Apellidos',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tiendas asociadas',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _proveedores.length,
                      itemBuilder: (context, index) {
                        final p = _proveedores[index];
                        final id = (p['id'] as num).toInt();
                        final name = p['name']?.toString() ?? 'Tienda #$id';
                        final checked = selected.contains(id);
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: checked,
                          title: Text(name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (v) {
                            setLocal(() {
                              if (v == true) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  if (agent != null) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activo'),
                      value: activo,
                      onChanged: (v) => setLocal(() => activo = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nombreCtrl.text.trim().isEmpty ||
                    apellidosCtrl.text.trim().isEmpty ||
                    selected.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Completa nombre, apellidos y al menos una tienda'),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      nombreCtrl.dispose();
      apellidosCtrl.dispose();
      return;
    }

    try {
      if (agent == null) {
        await InventtiaPaymentService.createAgent(
          nombre: nombreCtrl.text,
          apellidos: apellidosCtrl.text,
          proveedorIds: selected.toList(),
        );
      } else {
        await InventtiaPaymentService.updateAgent(
          id: agent.id,
          nombre: nombreCtrl.text,
          apellidos: apellidosCtrl.text,
          proveedorIds: selected.toList(),
          activo: activo,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agente guardado')),
        );
        await _loadAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      nombreCtrl.dispose();
      apellidosCtrl.dispose();
    }
  }

  void _showAgentDetail(AgentPaymentSummary summary) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.storefront, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.agent.fullName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Comisión ${_moneyFmt.format(summary.commissionCup)} CUP · '
                            'Ventas ${_moneyFmt.format(summary.salesCup)} CUP · '
                            '${summary.ordersCount} órdenes',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: summary.byStore.length,
                  itemBuilder: (context, index) {
                    final store = summary.byStore[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        initiallyExpanded: index == 0,
                        title: Text(
                          store.proveedorName ??
                              'Tienda #${store.proveedorId}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Ventas ${_moneyFmt.format(store.salesCup)} CUP · '
                          'Comisión ${_moneyFmt.format(store.commissionCup)} CUP · '
                          '${store.ordersCount} órdenes',
                        ),
                        children: store.orders.isEmpty
                            ? const [
                                ListTile(
                                  dense: true,
                                  title: Text('Sin órdenes en el período'),
                                ),
                              ]
                            : store.orders
                                .map(
                                  (o) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.receipt, size: 18),
                                    title: Text('Orden #${o.orderId}'),
                                    subtitle: Text(
                                      o.createdAt != null
                                          ? dateFormat.format(o.createdAt!)
                                          : '—',
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${_moneyFmt.format(o.commissionCup)} CUP',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.warning,
                                          ),
                                        ),
                                        Text(
                                          'Venta ${_moneyFmt.format(o.salesCup)}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAgent(InventtiaAgent agent) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar agente'),
        content: Text('¿Eliminar a ${agent.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await InventtiaPaymentService.deleteAgent(agent.id);
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isDesktop ? 'Pago a Inventtia y Agentes' : 'Pago Inventtia',
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Reparto', icon: Icon(Icons.account_balance_wallet)),
            Tab(text: 'Agentes', icon: Icon(Icons.people)),
          ],
        ),
        actions: [
          if (_exchangeRates != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Center(
                child: Text(
                  'USD ${_exchangeRates!.valorUsd.toStringAsFixed(2)} | EUR ${_exchangeRates!.valorEuro.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showConfigDialog,
            tooltip: 'Comisión Inventtia',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
            child: _buildDateFilters(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                PagoInventtiaResumen(
                  fechaInicio: _fechaInicio,
                  fechaFin: _fechaFin,
                  licenciaMes: _licenciaMes,
                ),
                _isLoading && _agents.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _buildAgentsTab(isDesktop),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(_errorMessage ?? 'Error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilters() {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final mesLicencia = DateFormat('MMMM yyyy', 'es_ES').format(_licenciaMes);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pagos de', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Mes anterior'),
                  selected: false,
                  onSelected: (_) => _setDateRange('previous'),
                ),
                FilterChip(
                  label: const Text('Este mes'),
                  selected: false,
                  onSelected: (_) => _setDateRange('month'),
                ),
                FilterChip(
                  label: const Text('3 meses'),
                  selected: false,
                  onSelected: (_) => _setDateRange('3months'),
                ),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _fechaInicio,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) setState(() => _fechaInicio = date);
                  },
                  child: Chip(
                    avatar: const Icon(Icons.calendar_today, size: 16),
                    label: Text('Desde ${dateFormat.format(_fechaInicio)}'),
                  ),
                ),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _fechaFin,
                      firstDate: _fechaInicio,
                      lastDate: DateTime.now(),
                    );
                    if (date != null) setState(() => _fechaFin = date);
                  },
                  child: Chip(
                    avatar: const Icon(Icons.event, size: 16),
                    label: Text('Hasta ${dateFormat.format(_fechaFin)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Licencias de', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: () => setState(() {
                    _licenciaMes = DateTime(_licenciaMes.year, _licenciaMes.month - 1, 1);
                  }),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  mesLicencia,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: () => setState(() {
                    _licenciaMes = DateTime(_licenciaMes.year, _licenciaMes.month + 1, 1);
                  }),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventtiaTab(bool isDesktop) {
    if (_paymentData == null) {
      return const Center(child: Text('Sin datos'));
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
        children: [
          _buildStatsSection(isDesktop),
          const SizedBox(height: 16),
          _buildCommissionCard(isDesktop),
          const SizedBox(height: 16),
          _buildOrdersList(),
        ],
      ),
    );
  }

  Widget _buildStatsSection(bool isDesktop) {
    final d = _paymentData!;
    final cards = [
      _buildStatCard(
        'Base costo CUP',
        '\$${_moneyFmt.format(d.costBaseCup)}',
        Icons.payments,
        AppColors.primary,
      ),
      _buildStatCard(
        'Base costo USD',
        '\$${_moneyFmt.format(d.costBaseUsd)}',
        Icons.attach_money,
        AppColors.success,
      ),
      _buildStatCard(
        'Base costo EUR',
        '€${_moneyFmt.format(d.costBaseEuro)}',
        Icons.euro,
        AppColors.warning,
      ),
      _buildStatCard(
        'Órdenes',
        '${d.ordersCount}',
        Icons.receipt,
        AppColors.info,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }
    return Column(
      children: [
        Row(children: [Expanded(child: cards[0]), const SizedBox(width: 8), Expanded(child: cards[1])]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: cards[2]), const SizedBox(width: 8), Expanded(child: cards[3])]),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionCard(bool isDesktop) {
    final d = _paymentData!;
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A pagar a Inventtia (${d.commissionPercentage.toStringAsFixed(1)}%)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sobre precio costo (misma base que pago a proveedores). '
                        '${d.linesCount} líneas · excluye canceladas/devueltas y productos excluidos de referidos.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _commissionBox('CUP', _moneyFmt.format(d.commissionCup), AppColors.primary, true),
                _commissionBox('USD', _moneyFmt.format(d.commissionUsd), AppColors.success, false),
                _commissionBox('EUR', _moneyFmt.format(d.commissionEuro), AppColors.warning, false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _commissionBox(String label, String value, Color color, bool highlight) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.12) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: highlight ? Border.all(color: color, width: 2) : Border.all(color: AppColors.info),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    final orders = _paymentData!.orders;
    if (orders.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No hay órdenes en el rango')),
        ),
      );
    }

    final dateFormat = DateFormat('dd/MM/yyyy');
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Órdenes por costo (${orders.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final o = orders[index];
              return ListTile(
                leading: const Icon(Icons.receipt, color: AppColors.primary),
                title: Text(
                  'Orden #${o.orderId}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${dateFormat.format(o.createdAt)} · ${o.linesCount} líneas · Costo ${_moneyFmt.format(o.costCup)} CUP',
                ),
                trailing: Text(
                  '${_moneyFmt.format(o.commissionCup)} CUP',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAgentsTab(bool isDesktop) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Agentes (1% de ventas de sus tiendas)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openAgentForm(),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Nuevo agente'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'La comisión es el ${InventtiaPaymentService.agentCommissionPercentage.toStringAsFixed(0)}% '
            'sobre la suma de ventas Carnaval de todas sus tiendas. '
            'No incluyen canceladas/devueltas ni productos excluidos de referidos. '
            'Toca un agente en el resumen para ver órdenes por tienda.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_agentPayments.isNotEmpty) ...[
            _buildAgentPayouts(isDesktop),
            const SizedBox(height: 20),
          ],
          const Text(
            'Gestión de agentes',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_agents.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay agentes. Crea uno y asígnalo a una tienda. '
                  'Si falla al guardar, aplica sql_updates/inventtia_agentes.sql.',
                ),
              ),
            )
          else
            ..._agents.map(_buildAgentCard),
        ],
      ),
    );
  }

  Widget _buildAgentPayouts(bool isDesktop) {
    final total = _agentPayments.fold<double>(0, (s, a) => s + a.commissionCup);
    return Card(
      color: AppColors.warning.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A pagar a agentes en el período: ${_moneyFmt.format(total)} CUP',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const Divider(),
            ..._agentPayments.map((p) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _showAgentDetail(p),
                title: Text(
                  p.agent.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${p.agent.tiendas.length} tienda(s) · '
                  'Ventas ${_moneyFmt.format(p.salesCup)} CUP · ${p.ordersCount} órdenes',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_moneyFmt.format(p.commissionCup)} CUP',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                          ),
                        ),
                        Text(
                          'USD ${_moneyFmt.format(p.commissionUsd)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentCard(InventtiaAgent agent) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: agent.activo
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.grey.shade300,
          child: Icon(
            Icons.person,
            color: agent.activo ? AppColors.primary : Colors.grey,
          ),
        ),
        title: Text(
          agent.fullName,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: agent.activo ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(
          '${agent.tiendasLabel}'
          '${agent.activo ? '' : ' · Inactivo'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () => _openAgentForm(agent: agent),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Eliminar',
              onPressed: () => _deleteAgent(agent),
            ),
          ],
        ),
      ),
    );
  }
}
