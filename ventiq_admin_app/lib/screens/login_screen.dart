import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/auth_service.dart';
import '../services/user_preferences_service.dart';
import '../services/permissions_service.dart';

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
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/dashboard',
        (route) => false,
      );
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              // Logo y título
              _buildHeader(),
              const SizedBox(height: 60),

              // Formulario de login
              _buildLoginForm(),
              const SizedBox(height: 32),

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
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

              // Enlaces adicionales
              _buildFooterLinks(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Image.asset(
          'assets/images/inventia.png',
          width: 120,
          height: 120,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 24),
        const Text(
          'Inventtia Admin',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Panel de Administración',
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Email
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

          // Password
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

          // Remember me checkbox
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
            // TODO: Implementar recuperación de contraseña
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

        // Botón para registrar nueva tienda
        Container(
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
                _showComingSoonDialog('Soporte Técnico');
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

      // Limpiar caché de permisos antes de detectar rol
      _permissionsService.clearCache();

      // Paso 2: Detectar rol con mayor jerarquía
      final userRole = await _permissionsService.getUserRole();
      final roleName = _permissionsService.getRoleName(userRole);

      print('🔍 Rol detectado: $roleName ($userRole)');

      // Paso 3: Verificar que tenga acceso (bloquear vendedores y sin rol)
      if (userRole == UserRole.none || userRole == UserRole.vendedor) {
        await _authService.signOut();
        throw Exception('NO_ADMIN_PRIVILEGES');
      }

      // Paso 4: Obtener tiendas según el rol
      List<Map<String, dynamic>> userStores = [];
      int? defaultStoreId;
      final supabase = Supabase.instance.client;

      if (userRole == UserRole.gerente) {
        // Gerente: obtener desde app_dat_gerente
        final gerenteData = await supabase
            .from('app_dat_gerente')
            .select('id_tienda, app_dat_tienda(id, denominacion)')
            .eq('uuid', user.id);

        if (gerenteData.isNotEmpty) {
          userStores = List<Map<String, dynamic>>.from(gerenteData);
          defaultStoreId = gerenteData.first['id_tienda'];
        }
      } else if (userRole == UserRole.supervisor) {
        // Supervisor: obtener desde app_dat_supervisor
        final supervisorData = await supabase
            .from('app_dat_supervisor')
            .select('id_tienda, app_dat_tienda(id, denominacion)')
            .eq('uuid', user.id);

        if (supervisorData.isNotEmpty) {
          userStores = List<Map<String, dynamic>>.from(supervisorData);
          defaultStoreId = supervisorData.first['id_tienda'];
        }
      } else if (userRole == UserRole.almacenero) {
        // Almacenero: obtener desde app_dat_almacenero
        final almaceneroData =
            await supabase
                .from('app_dat_almacenero')
                .select('id_almacen, app_dat_almacen(id_tienda)')
                .eq('uuid', user.id)
                .maybeSingle();

        if (almaceneroData != null) {
          final idTienda = almaceneroData['app_dat_almacen']['id_tienda'];
          defaultStoreId = idTienda;

          // Obtener info de la tienda
          final tiendaData =
              await supabase
                  .from('app_dat_tienda')
                  .select('id, denominacion')
                  .eq('id', idTienda)
                  .maybeSingle();

          userStores = [
            {'id_tienda': idTienda, 'app_dat_tienda': tiendaData},
          ];
        }
      }

      if (userStores.isEmpty || defaultStoreId == null) {
        await _authService.signOut();
        throw Exception('NO_STORE_ASSIGNED');
      }

      // Paso 5: Preparar datos para guardar
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

      // Paso 6: Guardar datos del usuario
      await _userPreferencesService.saveUserData(
        userId: user.id,
        email: user.email ?? _emailController.text.trim(),
        accessToken: session.accessToken,
        adminName: user.userMetadata?['full_name'] ?? user.email?.split('@')[0],
        adminRole: roleName,
        idTienda: defaultStoreId,
        userStores: storesForPreferences,
      );

      print('✅ Usuario autenticado:');
      print('  - ID: ${user.id}');
      print('  - Email: ${user.email}');
      print('  - Rol: $roleName');
      print('  - Tienda: $defaultStoreId');
      print('  - Total tiendas: ${userStores.length}');

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

      // Navigate to dashboard
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
      }
    } catch (e) {
      print('❌ Login error: $e');
      setState(() {
        if (e.toString().contains('NO_SUPERVISOR_PRIVILEGES')) {
          _errorMessage =
              'Esta es la app de administración. Los vendedores deben usar la app de ventas.';
        } else if (e.toString().contains('NO_ADMIN_PRIVILEGES')) {
          _errorMessage =
              'No tienes permisos de administrador. Solo gerentes, supervisores y almaceneros pueden acceder.';
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
}
