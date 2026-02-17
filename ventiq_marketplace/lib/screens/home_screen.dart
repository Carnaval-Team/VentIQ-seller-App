import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/store_card.dart';
import '../widgets/product_list_card.dart';
import '../widgets/store_list_card.dart';
import '../widgets/notifications_panel.dart';
import 'product_detail_screen.dart';
import 'store_detail_screen.dart';
import 'map_screen.dart';
import '../services/product_service.dart';
import '../services/store_service.dart';
import '../services/marketplace_service.dart'; // Added for searchProducts
import '../services/user_session_service.dart';
import '../services/auth_service.dart';
import '../services/store_management_service.dart';
import '../services/changelog_service.dart';
import '../services/user_preferences_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../services/user_activity_service.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/supabase_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

/// Pantalla principal del marketplace
class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ProductService _productService = ProductService();
  final StoreService _storeService = StoreService();
  final MarketplaceService _marketplaceService =
      MarketplaceService(); // Instance for searching products
  final UserSessionService _userSessionService = UserSessionService();
  final AuthService _authService = AuthService();
  final StoreManagementService _storeManagementService =
      StoreManagementService();
  final ChangelogService _changelogService = ChangelogService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final NotificationService _notificationService = NotificationService();
  final UserActivityService _userActivityService = UserActivityService();

  List<Map<String, dynamic>> _bestSellingProducts = [];
  List<Map<String, dynamic>> _mostRecentProducts = [];
  List<Map<String, dynamic>> _featuredStores = [];

  // Access mode state
  AccessModeInfo? _accessModeInfo;
  bool _isAccessModeLoading = true;

  // Search state
  bool _isLoadingProducts = true;
  bool _isLoadingRecentProducts = true;
  bool _isLoadingStores = true;
  bool _isSearching = false;
  bool _isLoadingSearch = false;
  List<Map<String, dynamic>> _searchResultsStores = [];
  List<Map<String, dynamic>> _searchResultsProducts = [];
  Timer? _debounceTimer;

  // Banner state
  bool _showBanner = true;
  Timer? _bannerTimer;
  final GlobalKey<_MarqueeTextState> _marqueeKey =
      GlobalKey<_MarqueeTextState>();

  // Auto-scroll carousels controllers
  final ScrollController _bestSellingScrollController = ScrollController();
  final ScrollController _recentProductsScrollController = ScrollController();
  final ScrollController _storesScrollController = ScrollController();
  Timer? _bestSellingAutoScrollTimer;
  Timer? _recentProductsAutoScrollTimer;
  Timer? _storesAutoScrollTimer;
  bool _isBestSellingUserScrolling = false;
  bool _isRecentUserScrolling = false;
  bool _isStoresUserScrolling = false;

  @override
  void initState() {
    super.initState();

    _loadData();
    _startBannerTimer();
    unawaited(_initializeAccessTracking());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupDialogs();
      // Start auto-scroll after data loads
      _startAutoScrollCarousels();
    });
  }

  /// Start auto-scroll for all carousels
  void _startAutoScrollCarousels() {
    // Best selling: left to right, slow (30s full cycle)
    _startBestSellingAutoScroll();
    // Recent products: right to left for contrast
    _startRecentProductsAutoScroll();
    // Stores: left to right
    _startStoresAutoScroll();
  }

  void _startBestSellingAutoScroll() {
    _bestSellingAutoScrollTimer?.cancel();
    _bestSellingAutoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (timer) {
        if (!mounted || _isBestSellingUserScrolling) return;
        if (!_bestSellingScrollController.hasClients) return;

        final maxScroll = _bestSellingScrollController.position.maxScrollExtent;
        final currentScroll = _bestSellingScrollController.offset;

        // Slow speed: 0.5 pixels per tick
        double newOffset = currentScroll + 0.5;

        if (newOffset >= maxScroll) {
          // Smooth loop back to start
          _bestSellingScrollController.jumpTo(0);
        } else {
          _bestSellingScrollController.jumpTo(newOffset);
        }
      },
    );
  }

  void _startRecentProductsAutoScroll() {
    _recentProductsAutoScrollTimer?.cancel();

    // Wait a bit for layout to complete
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (!_recentProductsScrollController.hasClients) return;

      // Start from the end for right-to-left effect
      final maxScroll = _recentProductsScrollController.position.maxScrollExtent;
      _recentProductsScrollController.jumpTo(maxScroll);

      _recentProductsAutoScrollTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (timer) {
          if (!mounted || _isRecentUserScrolling) return;
          if (!_recentProductsScrollController.hasClients) return;

          final currentScroll = _recentProductsScrollController.offset;

          // Move right to left: subtract pixels
          double newOffset = currentScroll - 0.6;

          if (newOffset <= 0) {
            // Loop back to end
            final max = _recentProductsScrollController.position.maxScrollExtent;
            _recentProductsScrollController.jumpTo(max);
          } else {
            _recentProductsScrollController.jumpTo(newOffset);
          }
        },
      );
    });
  }

  void _startStoresAutoScroll() {
    _storesAutoScrollTimer?.cancel();
    _storesAutoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (timer) {
        if (!mounted || _isStoresUserScrolling) return;
        if (!_storesScrollController.hasClients) return;

        final maxScroll = _storesScrollController.position.maxScrollExtent;
        final currentScroll = _storesScrollController.offset;

        // Medium speed
        double newOffset = currentScroll + 0.4;

        if (newOffset >= maxScroll) {
          _storesScrollController.jumpTo(0);
        } else {
          _storesScrollController.jumpTo(newOffset);
        }
      },
    );
  }

  void _pauseBestSellingAutoScroll() {
    _isBestSellingUserScrolling = true;
    // Resume after 3 seconds of no interaction
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _isBestSellingUserScrolling = false;
    });
  }

  void _pauseRecentAutoScroll() {
    _isRecentUserScrolling = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _isRecentUserScrolling = false;
    });
  }

  void _pauseStoresAutoScroll() {
    _isStoresUserScrolling = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _isStoresUserScrolling = false;
    });
  }

  Future<void> _initializeAccessTracking() async {
    try {
      final info = await _userActivityService.registerAccess();
      if (!mounted) return;
      setState(() {
        _accessModeInfo = info;
        _isAccessModeLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAccessModeLoading = false;
      });
      print('❌ Error inicializando acceso: $e');
    }
  }

  Future<void> _refreshAccessMode({bool register = false}) async {
    if (mounted) {
      setState(() {
        _isAccessModeLoading = true;
      });
    }

    try {
      final info = register
          ? await _userActivityService.registerAccess()
          : await _userActivityService.resolveAccessMode();
      if (!mounted) return;
      setState(() {
        _accessModeInfo = info;
        _isAccessModeLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAccessModeLoading = false;
      });
      print('❌ Error actualizando acceso: $e');
    }
  }

  Future<void> _handleAccessModeAction() async {
    final info = _accessModeInfo;
    if (info?.isLoggedIn == true) {
      await _onProfilePressed();
      return;
    }

    final result = await Navigator.of(context).pushNamed('/auth');
    if (!mounted) return;
    if (result == true) {
      await _notificationService.initializeUserNotifications(force: true);
      await _refreshAccessMode(register: true);
    }
  }

  Future<void> _runStartupDialogs() async {
    await _checkForChangelog();
    if (!mounted) return;
    await _maybeShowMigrationInfo();
    if (!mounted) return;
    await _checkForUpdatesAfterNavigation();
    if (!mounted) return;
    await _notificationService.syncNotificationConsentWithSupabase();
    if (!mounted) return;
    await _maybeShowNotificationConsentPrompt();
    if (!mounted) return;
    await _notificationService.initializeUserNotifications();
  }

  Future<void> _maybeShowMigrationInfo() async {
    try {
      final shouldShow = await _preferencesService.shouldShowMigrationDialog();
      if (!shouldShow) return;
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Expanded(child: Text('Información Importante')),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estamos migrando los datos y cambiamos la app.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'Si tiene otra app con el mismo nombre es recomendable desinstalarla antes de actualizar.',
              ),
              SizedBox(height: 12),
              Text(
                'La versión estable tiene de nombre Inventtia Marketplace LTS. Las otras no tendrán más soporte y puedes eliminarlas.',
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                await _preferencesService.markMigrationDialogShown();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _onNotificationsPressed() async {
    final status = await _preferencesService.getNotificationConsentStatus();
    if (!mounted) return;

    if (status != NotificationConsentStatus.accepted) {
      await _maybeShowNotificationConsentPrompt(force: true);
      return;
    }

    final isLoggedIn = await _userSessionService.isLoggedIn();
    if (!mounted) return;

    if (!isLoggedIn) {
      final goToLogin =
          await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Iniciar sesión'),
                content: const Text(
                  'Para ver tus notificaciones necesitas iniciar sesión o registrarte.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Ir a login'),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (!goToLogin || !mounted) return;

      final result = await Navigator.of(context).pushNamed('/auth');
      if (!mounted) return;
      if (result != true) return;

      await _refreshAccessMode(register: true);
      if (!mounted) return;
    }

    await _notificationService.initializeUserNotifications(force: true);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return NotificationsPanel(notificationService: _notificationService);
      },
    );
  }

  Future<void> _maybeShowNotificationConsentPrompt({bool force = false}) async {
    try {
      final shouldShow = force
          ? (await _preferencesService.getNotificationConsentStatus() !=
                NotificationConsentStatus.accepted)
          : await _preferencesService.shouldShowNotificationConsentPrompt();
      if (!shouldShow) return;
      if (!mounted) return;

      await _preferencesService.markNotificationConsentPromptShown();

      final selected = await showDialog<NotificationConsentStatus>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Notificaciones'),
            content: const Text(
              '¿Quieres recibir notificaciones sobre novedades, productos y recomendaciones?',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(NotificationConsentStatus.never),
                child: const Text('Nunca'),
              ),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(NotificationConsentStatus.remindLater),
                child: const Text('Más tarde'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(NotificationConsentStatus.denied),
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(NotificationConsentStatus.accepted),
                child: const Text('Sí'),
              ),
            ],
          );
        },
      );

      if (!mounted || selected == null) return;

      final enabled = await _notificationService.saveNotificationConsent(
        status: selected,
      );

      if (!mounted) return;

      if (selected == NotificationConsentStatus.accepted && !enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permiso de notificaciones denegado. Puedes activarlo desde Ajustes.',
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _checkForChangelog() async {
    try {
      final changelog = await _changelogService.getLatestChangelog();
      if (changelog == null) return;

      final shouldShow = await _preferencesService.isFirstTimeOpening(
        changelog.version,
      );
      if (!shouldShow) return;

      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ChangelogDialog(changelog: changelog),
      );

      await _preferencesService.saveAppVersion(changelog.version);
    } catch (_) {}
  }

  Future<void> _checkForUpdatesAfterNavigation() async {
    await Future.delayed(const Duration(seconds: 3));

    try {
      if (!mounted) return;

      final shouldShow = await _preferencesService.shouldShowUpdateDialog();
      if (!shouldShow) return;

      final updateInfo = await UpdateService.checkForUpdates();
      if (updateInfo['hay_actualizacion'] == true && mounted) {
        await _showUpdateAvailableDialog(updateInfo);
      }
    } catch (_) {}
  }

  Future<void> _checkForUpdatesManual() async {
    try {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );

      final updateInfo = await UpdateService.checkForUpdates();

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      if (updateInfo['hay_actualizacion'] == true) {
        await _showUpdateAvailableDialog(updateInfo);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Estás en la última versión'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error buscando actualizaciones'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _showUpdateAvailableDialog(
    Map<String, dynamic> updateInfo,
  ) async {
    final bool isObligatory = updateInfo['obligatoria'] ?? false;
    final String newVersion = updateInfo['version_disponible'] ?? 'Desconocida';
    final String currentVersion =
        updateInfo['current_version'] ?? 'Desconocida';

    if (!mounted) return;

    _preferencesService.markUpdateDialogShown();

    await showDialog(
      context: context,
      barrierDismissible: !isObligatory,
      builder: (context) => WillPopScope(
        onWillPop: () async => !isObligatory,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                isObligatory ? Icons.warning : Icons.system_update,
                color: isObligatory ? Colors.orange : Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isObligatory
                      ? 'Actualización Obligatoria'
                      : 'Nueva Versión Disponible',
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nueva versión disponible: $newVersion'),
              Text('Versión actual: $currentVersion'),
              const SizedBox(height: 16),
              if (isObligatory)
                const Text(
                  'Esta actualización es obligatoria y debe instalarse para continuar usando la aplicación.',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                const Text(
                  'Se recomienda actualizar para obtener las últimas mejoras y correcciones.',
                ),
            ],
          ),
          actions: [
            if (!isObligatory)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Más tarde'),
              ),
            ElevatedButton(
              onPressed: _downloadUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: isObligatory ? Colors.orange : Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Descargar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessModeCard() {
    final info = _accessModeInfo;
    final isLoggedIn = info?.isLoggedIn ?? false;
    final accentColor = isLoggedIn
        ? AppTheme.accentColor
        : AppTheme.primaryColor;
    final title = isLoggedIn ? 'Sesión activa' : 'Modo invitado';
    final subtitle = isLoggedIn
        ? 'Estás navegando como ${info?.friendlyName ?? 'tu cuenta'}.'
        : 'Explora el catálogo sin registrarte. Inicia sesión para recibir novedades y personalizar tu experiencia.';
    final actionLabel = isLoggedIn ? 'Ver perfil' : 'Iniciar sesión';
    final badgeLabel = isLoggedIn ? 'Con cuenta' : 'Invitado';
    final tokenLabel = info == null
        ? 'Identificando acceso...'
        : 'ID: ${_shortToken(info.token)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.paddingM,
        0,
        AppTheme.paddingM,
        AppTheme.paddingS,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, accentColor.withOpacity(0.06)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(color: accentColor.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.paddingM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isLoggedIn
                          ? Icons.verified_user_rounded
                          : Icons.person_outline_rounded,
                      color: accentColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                badgeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        size: 16,
                        color: accentColor.withOpacity(0.8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tokenLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _isAccessModeLoading
                        ? null
                        : _handleAccessModeAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    icon: Icon(
                      isLoggedIn
                          ? Icons.account_circle_rounded
                          : Icons.login_rounded,
                      size: 16,
                    ),
                    label: Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (_isAccessModeLoading) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  color: accentColor,
                  backgroundColor: accentColor.withOpacity(0.15),
                  minHeight: 3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _shortToken(String token) {
    if (token.isEmpty) return token;
    if (token.length <= 10) return token;
    return '${token.substring(0, 6)}…${token.substring(token.length - 4)}';
  }

  Future<void> _downloadUpdate() async {
    try {
      final url = Uri.parse(UpdateService.downloadUrl);
      bool launched = false;

      try {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {}

      if (!launched) {
        try {
          launched = await launchUrl(url, mode: LaunchMode.inAppWebView);
        } catch (_) {}
      }

      if (!launched) {
        try {
          launched = await launchUrl(url);
        } catch (_) {}
      }

      if (launched) {
        if (mounted) Navigator.of(context).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 Descarga iniciada - Instala la nueva versión'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        _showManualDownloadDialog();
      }
    } catch (_) {
      _showManualDownloadDialog();
    }
  }

  void _showManualDownloadDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.download, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Descarga Manual',
                style: TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se pudo abrir automáticamente el enlace de descarga.',
            ),
            const SizedBox(height: 16),
            SelectableText(UpdateService.downloadUrl),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await Clipboard.setData(
                  const ClipboardData(text: UpdateService.downloadUrl),
                );
              } catch (_) {}
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Enlace copiado al portapapeles'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Copiar enlace'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _onProfilePressed() async {
    final isLoggedIn = await _userSessionService.isLoggedIn();
    if (!mounted) return;

    if (!isLoggedIn) {
      final goToLogin =
          await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Iniciar sesión'),
                content: const Text(
                  'Para continuar necesitas iniciar sesión o registrarte.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Ir a login'),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (!goToLogin || !mounted) return;

      final result = await Navigator.of(context).pushNamed('/auth');
      if (!mounted) return;
      if (result == true) {
        await _notificationService.initializeUserNotifications(force: true);
        await _refreshAccessMode(register: true);
      }
      return;
    }

    final user = await _userSessionService.getUser();
    final uuid = await _userSessionService.getUserId();
    if (!mounted) return;

    bool hasManagedStore = false;
    if (uuid != null) {
      try {
        final storeIds = await _storeManagementService.getManagedStoreIds(
          uuid: uuid,
        );
        hasManagedStore = storeIds.isNotEmpty;
      } catch (_) {
        hasManagedStore = false;
      }
    }

    final nombres = (user?['nombres'] as String?)?.trim();
    final apellidos = (user?['apellidos'] as String?)?.trim();
    final email = (user?['email'] as String?)?.trim();
    final telefono = (user?['telefono'] as String?)?.trim();

    final displayName = [
      if (nombres != null && nombres.isNotEmpty) nombres,
      if (apellidos != null && apellidos.isNotEmpty) apellidos,
    ].join(' ');

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.paddingM),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.account_circle_rounded,
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
                            displayName.isNotEmpty ? displayName : 'Mi cuenta',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (email != null && email.isNotEmpty)
                            Text(
                              email,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (telefono != null && telefono.isNotEmpty)
                            Text(
                              telefono,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(
                    hasManagedStore
                        ? 'Ir a mi tienda'
                        : 'Administrar mi tienda',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (!mounted) return;
                    await Navigator.of(context).pushNamed('/store-management');
                    if (mounted) setState(() {});
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text(
                    'Recomendados y notificaciones',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (!mounted) return;
                    await Navigator.of(context).pushNamed(
                      '/notification-hub',
                      arguments: {'initialTabIndex': 0},
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune),
                  title: const Text(
                    'Configuración de notificaciones',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (!mounted) return;
                    await Navigator.of(
                      context,
                    ).pushNamed('/notification-settings');
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text(
                    'Configuración',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (!mounted) return;
                    await Navigator.of(context).pushNamed('/settings');
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.system_update),
                  title: const Text(
                    'Buscar actualizaciones',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _checkForUpdatesManual();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppTheme.errorColor,
                  ),
                  title: const Text(
                    'Cerrar sesión',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () async {
                    try {
                      await _authService.signOut();
                    } catch (_) {}
                    try {
                      await _notificationService.clearUserNotifications();
                    } catch (_) {}
                    if (context.mounted) Navigator.of(context).pop();
                    await _refreshAccessMode(register: true);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    _bannerTimer?.cancel();
    // Dispose auto-scroll timers and controllers
    _bestSellingAutoScrollTimer?.cancel();
    _recentProductsAutoScrollTimer?.cancel();
    _storesAutoScrollTimer?.cancel();
    _bestSellingScrollController.dispose();
    _recentProductsScrollController.dispose();
    _storesScrollController.dispose();
    super.dispose();
  }

  /// Iniciar timer para mostrar/ocultar banner
  void _startBannerTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 90), (timer) {
      if (mounted) {
        setState(() {
          _showBanner = !_showBanner;
        });
      }
    });
  }

  /// Cargar datos desde Supabase
  Future<void> _loadData() async {
    await Future.wait([
      _loadBestSellingProducts(),
      _loadMostRecentProducts(),
      _loadFeaturedStores(),
    ]);
  }

  /// Cargar productos más vendidos
  Future<void> _loadBestSellingProducts() async {
    setState(() {
      _isLoadingProducts = true;
    });

    try {
      final products = await _productService.getMostSoldProducts(limit: 10);
      setState(() {
        _bestSellingProducts = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      print('❌ Error cargando productos: $e');
      setState(() {
        _isLoadingProducts = false;
      });
    }
  }

  /// Cargar productos más recientes
  Future<void> _loadMostRecentProducts() async {
    setState(() {
      _isLoadingRecentProducts = true;
    });

    try {
      final products = await _productService.getMostRecent(limit: 20);
      setState(() {
        _mostRecentProducts = products;
        _isLoadingRecentProducts = false;
      });
    } catch (e) {
      print('❌ Error cargando productos recientes: $e');
      setState(() {
        _isLoadingRecentProducts = false;
      });
    }
  }

  /// Cargar tiendas destacadas
  Future<void> _loadFeaturedStores() async {
    setState(() {
      _isLoadingStores = true;
    });

    try {
      final stores = await _storeService.getFeaturedStores(limit: 10);
      setState(() {
        _featuredStores = stores;
        _isLoadingStores = false;
      });
    } catch (e) {
      print('❌ Error cargando tiendas: $e');
      setState(() {
        _isLoadingStores = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResultsStores = [];
        _searchResultsProducts = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingSearch = true;
    });

    try {
      // Parallel execution for better performance
      final results = await Future.wait([
        _storeService.searchStores(query, limit: 10),
        _marketplaceService.searchProducts(query, limit: 20),
      ]);

      setState(() {
        _searchResultsStores = results[0];
        _searchResultsProducts = results[1];
        _isLoadingSearch = false;
      });
    } catch (e) {
      print('Error searching: $e');
      setState(() {
        _isLoadingSearch = false;
      });
    }
  }

  /// Navegar a la pantalla del mapa
  Future<void> _navigateToMap() async {
    // Mostrar loading si es necesario, o navegar directamente y cargar allá
    // Aquí cargamos antes para pasar la lista filtrada
    try {
      // Mostrar indicador de carga rápido (opcional, o usar un overlay)
      if (!mounted) return;

      // Mostrar diálogo de carga simple
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );

      final stores = await _storeService.getStoresWithLocation();

      if (!mounted) return;

      // Cerrar diálogo de carga
      Navigator.of(context).pop();

      if (stores.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay tiendas con ubicación disponible'),
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => MapScreen(stores: stores)),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop(); // Cerrar diálogo solo si está abierto
      }
      print('❌ Error navegando al mapa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar el mapa')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = AppTheme.getAccentColor(context);

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundColor(context),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: accentColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // AppBar con efecto moderno
            _buildModernAppBar(),

            // Buscador fijo (aunque scrollea con el contenido, visualmente es el primer elemento)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildSearchSection(),
              ),
            ),

            // Banner informativo sobre Carnaval App
            SliverToBoxAdapter(child: _buildCarnavalInfoBanner()),

            // Estado de acceso (invitado vs. cuenta)
            // SliverToBoxAdapter(child: _buildAccessModeCard()),

            if (_isSearching) _buildSearchResults() else _buildHomeContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppTheme.paddingM),

          // Banner promocional
          // _buildPromoBanner(),
          const SizedBox(height: AppTheme.paddingM),

          // Productos más vendidos
          _buildBestSellingProducts(),

          const SizedBox(height: AppTheme.paddingL),

          // Productos nuevos
          _buildMostRecentProducts(),

          const SizedBox(height: AppTheme.paddingL),

          // Tiendas destacadas
          _buildTopStores(),

          const SizedBox(height: AppTheme.paddingL),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isLoadingSearch) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (_searchResultsStores.isEmpty && _searchResultsProducts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No se encontraron resultados',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        if (_searchResultsStores.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Tiendas (${_searchResultsStores.length})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          ..._searchResultsStores.map(
            (store) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: StoreListCard(
                storeName: store['denominacion'] ?? store['nombre'] ?? 'Tienda',
                logoUrl: store['imagen_url'],
                ubicacion: store['ubicacion'] ?? 'Sin ubicación',
                direccion: store['direccion'] ?? 'Sin dirección',
                productCount: (store['total_productos'] as num?)?.toInt() ?? 0,
                // Add dummy values for required fields if missing
                provincia: store['provincia'] ?? '',
                municipio: store['municipio'] ?? '',
                latitude: null,
                longitude: null,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StoreDetailScreen(
                        store: {
                          'id': store['id'] ?? store['id_tienda'],
                          'nombre': store['denominacion'] ?? store['nombre'],
                          'logoUrl': store['imagen_url'],
                          'ubicacion': store['ubicacion'],
                          'direccion': store['direccion'],
                          'phone': store['phone'] ?? store['telefono'],
                        },
                      ),
                    ),
                  );
                },
                onMapTap: () {}, // Optional
              ),
            ),
          ),
        ],

        if (_searchResultsProducts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Productos (${_searchResultsProducts.length})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          ..._searchResultsProducts.map(
            (product) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ProductListCard(
                productName: product['denominacion'] ?? 'Producto',
                price:
                    (product['app_dat_precio_venta']?[0]?['precio_venta'] ??
                            product['precio_venta'] ??
                            0)
                        .toDouble(),
                imageUrl: product['imagen'],
                storeName: 'Ver detalle', // Simplify for search result
                availableStock: 0,
                showStockStatus: false,
                rating: 0,
                presentations: const [], // Detailed view handles this
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProductDetailScreen(product: product),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ]),
    );
  }

  /// AppBar moderno con SliverAppBar
  Widget _buildModernAppBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);
    return SliverAppBar(
      expandedHeight: 100.0,
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.primaryColor,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF2D2D30),
                      const Color(0xFF1A1A1D),
                      accentColor.withOpacity(0.3),
                    ]
                  : [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.85),
                      AppTheme.secondaryColor,
                    ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.paddingM,
                vertical: AppTheme.paddingXS,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(isDark ? 0.1 : 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Image.asset(
                          'assets/logo_app_no_background.png',
                          width: 46,
                          height: 46,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [
                                  Colors.white,
                                  Colors.white.withOpacity(0.9),
                                ],
                              ).createShader(bounds),
                              child: const Text(
                                'Inventtia',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Catálogo',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Notification Button
                      StreamBuilder<int>(
                        stream: _notificationService.unreadCountStream,
                        initialData: _notificationService.unreadCount,
                        builder: (context, snapshot) {
                          final unread = snapshot.data ?? 0;

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(isDark ? 0.1 : 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.notifications_outlined,
                                    size: 22,
                                  ),
                                  color: Colors.white,
                                  onPressed: _onNotificationsPressed,
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(
                                    minWidth: 38,
                                    minHeight: 38,
                                  ),
                                ),
                              ),
                              if (unread > 0)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      unread > 99 ? '99+' : '$unread',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      // Map Button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(isDark ? 0.1 : 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.map_outlined, size: 22),
                          color: Colors.white,
                          onPressed: _navigateToMap,
                          tooltip: 'Ver Mapa',
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 38,
                            minHeight: 38,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Profile Button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(isDark ? 0.1 : 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.account_circle_outlined, size: 22),
                          color: Colors.white,
                          onPressed: _onProfilePressed,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 38,
                            minHeight: 38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sección del buscador mejorada
  Widget _buildSearchSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCardBackground : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Buscar productos o tiendas...',
            hintStyle: TextStyle(
              color: isDark
                  ? AppTheme.darkTextHint
                  : AppTheme.textSecondary.withOpacity(0.6),
              fontSize: 15,
            ),
            prefixIcon: Container(
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.search_rounded,
                color: AppTheme.primaryColor,
                size: 24,
              ),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            filled: false,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusL),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  /// Banner informativo sobre Carnaval App con efecto marquee
  Widget _buildCarnavalInfoBanner() {
    if (!_showBanner) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.paddingM,
        AppTheme.paddingS,
        AppTheme.paddingM,
        AppTheme.paddingS,
      ),
      child: GestureDetector(
        onTap: () {
          // Reiniciar animación del marquee
          _marqueeKey.currentState?.resetAnimation();
        },
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.blue.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200, width: 1),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
              ),
              Expanded(
                child: _MarqueeText(
                  key: _marqueeKey,
                  textSpan: TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'Algunos de los productos que aparecen en el catálogo se pueden comprar en línea a través de Carnaval App con ',
                      ),
                      TextSpan(
                        text: 'envío a domicilio gratis',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14, // Más grande
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const TextSpan(
                        text:
                            '. El precio puede diferir por temas logísticos y de preparación hasta en un 5%. Para ir a comprar haga click en el botón rojo en la parte inferior derecha.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Banner promocional
  Widget _buildPromoBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accentColor,
              AppTheme.accentColor.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentColor.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Patrón de fondo decorativo
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -30,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            // Contenido
            Padding(
              padding: const EdgeInsets.all(AppTheme.paddingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '🎉 OFERTA ESPECIAL',
                      style: TextStyle(
                        color: AppTheme.accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '¡Descuentos de hasta\n50% en productos!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aprovecha las mejores ofertas',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sección de productos más vendidos con diseño mejorado
  Widget _buildBestSellingProducts() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);
    final cardColor = AppTheme.getCardColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [AppTheme.darkAccentColor.withOpacity(0.25), AppTheme.warningColor.withOpacity(0.15)]
                            : [AppTheme.errorColor.withOpacity(0.2), AppTheme.warningColor.withOpacity(0.2)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      color: isDark ? AppTheme.darkAccentColor : AppTheme.errorColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Más Vendidos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'Los favoritos del momento',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextButton(
                  onPressed: () {
                    widget.onNavigateToTab?.call(2);
                  },
                  child: Row(
                    children: [
                      Text(
                        'Ver todos',
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: accentColor,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.paddingM),
        SizedBox(
          height: 275,
          child: _isLoadingProducts
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: accentColor),
                      const SizedBox(height: 12),
                      Text(
                        'Cargando productos...',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : _bestSellingProducts.isEmpty
              ? Center(
                  child: Container(
                    margin: const EdgeInsets.all(AppTheme.paddingM),
                    padding: const EdgeInsets.all(AppTheme.paddingL),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(AppTheme.radiusL),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: textSecondary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No hay productos disponibles',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification) {
                      _pauseBestSellingAutoScroll();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _bestSellingScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.paddingM,
                    ),
                    itemCount: _bestSellingProducts.length,
                    itemBuilder: (context, index) {
                      final product = _bestSellingProducts[index];

                      return Padding(
                        padding: const EdgeInsets.only(right: AppTheme.paddingM),
                        child: _AnimatedProductCard(
                          index: index,
                          child: ProductCard(
                            productName:
                                product['nombre'] as String? ?? 'Sin nombre',
                            price:
                                (product['precio_venta'] as num?)?.toDouble() ??
                                0.0,
                            category:
                                product['categoria_nombre'] as String? ??
                                'Sin categoría',
                            imageUrl: product['imagen'] as String?,
                            storeName:
                                product['tienda_nombre'] as String? ?? 'Tienda',
                            rating:
                                (product['rating_promedio'] as num?)?.toDouble() ??
                                0.0,
                            salesCount:
                                (product['total_vendido'] as num?)?.toInt() ?? 0,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ProductDetailScreen(product: product),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// Sección de productos nuevos con carrusel compacto
  Widget _buildMostRecentProducts() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);
    final cardColor = AppTheme.getCardColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [AppTheme.darkAccentColor.withOpacity(0.2), AppTheme.darkAccentColorLight.withOpacity(0.15)]
                            : [AppTheme.primaryColor.withOpacity(0.18), AppTheme.accentColor.withOpacity(0.18)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nuevos productos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'Lo más reciente en el catálogo',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextButton(
                  onPressed: () {
                    widget.onNavigateToTab?.call(2);
                  },
                  child: Row(
                    children: [
                      Text(
                        'Ver más',
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: accentColor,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.paddingM),
        SizedBox(
          height: 165,
          child: _isLoadingRecentProducts
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: accentColor),
                      const SizedBox(height: 12),
                      Text(
                        'Cargando novedades...',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : _mostRecentProducts.isEmpty
              ? Center(
                  child: Container(
                    margin: const EdgeInsets.all(AppTheme.paddingM),
                    padding: const EdgeInsets.all(AppTheme.paddingL),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(AppTheme.radiusL),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.new_releases_outlined,
                          size: 48,
                          color: textSecondary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Aún no hay productos nuevos',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth =
                        constraints.maxWidth - (AppTheme.paddingM * 2);
                    final double cardWidth = (availableWidth * 0.92)
                        .clamp(260.0, 360.0)
                        .toDouble();

                    return Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollStartNotification) {
                              _pauseRecentAutoScroll();
                            }
                            return false;
                          },
                          child: ListView.separated(
                            controller: _recentProductsScrollController,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.paddingM,
                            ),
                            itemCount: _mostRecentProducts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final product = _mostRecentProducts[index];
                              return SizedBox(
                                width: cardWidth,
                                child: _AnimatedProductCard(
                                  index: index,
                                  child: _buildMostRecentProductCard(product),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_mostRecentProducts.length > 1)
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                width: 46,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      AppTheme.getBackgroundColor(context).withOpacity(0),
                                      AppTheme.getBackgroundColor(context),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_mostRecentProducts.length > 1)
                          Positioned(
                            right: 14,
                            top: 0,
                            bottom: 0,
                            child: Align(
                              alignment: Alignment.center,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: cardColor.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.2),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMostRecentProductCard(Map<String, dynamic> product) {
    final String name =
        (product['nombre'] ?? product['denominacion'] ?? 'Producto').toString();
    final String category = (product['categoria_nombre'] ?? 'Categoría')
        .toString();
    final String storeName =
        (product['tienda_nombre'] ?? product['store'] ?? 'Tienda').toString();
    final String? imageUrl = product['imagen']?.toString();
    final double price = _parseDouble(product['precio_venta']);
    final double offerPrice = _parseDouble(product['precio_oferta']);
    final bool hasOffer =
        product['tiene_oferta'] == true && offerPrice > 0 && offerPrice < price;
    final double rating = _parseDouble(product['rating_promedio']);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppTheme.getCardColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final priceColor = AppTheme.getPriceColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(product: product),
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            border: Border.all(
              color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            child: Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          imageUrl != null && imageUrl.isNotEmpty
                              ? SupabaseImage(
                                  imageUrl: imageUrl,
                                  width: 130,
                                  height: 165,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: isDark ? AppTheme.darkSurfaceColor : Colors.grey[100],
                                  child: Center(
                                    child: Icon(
                                      Icons.shopping_bag_outlined,
                                      size: 38,
                                      color: isDark ? AppTheme.darkTextHint : Colors.grey[400],
                                    ),
                                  ),
                                ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: _buildCategoryBadge(category),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildStoreChip(storeName),
                            const Spacer(),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: priceColor.withOpacity(isDark ? 0.15 : 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '\$${(hasOffer ? offerPrice : price).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: priceColor,
                                      ),
                                    ),
                                  ),
                                  if (hasOffer) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '\$${price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: textSecondary,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(top: 8, right: 8, child: _buildRecentRating(rating)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreChip(String storeName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.store_rounded,
            size: 12,
            color: accentColor,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              storeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge(String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 110),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [AppTheme.darkAccentColor, AppTheme.darkAccentColorDark]
                : [AppTheme.primaryColor, AppTheme.primaryColor.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          category,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildRecentRating(double rating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.warningColor.withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            size: 12,
            color: AppTheme.warningColor,
          ),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.warningColor,
            ),
          ),
        ],
      ),
    );
  }

  double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Sección de tiendas destacadas con diseño mejorado
  Widget _buildTopStores() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);
    final cardColor = AppTheme.getCardColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.warningColor.withOpacity(isDark ? 0.25 : 0.2),
                          AppTheme.warningColor.withOpacity(isDark ? 0.15 : 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.store_rounded,
                      color: AppTheme.warningColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tiendas Destacadas',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'Las mejores valoradas',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(isDark ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextButton(
                  onPressed: () {
                    widget.onNavigateToTab?.call(1);
                  },
                  child: Row(
                    children: [
                      Text(
                        'Ver todas',
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: accentColor,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.paddingM),
        SizedBox(
          height: 210,
          child: _isLoadingStores
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: accentColor),
                      const SizedBox(height: 12),
                      Text(
                        'Cargando tiendas...',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : _featuredStores.isEmpty
              ? Center(
                  child: Container(
                    margin: const EdgeInsets.all(AppTheme.paddingM),
                    padding: const EdgeInsets.all(AppTheme.paddingL),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(AppTheme.radiusL),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.store_mall_directory_outlined,
                          size: 48,
                          color: textSecondary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No hay tiendas disponibles',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification) {
                      _pauseStoresAutoScroll();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _storesScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.paddingM,
                    ),
                    itemCount: _featuredStores.length,
                    itemBuilder: (context, index) {
                      final store = _featuredStores[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: AppTheme.paddingM),
                        child: _AnimatedStoreCard(
                          index: index,
                          child: StoreCard(
                            storeName: store['nombre'] as String? ?? 'Tienda',
                            productCount:
                                (store['total_productos'] as num?)?.toInt() ?? 0,
                            salesCount:
                                (store['total_ventas'] as num?)?.toInt() ?? 0,
                            rating:
                                (store['rating_promedio'] as num?)?.toDouble() ??
                                0.0,
                            logoUrl: store['imagen_url'] as String?,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => StoreDetailScreen(
                                    store: {
                                      'id': store['id_tienda'],
                                      'nombre': store['nombre'],
                                      'logoUrl': store['imagen_url'],
                                      'ubicacion':
                                          store['ubicacion'] ?? 'Sin ubicación',
                                      'provincia': 'Santo Domingo',
                                      'municipio': 'Santo Domingo Este',
                                      'direccion':
                                          store['direccion'] ?? 'Sin dirección',
                                      'phone': store['phone'] ?? store['telefono'],
                                      'productCount': store['total_productos'],
                                      'latitude': 18.4861,
                                      'longitude': -69.9312,
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// Widget de texto con efecto marquee (desplazamiento horizontal)
/// Widget de texto con efecto marquee (desplazamiento horizontal)
class _MarqueeText extends StatefulWidget {
  final TextSpan textSpan;

  const _MarqueeText({super.key, required this.textSpan});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late Timer _timer;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Iniciar animación después de un pequeño delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _startScrolling();
      }
    });
  }

  void resetAnimation() {
    _offset = 0;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _startScrolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || !_scrollController.hasClients) {
        timer.cancel();
        return;
      }

      _offset += 1.5;

      // Si llegamos al final, volver al inicio
      if (_offset >= _scrollController.position.maxScrollExtent) {
        _offset = 0;
      }

      _scrollController.jumpTo(_offset);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        children: [
          Text.rich(widget.textSpan),
          const SizedBox(width: 100), // Espacio antes de repetir
          Text.rich(widget.textSpan),
        ],
      ),
    );
  }
}

/// Animated product card with entrance animation and scale on tap
class _AnimatedProductCard extends StatefulWidget {
  final Widget child;
  final int index;

  const _AnimatedProductCard({
    required this.child,
    required this.index,
  });

  @override
  State<_AnimatedProductCard> createState() => _AnimatedProductCardState();
}

class _AnimatedProductCardState extends State<_AnimatedProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400 + (widget.index * 100).clamp(0, 300)),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Transform.scale(
              scale: _scaleAnimation.value * (_isPressed ? 0.95 : 1.0),
              child: GestureDetector(
                onTapDown: (_) => setState(() => _isPressed = true),
                onTapUp: (_) => setState(() => _isPressed = false),
                onTapCancel: () => setState(() => _isPressed = false),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Animated store card with entrance animation
class _AnimatedStoreCard extends StatefulWidget {
  final Widget child;
  final int index;

  const _AnimatedStoreCard({
    required this.child,
    required this.index,
  });

  @override
  State<_AnimatedStoreCard> createState() => _AnimatedStoreCardState();
}

class _AnimatedStoreCardState extends State<_AnimatedStoreCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500 + (widget.index * 80).clamp(0, 400)),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Transform.scale(
            scale: _scaleAnimation.value * (_isPressed ? 0.96 : 1.0),
            child: GestureDetector(
              onTapDown: (_) => setState(() => _isPressed = true),
              onTapUp: (_) => setState(() => _isPressed = false),
              onTapCancel: () => setState(() => _isPressed = false),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

/// Pulsing badge widget for offers/discounts - adds attention-grabbing effect
class PulsingBadge extends StatefulWidget {
  final Widget child;
  final Color? pulseColor;
  final bool enabled;

  const PulsingBadge({
    super.key,
    required this.child,
    this.pulseColor,
    this.enabled = true,
  });

  @override
  State<PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<PulsingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _animation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: widget.child,
        );
      },
    );
  }
}

/// Shimmer effect widget for loading states
class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Animated counter widget that counts up when appearing
class AnimatedCounter extends StatefulWidget {
  final int value;
  final TextStyle? style;
  final String? prefix;
  final String? suffix;
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.prefix,
    this.suffix,
    this.duration = const Duration(milliseconds: 1000),
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween<double>(begin: 0, end: widget.value.toDouble()).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.value.toDouble(),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          '${widget.prefix ?? ''}${_animation.value.toInt()}${widget.suffix ?? ''}',
          style: widget.style,
        );
      },
    );
  }
}

/// Glowing "NEW" badge for fresh products
class GlowingNewBadge extends StatefulWidget {
  final String text;

  const GlowingNewBadge({
    super.key,
    this.text = 'NUEVO',
  });

  @override
  State<GlowingNewBadge> createState() => _GlowingNewBadgeState();
}

class _GlowingNewBadgeState extends State<GlowingNewBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.successColor,
                AppTheme.successColor.withOpacity(_glowAnimation.value),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppTheme.successColor.withOpacity(0.4 * _glowAnimation.value),
                blurRadius: 8 * _glowAnimation.value,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            widget.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        );
      },
    );
  }
}
