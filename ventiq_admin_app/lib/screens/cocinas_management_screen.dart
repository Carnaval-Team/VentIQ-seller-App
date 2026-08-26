import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/cocina_service.dart';
import '../utils/navigation_guard.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/cocinas/cocina_form_dialog.dart';
import '../widgets/cocinas/cocinas_list_widget.dart';
import '../widgets/cocinas/cocinas_platos_widget.dart';
import '../widgets/cocinas/cocinas_categorias_widget.dart';

/// Pantalla de gestión de cocinas (Fase 1 del plan restaurante/cocina).
///
/// Dos pestañas:
///   - Cocinas: alta, edición, activar/desactivar y ligado con TPVs.
///   - Platos:  asignar productos elaborados a una cocina y su modo de
///              elaboración (al pedido / por tanda).
///
/// Sigue la estructura de `TpvManagementScreen`: pantalla coordinadora con
/// buscador compartido y widgets independientes por pestaña.
class CocinasManagementScreen extends StatefulWidget {
  const CocinasManagementScreen({super.key});

  @override
  State<CocinasManagementScreen> createState() =>
      _CocinasManagementScreenState();
}

class _CocinasManagementScreenState extends State<CocinasManagementScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  int _refreshKey = 0;

  bool _cocinaActiva = false;
  bool _modoRestaurante = false;
  bool _cargandoConfig = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChange);
    _cargarConfig();
  }

  void _onTabChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarConfig() async {
    try {
      final config = await CocinaService.leerConfigCocina();
      if (!mounted) return;
      setState(() {
        _modoRestaurante = config.modoRestaurante;
        _cocinaActiva = config.cocinaActiva;
        _cargandoConfig = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoConfig = false);
    }
  }

  void _refrescar() => setState(() => _refreshKey++);

  Future<void> _alternarCocinaActiva(bool valor) async {
    setState(() => _cocinaActiva = valor);
    try {
      // Al activar la cocina, el servicio activa el modo restaurante si falta:
      // las comandas salen de las cuentas de mesa.
      final activoRestaurante = await CocinaService.cambiarCocinaActiva(valor);

      if (!mounted) return;
      setState(() {
        if (activoRestaurante) _modoRestaurante = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !valor
                ? 'Módulo de cocina desactivado'
                : activoRestaurante
                ? 'Cocina activada. También se activó el modo restaurante '
                      '(las comandas salen de las cuentas de mesa).'
                : 'Módulo de cocina activado para esta tienda',
          ),
          backgroundColor: valor ? AppColors.success : AppColors.warning,
          duration: Duration(seconds: activoRestaurante ? 5 : 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cocinaActiva = !valor); // revertir
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar la configuración: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esTabCocinas = _tabController.index == 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cocinas'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.soup_kitchen), text: 'Cocinas'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Platos'),
            Tab(icon: Icon(Icons.category), text: 'Categorias'),
          ],
        ),
      ),
      drawer: const AdminDrawer(),
      body: Column(
        children: [
          if (!_cargandoConfig) _buildBannerConfig(),
          _buildBuscador(esTabCocinas),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                CocinasListWidget(
                  key: ValueKey('cocinas_$_refreshKey'),
                  searchQuery: _searchQuery,
                  onRefresh: _refrescar,
                ),
                CocinasPlatosWidget(
                  key: ValueKey('platos_$_refreshKey'),
                  searchQuery: _searchQuery,
                  onRefresh: _refrescar,
                ),
                CocinasCategoriasWidget(
                  key: ValueKey('categorias_$_refreshKey'),
                  searchQuery: _searchQuery,
                  onRefresh: _refrescar,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: esTabCocinas
          ? FloatingActionButton.extended(
              onPressed: _crearCocina,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva cocina'),
            )
          : null,
    );
  }

  Future<void> _crearCocina() async {
    final puede = await NavigationGuard.canPerformAction('tpv.create');
    if (!mounted) return;
    if (!puede) {
      NavigationGuard.showActionDeniedMessage(context, 'Crear cocina');
      return;
    }
    await CocinaFormDialog.mostrarCrear(
      context: context,
      onSuccess: _refrescar,
    );
  }

  /// Interruptor del módulo de cocina para la tienda. Se muestra arriba porque
  /// es el flag que decide si el vendedor ve algo de comandas.
  Widget _buildBannerConfig() {
    final activo = _cocinaActiva;
    final color = activo ? AppColors.success : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            activo ? Icons.restaurant : Icons.no_meals_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activo ? 'Cocina habilitada' : 'Cocina deshabilitada',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  activo
                      ? _modoRestaurante
                            ? 'Los TPVs enrutan platos a sus cocinas'
                            : 'Falta el modo restaurante'
                      : 'Al activar, se habilita también el modo restaurante',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: activo,
            activeThumbColor: AppColors.success,
            onChanged: _alternarCocinaActiva,
          ),
        ],
      ),
    );
  }

  Widget _buildBuscador(bool esTabCocinas) {
    // El hint depende de la pestaña activa: buscar "croqueta" en Cocinas no
    // encuentra nada y el usuario no sabría por qué.
    final hint = switch (_tabController.index) {
      0 => 'Buscar cocina, almacén o TPV...',
      1 => 'Buscar plato por nombre o SKU...',
      _ => 'Buscar categoría...',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }
}
