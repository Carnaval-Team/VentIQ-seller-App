import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/cobro.dart';
import '../../models/entidad.dart';
import '../../services/cobro_service.dart';
import '../../tutorial/tutorial_anchor.dart';
import '../../utils/esquema_pendiente.dart';
import 'cobro_config_screen.dart';
import 'pagos_reserva_screen.dart';

/// Pantalla dedicada de **pagos por adelantado** de una entidad.
///
/// Antes esta función vivía dentro de «Mi suscripción», mezclada con el plan y
/// el pago de la suscripción. Ahora tiene su propio sitio: el cobro por
/// adelantado es del **servicio** del cliente (la reserva), no de la
/// suscripción del negocio, y son dos circuitos distintos con dos administradores
/// distintos (el admin de la entidad vs. el superadmin).
///
/// No hay lógica de negocio nueva: la pantalla es una portada que reutiliza
/// [CobroService], [CobroConfigScreen] y [PagosReservaScreen]. Lo único que
/// decide por su cuenta es qué contar como «pago por verificar»
/// (`creado`/`reportado`), que es el mismo criterio que usa la bandeja.
class CobrosScreen extends StatefulWidget {
  const CobrosScreen({super.key, required this.entidad});

  /// Entidad cuyos cobros se gestionan. El contrato con el tutorial es esta
  /// firma exacta (la navegación del tutorial la instancia así).
  final Entidad entidad;

  @override
  State<CobrosScreen> createState() => _CobrosScreenState();
}

class _CobrosScreenState extends State<CobrosScreen> {
  CobroConfig? _config;

  /// Pagos de reservas esperando verificación (badge de la bandeja).
  int _porVerificar = 0;

  bool _cargando = true;

  /// La migración 62 todavía no está aplicada (o el RPC no existe aún): se avisa
  /// en vez de pintar el error crudo del servidor.
  bool _esquemaPendiente = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Carga config y contador **por separado**.
  ///
  /// El contador es accesorio: si falla (o falta la migración), la pantalla sigue
  /// siendo útil y solo se pierde el número del badge. La config sí es el dato
  /// principal, y su fallo decide entre «reintentar» y «migración pendiente».
  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    CobroConfig? config;
    var porVerificar = 0;
    var esquemaPendiente = false;
    String? error;

    try {
      config = await CobroService.configGet(widget.entidad.id);
    } catch (e) {
      if (esErrorDeEsquemaAusente(e)) {
        esquemaPendiente = true;
      } else {
        error = _mensaje(e);
      }
    }

    if (!esquemaPendiente) {
      try {
        final pagos = await CobroService.listarPagos(
          idEntidad: widget.entidad.id,
        );
        porVerificar = pagos
            .where(
              (p) => p.pago.estado == 'creado' || p.pago.estado == 'reportado',
            )
            .length;
      } catch (e) {
        // Silencio deliberado salvo por el esquema: un contador caído no puede
        // tumbar la pantalla entera.
        if (esErrorDeEsquemaAusente(e)) esquemaPendiente = true;
      }
    }

    if (!mounted) return;
    setState(() {
      _config = config;
      _porVerificar = porVerificar;
      _esquemaPendiente = esquemaPendiente;
      _error = error;
      _cargando = false;
    });
  }

  Future<void> _abrirConfig() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CobroConfigScreen(entidad: widget.entidad),
      ),
    );
    if (mounted) await _cargar();
  }

  Future<void> _abrirPagos() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PagosReservaScreen(entidad: widget.entidad),
      ),
    );
    if (mounted) await _cargar();
  }

  String _mensaje(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '').trim();
    return texto.isEmpty
        ? 'No se pudo cargar la configuración de cobro.'
        : texto;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Pagos por adelantado'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          // `AlwaysScrollable`: con poco contenido el gesto de refrescar también
          // tiene que funcionar.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            if (_esquemaPendiente)
              const _Aviso(
                icono: Icons.construction,
                texto:
                    'El cobro por adelantado todavía no está disponible: falta '
                    'activarlo en el servidor. Vuelve a intentarlo más tarde.',
              )
            else if (_error != null)
              _Aviso(
                icono: Icons.cloud_off,
                texto: _error!,
                accion: TextButton(
                  onPressed: _cargar,
                  child: const Text('Reintentar'),
                ),
              )
            else if (_config == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _TarjetaEstado(
                config: _config!,
                onConfigurar: _abrirConfig,
              ),

            const SizedBox(height: 12),

            // La tarjeta del tutorial vive aquí, fuera del ternario anterior: así
            // existe siempre (cargando, con error o sin migración) y el paso que
            // la resalta no depende de que el RPC haya contestado.
            _TarjetaPagos(
              pendientes: _porVerificar,
              habilitado: !_esquemaPendiente,
              onTap: _abrirPagos,
            ),

            const SizedBox(height: 12),

            _TarjetaConfigurar(
              habilitado: !_esquemaPendiente,
              onTap: _abrirConfig,
            ),

            const SizedBox(height: 22),
            const _ComoTrabaja(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Piezas de UI ──────────────────────────────

/// Tarjeta de estado: si el cobro está activo y con qué datos cobra.
///
/// Es lo primero que mira el admin porque contesta a la única pregunta que no
/// puede resolver solo: «¿está funcionando?».
class _TarjetaEstado extends StatelessWidget {
  const _TarjetaEstado({required this.config, required this.onConfigurar});

  final CobroConfig config;
  final VoidCallback onConfigurar;

  @override
  Widget build(BuildContext context) {
    // `cobrando` = activo **y** con número de proveedor; la BD no admite activo
    // sin número, así que la invariante es la misma aquí y en el servidor.
    final activo = config.cobrando;
    final color = activo ? AppTheme.success : AppTheme.warning;
    final whatsapp = config.whatsappVerificacion?.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                activo ? Icons.verified_outlined : Icons.power_settings_new,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activo ? 'Cobro activo' : 'Sin activar',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              _Pildora(texto: activo ? 'Activo' : 'Inactivo', color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            activo
                ? 'Tus clientes pueden pagar la reserva por adelantado desde la '
                      'app. Los pagos que reporten te llegan a «Pagos por '
                      'verificar».'
                : 'El cobro está apagado. Para activarlo necesitas tu número de '
                      'proveedor de Transfermóvil y, si quieres, el WhatsApp '
                      'donde recibir los comprobantes.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _Dato(
            etiqueta: 'Número de proveedor (Transfermóvil)',
            valor: config.numeroProveedor.trim().isEmpty
                ? 'Sin configurar'
                : config.numeroProveedor,
            vacio: config.numeroProveedor.trim().isEmpty,
          ),
          _Dato(etiqueta: 'Moneda', valor: config.moneda),
          _Dato(
            etiqueta: 'Plazo de vigencia',
            valor: _plazoEtiqueta(config.horasVigencia),
          ),
          _Dato(
            etiqueta: 'Si vence el pago',
            valor: config.cancelarSiExpira
                ? 'Se cancela la reserva'
                : 'La reserva queda sin pagar',
          ),
          _Dato(
            etiqueta: 'WhatsApp de verificación',
            valor: (whatsapp == null || whatsapp.isEmpty)
                ? 'Sin configurar'
                : whatsapp,
            vacio: whatsapp == null || whatsapp.isEmpty,
          ),
          if (!activo) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onConfigurar,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Configurar el cobro'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Entrada a la bandeja de pagos. **Ancla del tutorial** `admin_cobro_pagos`.
class _TarjetaPagos extends StatelessWidget {
  const _TarjetaPagos({
    required this.pendientes,
    required this.habilitado,
    required this.onTap,
  });

  final int pendientes;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hay = pendientes > 0;
    final subtitulo = !hay
        ? 'No hay pagos esperando verificación.'
        : pendientes == 1
        ? '1 pago espera tu verificación.'
        : '$pendientes pagos esperan tu verificación.';

    return TutorialAnchor(
      id: 'admin_cobro_pagos',
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hay
                ? AppTheme.warning.withValues(alpha: 0.5)
                : AppTheme.border,
          ),
        ),
        child: ListTile(
          leading: Icon(
            Icons.receipt_long_outlined,
            color: habilitado ? AppTheme.primary : AppTheme.textSecondary,
          ),
          title: const Text(
            'Pagos por verificar',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            subtitulo,
            style: const TextStyle(fontSize: 12, height: 1.3),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hay)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$pendientes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
          onTap: habilitado ? onTap : null,
        ),
      ),
    );
  }
}

/// Entrada a la configuración del cobro (número, moneda, plazo, WhatsApp).
class _TarjetaConfigurar extends StatelessWidget {
  const _TarjetaConfigurar({required this.habilitado, required this.onTap});

  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        leading: Icon(
          Icons.point_of_sale_outlined,
          color: habilitado ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: const Text(
          'Configurar el cobro',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: const Text(
          'Número de proveedor, WhatsApp de verificación, moneda y plazo.',
          style: TextStyle(fontSize: 12, height: 1.3),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppTheme.textSecondary,
        ),
        onTap: habilitado ? onTap : null,
      ),
    );
  }
}

/// Los tres pasos del circuito, contados como los vive el cliente.
///
/// No es decorativo: el admin no tiene forma de saber, sin salir de la app, que
/// el cobro no acredita nada por sí solo y que el último paso es suyo.
class _ComoTrabaja extends StatelessWidget {
  const _ComoTrabaja();

  static const List<_PasoCobro> _pasos = [
    _PasoCobro(
      titulo: 'El cliente paga con Transfermóvil',
      detalle:
          'Desde su reserva, con el número de proveedor que configuraste y el '
          'plazo que le hayas dado.',
    ),
    _PasoCobro(
      titulo: 'Marca «Ya he pagado»',
      detalle:
          'Te llega el aviso con el código de confirmación y el comprobante al '
          'WhatsApp de verificación.',
    ),
    _PasoCobro(
      titulo: 'Tú verificas el pago',
      detalle:
          'Lo confirmas en «Pagos por verificar» y la reserva queda pagada. Si '
          'lo rechazas, el cliente puede volver a reportarlo.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cómo funciona',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _pasos.length; i++)
                _FilaPaso(numero: i + 1, paso: _pasos[i]),
            ],
          ),
        ),
      ],
    );
  }
}

class _PasoCobro {
  const _PasoCobro({required this.titulo, required this.detalle});

  final String titulo;
  final String detalle;
}

class _FilaPaso extends StatelessWidget {
  const _FilaPaso({required this.numero, required this.paso});

  final int numero;
  final _PasoCobro paso;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$numero',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paso.titulo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  paso.detalle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso en tarjeta para «migración pendiente» y para el error de carga.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto, this.accion});

  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: AppTheme.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (accion != null) accion!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila «etiqueta / valor» de la tarjeta de estado.
class _Dato extends StatelessWidget {
  const _Dato({
    required this.etiqueta,
    required this.valor,
    this.vacio = false,
  });

  final String etiqueta;
  final String valor;

  /// El valor está sin configurar: se pinta en secundario y en cursiva para que
  /// no se confunda con un dato real.
  final bool vacio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: vacio ? FontWeight.w400 : FontWeight.w700,
                fontStyle: vacio ? FontStyle.italic : FontStyle.normal,
                color: vacio ? AppTheme.textSecondary : AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pildora extends StatelessWidget {
  const _Pildora({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// «24 horas» / «2 días». Es el mismo texto en lenguaje llano para el admin.
String _plazoEtiqueta(int horas) {
  if (horas <= 1) return '1 hora';
  if (horas < 48) return '$horas horas';
  final dias = horas ~/ 24;
  return dias == 1 ? '1 día' : '$dias días';
}
