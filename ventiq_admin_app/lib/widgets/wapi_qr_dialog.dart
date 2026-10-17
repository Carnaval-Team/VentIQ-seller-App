import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/wapi_session.dart';
import '../services/wapi_notification_service.dart';

/// Modal con polling de QR cada 3s hasta detectar status CONNECTED.
class WapiQrDialog extends StatefulWidget {
  final int idSesion;
  final String nombreBot;

  const WapiQrDialog({
    super.key,
    required this.idSesion,
    required this.nombreBot,
  });

  static Future<bool?> show(BuildContext context, {
    required int idSesion,
    required String nombreBot,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          WapiQrDialog(idSesion: idSesion, nombreBot: nombreBot),
    );
  }

  @override
  State<WapiQrDialog> createState() => _WapiQrDialogState();
}

class _WapiQrDialogState extends State<WapiQrDialog> {
  /// Cada cuánto se chequea el status (debe ser bajo para detectar CONNECTED rápido).
  static const _statusInterval = Duration(seconds: 3);

  /// Cada cuánto se pide un QR nuevo. El QR del server rota cada ~10s, así
  /// que pedirlo más seguido es desperdicio de red.
  static const _qrInterval = Duration(seconds: 10);

  Timer? _timer;
  WapiSessionStatus? _last;
  String? _error;
  bool _polling = false;
  bool _closed = false;
  DateTime _lastQrAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // Primera llamada con QR inmediatamente
    _poll(forceQr: true);
    _timer = Timer.periodic(_statusInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll({bool forceQr = false}) async {
    if (_polling || _closed) return;
    _polling = true;
    try {
      // Solo pide QR cada 10s (o cuando se fuerza) para no saturar el endpoint.
      final now = DateTime.now();
      final includeQr =
          forceQr || now.difference(_lastQrAt) >= _qrInterval;

      final s = await WapiNotificationService.instance.getStatus(
        widget.idSesion,
        includeQr: includeQr,
      );
      if (!mounted) return;
      setState(() {
        // Si no pedimos QR esta vez, conservamos el último que tenemos.
        if (includeQr) {
          _last = s;
          _lastQrAt = now;
        } else {
          _last = WapiSessionStatus(
            idSesion: s.idSesion,
            status: s.status,
            phoneNumber: s.phoneNumber,
            qrImage: _last?.qrImage ?? s.qrImage,
            qrCode: _last?.qrCode ?? s.qrCode,
            requiereConfirmacionManual: s.requiereConfirmacionManual,
          );
        }
        _error = null;
      });
      if (s.status == WapiStatus.connected) {
        _closed = true;
        _timer?.cancel();
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.of(context).pop(true);
      } else if (s.status == WapiStatus.failed) {
        // Se detiene el polling pero se puede reintentar desde el propio
        // diálogo: antes había que cerrarlo y volver a empezar.
        _closed = true;
        _timer?.cancel();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _polling = false;
    }
  }

  /// Rearma el polling tras un fallo, sin cerrar el diálogo.
  void _reintentar() {
    setState(() {
      _closed = false;
      _error = null;
      _lastQrAt = DateTime.fromMillisecondsSinceEpoch(0);
      _last = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(_statusInterval, (_) => _poll());
    _poll(forceQr: true);
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 700;
    final s = _last;
    final st = s?.status ?? WapiStatus.initializing;

    final qrImage = s?.qrImage;
    Widget body;
    if (st == WapiStatus.connected) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 72),
          const SizedBox(height: 14),
          Text(
            '¡Conectado!',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (s?.phoneNumber != null) ...[
            const SizedBox(height: 4),
            Text(s!.phoneNumber!,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ],
      );
    } else if (st == WapiStatus.failed) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 60),
          const SizedBox(height: 12),
          const Text(
            'No se pudo conectar el bot.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Suele resolverse reintentando. Si ya lo intentaste varias veces, '
            'cierra esto y usa «Reconectar bot» en la tarjeta del bot.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _reintentar,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      );
    } else if (s?.requiereConfirmacionManual == true) {
      // `action_required`: OpenWA pide confirmar el aviso "What's new" del
      // teléfono. Mostrar el QR aquí haría que el usuario escanee en vano: la
      // sesión vuelve a caerse a los minutos.
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_android, color: AppColors.warning, size: 60),
          const SizedBox(height: 12),
          const Text(
            'Falta un paso en tu teléfono',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '1. Abre WhatsApp en el teléfono del bot.\n'
            '2. Si aparece una ventana de "Novedades" / "What\'s new", '
            'tócala y ciérrala.\n'
            '3. Vuelve aquí y pulsa «Ya lo confirmé».',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _reintentar,
            icon: const Icon(Icons.check),
            label: const Text('Ya lo confirmé, reintentar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      );
    } else if (qrImage != null) {
      // QR base64
      final base64Part = qrImage.contains(',') ? qrImage.split(',').last : qrImage;
      try {
        final bytes = base64Decode(base64Part);
        body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Image.memory(bytes,
                  width: 260, height: 260, fit: BoxFit.contain),
            ),
            const SizedBox(height: 14),
            const Text(
              '1. Abre WhatsApp en tu teléfono\n'
              '2. Toca Menú → Dispositivos vinculados\n'
              '3. Toca "Vincular un dispositivo" y escanea',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        );
      } catch (_) {
        body = const _Loading(label: 'Generando QR...');
      }
    } else {
      body = _Loading(label: st.label);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWeb ? 0 : 16,
        vertical: 24,
      ),
      child: Container(
        width: isWeb ? 420 : double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.nombreBot,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const Divider(height: 18),
            body,
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: st.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(st.icon, size: 14, color: st.color),
                  const SizedBox(width: 6),
                  Text(st.label,
                      style: TextStyle(
                          color: st.color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Explicación en palabras: el estado solo ("Falta escanear el QR")
            // no dice qué hacer.
            Text(
              st.detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  final String label;
  const _Loading({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 30),
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 16),
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 30),
      ],
    );
  }
}
