import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../services/cobro_service.dart';

/// Configuración del **cobro por adelantado** de una entidad.
///
/// Es una sola configuración por entidad (vale para todos sus locales): el
/// número de proveedor de Transfermóvil del admin, su WhatsApp de verificación,
/// las instrucciones que verá el cliente, la moneda de cobro y el plazo del
/// intento.
///
/// Aviso de la BD que la pantalla anticipa: `flow.admin_cobro_config_set`
/// **rechaza** activar el cobro sin número de proveedor. Aquí se explica por qué
/// antes de gastar el viaje de red, que es el único error de esta pantalla que el
/// admin puede corregir sin ayuda.
class CobroConfigScreen extends StatefulWidget {
  /// Acepta la entidad completa ([entidad]) o solo su id ([idEntidad]), para
  /// poderla abrir tanto desde pantallas que ya tienen el objeto como desde «Mi
  /// suscripción», que solo conoce el identificador.
  CobroConfigScreen({
    super.key,
    Entidad? entidad,
    int? idEntidad,
    String? nombreEntidad,
  }) : entidad = entidad,
       idEntidad = idEntidad ?? entidad?.id ?? 0,
       nombreEntidad = nombreEntidad ?? entidad?.denominacion;

  final Entidad? entidad;
  final int idEntidad;
  final String? nombreEntidad;

  @override
  State<CobroConfigScreen> createState() => _CobroConfigScreenState();
}

class _CobroConfigScreenState extends State<CobroConfigScreen> {
  final _form = GlobalKey<FormState>();

  final _numero = TextEditingController();
  final _titulo = TextEditingController();
  final _whatsapp = TextEditingController();
  final _soporte = TextEditingController();
  final _instrucciones = TextEditingController();
  final _horas = TextEditingController();

  bool _activo = false;
  bool _cancelarSiExpira = true;
  String _moneda = 'CUP';

  bool _cargando = true;
  bool _guardando = false;
  String? _errorCarga;
  bool _guardado = false;

  static const _monedas = ['CUP', 'USD', 'EUR', 'MLC'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _numero.dispose();
    _titulo.dispose();
    _whatsapp.dispose();
    _soporte.dispose();
    _instrucciones.dispose();
    _horas.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (widget.idEntidad <= 0) {
      setState(() {
        _cargando = false;
        _errorCarga = 'No se pudo resolver la entidad. Vuelve a entrar.';
      });
      return;
    }

    setState(() {
      _cargando = true;
      _errorCarga = null;
    });

    try {
      final config = await CobroService.configGet(widget.idEntidad);
      if (!mounted) return;
      setState(() {
        _activo = config.activo;
        _cancelarSiExpira = config.cancelarSiExpira;
        _moneda = _monedas.contains(config.moneda) ? config.moneda : 'CUP';
        _numero.text = config.numeroProveedor;
        _titulo.text = config.titulo;
        _whatsapp.text = config.whatsappVerificacion ?? '';
        _soporte.text = config.soporteWhatsapp ?? '';
        _instrucciones.text = config.instrucciones ?? '';
        _horas.text = '${config.horasVigencia}';
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _errorCarga = _mensaje(e);
      });
    }
  }

  String _mensaje(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '').trim();
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  void _avisar(String mensaje, {required bool esError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: esError ? 5 : 3),
      ),
    );
  }

  /// Explica por qué no se puede activar sin número **antes** de llamar a la BD.
  Future<void> _explicarFaltaNumero() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: AppTheme.error),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Falta el número de proveedor',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: const Text(
          'Para activar el cobro por adelantado hace falta el número de '
          'proveedor de Transfermóvil: es la cuenta donde tus clientes van a '
          'pagar, y sin él no hay a dónde transferir.\n\n'
          'Escribe el número y vuelve a guardar. Mientras tanto, el cobro por '
          'adelantado queda apagado.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    final numero = _numero.text.trim();
    if (_activo && numero.isEmpty) {
      await _explicarFaltaNumero();
      return;
    }

    final horas = int.tryParse(_horas.text.trim()) ?? 24;
    if (horas < 1 || horas > 720) {
      _avisar('El plazo debe estar entre 1 y 720 horas.', esError: true);
      return;
    }

    setState(() => _guardando = true);
    try {
      await CobroService.configSet(
        idEntidad: widget.idEntidad,
        activo: _activo,
        numeroProveedor: numero,
        titulo: _titulo.text.trim(),
        whatsappVerificacion: _whatsapp.text.trim(),
        soporteWhatsapp: _soporte.text.trim(),
        instrucciones: _instrucciones.text.trim(),
        moneda: _moneda,
        horasVigencia: horas,
        cancelarSiExpira: _cancelarSiExpira,
      );
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _guardado = true;
      });
      _avisar('Configuración guardada', esError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar(_mensaje(e), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.nombreEntidad;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_guardado);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(
          title: const Text('Cobro por adelantado'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Guardar',
              onPressed: (_cargando || _guardando) ? null : _guardar,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _errorCarga != null
            ? _errorCargando(_errorCarga!)
            : _formulario(nombre),
        bottomNavigationBar: _cargando || _errorCarga != null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Guardar configuración'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _errorCargando(String error) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.cloud_off, size: 44, color: AppTheme.textSecondary),
        const SizedBox(height: 12),
        const Text(
          'No se pudo cargar la configuración',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _cargar,
            child: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }

  Widget _formulario(String? nombre) {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          _tituloSeccion(
            'Cobro por adelantado',
            'Tus clientes podrán pagar la reserva antes de la cita con '
                'Transfermóvil, y tú confirmas el pago desde la bandeja. '
                '${nombre == null ? '' : 'Aplica a todas las reservas de $nombre.'}',
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: _activo,
            onChanged: _guardando ? null : (v) => setState(() => _activo = v),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppTheme.primary,
            title: const Text(
              'Cobrar por adelantado',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Si lo activas, la ficha de cada servicio mostrará «Pagar por '
              'adelantado» con tu número de proveedor.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(height: 8),

          TextFormField(
            controller: _numero,
            enabled: !_guardando,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Número de proveedor Transfermóvil *',
              helperText: 'Es la cuenta que cobra. Sin él no se puede activar.',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.point_of_sale_outlined),
            ),
            validator: (v) {
              if (_activo && (v ?? '').trim().isEmpty) {
                return 'Escribe el número de proveedor para poder activarlo.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _titulo,
            enabled: !_guardando,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Título que verá el cliente',
              helperText:
                  'Aparece en Transfermóvil. Si lo dejas vacío se usa '
                  'el nombre de tu entidad.',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          const SizedBox(height: 4),

          TextFormField(
            controller: _whatsapp,
            enabled: !_guardando,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
            ],
            decoration: const InputDecoration(
              labelText: 'WhatsApp de verificación',
              helperText:
                  'Tu WhatsApp: ahí te llega el comprobante del '
                  'cliente. Si lo dejas vacío no se muestra ese botón.',
              helperMaxLines: 3,
              prefixIcon: Icon(Icons.chat_outlined),
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _soporte,
            enabled: !_guardando,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
            ],
            decoration: const InputDecoration(
              labelText: 'WhatsApp de soporte (opcional)',
              prefixIcon: Icon(Icons.support_agent_outlined),
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _instrucciones,
            enabled: !_guardando,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Instrucciones para el cliente',
              alignLabelWithHint: true,
              hintText:
                  'Ej.: Paga el importe a este número y mándame el comprobante '
                  'por WhatsApp. Si no puedo verificarlo en el plazo, la reserva '
                  'se libera.',
            ),
          ),
          const SizedBox(height: 4),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _moneda,
                  decoration: const InputDecoration(
                    labelText: 'Moneda de cobro',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  items: [
                    for (final m in _monedas)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _moneda = v ?? 'CUP'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _horas,
                  enabled: !_guardando,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Plazo (horas)',
                    helperText: 'Entre 1 y 720.',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  validator: (v) {
                    final horas = int.tryParse((v ?? '').trim());
                    if (horas == null) return 'Escribe un número.';
                    if (horas < 1 || horas > 720) return 'De 1 a 720.';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          SwitchListTile(
            value: _cancelarSiExpira,
            onChanged: _guardando
                ? null
                : (v) => setState(() => _cancelarSiExpira = v),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppTheme.primary,
            title: const Text(
              'Cancelar la reserva si el pago expira',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Si nadie verifica el pago en el plazo, la reserva se cancela sola '
              'y el turno se libera. Si lo apagas, la reserva se mantiene.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: const Text(
              'La reserva ocupa su turno desde que se crea, aunque el pago esté '
              'pendiente. Verifica o rechaza los pagos en la bandeja de «Pagos '
              'por adelantado».',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tituloSeccion(String titulo, String subtitulo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitulo,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppTheme.textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
