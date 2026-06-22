import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/entidad_provider.dart';
import 'catalogo_screen.dart';
import 'mis_listas_screen.dart';
import 'mis_tickets_screen.dart';
import 'perfil_screen.dart';
import 'admin/gestion_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    CatalogoScreen(),
    MisListasScreen(),
    MisTicketsScreen(),
    GestionScreen(),
    PerfilScreen(),
  ];

  static const List<Widget> _screensNoAdmin = [
    CatalogoScreen(),
    MisListasScreen(),
    MisTicketsScreen(),
    PerfilScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uuid = context.read<AuthProvider>().user?.id;
      if (uuid != null) {
        context.read<EntidadProvider>().cargarMisEntidades(uuid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entidadProvider = context.watch<EntidadProvider>();
    final isAdmin = entidadProvider.isAdmin;
    final screens = isAdmin ? _screens : _screensNoAdmin;

    // Mantener índice válido si el rol cambia
    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    return Scaffold(
      body: IndexedStack(index: safeIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.primary.withOpacity(0.12),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: AppTheme.primary),
            label: 'Servicios',
          ),
          const NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt, color: AppTheme.primary),
            label: 'Mis Listas',
          ),
          const NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon:
                Icon(Icons.confirmation_number, color: AppTheme.primary),
            label: 'Reservas',
          ),
          if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.business_outlined),
              selectedIcon: Icon(Icons.business, color: AppTheme.primary),
              label: 'Admin',
            ),
          const NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person, color: AppTheme.primary),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
