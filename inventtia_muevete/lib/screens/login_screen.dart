import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  static const _keyEmail = 'saved_email';
  static const _keyPassword = 'saved_password';
  static const _keyRemember = 'remember_me';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_keyRemember) ?? false;
    if (remember) {
      final email = prefs.getString(_keyEmail) ?? '';
      final password = prefs.getString(_keyPassword) ?? '';
      if (mounted) {
        setState(() {
          _rememberMe = true;
          _emailController.text = email;
          _passwordController.text = password;
        });
      }
    }
  }

  Future<void> _saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyPassword, password);
    await prefs.setBool(_keyRemember, true);
  }

  Future<void> _clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyPassword);
    await prefs.setBool(_keyRemember, false);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    authProvider.clearError();

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final success = await authProvider.signIn(email, password);

    if (!mounted) return;

    if (success) {
      // Ask user if they want to save credentials
      if (!_rememberMe) {
        final shouldSave = await _showSaveCredentialsDialog();
        if (shouldSave == true) {
          await _saveCredentials(email, password);
        } else {
          await _clearSavedCredentials();
        }
      } else {
        // Already remembered — update with latest credentials
        await _saveCredentials(email, password);
      }

      if (!mounted) return;
      if (authProvider.isDriver) {
        Navigator.pushReplacementNamed(context, '/driver/home');
      } else {
        Navigator.pushReplacementNamed(context, '/client/home');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.error ?? 'Error al iniciar sesion',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<bool?> _showSaveCredentialsDialog() {
    final isDark = context.read<ThemeProvider>().isDark;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Guardar credenciales',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1D27),
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '¿Deseas guardar tu usuario y contraseña para la proxima vez?',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.grey[600],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'No',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Sí, guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.grey[600]!;
    final textTertiary = isDark
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.grey[500]!;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[300]!;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                // App logo
                Center(
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 110,
                    height: 110,
                  ),
                ),

                const SizedBox(height: 16),

                // App name
                Center(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Muev',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        TextSpan(
                          text: 'ete',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Center(
                  child: Text(
                    'Inicia sesion para continuar',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textSecondary,
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                // Email field
                Text(
                  'Correo electronico',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.8)
                        : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'correo@ejemplo.com',
                    prefixIcon: Icon(Icons.email_outlined, size: 20),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El correo es requerido';
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                        .hasMatch(value.trim())) {
                      return 'Ingresa un correo valido';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Password field
                Text(
                  'Contrasena',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.8)
                        : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: TextStyle(color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Tu contrasena',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.grey[500],
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'La contrasena es requerida';
                    }
                    if (value.length < 6) {
                      return 'Minimo 6 caracteres';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                // Remember me checkbox
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: (v) async {
                          setState(() => _rememberMe = v ?? false);
                          if (!_rememberMe) {
                            await _clearSavedCredentials();
                          }
                        },
                        activeColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        setState(() => _rememberMe = !_rememberMe);
                        if (!_rememberMe) {
                          await _clearSavedCredentials();
                        }
                      },
                      child: Text(
                        'Recordarme',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Login button
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    return ElevatedButton(
                      onPressed: auth.isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor:
                            AppTheme.primaryColor.withValues(alpha: 0.5),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Iniciar Sesion',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Divider "Or continue with"
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: borderColor,
                        thickness: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'O continuar con',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textTertiary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: borderColor,
                        thickness: 1,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Social buttons (decorative)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Google sign-in placeholder
                        },
                        icon: const Icon(Icons.g_mobiledata, size: 24),
                        label: const Text('Google'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Facebook sign-in placeholder
                        },
                        icon: const Icon(Icons.facebook, size: 22),
                        label: const Text('Facebook'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Register link
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, '/register');
                    },
                    child: RichText(
                      text: TextSpan(
                        text: 'No tienes cuenta? ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textSecondary,
                        ),
                        children: [
                          TextSpan(
                            text: 'Registrate',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Terms of Service / Privacy Policy
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'Al continuar, aceptas nuestros ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.grey[400],
                        fontSize: 11,
                      ),
                      children: [
                        TextSpan(
                          text: 'Terminos de Servicio',
                          style: TextStyle(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.7),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        const TextSpan(text: ' y '),
                        TextSpan(
                          text: 'Politica de Privacidad',
                          style: TextStyle(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.7),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
