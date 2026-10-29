import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/wapi_agotado_config.dart';
import '../models/wapi_agotado_log.dart';
import '../models/wapi_destinatario.dart';
import '../models/wapi_session.dart';
import '../services/wapi_notification_service.dart';
import '../widgets/wapi_destinatario_picker.dart';

/// Configuración de los AVISOS DE AGOTADO: cuando un producto llega a stock 0,
/// el backend avisa a los grupos elegidos aquí, con esta plantilla y estos
/// delays.
///
/// Las tablas que respaldan la feature se crean en una migración aparte. Si
/// aún no están aplicadas, la pantalla NO se rompe: muestra el aviso de
/// "falta aplicar la migración" y deja el guardado deshabilitado.
class WapiAgotadoConfigScreen extends StatefulWidget {
  final int idTienda;
  final List<WapiSession> sesiones;
  final WapiAgotadoConfig? existente;

  const WapiAgotadoConfigScreen({
    super.key,
    required this.idTienda,
    required this.sesiones,
    this.existente,
  });

  @override
  State<WapiAgotadoConfigScreen> createState() =>
      _WapiAgotadoConfigScreenState();
}

class _WapiAgotadoConfigScreenState extends State<WapiAgotadoConfigScreen> {
  final _service = WapiNotificationService.instance;
  final _plantillaCtrl = TextEditingController();

  WapiSession? _sesion;
  bool _activo = false;
  int _delayMin = 5;
  int _delayMax = 10;
  int _cooldown = 60;

  List<WapiDestinatario> _destinatarios = [];
  List<WapiAgotadoLog> _logs = [];
  Map<String, String> _etiquetasChat = {};
  Map<int, String> _nombresProducto = {};

  int? _idConfig;
  bool _saving = false;
  bool _cargandoLogs = true;

  /// `true` cuando las tablas `app_wapi_agotado_*` todavía no existen.
  bool _noDisponible = false;

  /// Delay mínimo permitido por el backend (anti-ban).
  static const int _delayPiso = 5;
  static const int _delayTope = 120;
  static const int _cooldownPiso = 5;
  static const int _cooldownTope = 240;

  @override
  void initState() {
    super.initState();
    final ex = widget.existente;
    _idConfig = ex?.id;
    _activo = ex?.activo ?? false;
    _delayMin = ex?.delayMinSeconds ?? 5;
    _delayMax = ex?.delayMaxSeconds ?? 10;
    _cooldown = ex?.cooldownMinutos ?? 60;
    _plantillaCtrl.text = ex?.plantilla ?? WapiAgotadoConfig.plantillaDefault;
    _plantillaCtrl.addListener(_onPlantillaCambio);
    _sesion = _sesionInicial();
    if (ex != null) {
      _cargarDestinatarios(ex.destinatarioIds);
    } else {
      _cargarConfigRemota();
    }
    _cargarHistorial();
  }

  @override
  void dispose() {
    _plantillaCtrl.removeListener(_onPlantillaCambio);
    _plantillaCtrl.dispose();
    super.dispose();
  }

  void _onPlantillaCambio() {
    if (mounted) setState(() {});
  }

  /// El picker de destinatarios necesita una sesión para listar los grupos del
  /// bot. Preferimos una conectada; si no hay ninguna, sirve cualquiera (los
  /// grupos guardados se leen de la BD y no dependen de la conexión).
  WapiSession? _sesionInicial() {
    if (widget.sesiones.isEmpty) return null;
    for (final s in widget.sesiones) {
      if (s.status == WapiStatus.connected) return s;
    }
    return widget.sesiones.first;
  }

  /// Cuando la pantalla se abre sin configuración cargada (por ejemplo desde
  /// un enlace directo), la busca ella misma. Si las tablas no existen, cae al
  /// modo "no disponible" en vez de lanzar.
  Future<void> _cargarConfigRemota() async {
    try {
      final cfg = await _service.getAgotadoConfig(widget.idTienda);
      if (!mounted) return;
      if (cfg == null) return;
      setState(() {
        _idConfig = cfg.id;
        _activo = cfg.activo;
        _delayMin = cfg.delayMinSeconds;
        _delayMax = cfg.delayMaxSeconds;
        _cooldown = cfg.cooldownMinutos;
        _plantillaCtrl.text = cfg.plantilla;
        if (cfg.idSesion != null) {
          for (final s in widget.sesiones) {
            if (s.id == cfg.idSesion) {
              _sesion ??= s;
              break;
            }
          }
        }
      });
      await _cargarDestinatarios(cfg.destinatarioIds);
    } on WapiAgotadoNoDisponible {
      if (!mounted) return;
      setState(() => _noDisponible = true);
    } catch (_) {
      // Best-effort: se puede seguir editando y guardar.
    }
  }

  Future<void> _cargarDestinatarios(List<int> ids) async {
    try {
      final todos = await _service.getDestinatarios(widget.idTienda);
      if (!mounted) return;
      setState(() {
        _destinatarios = todos
            .where((d) => ids.contains(d.id))
            .toList(growable: false);
      });
    } catch (_) {
      // Sin etiquetas: se muestran los ids guardados al menos.
    }
  }

  Future<void> _cargarHistorial() async {
    try {
      final logs = await _service.getAgotadoLogs(widget.idTienda, limit: 30);
      final etiquetas = await _service.getEtiquetasDestinatarios(
        widget.idTienda,
      );
      final nombres = await _service.getDenominacionesProductos(
        logs.map((l) => l.idProducto).whereType<int>(),
      );
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _etiquetasChat = etiquetas;
        _nombresProducto = nombres;
        _cargandoLogs = false;
      });
    } on WapiAgotadoNoDisponible {
      if (!mounted) return;
      setState(() {
        _noDisponible = true;
        _cargandoLogs = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoLogs = false);
    }
  }

  Future<void> _elegirDestinatarios() async {
    final sesion = _sesion;
    if (sesion == null) {
      _toast('Necesitas al menos un bot creado para elegir grupos.');
      return;
    }
    final r = await WapiDestinatarioPicker.show(
      context,
      idTienda: widget.idTienda,
      sesion: sesion,
    );
    if (r == null || !mounted) return;
    setState(() => _destinatarios = r.destinatarios);
  }

  /// Inserta un placeholder en la posición del cursor (los chips son la forma
  /// de no equivocarse escribiendo `{produto}`).
  void _insertarPlaceholder(String token) {
    final texto = _plantillaCtrl.text;
    final sel = _plantillaCtrl.selection;
    final ini = sel.start >= 0 ? sel.start : texto.length;
    final fin = sel.end >= 0 ? sel.end : texto.length;
    final nuevo = texto.replaceRange(ini, fin, token);
    _plantillaCtrl.value = TextEditingValue(
      text: nuevo,
      selection: TextSelection.collapsed(offset: ini + token.length),
    );
  }

  void _toast(String m, {Color? color}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  Future<void> _guardar() async {
    if (_sesion == null) {
      _toast('Necesitas al menos un bot creado: los avisos salen desde él.');
      return;
    }
    if (_activo && _destinatarios.isEmpty) {
      _toast(
        'Elige al menos un destinatario o desactiva los avisos.',
        color: AppColors.warning,
      );
      return;
    }
    if (_delayMax < _delayMin + 1) {
      _toast('El delay máximo debe ser mayor que el mínimo.');
      return;
    }
    setState(() => _saving = true);
    try {
      final cfg = await _service.saveAgotadoConfig(
        idTienda: widget.idTienda,
        idSesion: _sesion!.id,
        activo: _activo,
        plantilla: _plantillaCtrl.text,
        delayMinSeconds: _delayMin,
        delayMaxSeconds: _delayMax,
        cooldownMinutos: _cooldown,
        destinatarioIds: _destinatarios.map((d) => d.id).toList(),
      );
      if (!mounted) return;
      setState(() => _idConfig = cfg.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Avisos de agotado guardados'),
        ),
      );
      Navigator.of(context).pop(true);
    } on WapiAgotadoNoDisponible catch (e) {
      if (!mounted) return;
      setState(() => _noDisponible = true);
      _toast('$e', color: AppColors.warning);
    } catch (e) {
      if (!mounted) return;
      _toast('Error al guardar: $e', color: AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Avisos de producto agotado'),
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
              const _InfoBanner(
                text:
                    'Cuando un producto llegue a stock 0, se avisará '
                    'automáticamente a los grupos elegidos. El aviso se repite '
                    'como mucho una vez por producto y grupo cada '
                    '"cooldown", para no llenar el chat mientras repones.',
              ),
              if (_noDisponible) ...[
                const SizedBox(height: 10),
                _BannerMigracion(
                  onReintentar: () {
                    setState(() {
                      _noDisponible = false;
                      _cargandoLogs = true;
                    });
                    _cargarConfigRemota();
                    _cargarHistorial();
                  },
                ),
              ],
              const SizedBox(height: 14),
              _Card(
                title: '1. Estado',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _activo
                            ? 'Los avisos están ACTIVADOS.'
                            : 'Los avisos están desactivados: no se enviará '
                                  'nada aunque un producto se agote.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Switch(
                      value: _activo,
                      activeThumbColor: AppColors.success,
                      onChanged: (v) => setState(() => _activo = v),
                    ),
                  ],
                ),
              ),
              _Card(
                title: '2. Bot que envía los avisos',
                child: widget.sesiones.isEmpty
                    ? const Text(
                        'No hay ningún bot creado. Crea uno en "Bots activos" '
                        'para poder enviar avisos.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : DropdownButtonFormField<int>(
                        value: _sesion?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: widget.sesiones
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      s.status.icon,
                                      color: s.status.color,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${s.nombre} (${s.phoneNumber ?? "?"})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          setState(() {
                            for (final s in widget.sesiones) {
                              if (s.id == id) {
                                _sesion = s;
                                break;
                              }
                            }
                          });
                        },
                      ),
              ),
              _Card(
                title: '3. Mensaje del aviso',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _plantillaCtrl,
                      maxLines: 6,
                      minLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Escribe el mensaje...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Toca un dato para insertarlo en el mensaje:',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: WapiAgotadoPlantilla.placeholders.entries
                          .map(
                            (e) => Tooltip(
                              message: e.value,
                              child: ActionChip(
                                label: Text(
                                  e.key,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _insertarPlaceholder(e.key),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    if (WapiAgotadoPlantilla.tokensDesconocidos(
                      _plantillaCtrl.text,
                    ).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _AvisoPlantilla(
                        tokens: WapiAgotadoPlantilla.tokensDesconocidos(
                          _plantillaCtrl.text,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Así lo verán tus clientes:',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        WapiAgotadoPlantilla.render(
                          _plantillaCtrl.text,
                          WapiAgotadoPlantilla.ejemplo,
                        ),
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _Card(
                title: '4. Destinatarios (${_destinatarios.length})',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_destinatarios.isEmpty)
                      const Text(
                        'Sin destinatarios: el aviso no saldrá hasta que '
                        'elija al menos un grupo o número.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textLight,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _destinatarios
                            .map(
                              (d) => Chip(
                                avatar: Icon(
                                  d.tipo == WapiDestinatarioTipo.grupo
                                      ? Icons.group_outlined
                                      : Icons.person_outline,
                                  size: 16,
                                ),
                                label: Text(
                                  d.etiqueta?.isNotEmpty == true
                                      ? d.etiqueta!
                                      : d.chatId,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _elegirDestinatarios,
                        icon: const Icon(Icons.group_add_outlined),
                        label: Text(
                          _destinatarios.isEmpty
                              ? 'Elegir grupos o números'
                              : 'Cambiar destinatarios',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _Card(
                title: '5. Ritmo de envío',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Delay entre mensajes: $_delayMin–$_delayMax s',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Slider(
                      value: _delayMin.toDouble(),
                      // El mínimo nunca llega al tope: el slider del máximo
                      // necesita al menos un valor por encima (min < max).
                      min: _delayPiso.toDouble(),
                      max: (_delayTope - 1).toDouble(),
                      divisions: _delayTope - 1 - _delayPiso,
                      label: '$_delayMin s',
                      onChanged: (v) => setState(() {
                        _delayMin = v.round();
                        if (_delayMax < _delayMin + 1) {
                          _delayMax = _delayMin + 1;
                        }
                      }),
                    ),
                    Slider(
                      value: _delayMax.toDouble(),
                      min: (_delayMin + 1).toDouble(),
                      max: _delayTope.toDouble(),
                      divisions: _delayTope - _delayMin - 1,
                      label: '$_delayMax s',
                      onChanged: (v) => setState(() => _delayMax = v.round()),
                    ),
                    const Divider(height: 18),
                    Text(
                      'Cooldown: $_cooldown min',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Text(
                      'No se repetirá un aviso del mismo producto al mismo '
                      'destino antes de este tiempo.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Slider(
                      value: _cooldown.toDouble(),
                      min: _cooldownPiso.toDouble(),
                      max: _cooldownTope.toDouble(),
                      divisions: _cooldownTope - _cooldownPiso,
                      label: '$_cooldown min',
                      onChanged: (v) => setState(() => _cooldown = v.round()),
                    ),
                  ],
                ),
              ),
              _buildHistorialCard(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: (_saving || _noDisponible) ? null : _guardar,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _idConfig == null
                      ? 'Guardar avisos de agotado'
                      : 'Actualizar avisos de agotado',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistorialCard() {
    final children = <Widget>[];
    if (_cargandoLogs) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    } else if (_noDisponible) {
      children.add(
        const Text(
          'Historial no disponible todavía: falta aplicar la migración.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      );
    } else if (_logs.isEmpty) {
      children.add(
        const Text(
          'Todavía no se ha enviado ningún aviso. Cuando un producto se agote, '
          'aparecerá aquí con su resultado.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      );
    } else {
      for (final log in _logs) {
        children.add(
          _LogTile(
            log: log,
            nombreProducto: log.idProducto == null
                ? null
                : _nombresProducto[log.idProducto],
            etiquetaChat: log.idDestinatario == null
                ? _etiquetasChat[log.chatId]
                : _nombreDestinatario(log.idDestinatario!),
          ),
        );
      }
    }
    return _Card(
      title: '6. Historial reciente',
      trailing: _noDisponible
          ? null
          : IconButton(
              tooltip: 'Actualizar historial',
              icon: const Icon(Icons.refresh, size: 20),
              color: AppColors.textSecondary,
              onPressed: () {
                setState(() => _cargandoLogs = true);
                _cargarHistorial();
              },
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// Etiqueta de un destinatario por id, cuando el log la trae y aún no
  /// tenemos el `chat_id` mapeado.
  String? _nombreDestinatario(int idDestinatario) {
    for (final d in _destinatarios) {
      if (d.id == idDestinatario) {
        return d.etiqueta?.isNotEmpty == true ? d.etiqueta : d.chatId;
      }
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Widgets de apoyo
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Card({required this.title, required this.child, this.trailing});

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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
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
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            color: AppColors.info,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de migración pendiente: la feature entera depende de tablas que
/// todavía no existen. Se dice qué pasa y que el resto sigue funcionando.
class _BannerMigracion extends StatelessWidget {
  final VoidCallback onReintentar;
  const _BannerMigracion({required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.construction, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Avisos de agotado no disponibles todavía: falta aplicar '
                  'la migración.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Puedes preparar el mensaje, pero no se guardará hasta que '
                  'el backend esté actualizado.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reintentar',
            icon: const Icon(Icons.refresh, size: 20),
            color: AppColors.warning,
            onPressed: onReintentar,
          ),
        ],
      ),
    );
  }
}

class _AvisoPlantilla extends StatelessWidget {
  final List<String> tokens;
  const _AvisoPlantilla({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Estos datos no se reemplazarán (revisa cómo se escriben): '
              '${tokens.join(', ')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final WapiAgotadoLog log;
  final String? nombreProducto;
  final String? etiquetaChat;

  const _LogTile({required this.log, this.nombreProducto, this.etiquetaChat});

  Color get _color {
    switch (log.estado) {
      case WapiAgotadoEstado.enviado:
        return AppColors.success;
      case WapiAgotadoEstado.fallido:
        return AppColors.error;
      case WapiAgotadoEstado.pendiente:
        return AppColors.warning;
      case WapiAgotadoEstado.omitido:
        return AppColors.textLight;
    }
  }

  IconData get _icon {
    switch (log.estado) {
      case WapiAgotadoEstado.enviado:
        return Icons.check_circle_outline;
      case WapiAgotadoEstado.fallido:
        return Icons.error_outline;
      case WapiAgotadoEstado.pendiente:
        return Icons.schedule;
      case WapiAgotadoEstado.omitido:
        return Icons.remove_circle_outline;
    }
  }

  String get _fecha {
    final d = log.sentAt ?? log.createdAt;
    if (d == null) return '';
    final l = d.toLocal();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(l.day)}/${dos(l.month)} ${dos(l.hour)}:${dos(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 18, color: _color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreProducto ??
                      (log.idProducto == null
                          ? 'Producto'
                          : 'Producto #${log.idProducto}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${log.estado.label} • '
                  '${etiquetaChat ?? _etiquetaCorta(log.chatId)}'
                  '${_fecha.isEmpty ? '' : ' • $_fecha'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: _color),
                ),
                if (log.errorMessage != null &&
                    log.errorMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${log.errorCode ?? 'Error'}: ${log.errorMessage}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _etiquetaCorta(String chatId) {
    if (chatId.isEmpty) return 'destino desconocido';
    final id = chatId.split('@').first;
    return id.length > 12 ? '...${id.substring(id.length - 8)}' : id;
  }
}
