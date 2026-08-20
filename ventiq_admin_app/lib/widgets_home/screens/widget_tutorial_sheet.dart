import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../data/widget_config_store.dart';
import '../home_widget_service.dart';
import '../widget_keys.dart';

/// Tutorial de los Home Screen Widgets.
///
/// Se muestra una sola vez (o desde Ajustes) y explica qué widgets existen y
/// cómo añadirlos. En Android 8+ ofrece además el botón "Añadir ahora", que usa
/// `requestPinAppWidget` para colocar el widget sin salir de la app.
class WidgetTutorialSheet extends StatefulWidget {
  const WidgetTutorialSheet({super.key});

  /// Muestra el tutorial si el usuario no lo ha visto y no tiene widgets aún.
  ///
  /// Se llama tras el arranque del Dashboard, después del diálogo de changelog,
  /// para no apilar dos modales.
  static Future<void> showIfNeeded(BuildContext context) async {
    final seen = await WidgetConfigStore.hasSeenTutorial();
    if (seen) return;

    // Si ya colocó widgets, no hace falta explicarle nada.
    final hasWidgets = await HomeWidgetService.hasInstalledWidgets();
    if (hasWidgets) {
      await WidgetConfigStore.markTutorialSeen();
      return;
    }

    if (!context.mounted) return;
    await show(context);
  }

  /// Muestra el tutorial siempre (entrada manual desde Ajustes).
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WidgetTutorialSheet(),
    );
    await WidgetConfigStore.markTutorialSeen();
  }

  @override
  State<WidgetTutorialSheet> createState() => _WidgetTutorialSheetState();
}

class _WidgetTutorialSheetState extends State<WidgetTutorialSheet> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const List<_TutorialPage> _pages = [
    _TutorialPage(
      icon: Icons.dashboard_customize,
      title: 'Tus métricas en la pantalla de inicio',
      body:
          'Añade widgets de Inventtia al escritorio de tu teléfono y consulta '
          'lo importante sin abrir la app. Se actualizan solos en segundo plano.',
    ),
    _TutorialPage(
      icon: Icons.insights,
      title: 'Resumen',
      body:
          'Gastos, ganancia neta, órdenes y la tasa del dólar del periodo que '
          'elijas, con un mini-gráfico de la tendencia de ventas.',
      type: HomeWidgetType.miniDashboard,
    ),
    _TutorialPage(
      icon: Icons.point_of_sale,
      title: 'Ventas / TPV',
      body:
          'En Tiempo Real o por rango de fechas: dinero total, efectivo, '
          'transferencia y egresos. Tócalo para desplegar el desglose por TPV.',
      type: HomeWidgetType.sales,
    ),
    _TutorialPage(
      icon: Icons.inventory_2,
      title: 'Seguimiento de Producto',
      body:
          'Elige un producto y verás su precio de venta, costo en CUP y USD, '
          'total vendido e inventario actual.',
      type: HomeWidgetType.product,
    ),
    _TutorialPage(
      icon: Icons.touch_app,
      title: 'Cómo añadirlos',
      body:
          'Mantén pulsado un espacio vacío de tu pantalla de inicio → Widgets → '
          'busca “Inventtia”. Arrastra el widget y elige tienda, periodo o '
          'producto en la pantalla de configuración que aparece.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pages.length - 1;

  Future<void> _pin(HomeWidgetType type) async {
    final ok = await HomeWidgetService.requestPin(type);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Confirma en el lanzador para colocar el widget.'
              : 'Tu lanzador no permite añadir widgets desde la app. '
                  'Hazlo manteniendo pulsada la pantalla de inicio.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      height: size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => _PageBody(
                page: _pages[index],
                onPin: _pages[index].type == null
                    ? null
                    : () => _pin(_pages[index].type!),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length, (index) {
              final active = index == _page;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    if (_isLast) {
                      Navigator.of(context).pop();
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Text(_isLast ? 'Entendido' : 'Siguiente'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialPage {
  const _TutorialPage({
    required this.icon,
    required this.title,
    required this.body,
    this.type,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Si está definido, la página ofrece añadir ese widget directamente.
  final HomeWidgetType? type;
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page, this.onPin});

  final _TutorialPage page;
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.info],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(page.icon, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 24),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          if (onPin != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onPin,
              icon: const Icon(Icons.add_to_home_screen),
              label: const Text('Añadir ahora'),
            ),
          ],
        ],
      ),
    );
  }
}
