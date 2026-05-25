import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/wapi_session.dart';
import '../services/wapi_notification_service.dart';

/// Modal/bottom sheet para crear un nuevo bot WhatsApp.
/// Devuelve la `WapiSession` creada, o null si se cancela.
class WapiAddBotSheet extends StatefulWidget {
  final int idTienda;
  const WapiAddBotSheet({super.key, required this.idTienda});

  static Future<WapiSession?> show(BuildContext context, {required int idTienda}) {
    final isWeb = MediaQuery.of(context).size.width >= 700;
    if (isWeb) {
      return showDialog<WapiSession>(
        context: context,
        builder: (_) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 420,
            child: WapiAddBotSheet(idTienda: idTienda),
          ),
        ),
      );
    }
    return showModalBottomSheet<WapiSession>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: WapiAddBotSheet(idTienda: idTienda),
      ),
    );
  }

  @override
  State<WapiAddBotSheet> createState() => _WapiAddBotSheetState();
}

class _WapiAddBotSheetState extends State<WapiAddBotSheet> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final s = await WapiNotificationService.instance.createSession(
        idTienda: widget.idTienda,
        nombre: _ctrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(s);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.add_circle_outline, color: AppColors.primary),
                SizedBox(width: 10),
                Text(
                  'Nuevo bot WhatsApp',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Asigna un nombre para identificar este bot. '
              'Después escanearás el QR para vincular un teléfono.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ctrl,
              autofocus: true,
              maxLength: 40,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Nombre del bot',
                hintText: 'Ej: Promociones tienda 1',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.smart_toy_outlined),
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Indica un nombre';
                if (t.length < 3) return 'Mínimo 3 caracteres';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style:
                        const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _create,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.qr_code_2),
                  label: const Text('Crear y mostrar QR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
