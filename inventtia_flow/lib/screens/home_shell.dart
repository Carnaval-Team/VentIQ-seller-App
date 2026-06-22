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

  // GlobalKeys para poder llamar reload() en las pantallas con IndexedStack
  final GlobalKey<MisListasScreenState> _misListasKey =
      GlobalKey<MisListasScreenState>();
  final GlobalKey<MisTicketsScreenState> _misTicketsKey =
      GlobalKey<MisTicketsScreenState>();

  late final List<Widget> _screens;
  late final List<Widget> _screensNoAdmin;

  // Índice de tab → tipo de pantalla a refrescar
  // Admin:    0=Catalogo 1=MisListas 2=MisTickets 3=Gestion 4=Perfil
  // No admin: 0=Catalogo 1=MisListas 2=MisTickets 3=Perfil
  static const int _idxListasAdmin = 1;
  static const int _idxTicketsAdmin = 2;
  static const int _idxListasNoAdmin = 1;
  static const int _idxTicketsNoAdmin = 2;

  @override
  void initState() {
    super.initState();
    _screens = [
      const CatalogoScreen(),
      MisListasScreen(key: _misListasKey),
      MisTicketsScreen(key: _misTicketsKey),
      const GestionScreen(),
      const PerfilScreen(),
    ];
    _screensNoAdmin = [
      const CatalogoScreen(),
      MisListasScreen(key: _misListasKey),
      MisTicketsScreen(key: _misTicketsKey),
      const PerfilScreen(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uuid = context.read<AuthProvider>().user?.id;
      if (uuid != null) {
        context.read<EntidadProvider>().cargarMisEntidades(uuid);
      }
    });
  }

  void _onTabSelected(int i, bool isAdmin) {
    final idxListas = isAdmin ? _idxListasAdmin : _idxListasNoAdmin;
    final idxTickets = isAdmin ? _idxTicketsAdmin : _idxTicketsNoAdmin;
    if (i == idxListas) _misListasKey.currentState?.reload();
    if (i == idxTickets) _misTicketsKey.currentState?.reload();
    setState(() => _currentIndex = i);
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
        onDestinationSelected: (i) => _onTabSelected(i, isAdmin),
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
