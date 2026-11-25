import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/auth_service.dart';
import '../services/user_preferences_service.dart';
import '../services/permissions_service.dart';
import '../services/subscription_service.dart';
import '../services/subscription_guard_service.dart';
import '../services/update_service.dart';
import '../models/subscription.dart';
import '../widgets/update_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _userPreferencesService = UserPreferencesService();
  final _permissionsService = PermissionsService();
  final _subscriptionService = SubscriptionService();
  final _subscriptionGuard = SubscriptionGuardService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkAutoLogin() async {
    // Check if user has a valid session and auto-login
    final hasValidSession = await _userPreferencesService.hasValidSession();
    if (hasValidSession && mounted) {
      print('✅ Valid session found, auto-logging in...');
      // Agregar pequeño delay para asegurar que la UI se renderice primero
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      // Verificar rol para redirigir correctamente
      try {
        final role = await _permissionsService.getUserRole();
        if (role == UserRole.recursosHumanos && mounted) {
          print(
            '✅ Usuario HR detectado en auto-login, navegando a HR dashboard...',
          );
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/hr-dashboard',
            (route) => false,
          );
          return;
        }
      } catch (e) {
        print('⚠️ Error verificando rol en auto-login: $e');
      }

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
      }
    } else {
      print('❌ No valid session, staying on login screen');
    }
  }

  Future<void> _loadSavedCredentials() async {
    final shouldRemember = await _userPreferencesService.shouldRememberMe();
    if (shouldRemember) {
      final credentials = await _userPreferencesService.getSavedCredentials();
      setState(() {
        _emailController.text = credentials['email'] ?? '';
        _passwordController.text = credentials['password'] ?? '';
        _rememberMe = true;
      });
    }
  }

  /// Logo de Inventtia Gestión.
  ///
  /// Es `ic.png`, el icono de esta app (el mismo de `flutter_launcher_icons`).
  /// **No** usar `inventia_logo.png` (ese es el de VentiQ Caja, otro producto y
  /// otro color) ni `inventia.png` (cuadro casi opaco: al teñirlo con `srcIn`
  /// pintaba el bloque entero, que era el azul del móvil y el gris del
  /// escritorio).
  ///
  /// `ic.png` viene sobre fondo blanco, sin wordmark, con márgenes amplios: el
  /// contenido ocupa ~50 % del lienzo. Por eso las llamadas piden un ancho
  /// mayor del que se quiere ver.
  ///
  /// [enPastilla] lo monta sobre una pastilla blanca (panel azul). Sin él va
  /// suelto: sobre la tarjeta blanca del móvil se funde solo.
  Widget _logo({required double ancho, bool enPastilla = false}) {
    final imagen = Image.asset(
      'assets/images/ic.png',
      width: ancho,
      fit: BoxFit.contain,
    );
    if (!enPastilla) return imagen;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: imagen,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final dosColumnas = ancho >= 980;

    if (dosColumnas) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Row(
            children: [
              // Panel de marca: solo en pantallas anchas. Es lo que hace que el
              // login parezca un producto y no un formulario suelto.
              Expanded(flex: 5, child: _panelMarca()),
              Expanded(
                flex: 4,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: _formulario(compacto: false),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Móvil y tablet estrecha: el mismo patrón que el login de VentiQ Caja —
    // fondo azul y el formulario en una tarjeta blanca flotante.
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // `ic.png` no trae wordmark y tiene márgenes blancos: el
                      // contenido ocupa ~50 % del lienzo, así que se pide más
                      // ancho del que se quiere ver.
                      Center(child: _logo(ancho: 132)),
                      const SizedBox(height: 14),
                      const Text(
                        'Inventtia Gestión',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Inicia sesión en tu cuenta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 26),
                      _formulario(compacto: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Panel izquierdo con la marca y los tres argumentos del producto.
  Widget _panelMarca() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // `ic.png` es un cuadro blanco: sobre el azul va en pastilla.
            Row(
              children: [
                _logo(ancho: 56, enPastilla: true),
                const SizedBox(width: 12),
                const Text(
                  'Inventtia Gestión',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              'Tu tienda,\n bajo control.',
              style: TextStyle(
                fontSize: 40,
                height: 1.12,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.1,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Inventario, ventas, caja y equipo en un solo sitio. '
              'Sin cuadernos y sin sorpresas al cerrar el día.',
              style: TextStyle(
                fontSize: 15,
                height: 1.55,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
            const SizedBox(height: 36),
            for (final (icono, texto) in const [
              (Icons.speed_outlined, 'Cobra rápido, incluso sin internet'),
              (Icons.inventory_2_outlined, 'Sabes qué tienes y dónde está'),
              (Icons.insights_outlined, 'Ves tus ganancias reales del día'),
            ]) ...[
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icono, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      texto,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            const Spacer(),
            Text(
              '© ${DateTime.now().year} Inventtia',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulario({required bool compacto}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En la tarjeta móvil el título ya va fuera, encima del formulario.
          if (!compacto) ...[
            const Text(
              'Iniciar sesión',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Usa el correo con el que registraste tu tienda.',
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
          ],

          const Text(
            'Email',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 14.5),
            decoration: _decoracionCampo(
              icono: Icons.alternate_email,
              pista: 'tu@correo.com',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa tu email';
              }
              if (!RegExp(
                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
              ).hasMatch(value.trim())) {
                return 'Ingresa un email válido';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          const Text(
            'Contraseña',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 14.5),
            decoration: _decoracionCampo(
              icono: Icons.lock_outline,
              pista: '••••••••',
              sufijo: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                ),
                color: AppColors.textSecondary,
                tooltip: _obscurePassword ? 'Mostrar' : 'Ocultar',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onFieldSubmitted: (_) => _handleLogin(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Ingresa tu contraseña';
              }
              if (value.length < 6) {
                return 'La contraseña debe tener al menos 6 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),

          // En 390 px la fila «Recordarme | ¿Olvidaste?» no cabe: el enlace
          // baja a su propia línea en pantallas estrechas.
          LayoutBuilder(
            builder: (context, constraints) {
              final recordarme = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (value) =>
                          setState(() => _rememberMe = value ?? false),
                      activeColor: AppColors.primary,
                      side: const BorderSide(
                        color: AppColors.border,
                        width: 1.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: const Text(
                      'Recordarme',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              );

              final olvido = TextButton(
                onPressed: () => _showComingSoonDialog('Recuperar contraseña'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('¿Olvidaste tu contraseña?'),
              );

              if (constraints.maxWidth < 340) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [recordarme, olvido],
                );
              }
              return Row(
                children: [
                  recordarme,
                  const Spacer(),
                  Flexible(child: olvido),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.error,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Entrar'),
            ),
          ),
          const SizedBox(height: 24),

          // Separador con el texto en medio. El texto no se encoge: si la caja
          // es estrecha (tarjeta móvil), los `Divider` desaparecen en vez de
          // empujar la fila fuera del ancho. Antes desbordaba 44 px a 390.
          LayoutBuilder(
            builder: (context, constraints) {
              final etiqueta = Text(
                '¿Todavía no tienes tienda?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                ),
              );
              // 220 px cubre el texto a 11.5 px con holgura.
              if (constraints.maxWidth < 260) {
                return Center(child: etiqueta);
              }
              return Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.border)),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: etiqueta,
                    ),
                  ),
                  const Expanded(child: Divider(color: AppColors.border)),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, '/store-registration'),
              icon: const Icon(Icons.add_business_outlined, size: 18),
              label: const Text('Crear mi tienda'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Center(
            child: TextButton.icon(
              onPressed: _showSupportDialog,
              icon: const Icon(Icons.support_agent, size: 16),
              label: const Text('Contactar soporte'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoracionCampo({
    required IconData icono,
    String? pista,
    Widget? sufijo,
  }) {
    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return InputDecoration(
      isDense: true,
      hintText: pista,
      hintStyle: const TextStyle(fontSize: 14, color: AppColors.textLight),
      prefixIcon: Icon(icono, size: 19, color: AppColors.textSecondary),
      suffixIcon: sufijo,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      border: borde,
      enabledBorder: borde,
      focusedBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      errorBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 1.2),
      ),
      focusedErrorBorder: borde.copyWith(
        borderSide: const BorderSide(color: AppColors.error, width: 1.6),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    FocusScope.of(context).unfocus();

    try {
      // Paso 1: Autenticar con Supabase
      final authResponse = await _authService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (authResponse.user == null) {
        throw Exception('Authentication failed');
      }

      final user = authResponse.user!;
      final session = authResponse.session!;

      // Limpiar TODO el caché de permisos antes de detectar rol del nuevo usuario
      _permissionsService.clearAllCache();
      print('🧹 TODO el caché de permisos limpiado para nuevo login');

      // Paso 2: Obtener todos los roles del usuario por tienda
      final rolesByStore = await _permissionsService.getUserRolesByStore();
      print('🔍 Roles por tienda detectados: $rolesByStore');

      // Paso 3: Verificar que tenga acceso a al menos una tienda como admin
      // Filtrar solo roles de admin (gerente, supervisor, almacenero)
      final adminRolesByStore = Map<int, UserRole>.fromEntries(
        rolesByStore.entries.where(
          (entry) =>
              entry.value != UserRole.vendedor && entry.value != UserRole.none,
        ),
      );

      if (adminRolesByStore.isEmpty) {
        await _authService.signOut();
        throw Exception('NO_ADMIN_PRIVILEGES');
      }

      // Usar el primer rol de admin para compatibilidad con código existente
      final defaultStoreId = adminRolesByStore.keys.first;
      final userRole = adminRolesByStore[defaultStoreId]!;
      final roleName = _permissionsService.getRoleName(userRole);
      print(
        '🔍 Rol principal detectado: $roleName ($userRole) en tienda $defaultStoreId',
      );

      // Paso 4: Obtener tiendas del usuario (todas las tiendas donde tiene algún rol)
      List<Map<String, dynamic>> userStores = [];
      final supabase = Supabase.instance.client;

      // Obtener información de todas las tiendas donde el usuario tiene acceso.
      // `estado_onboarding` viaja en el mapa porque es lo que decide si el
      // usuario aterriza en el dashboard o en el checklist de activación: una
      // tienda recién creada está en `borrador` y no debe ver un dashboard de
      // ceros como si ya vendiera.
      //
      // Cuidado: la columna `estado` de `app_dat_tienda` NO es el estado de la
      // tienda, guarda el código de provincia (`'16'`, `'04'`). El estado de
      // onboarding es `estado_onboarding`.
      for (final storeId in adminRolesByStore.keys) {
        try {
          final tiendaData = await supabase
              .from('app_dat_tienda')
              .select('id, denominacion, estado_onboarding')
              .eq('id', storeId)
              .maybeSingle();

          if (tiendaData != null) {
            userStores.add({
              'id_tienda': storeId,
              'app_dat_tienda': tiendaData,
            });
          }
        } catch (e) {
          print('⚠️ Error obteniendo datos de tienda $storeId: $e');
        }
      }

      if (userStores.isEmpty || defaultStoreId == null) {
        await _authService.signOut();
        throw Exception('NO_STORE_ASSIGNED');
      }

      // Estado de onboarding de la tienda por defecto. Si la tienda no está en
      // el mapa (no se pudo leer su fila), se asume `activa`: es el
      // comportamiento de antes de esta fase y no queremos encerrar en un
      // checklist a quien sí puede vender por un fallo de lectura.
      String? estadoOnboardingTiendaPorDefecto;
      for (final store in userStores) {
        if (store['id_tienda'] != defaultStoreId) continue;
        final datosTienda = store['app_dat_tienda'];
        if (datosTienda is Map) {
          estadoOnboardingTiendaPorDefecto =
              datosTienda['estado_onboarding']?.toString();
        }
        break;
      }
      estadoOnboardingTiendaPorDefecto ??= 'activa';
      final tiendaEnBorrador =
          estadoOnboardingTiendaPorDefecto == 'borrador';
      print(
        '🏪 Estado de onboarding de la tienda $defaultStoreId: '
        '$estadoOnboardingTiendaPorDefecto',
      );

      // Paso 5: Obtener suscripción activa de la tienda por defecto
      Subscription? activeSubscription;
      try {
        activeSubscription = await _subscriptionService.getActiveSubscription(
          defaultStoreId,
        );
        if (activeSubscription != null) {
          print('✅ Suscripción activa encontrada:');
          print('  - Plan: ${activeSubscription.planDenominacion}');
          print('  - Estado: ${activeSubscription.estadoText}');
          print(
            '  - Vence: ${activeSubscription.fechaFin ?? 'Sin vencimiento'}',
          );
          if (activeSubscription.diasRestantes > 0) {
            print('  - Días restantes: ${activeSubscription.diasRestantes}');
          }
        } else {
          print(
            '⚠️ No se encontró suscripción activa para la tienda $defaultStoreId',
          );
        }
      } catch (e) {
        print('❌ Error obteniendo suscripción: $e');
        // No bloquear el login por error de suscripción
      }

      // Paso 6: Preparar datos para guardar
      final storesForPreferences = userStores
          .map(
            (store) => {
              'id_tienda': store['id_tienda'],
              'denominacion':
                  store['app_dat_tienda']?['denominacion'] ??
                  'Tienda ${store['id_tienda']}',
              'id': store['app_dat_tienda']?['id'] ?? store['id_tienda'],
            },
          )
          .toList();

      // Paso 7: Guardar datos del usuario
      await _userPreferencesService.saveUserData(
        userId: user.id,
        email: user.email ?? _emailController.text.trim(),
        accessToken: session.accessToken,
        adminName: user.userMetadata?['full_name'] ?? user.email?.split('@')[0],
        adminRole: roleName,
        idTienda: defaultStoreId,
        userStores: storesForPreferences,
      );

      // Paso 7b: Guardar roles por tienda
      final rolesForStorage = <int, String>{};
      for (final entry in adminRolesByStore.entries) {
        rolesForStorage[entry.key] = _permissionsService.getRoleName(
          entry.value,
        );
      }
      await _userPreferencesService.saveUserRolesByStore(rolesForStorage);
      await _permissionsService.initializeSessionPermissions();
      print('💾 Roles por tienda guardados: $rolesForStorage');

      print('✅ Usuario autenticado:');
      print('  - ID: ${user.id}');
      print('  - Email: ${user.email}');
      print('  - Rol principal: $roleName');
      print('  - Tienda principal: $defaultStoreId');
      print('  - Total tiendas: ${userStores.length}');
      print('  - Roles por tienda: $rolesForStorage');

      // Save credentials if user marked "Remember me"
      if (_rememberMe) {
        await _userPreferencesService.saveCredentials(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await _userPreferencesService.clearSavedCredentials();
      }

      print('✅ Login exitoso como $roleName');

      // Verificar actualizaciones obligatorias antes de navegar al dashboard
      if (mounted) {
        await _checkAndShowMandatoryUpdate();
      }

      // Verificar suscripción antes de navegar al dashboard
      if (mounted) {
        final hasActiveSubscription = await _subscriptionGuard
            .hasActiveSubscription(forceRefresh: true);

        // Guardar datos de suscripción si existe
        if (activeSubscription != null) {
          await _userPreferencesService.saveSubscriptionData(
            subscriptionId: activeSubscription.id,
            state: activeSubscription.estado,
            planId: activeSubscription.idPlan,
            planName: activeSubscription.planDenominacion ?? 'Plan desconocido',
            startDate: activeSubscription.fechaInicio,
            endDate: activeSubscription.fechaFin,
            features: activeSubscription.planFuncionesHabilitadas,
          );
          print('💾 Datos de suscripción guardados en preferencias');
        }

        // Si hay múltiples tiendas, mostrar pantalla de selección
        if (userStores.length > 1) {
          print('🏪 Múltiples tiendas detectadas - Mostrando selector');
          Navigator.pushReplacementNamed(
            context,
            '/store-selection',
            arguments: {'stores': userStores, 'defaultStoreId': defaultStoreId},
          );
        } else if (hasActiveSubscription) {
          print('✅ Suscripción válida - Navegando al dashboard');

          // Verificar si la suscripción está próxima a vencer
          await _checkAndShowSubscriptionWarning(defaultStoreId);

          // Si es usuario HR puro, ir al dashboard HR
          if (userRole == UserRole.recursosHumanos && mounted) {
            print('✅ Usuario Recursos Humanos - navegando a HR dashboard');
            Navigator.pushReplacementNamed(context, '/hr-dashboard');
            return;
          }

          // Tienda en borrador: **también** al dashboard.
          //
          // Antes se mandaba a `/activacion`, una pantalla completa sin salida:
          // el cliente aterrizaba en un checklist a pantalla completa, sin
          // dashboard y sin más forma de salir que volver a iniciar sesión. Eso
          // convertía la ayuda en un muro.
          //
          // Ahora el destino es siempre el dashboard y el checklist vive en una
          // burbuja flotante abajo a la derecha (`OnboardingBurbuja`), que se
          // cierra y se reabre sin perder nada. `tiendaEnBorrador` se sigue
          // calculando porque el dashboard no necesita saberlo: la burbuja
          // consulta el estado por su cuenta y se oculta sola si la tienda ya
          // está activa.
          Navigator.pushReplacementNamed(context, '/dashboard');
        } else {
          print(
            '⚠️ Sin suscripción activa - Navegando a detalles de suscripción',
          );

          // Mostrar mensaje informativo
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_subscriptionGuard.getSubscriptionStatusMessage()),
              backgroundColor: _subscriptionGuard.getSubscriptionStatusColor(),
              duration: const Duration(seconds: 5),
            ),
          );

          // Navegar a detalles de suscripción
          Navigator.pushReplacementNamed(context, '/subscription-detail');
        }
      }
    } catch (e) {
      print('❌ Login error: $e');
      setState(() {
        if (e.toString().contains('NO_SUPERVISOR_PRIVILEGES')) {
          _errorMessage =
              'Esta es la app de administración. Los vendedores deben usar la app de ventas.';
        } else if (e.toString().contains('NO_ADMIN_PRIVILEGES')) {
          _errorMessage =
              'No tienes permisos de administrador. Solo gerentes, supervisores, auditores y almaceneros pueden acceder.';
        } else if (e.toString().contains('NO_STORE_ASSIGNED')) {
          _errorMessage =
              'Tu usuario no tiene una tienda asignada. Contacta al administrador.';
        } else if (e.toString().contains('Invalid login credentials')) {
          _errorMessage =
              'Credenciales inválidas. Verifica tu email y contraseña.';
        } else if (e.toString().contains('Email not confirmed')) {
          _errorMessage = 'Email no confirmado. Revisa tu bandeja de entrada.';
        } else if (e.toString().contains('Too many requests')) {
          _errorMessage = 'Demasiados intentos. Intenta de nuevo más tarde.';
        } else {
          _errorMessage =
              'Error de conexión. Verifica tu internet e intenta de nuevo.';
        }
        _isLoading = false;
      });
    }
  }

  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.support_agent, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Contactar Soporte'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nuestro equipo de soporte está disponible para ayudarte:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),

            // Teléfono
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Teléfono - Via Whatsapp',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '+53 53765120',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Email
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.email, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Email',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'soporteinventtia@gmail.com',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Horarios de atención: Lunes a Viernes de 9:00 AM a 6:00 PM',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showComingSoonDialog(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(feature),
        content: const Text('Esta funcionalidad se implementará próximamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Verificar si la suscripción está próxima a vencer y mostrar diálogo de advertencia
  Future<void> _checkAndShowSubscriptionWarning(int idTienda) async {
    try {
      print('⏰ Verificando expiración de suscripción...');

      final expirationInfo = await _subscriptionService
          .checkSubscriptionExpiration(idTienda);

      if (expirationInfo != null && mounted) {
        final diasRestantes = expirationInfo['diasRestantes'] as int;
        final fechaFin = expirationInfo['fechaFin'] as DateTime;
        final planNombre = expirationInfo['planNombre'] as String;
        final estado = expirationInfo['estado'] as String;

        print('⚠️ Suscripción próxima a vencer: $diasRestantes días restantes');

        // Obtener información de la tienda
        String nombreTienda = 'Tu tienda';

        try {
          final tiendaData = await Supabase.instance.client
              .from('app_dat_tienda')
              .select('denominacion')
              .eq('id', idTienda)
              .single();
          nombreTienda = tiendaData['denominacion'] ?? nombreTienda;
        } catch (e) {
          print('⚠️ No se pudo obtener nombre de tienda: $e');
        }

        final dateFormat = DateFormat('dd/MM/yyyy');

        // Mostrar diálogo de advertencia
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: diasRestantes == 0 ? AppColors.error : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '⚠️ Suscripción Próxima a Vencer',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: diasRestantes == 0
                          ? AppColors.error.withOpacity(0.1)
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: diasRestantes == 0
                            ? AppColors.error.withOpacity(0.3)
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diasRestantes == 0
                              ? '¡Tu suscripción vence HOY!'
                              : diasRestantes == 1
                              ? '¡Tu suscripción vence MAÑANA!'
                              : 'Tu suscripción vence en $diasRestantes días',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: diasRestantes == 0
                                ? AppColors.error
                                : Colors.orange.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        _buildInfoRow('🏪 Tienda:', nombreTienda),
                        const SizedBox(height: 6),
                        _buildInfoRow('📦 Plan:', planNombre),
                        const SizedBox(height: 6),
                        _buildInfoRow('📊 Estado:', estado),
                        const SizedBox(height: 6),
                        _buildInfoRow(
                          '📅 Fecha de vencimiento:',
                          dateFormat.format(fechaFin),
                        ),
                        const SizedBox(height: 6),
                        _buildInfoRow(
                          '⏰ Días restantes:',
                          diasRestantes == 0
                              ? 'Vence hoy'
                              : '$diasRestantes días',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Por favor, renueva tu suscripción para continuar disfrutando de todos los servicios sin interrupciones.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navegar a la pantalla de suscripción
                  Navigator.of(context).pushNamed('/subscription-detail');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Ver Suscripción'),
              ),
            ],
          ),
        );
      } else {
        print('✅ Suscripción no requiere advertencia');
      }
    } catch (e) {
      print('❌ Error verificando expiración de suscripción: $e');
      // No mostrar error al usuario, solo log
    }
  }

  /// Verificar si hay actualizaciones obligatorias y mostrar diálogo si es necesario
  Future<void> _checkAndShowMandatoryUpdate() async {
    try {
      print('🔍 Verificando actualizaciones obligatorias...');

      final updateInfo = await UpdateService.checkForUpdates();

      if (updateInfo['hay_actualizacion'] == true && mounted) {
        final isObligatory = updateInfo['obligatoria'] == true;

        if (isObligatory) {
          print('⚠️ Actualización obligatoria detectada');

          // Mostrar diálogo de actualización obligatoria (no se puede cerrar)
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => UpdateDialog(updateInfo: updateInfo),
          );

          // Si el usuario descargó, no continuar con el login
          // El diálogo no permite cerrar sin actualizar
        } else {
          print('ℹ️ Actualización opcional disponible');
          // Para actualizaciones opcionales, mostrar pero permitir continuar
          if (mounted) {
            await showDialog(
              context: context,
              builder: (context) => UpdateDialog(updateInfo: updateInfo),
            );
          }
        }
      } else {
        print('✅ Aplicación está actualizada');
      }
    } catch (e) {
      print('❌ Error verificando actualizaciones: $e');
      // No bloquear el login si hay error al verificar actualizaciones
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
