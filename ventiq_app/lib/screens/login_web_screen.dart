import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_preferences_service.dart';
import '../services/seller_service.dart';
import '../services/promotion_service.dart';

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
  final _sellerService = SellerService();
  final _promotionService = PromotionService();
  bool _isLoading = false;
  bool _obscure = true;
  bool _rememberMe = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      FocusScope.of(context).unfocus();

      try {
        final response = await _authService.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (response.user != null) {
          // Guardar datos básicos del usuario en las preferencias
          await _userPreferencesService.saveUserData(
            userId: response.user!.id,
            email: response.user!.email ?? _emailController.text.trim(),
            accessToken: response.session?.accessToken ?? '',
          );

          print('✅ Usuario guardado en preferencias:');
          print('  - ID: ${response.user!.id}');
          print('  - Email: ${response.user!.email}');
          print(
            '  - Access Token: ${response.session?.accessToken != null ? response.session!.accessToken.substring(0, 20) : "null"}...',
          );

          // Verificar si el usuario es un vendedor válido
          try {
            final sellerProfile = await _sellerService
                .verifySellerAndGetProfile(response.user!.id);

            final sellerData = sellerProfile['seller'] as Map<String, dynamic>;
            final workerData = sellerProfile['worker'] as Map<String, dynamic>;

            // Extraer IDs por separado
            final idTpv =
                sellerProfile['idTpv'] as int; // Desde app_dat_vendedor
            final idTienda =
                sellerProfile['idTienda'] as int; // Desde app_dat_trabajadores
            final idSeller =
                sellerData['id']
                    as int; // ID del vendedor desde app_dat_vendedor

            print('🔍 IDs extraídos por separado:');
            print('  - ID TPV (app_dat_vendedor): $idTpv');
            print('  - ID Tienda (app_dat_trabajadores): $idTienda');
            print('  - ID Seller (app_dat_vendedor): $idSeller');

            // Guardar datos del vendedor
            await _userPreferencesService.saveSellerData(
              idTpv: idTpv,
              idTrabajador: sellerData['id_trabajador'] as int,
            );

            // Guardar ID del vendedor
            await _userPreferencesService.saveIdSeller(idSeller);

            // Guardar perfil del trabajador
            await _userPreferencesService.saveWorkerProfile(
              nombres: workerData['nombres'] as String,
              apellidos: workerData['apellidos'] as String,
              idTienda: idTienda,
              idRoll: workerData['id_roll'] as int,
            );

            // Guardar credenciales si el usuario marcó "Recordarme"
            if (_rememberMe) {
              await _userPreferencesService.saveCredentials(
                _emailController.text.trim(),
                _passwordController.text,
              );
            } else {
              await _userPreferencesService.clearSavedCredentials();
            }

            print('✅ Perfil completo del vendedor guardado');

            // Buscar promoción global para la tienda
            try {
              final globalPromotion = await _promotionService
                  .getGlobalPromotion(idTienda);
              if (globalPromotion != null) {
                await _promotionService.saveGlobalPromotion(
                  idPromocion: globalPromotion['id_promocion'],
                  codigoPromocion: globalPromotion['codigo_promocion'],
                  valorDescuento: globalPromotion['valor_descuento'],
                  tipoDescuento: globalPromotion['tipo_descuento'],
                );
                print('🎯 Promoción global configurada para la tienda');
              } else {
                // Guardar null cuando no hay promoción
                await _promotionService.saveGlobalPromotion(
                  idPromocion: null,
                  codigoPromocion: null,
                  valorDescuento: null,
                  tipoDescuento: null,
                );
                print('ℹ️ No hay promoción global activa - guardando null');
              }
            } catch (e) {
              print('⚠️ Error obteniendo promoción global: $e');
              // Guardar null en caso de error también
              await _promotionService.saveGlobalPromotion(
                idPromocion: null,
                codigoPromocion: null,
                valorDescuento: null,
                tipoDescuento: null,
              );
            }

            // Login exitoso - ir al catálogo
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/categories');
            }
          } catch (e) {
            // Error: usuario no es vendedor válido
            print('❌ Error de verificación: $e');

            // Limpiar datos guardados
            await _userPreferencesService.clearUserData();
            await _authService.signOut();

            setState(() {
              _errorMessage = 'Acceso denegado: $e';
              _isLoading = false;
            });
            return;
          }
        } else {
          setState(() {
            _errorMessage =
                'Error de autenticación. Verifica tus credenciales.';
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = _getErrorMessage(e.toString());
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  String _getErrorMessage(String error) {
    if (error.contains('Invalid login credentials')) {
      return 'Credenciales inválidas. Verifica tu email y contraseña.';
    } else if (error.contains('Email not confirmed')) {
      return 'Email no confirmado. Revisa tu bandeja de entrada.';
    } else if (error.contains('Too many requests')) {
      return 'Demasiados intentos. Intenta de nuevo más tarde.';
    } else if (error.contains('Network')) {
      return 'Error de conexión. Verifica tu internet.';
    }
    return 'Error de autenticación. Intenta de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 1200;
    final cardWidth = isLargeScreen ? 500.0 : screenSize.width * 0.9;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF4A90E2),
              Color(0xFF357ABD),
              Color(0xFF2E6BA8),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 20,
              shadowColor: Colors.black.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: cardWidth,
                padding: const EdgeInsets.all(48.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo y título
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF4A90E2),
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          'assets/ventas.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Título
                    const Text(
                      'VentIQ POS',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Subtítulo
                    Text(
                      'Inicia sesión en tu cuenta',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Formulario
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Campo de email
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                            child: TextFormField(
                              controller: _emailController,
                              textInputAction: TextInputAction.next,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'Correo electrónico',
                                hintStyle: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                ),
                                prefixIcon: Icon(
                                  Icons.email_outlined,
                                  color: Color(0xFF4A90E2),
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 20,
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Ingrese su email';
                                }
                                if (!v.contains('@')) {
                                  return 'Ingrese un email válido';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Campo de contraseña
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                            child: TextFormField(
                              controller: _passwordController,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                hintText: 'Contraseña',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: Color(0xFF4A90E2),
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF9CA3AF),
                                  ),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 20,
                                ),
                              ),
                              onFieldSubmitted: (_) => _submit(),
                              validator: (v) =>
                                  (v == null || v.isEmpty)
                                      ? 'Ingrese su contraseña'
                                      : null,
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Checkbox recordarme
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                                activeColor: const Color(0xFF4A90E2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const Text(
                                'Recordar mis credenciales',
                                style: TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // Mensaje de error
                          if (_errorMessage != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red.shade600,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          // Botón de login
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A90E2),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                                shadowColor: const Color(0xFF4A90E2).withOpacity(0.3),
                              ),
                              onPressed: _isLoading ? null : _submit,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      'Iniciar Sesión',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Enlace de contraseña olvidada
                          TextButton(
                            onPressed: () {
                              /* TODO: forgot password flow */
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF4A90E2),
                            ),
                            child: const Text(
                              '¿Olvidaste tu contraseña?',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
