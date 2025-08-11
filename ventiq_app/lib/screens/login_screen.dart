import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _obscure = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
          // Login exitoso
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/categories');
          }
        } else {
          setState(() {
            _errorMessage = 'Error de autenticación. Verifica tus credenciales.';
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
    return Scaffold(
      body: Stack(
        children: [
          // Solid blue background
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF4A90E2),
            ),
          ),
          // Top section with logo
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: Container(
              color: const Color(0xFF4A90E2),
              child: Center(
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/ventas.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          // White wavy panel with form
          Positioned(
            top: 250,
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Email field
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(color: const Color(0xFFE9ECEF)),
                              ),
                              child: TextFormField(
                                controller: _emailController,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  hintText: 'Email',
                                  hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                                  prefixIcon: Icon(Icons.email_outlined, color: Color(0xFF4A90E2)),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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
                            const SizedBox(height: 16),
                            // Password field
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(color: const Color(0xFFE9ECEF)),
                              ),
                              child: TextFormField(
                                controller: _passwordController,
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                                  prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF4A90E2)),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure ? Icons.visibility_off : Icons.visibility,
                                      color: const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                                ),
                                onFieldSubmitted: (_) => _submit(),
                                validator: (v) => (v == null || v.isEmpty) ? 'Ingrese su contraseña' : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Error message
                            if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                                    const SizedBox(width: 8),
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
                            if (_errorMessage != null) const SizedBox(height: 16),
                            // Login button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4A90E2),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: _isLoading ? null : _submit,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Login',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Forgot password link
                            TextButton(
                              onPressed: () {/* TODO: forgot password flow */},
                              child: const Text(
                                'FORGOT PASSWORD ?',
                                style: TextStyle(
                                  color: Color(0xFF4A90E2),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
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
        ],
      ),
    );
  }
}

// Simple wave clipper for the top edge of the white panel
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    // Create a panel with a wavy TOP edge and straight sides/bottom
    final path = Path()
      ..moveTo(0, 60)
      // First curve peak/trough
      ..quadraticBezierTo(size.width * 0.25, 20, size.width * 0.5, 40)
      // Second curve
      ..quadraticBezierTo(size.width * 0.75, 60, size.width, 30)
      // Right edge down to bottom
      ..lineTo(size.width, size.height)
      // Bottom edge to left
      ..lineTo(0, size.height)
      // Close back to start to complete shape
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
