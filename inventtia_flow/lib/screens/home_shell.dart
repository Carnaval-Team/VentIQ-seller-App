import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/entidad_provider.dart';
import '../providers/favoritos_provider.dart';
import '../providers/modo_vista_provider.dart';
import '../providers/reservas_provider.dart';
import '../providers/suscripcion_provider.dart';
import '../services/auth_service.dart';
import '../services/tutorial_service.dart';
import '../services/update_service.dart';
import '../tutorial/tutorial_destino.dart';
import '../tutorial/tutorial_flujos.dart';
import '../tutorial/tutorial_navegacion.dart';
import '../utils/modo_vista.dart';
import '../utils/shell_navegacion.dart';
import '../widgets/aviso_suscripcion.dart';
import '../widgets/barra_navegacion_cliente.dart';
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

  /// El tutorial de primer uso se intenta lanzar una sola vez por sesión de
  /// shell; es el `TutorialService` el que recuerda si ya se vio (o se saltó).
  bool _tutorialRevisado = false;

  /// Si el admin está viendo la app como cliente. Lo leen también las pantallas
  /// que cambian de contenido según el rol (Perfil), por eso es un provider.
  final ModoVistaProvider _modo = ModoVistaProvider();

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

  /// Pestaña del catálogo en el shell del cliente (`_screensNoAdmin`). El
  /// tutorial la necesita para llevar al cliente al listado de servicios.
  static const int _idxCatalogoCliente = 1;

  @override
  void initState() {
    super.initState();
    _screens = [
      // «Ver como cliente»: el admin sale de Gestión para ver la app con los
      // ojos de un cliente y puede volver (la vuelta está en el Home y en
      // Perfil). Los dos accesos pasan por `_verComoCliente`, que además deja la
      // pestaña correcta.
      GestionScreen(onVerComoCliente: _verComoCliente),
      PerfilScreen(onVerComoCliente: _verComoCliente),
    ];
    _screensNoAdmin = [
      HomeClientScreen(
        key: _homeKey,
        // "Ver todo" de servicios abre la lista completa del catálogo.
        onVerCatalogo: _abrirCatalogoServicios,
        // "Publica tu negocio" lleva al perfil, a "Registrar Entidad".
        onPublicarNegocio: _abrirRegistrarEntidad,
        // Vuelta al panel de administración. La pantalla solo enseña el acceso
        // si el usuario administra algo (un cliente puro nunca lo ve).
        onVerAdmin: _volverAlAdmin,
      ),
      CatalogoScreen(key: _catalogoKey),
      MisListasScreen(key: _misListasKey),
      MisTicketsScreen(key: _misTicketsKey),
      PerfilScreen(
        key: _perfilKey,
        // "Ver el tutorial otra vez" del perfil del cliente.
        onRepetirTutorial: _repetirTutorialCliente,
        // Vuelta al panel desde la pestaña Perfil (la otra vía es el Home).
        onVerAdmin: _volverAlAdmin,
      ),
    ];
    _screensVendedor = [
      MisTicketsScreen(key: _misTicketsKey),
      const PerfilScreen(),
    ];
    _screensVendedorAdmin = [
      MisTicketsScreen(key: _misTicketsKey),
      GestionScreen(onVerComoCliente: _verComoCliente),
      PerfilScreen(onVerComoCliente: _verComoCliente),
    ];

    // Load entities immediately to prevent UI flash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });

    // Las vistas apiladas de «Exploración rápida» pintan su propia barra: para
    // cambiar de pestaña tienen que poder pedírselo al shell (ver
    // `ShellNavegacion`). Se registra una sola vez por vida de este State.
    ShellNavegacion.registrar(_irAPestanaDesdeUnaPantalla);
  }

  @override
  void dispose() {
    // El puente es estático: si el shell se desmonta (cierre de sesión, cambio de
    // rol), hay que soltarlo o una ruta apilada que sobreviva intentaría cambiar
    // de pestaña en un State muerto.
    ShellNavegacion.limpiar();
    _modo.dispose();
    super.dispose();
  }

  /// Pasa a ver la app como cliente (desde «Gestión» o Perfil del admin).
  ///
  /// Se vuelve a la primera pestaña: las dos listas de pantallas no comparten
  /// índices (Gestión es la 0 del admin y el Home la 0 del cliente), así que
  /// conservar el índice dejaría al usuario en una pestaña que no pidió. Por eso
  /// **todos** los accesos al modo cliente pasan por aquí, no por el provider
  /// directamente: el provider no sabe nada de pestañas.
  void _verComoCliente() {
    if (!mounted) return;
    if (!puedeVerComoCliente(esAdmin: context.read<EntidadProvider>().isAdmin)) {
      return;
    }
    setState(() => _currentIndex = 0);
    _modo.verComoCliente();
  }

  /// Vuelve al panel de administración.
  void _volverAlAdmin() {
    if (!mounted) return;
    setState(() => _currentIndex = 0);
    _modo.verComoAdmin();
  }

  /// Cambia de pestaña cuando lo pide una pantalla apilada.
  ///
  /// El rol y el modo se leen en el momento del toque, no al registrar: el mismo
  /// shell atiende al cliente, al vendedor y al admin en modo cliente. Se
  /// resuelve la **vista** (no el rol) porque `_onTabSelected` decide con ella
  /// qué pestañas hay que refrescar: pasarle «es admin» dejaba al cliente puro
  /// sin refrescos.
  void _irAPestanaDesdeUnaPantalla(int indice) {
    if (!mounted) return;
    final entidad = context.read<EntidadProvider>();
    _onTabSelected(
      indice,
      esVistaCliente(
        vistaDelShell(
          esAdmin: entidad.isAdmin,
          esVendedor: entidad.isVendedor,
          comoCliente: _modo.comoCliente,
        ),
      ),
    );
  }

  Future<void> _loadInitialData() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) {
      if (!mounted) return;
      context.read<EntidadProvider>().limpiar();
      // La suscripción era de la entidad del usuario anterior: si no se limpia,
      // el siguiente en entrar vería el aviso de impago de otro.
      context.read<SuscripcionProvider>().limpiar();
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

  /// Lanza el tutorial de primer uso la primera vez que se entra al shell.
  ///
  /// Cliente → recorrido «crear una reserva / anotarse en la lista».
  /// Admin → recorrido «publicar el primer local, servicio y turnos», por
  /// entidad (si crea otra entidad, el tutorial vuelve a mostrarse para ella).
  ///
  /// Se difiere a post-frame porque puede cambiar de pestaña antes de empezar
  /// (el admin debe estar en «Gestión», que es donde viven sus anclas).
  void _quizasLanzarTutorial({
    required bool isAdmin,
    required bool isVendedor,
  }) {
    if (_tutorialRevisado) return;
    _tutorialRevisado = true;

    final uuid = AuthService.currentUserId;
    if (uuid == null) return;
    final entidad = context.read<EntidadProvider>().entidadSeleccionada;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Cliente puro (ni admin ni vendedor): el recorrido empieza en el Home.
      if (!isAdmin && !isVendedor) {
        if (_currentIndex != 0) setState(() => _currentIndex = 0);
        if (!await TutorialService.debeMostrarCliente(uuid)) return;
        if (!mounted) return;
        TutorialFlujos.iniciarCliente(uuid, navegador: _navegarTutorial);
        return;
      }

      if (!isAdmin || entidad == null) return;

      // En el shell de admin+vendedor «Gestión» es la pestaña 1.
      final idxGestion = isVendedor ? 1 : 0;
      if (_currentIndex != idxGestion) setState(() => _currentIndex = idxGestion);

      if (!await TutorialService.debeMostrarAdmin(uuid, entidad.id)) return;
      if (!mounted) return;
      TutorialFlujos.iniciarAdmin(
        uuid,
        entidad.id,
        navegador: _navegarTutorial,
      );
    });
  }

  /// Relanza el tutorial del cliente desde el paso 1 ("Ver el tutorial otra vez"
  /// del perfil).
  ///
  /// Cambia a la pestaña Home antes de arrancar: el primer elemento resaltado
  /// (`home_buscar`) vive ahí y, sin ese cambio, la burbuja aparecería sobre una
  /// pantalla sin el elemento a resaltar.
  Future<void> _repetirTutorialCliente() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;
    if (_currentIndex != 0) setState(() => _currentIndex = 0);
    await TutorialFlujos.repetirCliente(uuid, navegador: _navegarTutorial);
  }

  /// Navegación del tutorial: deja la pantalla lista para el paso nuevo.
  ///
  /// El cliente se mueve entre las pestañas del shell (Home y catálogo) y el
  /// detalle del primer servicio; además, desde v2, el recorrido abre las
  /// pantallas nuevas de «Exploración rápida» (categorías, establecimientos,
  /// ficha y top 10), que son rutas apiladas y las resuelve `irACliente` con las
  /// MISMAS rutas que usan las tarjetas del Home. El admin se mueve entre los
  /// módulos de «Gestión». Es lo que hace que «Siguiente» no se quede esperando a
  /// que el usuario navegue por su cuenta. Solo se llama con los destinos del rol
  /// que toca: los del cliente son de `_screensNoAdmin`.
  Future<void> _navegarTutorial(TutorialDestino destino) async {
    if (!mounted) return;

    if (destino == TutorialDestino.home ||
        destino == TutorialDestino.catalogo ||
        destino == TutorialDestino.servicio) {
      // Si había un detalle abierto (o cualquier ruta encima), se cierra: las
      // anclas de una pestaña solo cuentan como visibles en la ruta actual.
      TutorialNavegacion.volverAlShell(context);
      final indice = destino == TutorialDestino.home ? 0 : _idxCatalogoCliente;
      if (_currentIndex != indice) setState(() => _currentIndex = indice);
      if (destino == TutorialDestino.servicio) {
        // El paso vive en el detalle de un servicio concreto: se abre el
        // primero del catálogo.
        await _catalogoKey.currentState?.abrirPrimerServicio();
      }
      return;
    }

    // Pantallas nuevas del cliente (rutas apiladas sobre el shell).
    if (destino == TutorialDestino.listaCategorias ||
        destino == TutorialDestino.listaEstablecimientos ||
        destino == TutorialDestino.fichaEstablecimiento ||
        destino == TutorialDestino.topServicios) {
      await TutorialNavegacion.irACliente(context, destino);
      return;
    }

    await TutorialNavegacion.irAAdmin(
      context,
      context.read<EntidadProvider>().entidadSeleccionada,
      destino,
    );
  }

  void _redirectToLoginIfSignedOut() {
    if (!mounted || _redirectingToLogin) return;
    _redirectingToLogin = true;
    context.read<EntidadProvider>().limpiar();
    context.read<SuscripcionProvider>().limpiar();
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

  /// Cambia de pestaña y refresca lo que toque.
  ///
  /// [esVistaCliente] es «esta vista es la del cliente» (no «el usuario es
  /// cliente»): un admin que pidió ver la app como cliente entra por aquí con
  /// las pantallas del cliente y necesita los mismos refrescos.
  void _onTabSelected(int i, bool esVistaCliente) {
    if (esVistaCliente) {
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
    // Las pantallas del admin no tienen catálogo, listas ni reservas que
    // refrescar: se cambia de pestaña y ya.
    setState(() => _currentIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    // El modo se expone a las pantallas de dentro (Perfil decide con él qué
    // ofrece) y el shell se reconstruye al cambiar.
    return ChangeNotifierProvider<ModoVistaProvider>.value(
      value: _modo,
      child: ListenableBuilder(
        listenable: _modo,
        builder: (context, _) => _buildShell(context),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
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

    // Tutorial guiado de primer uso: se decide aquí, con el rol ya resuelto.
    _quizasLanzarTutorial(isAdmin: isAdmin, isVendedor: isVendedor);

    // Qué pantallas le tocan: cliente puro, admin, vendedor… o **admin viendo
    // como cliente** (ver `utils/modo_vista.dart`).
    final vista = vistaDelShell(
      esAdmin: isAdmin,
      esVendedor: isVendedor,
      comoCliente: _modo.comoCliente,
    );
    final screens = switch (vista) {
      VistaShell.admin => _screens,
      VistaShell.vendedor => _screensVendedor,
      VistaShell.vendedorAdmin => _screensVendedorAdmin,
      VistaShell.cliente => _screensNoAdmin,
    };
    final enVistaCliente = esVistaCliente(vista);

    // Badge real: reservas en estado "Reservado" del usuario.
    final pendientes = context.select<ReservasProvider, int>(
      (p) => p.pendientes,
    );

    // Mantener índice válido si el rol cambia
    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    return Scaffold(
      // El aviso de suscripción va ENCIMA del IndexedStack, no dentro de una
      // pestaña: así el impago se ve en todo momento, que es el requisito. El
      // widget se pinta solo cuando hay algo que decir (y se oculta si el módulo
      // todavía no está migrado), así que los usuarios al día no ven nada.
      body: Column(
        children: [
          if (isAdmin) const AvisoSuscripcion(),
          Expanded(
            child: IndexedStack(index: safeIndex, children: screens),
          ),
        ],
      ),
      bottomNavigationBar: enVistaCliente
          // El cliente usa la barra compartida: la misma que pintan las vistas
          // apiladas de «Exploración rápida» (categorías, establecimientos, ficha
          // y top 10), para que no haya dos listas de pestañas que se separen.
          // La usa también el admin que está viendo la app como cliente.
          ? BarraNavegacionCliente(
              indiceActivo: safeIndex,
              onSeleccion: (i) => _onTabSelected(i, enVistaCliente),
              // El número ya está calculado aquí para la barra del admin; se pasa
              // para no repetir el `select`.
              pendientesReservas: pendientes,
            )
          : NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (i) => _onTabSelected(i, enVistaCliente),
              backgroundColor: Colors.white,
              indicatorColor: AppTheme.primary.withValues(alpha: 0.12),
              destinations: [
                // Admin+Vendedor: Reservas primero (misma orden que
                // _screensVendedorAdmin).
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
                // El vendedor (no admin) sí lleva el badge; el admin no.
                if (!isAdmin)
                  NavigationDestination(
                    icon: IconoReservaConBadge(
                      pendientes: pendientes,
                      showBadge: !isVendedor,
                    ),
                    selectedIcon: IconoReservaConBadge(
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
