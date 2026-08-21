import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../models/cxc_cliente.dart';
import '../services/cxc_service.dart';
import 'cliente_cxc_detail_screen.dart';

class CuentasPorCobrarScreen extends StatefulWidget {
  const CuentasPorCobrarScreen({super.key});

  @override
  State<CuentasPorCobrarScreen> createState() =>
      _CuentasPorCobrarScreenState();
}

class _CuentasPorCobrarScreenState extends State<CuentasPorCobrarScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<CxcCliente> _clientes = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final clientes = await CxcService.listarClientesConSaldo();
      if (!mounted) return;
      setState(() {
        _clientes = clientes;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error al cargar cuentas por cobrar: $e';
        _isLoading = false;
      });
    }
  }

  List<CxcCliente> get _filteredClientes {
    if (_searchQuery.isEmpty) return _clientes;
    return _clientes.where((c) {
      return c.nombreCompleto.toLowerCase().contains(_searchQuery) ||
          c.codigoCliente.toLowerCase().contains(_searchQuery) ||
          (c.telefono?.toLowerCase().contains(_searchQuery) ?? false);
    }).toList();
  }

  double get _totalCartera =>
      _clientes.fold(0.0, (sum, c) => sum + c.saldoPendiente);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Cuentas por Cobrar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      endDrawer: const AdminDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: Column(
                    children: [
                      _buildSummaryCard(),
                      _buildSearchBar(),
                      Expanded(child: _buildClientesList()),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadData, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cartera total pendiente',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  '\$${_totalCartera.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_clientes.length} cliente(s) con saldo pendiente',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar cliente por nombre, código o teléfono',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildClientesList() {
    final clientes = _filteredClientes;
    if (clientes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  color: Colors.green.shade300, size: 48),
              const SizedBox(height: 12),
              Text(
                _clientes.isEmpty
                    ? 'No hay clientes con cuentas por cobrar pendientes'
                    : 'Sin resultados para tu búsqueda',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: clientes.length,
      itemBuilder: (context, index) => _buildClienteCard(clientes[index]),
    );
  }

  Widget _buildClienteCard(CxcCliente cliente) {
    final dias = cliente.diasAntiguedad;
    Color badgeColor = Colors.green;
    if (dias != null) {
      if (dias > 60) {
        badgeColor = Colors.red;
      } else if (dias > 30) {
        badgeColor = Colors.orange;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Icon(Icons.person, color: AppColors.primary),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                cliente.nombreCompleto,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (cliente.bloqueadoCxc)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'Bloqueado',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                '${cliente.ordenesPendientes} orden(es) pendiente(s)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              if (dias != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$dias días',
                    style: TextStyle(fontSize: 11, color: badgeColor),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Text(
          '\$${cliente.saldoPendiente.toStringAsFixed(2)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClienteCxcDetailScreen(
                idCliente: cliente.idCliente,
                nombreCliente: cliente.nombreCompleto,
              ),
            ),
          );
          _loadData();
        },
      ),
    );
  }
}
