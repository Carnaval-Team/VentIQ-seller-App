import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/entidad_provider.dart';
import '../services/update_service.dart';
import 'catalogo_screen.dart';
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

  // GlobalKeys para poder llamar reload() en las pantallas con IndexedStack
  final GlobalKey<CatalogoScreenState> _catalogoKey =
      GlobalKey<CatalogoScreenState>();
  final GlobalKey<MisListasScreenState> _misListasKey =
      GlobalKey<MisListasScreenState>();
  final GlobalKey<MisTicketsScreenState> _misTicketsKey =
      GlobalKey<MisTicketsScreenState>();

  late final List<Widget> _screens;
  late final List<Widget> _screensNoAdmin;
  late final List<Widget> _screensVendedor;
  late final List<Widget> _screensVendedorAdmin;

  // Índice de tab → tipo de pantalla a refrescar
  // Admin:           0=Catalogo 1=MisListas 2=MisTickets 3=Gestion 4=Perfil
  // No admin:        0=Catalogo 1=MisListas 2=MisTickets 3=Perfil
  // Vendedor:        0=Catalogo 1=MisListas 2=MisTickets 3=Vendedor 4=Perfil
  // Admin+Vendedor:  0=Catalogo 1=MisListas 2=MisTickets 3=Gestion 4=Vendedor 5=Perfil
  static const int _idxListasAdmin = 1;
  static const int _idxTicketsAdmin = 2;
  static const int _idxListasNoAdmin = 1;
  static const int _idxTicketsNoAdmin = 2;

  @override
  void initState() {
    super.initState();
    _screens = [
      const GestionScreen(),
      const PerfilScreen(),
    ];
    _screensNoAdmin = [
      CatalogoScreen(key: _catalogoKey),
      MisListasScreen(key: _misListasKey),
      MisTicketsScreen(key: _misTicketsKey),
      const PerfilScreen(),
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
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid != null) {
      await context.read<EntidadProvider>().cargarMisEntidades(uuid);
    }
    if (mounted) {
      setState(() {
        _isInitialLoading = false;
      });
    }
    _checkForUpdatesAfterNavigation();
  }

  static const String _lastUpdateDialogKey = 'flow_last_update_dialog';
  static const int _updateDialogIntervalHours = 3;

  Future<bool> _shouldShowUpdateDialog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTs = prefs.getInt(_lastUpdateDialogKey);
      if (lastTs == null) return true;
      final diff = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastTs));
      return diff.inHours >= _updateDialogIntervalHours;
    } catch (_) {
      return true;
    }
  }

  Future<void> _markUpdateDialogShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _lastUpdateDialogKey, DateTime.now().millisecondsSinceEpoch);
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
    final String newVersion =
        updateInfo['version_disponible'] ?? 'Desconocida';
    final String currentVersion =
        updateInfo['current_version'] ?? 'Desconocida';

    _markUpdateDialogShown();

    showDialog(
      context: context,
      barrierDismissible: !isObligatory,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => !isObligatory,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                isObligatory ? Icons.warning_amber_rounded : Icons.system_update,
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
                      fontSize: 16, fontWeight: FontWeight.bold),
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
                  label: 'Versión disponible', value: newVersion, highlight: true),
              const SizedBox(height: 6),
              _UpdateInfoRow(
                  label: 'Versión actual', value: currentVersion),
              const SizedBox(height: 16),
              Text(
                isObligatory
                    ? 'Esta actualización es obligatoria y debe instalarse para continuar usando la aplicación.'
                    : 'Se recomienda actualizar para obtener las últimas mejoras y correcciones.',
                style: TextStyle(
                  color: isObligatory ? Colors.orange.shade800 : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: isObligatory ? FontWeight.w500 : FontWeight.normal,
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
                backgroundColor:
                    isObligatory ? Colors.orange : AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
      launched =
          await launchUrl(url, mode: LaunchMode.externalApplication);
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
            const Text('No se pudo abrir el enlace automáticamente.\nCópialo y ábrelo en tu navegador:'),
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

  void _onTabSelected(int i, bool isAdmin) {
    if (!isAdmin) {
      final idxListas = _idxListasNoAdmin;
      final idxTickets = _idxTicketsNoAdmin;
      if (i == 0) _catalogoKey.currentState?.reload();
      if (i == idxListas) _misListasKey.currentState?.reload();
      if (i == idxTickets) _misTicketsKey.currentState?.reload();
    }
    // Admin users don't need to reload catalog, listas, or tickets since they don't have those screens
    setState(() => _currentIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final entidadProvider = context.watch<EntidadProvider>();
    final isAdmin = entidadProvider.isAdmin;
    final isVendedor = entidadProvider.isVendedor;

    // Show loading indicator during initial data loading
    if (_isInitialLoading || entidadProvider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
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
          if (isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.business_outlined),
              selectedIcon: Icon(Icons.business, color: AppTheme.primary),
              label: 'Admin',
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
            const NavigationDestination(
              icon: Icon(Icons.confirmation_number_outlined),
              selectedIcon:
                  Icon(Icons.confirmation_number, color: AppTheme.primary),
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
          style: const TextStyle(
              fontSize: 13, color: AppTheme.textSecondary),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 15 : 13,
              fontWeight:
                  highlight ? FontWeight.bold : FontWeight.w500,
              color: highlight ? AppTheme.primary : AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
