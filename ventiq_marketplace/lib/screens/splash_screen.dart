import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';

/// Pantalla de splash con logo de Inventtia
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  int? _parseStoreIdFromUri(Uri? uri) {
    if (uri == null) return null;
    final raw = (uri.queryParameters['storeId'] ?? '').toString();
    final id = int.tryParse(raw);
    if (id != null && id > 0) return id;
    return null;
  }

  int? _parseStoreIdFromUrl() {
    final base = Uri.base;

    final direct = (base.queryParameters['storeId'] ?? '').toString();
    final directId = int.tryParse(direct);
    if (directId != null && directId > 0) return directId;

    final fragment = base.fragment;
    if (fragment.isEmpty) return null;

    final fragPath = fragment.startsWith('/') ? fragment : '/$fragment';
    final fragUri = Uri.tryParse('http://localhost$fragPath');
    final fragRaw = (fragUri?.queryParameters['storeId'] ?? '').toString();
    final fragId = int.tryParse(fragRaw);
    if (fragId != null && fragId > 0) return fragId;

    return null;
  }

  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  /// Navegar a la pantalla principal después de 2 segundos
  Future<void> _navigateToHome() async {
    int? storeIdFromLink = _parseStoreIdFromUrl();

    if (storeIdFromLink == null) {
      try {
        final uri = await AppLinks().getInitialLink();
        storeIdFromLink = _parseStoreIdFromUri(uri);
      } catch (_) {
        storeIdFromLink = null;
      }
    }

    await Future.delayed(const Duration(seconds: 2));

    try {
      final authService = AuthService();
      await authService.syncLocalUserFromSupabaseIfNeeded();
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pushReplacementNamed(
        '/home',
        arguments: storeIdFromLink == null
            ? null
            : {'storeId': storeIdFromLink},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryColor,
              AppTheme.primaryColor.withOpacity(0.8),
              AppTheme.secondaryColor,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo con filtro blanco
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
                child: Image.asset(
                  'assets/logo_app_no_background.png',
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              // Nombre de la app
              const Text(
                'Inventtia',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              // Subtítulo
              const Text(
                'Catálogo',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 48),
              // Loading indicator
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              // Loading text
              const Text(
                'Cargando...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
