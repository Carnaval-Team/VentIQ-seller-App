import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/entidad_provider.dart';
import '../providers/favoritos_provider.dart';
import '../providers/reservas_provider.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import 'catalogo_screen.dart';
import 'home_client_screen.dart';
import 'mis_listas_screen.dart';
import 'mis_tickets_screen.dart';
import 'perfil_screen.dart';
import 'admin/gestion_screen.dart';
import 'vendedor/vendedor_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  bool _isInitialLoading = true;
  bool _redirectingToLogin = false;

  // GlobalKeys para poder llamar reload() en las pantallas con IndexedStack
  final GlobalKey<HomeClientScreenState> _homeKey =
      GlobalKey<HomeClientScreenState>();
  final GlobalKey<CatalogoScreenState> _catalogoKey =
      GlobalKey<CatalogoScreenState>();
  final GlobalKey<MisListasScreenState> _misListasKey =
      GlobalKey<MisListasScreenState>();
  final GlobalKey<MisTicketsScreenState> _misTicketsKey =
      GlobalKey<MisTicketsScreenState>();
  // Perfil con acceso por clave: "Publica tu negocio" salta a "Registrar
  // Entidad" dentro de esta pestaña.
  final GlobalKey<PerfilScreenState> _perfilKey =
      GlobalKey<PerfilScreenState>();

  late final List<Widget> _screens;
  late final List<Widget> _screensNoAdmin;
  late final List<Widget> _screensVendedor;
  late final List<Widget> _screensVendedorAdmin;

  // Índice de tab → tipo de pantalla a refrescar
  // Cliente: 0=Home 1=Catálogo 2=MisListas 3=MisTickets 4=Perfil
  // Admin y vendedor conservan sus índices/flujo actuales.
  static const int _idxListasAdmin = 1;
  static const int _idxTicketsAdmin = 2;
  static const int _idxListasNoAdmin = 2;
  static const int _idxTicketsNoAdmin = 3;

  @override
  void initState() {
    super.initState();
    _screens = [const GestionScreen(), const PerfilScreen()];
    _screensNoAdmin = [
      HomeClientScreen(
        key: _homeKey,
        // "Ver todo" de servicios abre la lista completa del catálogo.
        onVerCatalogo: _abrirCatalogoServicios,
        // "Publica tu negocio" lleva al perfil, a "Registrar Entidad".
        onPublicarNegocio: _abrirRegistrarEntidad,
        // Tocar un establecimiento abre el catálogo filtrado por ese local.
        onVerEstablecimiento: _abrirCatalogoDeEstablecimiento,
      ),
      CatalogoScreen(key: _catalogoKey),
      MisListasScreen(key: _misListasKey),
      MisTicketsScreen(key: _misTicketsKey),
      PerfilScreen(key: _perfilKey),
    ];
    _screensVendedor = [
      MisTicketsScreen(key: _misTicketsKey),
      const PerfilScreen(),
    ];
    _screensVendedorAdmin = [
      MisTicketsScreen(key: _misTicketsKey),
      const GestionScreen(),
      const PerfilScreen(),
    ];

    // Load entities immediately to prevent UI flash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) {
      if (!mounted) return;
      context.read<EntidadProvider>().limpiar();
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }
    await context.read<EntidadProvider>().cargarMisEntidades(uuid);
    if (mounted) {
      setState(() {
        _isInitialLoading = false;
      });
    }
    _checkForUpdatesAfterNavigation();
  }

  void _redirectToLoginIfSignedOut() {
    if (!mounted || _redirectingToLogin) return;
    _redirectingToLogin = true;
    context.read<EntidadProvider>().limpiar();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  static const String _lastUpdateDialogKey = 'flow_last_update_dialog';
  static const int _updateDialogIntervalHours = 3;

  Future<bool> _shouldShowUpdateDialog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTs = prefs.getInt(_lastUpdateDialogKey);
      if (lastTs == null) return true;
      final diff = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastTs),
      );
      return diff.inHours >= _updateDialogIntervalHours;
    } catch (_) {
      return true;
    }
  }

  Future<void> _markUpdateDialogShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _lastUpdateDialogKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<void> _checkForUpdatesAfterNavigation() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    try {
      final shouldShow = await _shouldShowUpdateDialog();
      if (!shouldShow) {
        print('[flow] HomeShell → diálogo de actualización omitido (throttle)');
        return;
      }
      final updateInfo = await UpdateService.checkForUpdates();
      if (updateInfo['hay_actualizacion'] == true && mounted) {
        _showUpdateAvailableDialog(updateInfo);
      }
    } catch (e) {
      print('[flow] HomeShell._checkForUpdatesAfterNavigation ERROR: $e');
    }
  }

  void _showUpdateAvailableDialog(Map<String, dynamic> updateInfo) {
    if (!mounted) return;
    final bool isObligatory = updateInfo['obligatoria'] ?? false;
    final String newVersion = updateInfo['version_disponible'] ?? 'Desconocida';
    final String currentVersion =
        updateInfo['current_version'] ?? 'Desconocida';

    _markUpdateDialogShown();

    showDialog(
      context: context,
      barrierDismissible: !isObligatory,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => !isObligatory,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                isObligatory
                    ? Icons.warning_amber_rounded
                    : Icons.system_update,
                color: isObligatory ? Colors.orange : AppTheme.primary,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isObligatory
                      ? 'Actualización obligatoria'
                      : 'Nueva versión disponible',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _UpdateInfoRow(
                label: 'Versión disponible',
                value: newVersion,
                highlight: true,
              ),
              const SizedBox(height: 6),
              _UpdateInfoRow(label: 'Versión actual', value: currentVersion),
              const SizedBox(height: 16),
              Text(
                isObligatory
                    ? 'Esta actualización es obligatoria y debe instalarse para continuar usando la aplicación.'
                    : 'Se recomienda actualizar para obtener las últimas mejoras y correcciones.',
                style: TextStyle(
                  color: isObligatory
                      ? Colors.orange.shade800
                      : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: isObligatory
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
          actions: [
            if (!isObligatory)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Más tarde'),
              ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Descargar'),
              onPressed: () => _downloadUpdate(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: isObligatory
                    ? Colors.orange
                    : AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadUpdate(BuildContext dialogCtx) async {
    final Uri url = Uri.parse(UpdateService.downloadUrl);
    bool launched = false;
    try {
      launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!launched) {
      try {
        launched = await launchUrl(url);
      } catch (_) {}
    }
    if (launched) {
      if (mounted) Navigator.of(dialogCtx).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Descarga iniciada — instala la nueva versión'),
            backgroundColor: AppTheme.primary,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else {
      _showManualDownloadDialog(dialogCtx);
    }
  }

  void _showManualDownloadDialog(BuildContext parentCtx) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.link, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('Descarga manual', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se pudo abrir el enlace automáticamente.\nCópialo y ábrelo en tu navegador:',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                UpdateService.downloadUrl,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(parentCtx).pop();
            },
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Abre la pestaña de Servicios (catálogo) desde el Home.
  ///
  /// Es el destino de "Ver todo" en la sección de servicios disponibles: la
  /// lista completa, no el carrusel del Home.
  void _abrirCatalogoServicios() {
    if (!mounted) return;
    setState(() => _currentIndex = 1);
    _catalogoKey.currentState?.reload();
  }

  /// Abre el catálogo **filtrado por un establecimiento** desde el Home.
  ///
  /// Es el destino de tocar una tarjeta de "Establecimientos": se ve todo lo que
  /// publica ese local, no el detalle del primer servicio que aparezca.
  void _abrirCatalogoDeEstablecimiento(int idLocal, String nombreLocal) {
    if (!mounted) return;
    setState(() => _currentIndex = 1);
    // El filtro se aplica después de cambiar de pestaña: así la lista ya está
    // montada y el estado del catálogo no se pierde por el orden de los frames.
    _catalogoKey.currentState?.filtrarPorLocal(idLocal, nombreLocal);
  }

  /// Lleva al perfil y desplaza hasta la sección "Registrar Entidad".
  ///
  /// Es el destino de "Publica tu negocio": publicar se hace registrando una
  /// entidad, así que el atajo debe dejar esa sección a la vista.
  void _abrirRegistrarEntidad() {
    if (!mounted) return;
    setState(() => _currentIndex = _screensNoAdmin.length - 1);
    // La pestaña ya está montada (IndexedStack), pero el desplazamiento se pide
    // un frame después para que el perfil esté visible y con layout hecho.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _perfilKey.currentState?.irARegistrarEntidad();
    });
  }

  void _onTabSelected(int i, bool isAdmin) {
    if (!isAdmin) {
      final idxListas = _idxListasNoAdmin;
      final idxTickets = _idxTicketsNoAdmin;
      if (i == 0) {
        _homeKey.currentState?.reload();
        // Los favoritos se quitan también desde su propia pantalla: al volver
        // al Home hay que reconciliar los corazones.
        context.read<FavoritosProvider>().recargar();
      }
      if (i == 1) _catalogoKey.currentState?.reload();
      if (i == idxListas) _misListasKey.currentState?.reload();
      if (i == idxTickets) {
        _misTicketsKey.currentState?.reload();
        // Al entrar a Reservas el contador del badge se recalcula.
        context.read<ReservasProvider>().recargar();
      }
    }
    // Admin users don't need to reload catalog, listas, or tickets since they don't have those screens
    setState(() => _currentIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final entidadProvider = context.watch<EntidadProvider>();
    final isAdmin = entidadProvider.isAdmin;
    final isVendedor = entidadProvider.isVendedor;

    // Tras actualizar la web / expirar sesión, AuthProvider limpia el user
    // pero nadie navegaba a login → home en blanco o spinner eterno.
    if (!auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redirectToLoginIfSignedOut();
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Show loading indicator during initial data loading
    if (_isInitialLoading || entidadProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<Widget> screens;
    if (isAdmin && isVendedor) {
      screens = _screensVendedorAdmin;
    } else if (isAdmin) {
      screens = _screens;
    } else if (isVendedor) {
      screens = _screensVendedor;
    } else {
      screens = _screensNoAdmin;
    }

    // Badge real: reservas en estado "Reservado" del usuario.
    final pendientes = context.select<ReservasProvider, int>(
      (p) => p.pendientes,
    );

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
          // Admin+Vendedor: Reservas primero (misma orden que _screensVendedorAdmin)
          if (isAdmin && isVendedor)
            const NavigationDestination(
              icon: Icon(Icons.confirmation_number_outlined),
              selectedIcon: Icon(
                Icons.confirmation_number,
                color: AppTheme.primary,
              ),
              label: 'Reservas',
            ),
          if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.business_outlined),
              selectedIcon: Icon(Icons.business, color: AppTheme.primary),
              label: 'Admin',
            ),
          if (!isAdmin && !isVendedor)
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppTheme.primary),
              label: 'Inicio',
            ),
          if (!isAdmin && !isVendedor)
            const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view, color: AppTheme.primary),
              label: 'Servicios',
            ),
          if (!isAdmin && !isVendedor)
            const NavigationDestination(
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt, color: AppTheme.primary),
              label: 'Mis Listas',
            ),
          if (!isAdmin)
            NavigationDestination(
              icon: _ReservationNavIcon(
                pendientes: pendientes,
                showBadge: !isVendedor,
              ),
              selectedIcon: _ReservationNavIcon(
                pendientes: pendientes,
                showBadge: !isVendedor,
                selected: true,
              ),
              label: 'Reservas',
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

class _ReservationNavIcon extends StatelessWidget {
  final bool showBadge;
  final bool selected;

  /// Reservas activas del usuario. El badge solo aparece si hay alguna.
  final int pendientes;

  const _ReservationNavIcon({
    this.showBadge = false,
    this.selected = false,
    this.pendientes = 0,
  });

  @override
  Widget build(BuildContext context) {
    final mostrar = showBadge && pendientes > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          selected
              ? Icons.confirmation_number
              : Icons.confirmation_number_outlined,
          color: selected ? AppTheme.primary : null,
        ),
        if (mostrar)
          Positioned(
            right: -8,
            top: -7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 15),
              decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Center(
                child: Text(
                  pendientes > 99 ? '99+' : '$pendientes',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _UpdateInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _UpdateInfoRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 15 : 13,
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              color: highlight ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
