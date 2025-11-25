import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _planes = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPlanes();
  }

  Future<void> _loadPlanes() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase
          .from('app_suscripciones_plan')
          .select()
          .order('id');

      setState(() {
        _planes = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      print('Error cargando planes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando planes: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  void _showCreatePlanDialog() {
    final denominacionController = TextEditingController();
    final descripcionController = TextEditingController();
    final precioMensualController = TextEditingController();
    final precioAnualController = TextEditingController();
    final limiteUsuariosController = TextEditingController();
    final limiteProductosController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Nuevo Plan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: denominacionController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Plan',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descripcionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioMensualController,
                decoration: const InputDecoration(
                  labelText: 'Precio Mensual',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioAnualController,
                decoration: const InputDecoration(
                  labelText: 'Precio Anual',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limiteUsuariosController,
                decoration: const InputDecoration(
                  labelText: 'Límite de Usuarios',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limiteProductosController,
                decoration: const InputDecoration(
                  labelText: 'Límite de Productos',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (denominacionController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El nombre del plan es requerido')),
                );
                return;
              }

              try {
                await _supabase.from('app_suscripciones_plan').insert({
                  'denominacion': denominacionController.text,
                  'descripcion': descripcionController.text,
                  'precio_mensual': double.tryParse(precioMensualController.text) ?? 0,
                  'precio_anual': double.tryParse(precioAnualController.text) ?? 0,
                  'limite_usuarios': int.tryParse(limiteUsuariosController.text) ?? 0,
                  'limite_productos': int.tryParse(limiteProductosController.text) ?? 0,
                  'es_activo': true,
                });

                if (mounted) {
                  Navigator.pop(context);
                  _loadPlanes();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Plan creado exitosamente')),
                  );
                }
              } catch (e) {
                print('Error creando plan: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creando plan: $e')),
                  );
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _showEditPlanDialog(Map<String, dynamic> plan) {
    final denominacionController = TextEditingController(text: plan['denominacion']);
    final descripcionController = TextEditingController(text: plan['descripcion'] ?? '');
    final precioMensualController = TextEditingController(
      text: (plan['precio_mensual'] ?? 0).toString(),
    );
    final precioAnualController = TextEditingController(
      text: (plan['precio_anual'] ?? 0).toString(),
    );
    final limiteUsuariosController = TextEditingController(
      text: (plan['limite_usuarios'] ?? 0).toString(),
    );
    final limiteProductosController = TextEditingController(
      text: (plan['limite_productos'] ?? 0).toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Plan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: denominacionController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Plan',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descripcionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioMensualController,
                decoration: const InputDecoration(
                  labelText: 'Precio Mensual',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: precioAnualController,
                decoration: const InputDecoration(
                  labelText: 'Precio Anual',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limiteUsuariosController,
                decoration: const InputDecoration(
                  labelText: 'Límite de Usuarios',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limiteProductosController,
                decoration: const InputDecoration(
                  labelText: 'Límite de Productos',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _supabase.from('app_suscripciones_plan').update({
                  'denominacion': denominacionController.text,
                  'descripcion': descripcionController.text,
                  'precio_mensual': double.tryParse(precioMensualController.text) ?? 0,
                  'precio_anual': double.tryParse(precioAnualController.text) ?? 0,
                  'limite_usuarios': int.tryParse(limiteUsuariosController.text) ?? 0,
                  'limite_productos': int.tryParse(limiteProductosController.text) ?? 0,
                }).eq('id', plan['id']);

                if (mounted) {
                  Navigator.pop(context);
                  _loadPlanes();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Plan actualizado exitosamente')),
                  );
                }
              } catch (e) {
                print('Error actualizando plan: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error actualizando plan: $e')),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(Map<String, dynamic> plan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Plan'),
        content: Text('¿Estás seguro de que deseas eliminar el plan "${plan['denominacion']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _supabase.from('app_suscripciones_plan').delete().eq('id', plan['id']);

                if (mounted) {
                  Navigator.pop(context);
                  _loadPlanes();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Plan eliminado exitosamente')),
                  );
                }
              } catch (e) {
                print('Error eliminando plan: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error eliminando plan: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreatePlanDialog,
            tooltip: 'Nuevo Plan',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestión de Planes de Suscripción',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: isDesktop
                        ? _buildDesktopTable()
                        : _buildMobileList(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDesktopTable() {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 12,
            columns: const [
              DataColumn(label: Text('ID')),
              DataColumn(label: Text('Nombre')),
              DataColumn(label: Text('Precio/Mes')),
              DataColumn(label: Text('Precio/Año')),
              DataColumn(label: Text('Usuarios')),
              DataColumn(label: Text('Productos')),
              DataColumn(label: Text('Activo')),
              DataColumn(label: Text('Acciones')),
            ],
            rows: _planes.map((plan) {
              return DataRow(
                cells: [
                  DataCell(Text(plan['id'].toString())),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Text(
                        plan['denominacion'] ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text('\$${plan['precio_mensual'] ?? 0}')),
                  DataCell(Text('\$${plan['precio_anual'] ?? 0}')),
                  DataCell(Text((plan['limite_usuarios'] ?? 0).toString())),
                  DataCell(Text((plan['limite_productos'] ?? 0).toString())),
                  DataCell(
                    Chip(
                      label: Text(plan['es_activo'] ? 'Sí' : 'No'),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      backgroundColor: plan['es_activo']
                          ? AppColors.success.withOpacity(0.2)
                          : AppColors.error.withOpacity(0.2),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showEditPlanDialog(plan),
                          tooltip: 'Editar',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () => _showDeleteConfirmDialog(plan),
                          tooltip: 'Eliminar',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.builder(
      itemCount: _planes.length,
      itemBuilder: (context, index) {
        final plan = _planes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(plan['denominacion'] ?? 'Sin nombre'),
            subtitle: Text(
              '\$${plan['precio_mensual'] ?? 0}/mes',
              style: const TextStyle(color: AppColors.primary),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Descripción', plan['descripcion'] ?? 'N/A'),
                    _buildInfoRow('Precio Mensual', '\$${plan['precio_mensual'] ?? 0}'),
                    _buildInfoRow('Precio Anual', '\$${plan['precio_anual'] ?? 0}'),
                    _buildInfoRow('Límite Usuarios', (plan['limite_usuarios'] ?? 0).toString()),
                    _buildInfoRow('Límite Productos', (plan['limite_productos'] ?? 0).toString()),
                    _buildInfoRow(
                      'Estado',
                      plan['es_activo'] ? 'Activo' : 'Inactivo',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showEditPlanDialog(plan),
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Editar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showDeleteConfirmDialog(plan),
                          icon: const Icon(Icons.delete, size: 16),
                          label: const Text('Eliminar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 1,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
