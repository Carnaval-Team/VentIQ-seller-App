import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/wapi_destinatario.dart';
import '../models/wapi_programacion.dart';
import '../models/wapi_session.dart';
import '../services/wapi_notification_service.dart';
import '../utils/timezone_helper.dart';
import '../widgets/wapi_destinatario_picker.dart';
import 'wapi_product_selector_screen.dart';

/// Configuración de envío automático diario (Plan Avanzado).
class WapiScheduleConfigScreen extends StatefulWidget {
  final int idTienda;
  final List<WapiSession> sesiones;
  final WapiProgramacion? existente;

  const WapiScheduleConfigScreen({
    super.key,
    required this.idTienda,
    required this.sesiones,
    this.existente,
  });

  @override
  State<WapiScheduleConfigScreen> createState() =>
      _WapiScheduleConfigScreenState();
}

class _WapiScheduleConfigScreenState extends State<WapiScheduleConfigScreen> {
  final _service = WapiNotificationService.instance;

  WapiSession? _sesion;
  TimeOfDay _hora = const TimeOfDay(hour: 10, minute: 0);
  bool _activa = true;
  int _delayMin = 5;
  int _delayMax = 10;

  Set<int> _productIds = {};
  List<WapiDestinatario> _destinatarios = [];

  bool _saving = false;

  /// Zona IANA detectada del dispositivo (ej. 'America/Havana').
  /// Si la programación ya existe y trae otra zona, mostramos ambas.
  String? _detectedTz;

  /// Zona que se GUARDARÁ. Antes se tomaba siempre la detectada, pero la
  /// detección puede fallar (navegadores con VPN, perfiles mal configurados)
  /// y entonces el cron dispara a una hora que no es la del cliente — sin
  /// error visible, simplemente "no se envía a las 9". Ahora es explícita y
  /// editable.
  String? _tzSeleccionada;

  @override
  void initState() {
    super.initState();
    if (widget.existente != null) {
      _hora = widget.existente!.horaEnvio;
      _activa = widget.existente!.activa;
      _delayMin = widget.existente!.delayMinSeconds;
      _delayMax = widget.existente!.delayMaxSeconds;
      _productIds = widget.existente!.productIds.toSet();
      // Respetamos la zona ya guardada: si el usuario la corrigió, no la
      // pisamos con la del dispositivo al reeditar.
      _tzSeleccionada = widget.existente!.timezone;
      _sesion = widget.sesiones.firstWhere(
        (s) => s.id == widget.existente!.idSesion,
        orElse: () => widget.sesiones.first,
      );
      _loadExistingDestinatarios();
    } else {
      _sesion = widget.sesiones.first;
    }
    _resolveTimezone();
  }

  Future<void> _resolveTimezone() async {
    final tz = await TimezoneHelper.getLocalTimezone();
    if (!mounted) return;
    setState(() {
      _detectedTz = tz;
      _tzSeleccionada ??= tz;
    });
  }

  /// Zonas ofrecidas en el selector: las habituales de la base de clientes
  /// más la detectada y la ya guardada (para no perderlas si son exóticas).
  List<String> get _opcionesTz {
    final base = <String>[
      'America/Havana',
      'America/Mexico_City',
      'America/Bogota',
      'America/Santo_Domingo',
      'America/New_York',
      'America/Santiago',
      'Europe/Madrid',
    ];
    final set = <String>{
      if (_detectedTz != null) _detectedTz!,
      if (_tzSeleccionada != null) _tzSeleccionada!,
      ...base,
    };
    return set.toList()..sort();
  }

  Future<void> _loadExistingDestinatarios() async {
    if (widget.existente == null) return;
    final all = await _service.getDestinatarios(widget.idTienda);
    if (!mounted) return;
    setState(() {
      _destinatarios = all
          .where((d) => widget.existente!.destinatarioIds.contains(d.id))
          .toList();
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _hora);
    if (t != null) setState(() => _hora = t);
  }

  Future<void> _pickProducts() async {
    final ids = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => WapiProductSelectorScreen(
          idTienda: widget.idTienda,
          mode: WapiProductSelectorMode.schedule,
          initialSelected: _productIds,
        ),
      ),
    );
    if (ids != null) setState(() => _productIds = ids.toSet());
  }

  Future<void> _pickDestinatarios() async {
    if (_sesion == null) return;
    final r = await WapiDestinatarioPicker.show(
      context,
      idTienda: widget.idTienda,
      sesion: _sesion!,
    );
    if (r != null) setState(() => _destinatarios = r.destinatarios);
  }

  Future<void> _save() async {
    if (_sesion == null) {
      _toast('Selecciona un bot');
      return;
    }
    if (_productIds.isEmpty) {
      _toast('Selecciona al menos un producto');
      return;
    }
    if (_destinatarios.isEmpty) {
      _toast('Selecciona al menos un destinatario');
      return;
    }
    if (_delayMax < _delayMin + 1) {
      _toast('El delay máximo debe ser mayor que el mínimo');
      return;
    }
    if (_delayMin < 5) {
      _toast('El delay mínimo no puede ser menor a 5 s');
      return;
    }
    setState(() => _saving = true);
    try {
      // Asegura que la zona ya esté resuelta antes de guardar (evita
      // condición de carrera si el usuario toca "Guardar" muy rápido).
      final tz = _tzSeleccionada ??
          _detectedTz ??
          await TimezoneHelper.getLocalTimezone();
      await _service.saveProgramacion(
        idTienda: widget.idTienda,
        idSesion: _sesion!.id,
        hora: _hora,
        productIds: _productIds.toList(),
        destinatarioIds: _destinatarios.map((d) => d.id).toList(),
        activa: _activa,
        delayMinSeconds: _delayMin,
        delayMaxSeconds: _delayMax,
        timezone: tz,
        idExistente: widget.existente?.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: AppColors.success,
        content: Text('Programación guardada'),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.existente == null
            ? 'Nueva programación diaria'
            : 'Editar programación diaria'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWeb ? 760 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoBanner(
                text:
                    'Esta programación se ejecutará una vez al día a la hora '
                    'configurada en tu zona horaria local. Los mensajes se '
                    'enviarán con un delay aleatorio entre $_delayMin–$_delayMax '
                    'segundos para reducir el riesgo de bloqueo por WhatsApp.',
              ),
              if (_detectedTz != null) ...[
                const SizedBox(height: 8),
                _TimezoneNotice(
                  detected: _detectedTz!,
                  seleccionada: _tzSeleccionada,
                  opciones: _opcionesTz,
                  onCambiar: (tz) => setState(() => _tzSeleccionada = tz),
                ),
              ],
              const SizedBox(height: 14),
              _Card(
                title: '1. Bot a usar',
                child: DropdownButtonFormField<int>(
                  value: _sesion?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: widget.sesiones
                      .map((s) => DropdownMenuItem<int>(
                            value: s.id,
                            child: Row(children: [
                              Icon(s.status.icon,
                                  color: s.status.color, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${s.nombre} (${s.phoneNumber ?? "?"})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                          ))
                      .toList(),
                  onChanged: (id) => setState(() =>
                      _sesion = widget.sesiones.firstWhere((s) => s.id == id)),
                ),
              ),
              _Card(
                title: '2. Hora de envío diaria',
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time,
                                  color: AppColors.primary),
                              const SizedBox(width: 10),
                              Text(
                                _hora.format(context),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: _activa,
                      activeColor: AppColors.success,
                      onChanged: (v) => setState(() => _activa = v),
                    ),
                    Text(_activa ? 'Activa' : 'Pausada',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              _Card(
                title: '3. Productos (${_productIds.length})',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _productIds.isEmpty
                            ? 'Sin productos seleccionados'
                            : '${_productIds.length} producto(s) configurado(s)',
                        style: TextStyle(
                          color: _productIds.isEmpty
                              ? AppColors.textLight
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickProducts,
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: const Text('Seleccionar'),
                    ),
                  ],
                ),
              ),
              _Card(
                title: '4. Destinatarios (${_destinatarios.length})',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _destinatarios.isEmpty
                            ? 'Sin destinatarios'
                            : _destinatarios
                                .map((d) => d.etiqueta ?? d.chatId)
                                .take(3)
                                .join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _destinatarios.isEmpty
                              ? AppColors.textLight
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickDestinatarios,
                      icon: const Icon(Icons.group_outlined),
                      label: const Text('Seleccionar'),
                    ),
                  ],
                ),
              ),
              _Card(
                title: '5. Anti-ban: delay entre mensajes',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Cada mensaje se envía con un retraso aleatorio dentro '
                      'del rango. Valores mayores reducen el riesgo de ban.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: _delayMin.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Mín. (seg)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                _delayMin = int.tryParse(v) ?? 5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            initialValue: _delayMax.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Máx. (seg)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                _delayMax = int.tryParse(v) ?? 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(widget.existente == null
                    ? 'Guardar programación'
                    : 'Actualizar programación'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  const _Card({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Muestra la zona horaria detectada del dispositivo y, si el registro
/// existente tiene otra zona guardada, advierte al usuario.
/// Selector de zona horaria de la programación.
///
/// Es un selector y no un simple aviso porque la zona determina a qué hora
/// real dispara el cron: si la detección del dispositivo falla, la difusión
/// sale a una hora equivocada sin producir ningún error visible.
class _TimezoneNotice extends StatelessWidget {
  final String detected;
  final String? seleccionada;
  final List<String> opciones;
  final ValueChanged<String> onCambiar;

  const _TimezoneNotice({
    required this.detected,
    required this.seleccionada,
    required this.opciones,
    required this.onCambiar,
  });

  @override
  Widget build(BuildContext context) {
    final tz = seleccionada ?? detected;
    final mismatch = tz != detected;
    final color = mismatch ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(mismatch ? Icons.warning_amber_rounded : Icons.public,
                  color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mismatch
                      ? 'Tu dispositivo reporta $detected, pero la difusión '
                          'se programará en $tz. Verifica que sea la zona de '
                          'tu tienda: la hora se interpreta en esta zona.'
                      : 'Zona horaria: $detected (detectada de tu dispositivo). '
                          'La hora se interpreta en esta zona — cámbiala si tu '
                          'tienda está en otra.',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: opciones.contains(tz) ? tz : null,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Zona horaria de la difusión',
            ),
            items: opciones
                .map((o) => DropdownMenuItem(
                      value: o,
                      child: Text(
                        o == detected ? '$o  (tu dispositivo)' : o,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onCambiar(v);
            },
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}
