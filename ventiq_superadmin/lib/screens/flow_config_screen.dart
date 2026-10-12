import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/suscripcion_admin_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/suscripcion_ui.dart';

/// Configuración de la suscripción: los números que el superadmin decide.
///
/// Todo lo que hay aquí gobierna el comportamiento del módulo en la app del
/// cliente **sin recompilar nada**: meses de prueba, días de gracia, datos del
/// comercio para Transfermóvil y el WhatsApp de soporte. Es la respuesta directa
/// al requisito "configurable por el superadmin".
///
/// Se guardan solo las claves que cambian (`admin_config_guardar` hace merge), no
/// la fila completa: así dos superadmins editando secciones distintas no se
/// pisan, y un campo que aquí no se muestre no se reescribe por accidente.
class FlowConfigScreen extends StatefulWidget {
  const FlowConfigScreen({super.key});

  @override
  State<FlowConfigScreen> createState() => _FlowConfigScreenState();
}

class _FlowConfigScreenState extends State<FlowConfigScreen> {
  /// Copia de lo que devolvió el servidor, para calcular el diff al guardar.
  Map<String, dynamic> _original = const {};

  final _mesesTrial = TextEditingController();
  final _diasGracia = TextEditingController();
  final _diasAviso = TextEditingController();
  final _soporte = TextEditingController();
  final _txNumero = TextEditingController();
  final _txTitulo = TextEditingController();
  final _txIntent = TextEditingController();
  final _txUrl = TextEditingController();
  final _moneda = TextEditingController();
  final _horasIntent = TextEditingController();

  bool _trialAuto = true;
  bool _trialPorUsuario = true;
  bool _waNotif = false;
  bool _waBot = false;
  bool _modoPrueba = false;

  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _mesesTrial.dispose();
    _diasGracia.dispose();
    _diasAviso.dispose();
    _soporte.dispose();
    _txNumero.dispose();
    _txTitulo.dispose();
    _txIntent.dispose();
    _txUrl.dispose();
    _moneda.dispose();
    _horasIntent.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final cfg = await SuscripcionAdminService.config();
      if (!mounted) return;
      setState(() {
        _original = cfg;
        _volcarEn(cfg);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  void _volcarEn(Map<String, dynamic> cfg) {
    _mesesTrial.text = '${enteroDe(cfg['trial_meses_default']) ?? 0}';
    _diasGracia.text = '${enteroDe(cfg['dias_gracia']) ?? 0}';
    _diasAviso.text = '${enteroDe(cfg['dias_aviso_previo']) ?? 0}';
    _soporte.text = textoDe(cfg['soporte_whatsapp']);
    _txNumero.text = textoDe(cfg['transfermovil_numero_proveedor']);
    _txTitulo.text = textoDe(cfg['transfermovil_titulo']);
    _txIntent.text = textoDe(cfg['transfermovil_intent_template']);
    _txUrl.text = textoDe(cfg['transfermovil_url_template']);
    _moneda.text = textoDe(cfg['moneda_default'], porDefecto: 'CUP');
    _horasIntent.text = '${enteroDe(cfg['intent_horas_vigencia']) ?? 24}';

    _trialAuto = boolDe(cfg['trial_auto'], porDefecto: true);
    _trialPorUsuario = boolDe(cfg['trial_por_usuario'], porDefecto: true);
    _waNotif = boolDe(cfg['whatsapp_notif_activa']);
    _waBot = boolDe(cfg['whatsapp_bot_activo']);
    _modoPrueba = boolDe(cfg['modo_prueba']);
  }

  /// Construye el mapa de cambios comparando contra lo que había en el servidor.
  ///
  /// Los enteros se comparan como enteros y los booleanos como booleanos: si se
  /// mandara siempre todo, cada guardado marcaría `updated_at` y el historial de
  /// cambios dejaría de servir para saber qué se tocó de verdad.
  Map<String, dynamic> _cambios() {
    final cambios = <String, dynamic>{};

    void entero(String clave, TextEditingController ctrl) {
      final v = int.tryParse(ctrl.text.trim());
      if (v != null && v != enteroDe(_original[clave])) cambios[clave] = v;
    }

    void texto(String clave, TextEditingController ctrl) {
      final v = ctrl.text.trim();
      if (v != textoDe(_original[clave])) cambios[clave] = v;
    }

    void flag(String clave, bool valor) {
      if (valor != boolDe(_original[clave], porDefecto: false)) {
        cambios[clave] = valor;
      }
    }

    entero('trial_meses_default', _mesesTrial);
    entero('dias_gracia', _diasGracia);
    entero('dias_aviso_previo', _diasAviso);
    entero('intent_horas_vigencia', _horasIntent);
    texto('soporte_whatsapp', _soporte);
    texto('transfermovil_numero_proveedor', _txNumero);
    texto('transfermovil_titulo', _txTitulo);
    texto('transfermovil_intent_template', _txIntent);
    texto('transfermovil_url_template', _txUrl);
    texto('moneda_default', _moneda);

    flag('trial_auto', _trialAuto);
    flag('trial_por_usuario', _trialPorUsuario);
    flag('whatsapp_notif_activa', _waNotif);
    flag('whatsapp_bot_activo', _waBot);
    flag('modo_prueba', _modoPrueba);

    return cambios;
  }

  Future<void> _guardar() async {
    final cambios = _cambios();
    if (cambios.isEmpty) {
      _avisar('No hay cambios que guardar.', esError: false);
      return;
    }

    if (!_validar(cambios)) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Guardar configuración'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Estos cambios se aplican de inmediato a todos los clientes:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  ...cambios.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${e.key}: ${_resumir(e.value)}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _guardando = true);
    try {
      final res = await SuscripcionAdminService.guardarConfig(cambios);
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _original = res;
        _volcarEn(res);
      });
      _avisar('Configuración guardada.', esError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar('$e', esError: true);
    }
  }

  bool _validar(Map<String, dynamic> cambios) {
    // Los mismos rangos que tienen los CHECK en la tabla: si se envía fuera de
    // rango el servidor lo rechaza, pero es mejor no hacer el viaje.
    final rangos = <String, (int, int)>{
      'trial_meses_default': (0, 24),
      'dias_gracia': (0, 90),
      'dias_aviso_previo': (0, 90),
      'intent_horas_vigencia': (1, 720),
    };

    for (final r in rangos.entries) {
      final v = cambios[r.key];
      if (v is int && (v < r.value.$1 || v > r.value.$2)) {
        _avisar(
          'El valor de ${r.key} debe estar entre ${r.value.$1} y ${r.value.$2}.',
          esError: true,
        );
        return false;
      }
    }

    // Un WhatsApp de soporte no numérico deja al cliente sin poder reportar.
    final soporte = cambios['soporte_whatsapp'];
    if (soporte is String && soporte.replaceAll(RegExp(r'\D'), '').length < 8) {
      _avisar(
        'El WhatsApp de soporte debe tener al menos 8 dígitos (con el código de país).',
        esError: true,
      );
      return false;
    }

    // Las plantillas se rellenan por sustitución de tokens: si falta $importe o
    // $id_transaccion, Transfermóvil abriría una pantalla de pago incompleta.
    for (final clave in const [
      'transfermovil_intent_template',
      'transfermovil_url_template',
    ]) {
      final t = cambios[clave];
      if (t is String && t.isNotEmpty) {
        for (final token in const ['\$id_transaccion', '\$importe']) {
          if (!t.contains(token)) {
            _avisar(
              'La plantilla $clave debe incluir $token: sin ese dato el pago '
              'no se puede casar con la entidad.',
              esError: true,
            );
            return false;
          }
        }
      }
    }

    return true;
  }

  String _resumir(dynamic v) {
    if (v is String && v.length > 60) return '${v.substring(0, 57)}…';
    return '$v';
  }

  void _avisar(String mensaje, {required bool esError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppColors.error : AppColors.success,
        duration: Duration(seconds: esError ? 6 : 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Configuración de suscripciones'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _cargando || _guardando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Guardar cambios',
            onPressed: _cargando || _guardando ? null : _guardar,
            icon:
                _guardando
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 44, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
      children: [
        _Seccion(
          titulo: 'Prueba gratuita',
          descripcion:
              'Meses gratis que recibe una entidad nueva al crearse (x 30 días).',
          children: [
            _CampoNumero(
              controlador: _mesesTrial,
              etiqueta: 'Meses gratis por entidad',
              ayuda: '0 = las entidades nuevas nacen sin plan',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Otorgar la prueba automáticamente'),
              subtitle: const Text(
                'Si se apaga, el tiempo se acredita a mano desde la bandeja.',
                style: TextStyle(fontSize: 12),
              ),
              value: _trialAuto,
              onChanged: (v) => setState(() => _trialAuto = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Una prueba por usuario'),
              subtitle: const Text(
                'Un mismo dueño recibe la prueba una sola vez; sus demás '
                'entidades nacen sin plan hasta pagar.',
                style: TextStyle(fontSize: 12),
              ),
              value: _trialPorUsuario,
              onChanged: (v) => setState(() => _trialPorUsuario = v),
            ),
          ],
        ),
        _Seccion(
          titulo: 'Corte y avisos',
          descripcion:
              'El margen de retraso antes de desactivar la entidad y con cuánta '
              'antelación se avisa del vencimiento.',
          children: [
            _CampoNumero(
              controlador: _diasGracia,
              etiqueta: 'Días de gracia tras el vencimiento',
              ayuda:
                  'Durante la gracia la entidad sigue funcionando y se avisa del '
                  'impago. Al agotarse, deja de mostrarse y no admite reservas. '
                  'Se aplica a los vencimientos que ocurran a partir de ahora.',
            ),
            _CampoNumero(
              controlador: _diasAviso,
              etiqueta: 'Días de antelación del aviso',
              ayuda: 'Cuándo empieza a aparecer "tu suscripción vence pronto".',
            ),
          ],
        ),
        _Seccion(
          titulo: 'Transfermóvil',
          descripcion:
              'Datos del comercio con los que la app arma el pago. Los tokens '
              'disponibles son \$id_transaccion, \$importe, \$moneda, '
              '\$numero_proveedor y \$titulo.',
          children: [
            _CampoTexto(
              controlador: _txNumero,
              etiqueta: 'Número del comercio',
            ),
            _CampoTexto(
              controlador: _txTitulo,
              etiqueta: 'Título / comercio',
              ayuda: 'Es el texto que ve el cliente en Transfermóvil.',
            ),
            _CampoTexto(
              controlador: _moneda,
              etiqueta: 'Moneda',
              ayuda: 'En esta versión solo se usa CUP.',
            ),
            _CampoNumero(
              controlador: _horasIntent,
              etiqueta: 'Horas de vigencia de un intento de pago',
              ayuda:
                  'Pasado ese tiempo el intento vence y hay que generar otro. '
                  'No afecta a un pago ya reportado.',
            ),
            _CampoTexto(
              controlador: _txIntent,
              etiqueta: 'Plantilla del deep link',
              maxLineas: 3,
              monoespaciado: true,
            ),
            _CampoTexto(
              controlador: _txUrl,
              etiqueta: 'Plantilla del enlace https (respaldo)',
              maxLineas: 3,
              monoespaciado: true,
              ayuda:
                  'Se usa cuando el dispositivo no tiene la app instalada, para '
                  'copiar y pegar el enlace.',
            ),
          ],
        ),
        _Seccion(
          titulo: 'WhatsApp',
          descripcion:
              'A quién escribe el cliente cuando reporta un pago y si el sistema '
              'puede avisar solo.',
          children: [
            _CampoTexto(
              controlador: _soporte,
              etiqueta: 'WhatsApp de soporte',
              ayuda:
                  'Formato internacional sin "+": 5354590207. La app lo abre con '
                  'wa.me, así que si no hay WhatsApp instalado el mensaje se puede '
                  'copiar.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enviar avisos por WhatsApp (servidor)'),
              subtitle: const Text(
                'Avisos al cliente desde el outbox del servidor.',
                style: TextStyle(fontSize: 12),
              ),
              value: _waNotif,
              onChanged: (v) => setState(() => _waNotif = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bot de WhatsApp conectado'),
              subtitle: Text(
                _waBot
                    ? 'Los avisos quedan en cola para que los envíe el bot.'
                    : 'Sin bot conectado. Los avisos se registran como omitidos '
                        'y el cliente los ve dentro de la app; no se acumula una '
                        'cola que nadie vacía.',
                style: const TextStyle(fontSize: 12),
              ),
              value: _waBot,
              onChanged: (v) => setState(() => _waBot = v),
            ),
          ],
        ),
        _Seccion(
          titulo: 'Avanzado',
          descripcion:
              'Solo para pruebas del circuito de pago. Ninguna de estas opciones '
              'acredita tiempo automáticamente.',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Modo prueba'),
              subtitle: const Text(
                'Marca los pagos como de prueba para poder distinguirlos. La '
                'verificación del pago sigue siendo manual.',
                style: TextStyle(fontSize: 12),
              ),
              value: _modoPrueba,
              onChanged: (v) => setState(() => _modoPrueba = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar cambios'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Última actualización: ${fechaHora(fechaDe(_original['updated_at']))}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.titulo,
    required this.descripcion,
    required this.children,
  });

  final String titulo;
  final String descripcion;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TarjetaFlow(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              descripcion,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CampoTexto extends StatelessWidget {
  const _CampoTexto({
    required this.controlador,
    required this.etiqueta,
    this.ayuda,
    this.maxLineas = 1,
    this.monoespaciado = false,
  });

  final TextEditingController controlador;
  final String etiqueta;
  final String? ayuda;
  final int maxLineas;
  final bool monoespaciado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controlador,
        maxLines: maxLineas,
        minLines: 1,
        style:
            monoespaciado
                ? const TextStyle(fontSize: 12, fontFamily: 'monospace')
                : null,
        decoration: InputDecoration(
          labelText: etiqueta,
          helperText: ayuda,
          helperMaxLines: 4,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _CampoNumero extends StatelessWidget {
  const _CampoNumero({
    required this.controlador,
    required this.etiqueta,
    this.ayuda,
  });

  final TextEditingController controlador;
  final String etiqueta;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controlador,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: etiqueta,
          helperText: ayuda,
          helperMaxLines: 4,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
