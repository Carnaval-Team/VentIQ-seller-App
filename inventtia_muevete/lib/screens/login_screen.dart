import 'package:flutter/foundation.dart' show kIsWeb;
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
      if (authProvider.role == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo cargar el perfil. Verifica tu conexión.',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return;
      }
      if (kIsWeb) {
        Navigator.pushNamedAndRemoveUntil(context, '/landing', (_) => false);
      } else if (authProvider.isDriver) {
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

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!kIsWeb) const SizedBox(height: 60),
          if (kIsWeb) const SizedBox(height: 8),

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
                    Flexible(
                      child: GestureDetector(
                        onTap: () async {
                          setState(() => _rememberMe = !_rememberMe);
                          if (!_rememberMe) {
                            await _clearSavedCredentials();
                          }
                        },
                        child: Text(
                          'Recordarme',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textSecondary,
                          ),
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
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Google'),
                        ),
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
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Facebook'),
                        ),
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
    );

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: kIsWeb
            ? _WebAuthShell(isDark: isDark, child: form)
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: form,
              ),
      ),
    );
  }
}

class _WebAuthShell extends StatefulWidget {
  final bool isDark;
  final Widget child;
  const _WebAuthShell({required this.isDark, required this.child});

  @override
  State<_WebAuthShell> createState() => _WebAuthShellState();
}

class _WebAuthShellState extends State<_WebAuthShell> {
  final ScrollController _scrollController = ScrollController();
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    final canScroll = max > 0 && (max - current) > 16;
    if (canScroll != _showHint) {
      setState(() => _showHint = canScroll);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            isDark
                ? 'assets/images/back_oscuro.png'
                : 'assets/images/back_claro.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: AppTheme.bg(isDark)),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        AppTheme.darkBg.withValues(alpha: 0.45),
                        AppTheme.darkBg.withValues(alpha: 0.75),
                      ]
                    : [
                        AppTheme.lightBg.withValues(alpha: 0.35),
                        AppTheme.lightBg.withValues(alpha: 0.70),
                      ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 10,
              radius: const Radius.circular(8),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                      decoration: BoxDecoration(
                        color: AppTheme.card(isDark)
                            .withValues(alpha: isDark ? 0.92 : 0.97),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border(isDark)),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.45)
                                : const Color(0x1F0A1D37),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: IgnorePointer(
            child: Center(
              child: _ScrollHint(isDark: isDark, visible: _showHint),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollHint extends StatefulWidget {
  final bool isDark;
  final bool visible;
  const _ScrollHint({required this.isDark, required this.visible});

  @override
  State<_ScrollHint> createState() => _ScrollHintState();
}

class _ScrollHintState extends State<_ScrollHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final dy = (1 - _controller.value) * 4;
          return Transform.translate(
            offset: Offset(0, dy),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppTheme.card(widget.isDark)
                    .withValues(alpha: widget.isDark ? 0.85 : 0.95),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.border(widget.isDark)),
                boxShadow: [
                  BoxShadow(
                    color: widget.isDark
                        ? Colors.black.withValues(alpha: 0.35)
                        : const Color(0x140A1D37),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Desliza para más',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary(widget.isDark),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppTheme.textSecondary(widget.isDark),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
