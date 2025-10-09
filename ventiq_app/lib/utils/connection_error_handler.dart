import 'package:flutter/material.dart';

class ConnectionErrorHandler {
  /// Detecta si un error es de conexión/red
  static bool isConnectionError(dynamic error) {
    if (error == null) return false;
    
    final errorString = error.toString().toLowerCase();
    
    // Patrones comunes de errores de conexión
    final connectionPatterns = [
      'socketexception',
      'failed host lookup',
      'no address associated with hostname',
      'network is unreachable',
      'connection refused',
      'connection timed out',
      'no internet connection',
      'clientexception',
      'handshakeexception',
      'connection closed',
      'connection reset',
      'errno = 7',
      'errno = 111',
      'errno = 110',
    ];
    
    return connectionPatterns.any((pattern) => errorString.contains(pattern));
  }

  /// Obtiene un mensaje amigable para errores de conexión
  static String getConnectionErrorMessage() {
    return 'Hemos perdido la conexión con el servidor. Entrando en modo offline...';
  }

  /// Obtiene un mensaje genérico para otros errores
  static String getGenericErrorMessage(dynamic error) {
    return 'Error inesperado: ${error.toString()}';
  }

  /// Muestra un SnackBar con manejo inteligente de errores de conexión
  static void showConnectionErrorSnackBar({
    required BuildContext context,
    required dynamic error,
    required VoidCallback onRetry,
    Duration retryDelay = const Duration(seconds: 10),
  }) {
    final isConnectionError = ConnectionErrorHandler.isConnectionError(error);
    final message = isConnectionError 
        ? getConnectionErrorMessage()
        : getGenericErrorMessage(error);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isConnectionError ? Colors.orange : Colors.red,
        duration: Duration(seconds: isConnectionError ? 12 : 6),
        action: SnackBarAction(
          label: 'Reintentar',
          textColor: Colors.white,
          onPressed: onRetry,
        ),
      ),
    );
  }
}

/// Widget para mostrar estado de carga con countdown para reconexión
class ConnectionRetryWidget extends StatefulWidget {
  final VoidCallback onRetry;
  final String message;
  final Duration retryDelay;

  const ConnectionRetryWidget({
    Key? key,
    required this.onRetry,
    this.message = 'Reconectando...',
    this.retryDelay = const Duration(seconds: 10),
  }) : super(key: key);

  @override
  State<ConnectionRetryWidget> createState() => _ConnectionRetryWidgetState();
}

class _ConnectionRetryWidgetState extends State<ConnectionRetryWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  int _countdown = 10;
  bool _canRetry = false;

  @override
  void initState() {
    super.initState();
    _countdown = widget.retryDelay.inSeconds;
    
    _animationController = AnimationController(
      duration: widget.retryDelay,
      vsync: this,
    );
    
    _animation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));

    _startCountdown();
  }

  void _startCountdown() {
    _animationController.forward();
    
    // Countdown timer
    Stream.periodic(const Duration(seconds: 1), (i) => i)
        .take(_countdown)
        .listen((i) {
      if (mounted) {
        setState(() {
          _countdown = widget.retryDelay.inSeconds - i - 1;
        });
      }
    }).onDone(() {
      if (mounted) {
        setState(() {
          _canRetry = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icono de conexión perdida
          Icon(
            Icons.wifi_off,
            size: 64,
            color: Colors.orange[600],
          ),
          const SizedBox(height: 16),
          
          // Mensaje
          Text(
            widget.message,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          // Progress indicator circular con countdown
          if (!_canRetry) ...[
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Círculo de progreso
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return CircularProgressIndicator(
                        value: 1.0 - _animation.value,
                        strokeWidth: 4,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.orange[600]!,
                        ),
                      );
                    },
                  ),
                  // Countdown text
                  Text(
                    '$_countdown',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Reintentando en $_countdown segundos...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
          
          // Botón de reintentar (habilitado después del countdown)
          if (_canRetry) ...[
            ElevatedButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar Conexión'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
