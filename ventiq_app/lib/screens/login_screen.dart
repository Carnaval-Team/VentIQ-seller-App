import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pushReplacementNamed('/categories');
    }
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
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  hintText: 'Email',
                                  hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
                                  prefixIcon: Icon(Icons.email_outlined, color: Color(0xFF4A90E2)),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese su email' : null,
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
                            const SizedBox(height: 24),
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
                                onPressed: _submit,
                                child: const Text(
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
