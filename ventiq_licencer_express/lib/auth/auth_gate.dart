import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  bool _signingOut = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        if (session == null) {
          return LoginScreen(message: _message);
        }

        return FutureBuilder<bool>(
          future: _authService.isCurrentUserSuperadmin(),
          builder: (context, adminSnapshot) {
            if (adminSnapshot.connectionState != ConnectionState.done) {
              return _buildLoading();
            }
            if (adminSnapshot.hasError) {
              return _buildError(
                'Error validando superadmin. Intenta de nuevo.',
              );
            }
            if (adminSnapshot.data != true) {
              _scheduleSignOut();
              return LoginScreen(
                message: 'Acceso restringido solo a superadmin.',
              );
            }
            _message = null;
            return widget.child;
          },
        );
      },
    );
  }

  void _scheduleSignOut() {
    if (_signingOut) {
      return;
    }
    _signingOut = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _authService.signOut();
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'Acceso restringido solo a superadmin.';
      });
      _signingOut = false;
    });
  }

  Widget _buildLoading() {
    return const AppBackground(
      child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );
  }

  Widget _buildError(String message) {
    return AppBackground(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.danger,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
