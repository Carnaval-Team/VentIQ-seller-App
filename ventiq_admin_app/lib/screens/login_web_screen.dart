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

class LoginWebScreen extends StatefulWidget {
  const LoginWebScreen({super.key});

  @override
  State<LoginWebScreen> createState() => _LoginWebScreenState();
}

class _LoginWebScreenState extends State<LoginWebScreen> {
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
    final hasValidSession = await _userPreferencesService.hasValidSession();
    if (hasValidSession && mounted) {
      print('✅ Valid session found, auto-logging in...');
      await Future.delayed(const Duration(milliseconds: 100));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Card(
            elevation: 8,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              width: 480,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo y título centrado
                  Center(
                    child: Image.asset(
                      'assets/images/inventia.png',
                      width: 90,
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Inventtia Admin',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Panel de Administración',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Formulario
                  _buildLoginForm(),
                  const SizedBox(height: 24),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.error.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Botón de login
                  _buildLoginButton(),
                  const SizedBox(height: 24),

                  // Footer links
                  _buildFooterLinks(),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'admin@ventiq.com',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Por favor ingresa tu email';
              }
              if (!value.contains('@')) {
                return 'Ingresa un email válido';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onFieldSubmitted: (_) => _handleLogin(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Por favor ingresa tu contraseña';
              }
              if (value.length < 6) {
                return 'La contraseña debe tener al menos 6 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value ?? false;
                  });
                },
                activeColor: AppColors.primary,
              ),
              const Text(
                'Recordarme',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child:
            _isLoading
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                : const Text(
                  'Iniciar Sesión',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
      ),
    );
  }

  Widget _buildFooterLinks() {
    return Column(
      children: [
        TextButton(
          onPressed: () {
            _showComingSoonDialog('Recuperar Contraseña');
          },
          child: const Text(
            '¿Olvidaste tu contraseña?',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/store-registration');
            },
            icon: const Icon(Icons.store, size: 20),
            label: const Text(
              'Registrar Nueva Tienda',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '¿Necesitas ayuda? ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            TextButton(
              onPressed: () {
                _showSupportDialog();
              },
              child: const Text(
                'Contactar Soporte',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
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
      final authResponse = await _authService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (authResponse.user == null) {
        throw Exception('Authentication failed');
      }

      final user = authResponse.user!;
      final session = authResponse.session!;

      _permissionsService.clearAllCache();
      print('🧹 TODO el caché de permisos limpiado para nuevo login');

      final rolesByStore = await _permissionsService.getUserRolesByStore();
      print('🔍 Roles por tienda detectados: $rolesByStore');

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

      final defaultStoreId = adminRolesByStore.keys.first;
      final userRole = adminRolesByStore[defaultStoreId]!;
      final roleName = _permissionsService.getRoleName(userRole);
      print(
        '🔍 Rol principal detectado: $roleName ($userRole) en tienda $defaultStoreId',
      );

      List<Map<String, dynamic>> userStores = [];
      final supabase = Supabase.instance.client;

      for (final storeId in adminRolesByStore.keys) {
        try {
          final tiendaData =
              await supabase
                  .from('app_dat_tienda')
                  .select('id, denominacion')
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
      }

      final storesForPreferences =
          userStores
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

      await _userPreferencesService.saveUserData(
        userId: user.id,
        email: user.email ?? _emailController.text.trim(),
        accessToken: session.accessToken,
        adminName: user.userMetadata?['full_name'] ?? user.email?.split('@')[0],
        adminRole: roleName,
        idTienda: defaultStoreId,
        userStores: storesForPreferences,
      );

      final rolesForStorage = <int, String>{};
      for (final entry in adminRolesByStore.entries) {
        rolesForStorage[entry.key] = _permissionsService.getRoleName(
          entry.value,
        );
      }
      await _userPreferencesService.saveUserRolesByStore(rolesForStorage);
      print('💾 Roles por tienda guardados: $rolesForStorage');

      print('✅ Usuario autenticado:');
      print('  - ID: ${user.id}');
      print('  - Email: ${user.email}');
      print('  - Rol principal: $roleName');
      print('  - Tienda principal: $defaultStoreId');
      print('  - Total tiendas: ${userStores.length}');
      print('  - Roles por tienda: $rolesForStorage');

      if (_rememberMe) {
        await _userPreferencesService.saveCredentials(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await _userPreferencesService.clearSavedCredentials();
      }

      print('✅ Login exitoso como $roleName');

      if (mounted) {
        await _checkAndShowMandatoryUpdate();
      }

      if (mounted) {
        final hasActiveSubscription = await _subscriptionGuard
            .hasActiveSubscription(forceRefresh: true);

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

        if (userStores.length > 1) {
          print('🏪 Múltiples tiendas detectadas - Mostrando selector');
          Navigator.pushReplacementNamed(
            context,
            '/store-selection',
            arguments: {'stores': userStores, 'defaultStoreId': defaultStoreId},
          );
        } else if (hasActiveSubscription) {
          print('✅ Suscripción válida - Navegando al dashboard');
          await _checkAndShowSubscriptionWarning(defaultStoreId);
          Navigator.pushReplacementNamed(context, '/dashboard');
        } else {
          print(
            '⚠️ Sin suscripción activa - Navegando a detalles de suscripción',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_subscriptionGuard.getSubscriptionStatusMessage()),
              backgroundColor: _subscriptionGuard.getSubscriptionStatusColor(),
              duration: const Duration(seconds: 5),
            ),
          );
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
      builder:
          (context) => AlertDialog(
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
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
      builder:
          (context) => AlertDialog(
            title: Text(feature),
            content: const Text(
              'Esta funcionalidad se implementará próximamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

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

        String nombreTienda = 'Tu tienda';

        try {
          final tiendaData =
              await Supabase.instance.client
                  .from('app_dat_tienda')
                  .select('denominacion')
                  .eq('id', idTienda)
                  .single();
          nombreTienda = tiendaData['denominacion'] ?? nombreTienda;
        } catch (e) {
          print('⚠️ No se pudo obtener nombre de tienda: $e');
        }

        final dateFormat = DateFormat('dd/MM/yyyy');

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color:
                          diasRestantes == 0 ? AppColors.error : Colors.orange,
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
                          color:
                              diasRestantes == 0
                                  ? AppColors.error.withOpacity(0.1)
                                  : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                diasRestantes == 0
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
                                color:
                                    diasRestantes == 0
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
    }
  }

  Future<void> _checkAndShowMandatoryUpdate() async {
    try {
      print('🔍 Verificando actualizaciones obligatorias...');

      final updateInfo = await UpdateService.checkForUpdates();

      if (updateInfo['hay_actualizacion'] == true && mounted) {
        final isObligatory = updateInfo['obligatoria'] == true;

        if (isObligatory) {
          print('⚠️ Actualización obligatoria detectada');
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => UpdateDialog(updateInfo: updateInfo),
          );
        } else {
          print('ℹ️ Actualización opcional disponible');
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
