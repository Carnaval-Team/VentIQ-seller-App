import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/ingresos_service.dart';
import '../widgets/app_drawer.dart';

class IngresosDistribucionScreen extends StatefulWidget {
  const IngresosDistribucionScreen({super.key});

  @override
  State<IngresosDistribucionScreen> createState() =>
      _IngresosDistribucionScreenState();
}

class _IngresosDistribucionScreenState extends State<IngresosDistribucionScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _licencias = [];
  double _tasaCambio = 440.0;
  double _totalUsd = 0.0;
  double _totalCup = 0.0;
  late Map<String, dynamic> _distribucion;
  final TextEditingController _tasaCambioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tasaCambioController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final tasaCambio = await IngresosService.getUsdToCupRate();
      final licencias = await IngresosService.getLicenciasActivasConPrecio();

      double totalUsd = 0.0;
      for (var lic in licencias) {
        totalUsd += lic['precio_usd'] as double;
      }

      final totalCup = totalUsd * tasaCambio;
      final distribucion = IngresosService.calcularDistribucionConAgentes(
        licencias,
        tasaCambio,
      );

      if (mounted) {
        setState(() {
          _tasaCambio = tasaCambio;
          _tasaCambioController.text = tasaCambio.toStringAsFixed(2);
          _licencias = licencias;
          _totalUsd = totalUsd;
          _totalCup = totalCup;
          _distribucion = distribucion;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando datos de ingresos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _recalcularDistribucion() {
    final nuevaTasa = double.tryParse(_tasaCambioController.text) ?? _tasaCambio;
    final nuevaTotalCup = _totalUsd * nuevaTasa;
    final nuevaDistribucion =
        IngresosService.calcularDistribucionConAgentes(_licencias, nuevaTasa);

    setState(() {
      _tasaCambio = nuevaTasa;
      _totalCup = nuevaTotalCup;
      _distribucion = nuevaDistribucion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Distribución de Ingresos'),
        elevation: 0,
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resumen de ingresos totales
                  _buildResumenCard(),
                  const SizedBox(height: 24),

                  // Distribución de ganancias
                  _buildDistribucionCard(),
                  const SizedBox(height: 24),

                  // Listado de licencias activas
                  _buildLicenciasCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildResumenCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen de Ingresos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoColumn(
                  'Total USD',
                  '\$${_totalUsd.toStringAsFixed(2)}',
                  AppColors.primary,
                ),
                _buildInfoColumn(
                  'Total CUP',
                  '${_totalCup.toStringAsFixed(2)} CUP',
                  AppColors.success,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Tasa de cambio input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tasaCambioController,
                    decoration: InputDecoration(
                      labelText: 'Tasa de Cambio (USD → CUP)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.currency_exchange),
                      suffixText: 'CUP',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _recalcularDistribucion(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Licencias activas: ${_licencias.length}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDistribucionCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Distribución de Ganancias (CUP)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Catálogo
            _buildDistribucionSection(
              'CATÁLOGO (500 CUP total)',
              [
                _buildDistribucionItem(
                  'Odeimys',
                  _distribucion['odeimys_catalogo'] ?? 0.0,
                  Colors.blue,
                ),
                _buildDistribucionItem(
                  'Yoelvis',
                  _distribucion['yoelvis_catalogo'] ?? 0.0,
                  Colors.green,
                ),
                _buildDistribucionItem(
                  'Cesar',
                  _distribucion['cesar_catalogo'] ?? 0.0,
                  Colors.orange,
                ),
                _buildDistribucionItem(
                  'Jandro',
                  _distribucion['jandro_catalogo'] ?? 0.0,
                  Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Resto
            _buildDistribucionSection(
              'DEL RESTO',
              [
                _buildDistribucionItem(
                  'Odeimys (45%)',
                  _distribucion['odeimys_resto'] ?? 0.0,
                  Colors.blue,
                ),
                _buildDistribucionItem(
                  'Agentes de Tienda (5% total)',
                  _distribucion['agente_total'] ?? 0.0,
                  Colors.red,
                ),
                _buildDistribucionItem(
                  'Cesar (16.67%)',
                  _distribucion['cesar_resto'] ?? 0.0,
                  Colors.orange,
                ),
                _buildDistribucionItem(
                  'Jandro (16.67%)',
                  _distribucion['jandro_resto'] ?? 0.0,
                  Colors.purple,
                ),
                _buildDistribucionItem(
                  'Yoelvis (16.67%)',
                  _distribucion['yoelvis_resto'] ?? 0.0,
                  Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Agentes individuales
            if ((_distribucion['agentes_por_nombre'] as Map?)?.isNotEmpty ?? false)
              _buildDistribucionSection(
                'COMISIÓN POR AGENTE (5% de sus tiendas)',
                [
                  for (var entry
                      in ((_distribucion['agentes_por_nombre'] as Map?) ?? {})
                          .entries)
                    _buildDistribucionItem(
                      entry.key,
                      entry.value as double,
                      Colors.teal,
                    ),
                ],
              ),
            const SizedBox(height: 20),

            // Totales
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  Text(
                    'TOTALES POR BENEFICIARIO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildTotalItem(
                        'Odeimys',
                        _distribucion['odeimys_total'] ?? 0.0,
                        Colors.blue,
                      ),
                      _buildTotalItem(
                        'Yoelvis',
                        _distribucion['yoelvis_total'] ?? 0.0,
                        Colors.green,
                      ),
                      _buildTotalItem(
                        'Cesar',
                        _distribucion['cesar_total'] ?? 0.0,
                        Colors.orange,
                      ),
                      _buildTotalItem(
                        'Jandro',
                        _distribucion['jandro_total'] ?? 0.0,
                        Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistribucionSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...items,
      ],
    );
  }

  Widget _buildDistribucionItem(String nombre, double monto, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                nombre,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          Text(
            '${monto.toStringAsFixed(2)} CUP',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalItem(String nombre, double monto, Color color) {
    return Column(
      children: [
        Text(
          nombre,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${monto.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLicenciasCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Licencias Activas',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_licencias.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No hay licencias activas',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _licencias.length,
                itemBuilder: (context, index) {
                  final lic = _licencias[index];
                  return _buildLicenciaItem(lic);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenciaItem(Map<String, dynamic> licencia) {
    final precioUsd = licencia['precio_usd'] as double;
    final precioCup = precioUsd * _tasaCambio;
    final agenteNombre = licencia['agente_nombre'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      licencia['tienda_nombre'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      licencia['plan_nombre'],
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${precioUsd.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${precioCup.toStringAsFixed(2)} CUP',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (agenteNombre != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.support_agent,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Agente: $agenteNombre',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
