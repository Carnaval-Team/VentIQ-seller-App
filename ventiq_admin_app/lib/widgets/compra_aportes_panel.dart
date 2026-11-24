/// Panel de aportes de inversores de una compra (fase 7 del módulo Compras).
///
/// Se muestra solo con `modo_liquidacion = 'inversores'`, justo debajo de las
/// cifras del detalle. Todo lo que decide —faltante, porcentaje, si se puede
/// pagar y por qué no— lo manda `fn_fdi_compra_aportes`; aquí no se recalcula
/// dinero: solo se pinta, y el diálogo previsualiza lo que el servidor va a
/// validar de todas formas.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/aportes_resumen.dart';
import '../screens/compras/compras_widgets.dart';
import '../services/compra_service.dart';
import '../services/fondo_inversion_service.dart';

// ===========================================================================
// Paleta y formato
// ===========================================================================

/// Fondos de los bloques destacados del panel (misma pareja que usa el resto
/// del módulo para naranja y verde).
const Color _fondoNaranja = Color(0xFFFFF1EC);
const Color _fondoVerde = Color(0xFFE7F7F0);

/// Colores de la barra segmentada: solo colores de la paleta, en ciclo.
const List<Color> _coloresSegmento = [
  AppColors.primary,
  AppColors.info,
  AppColors.success,
  AppColors.warning,
  AppColors.secondary,
];

final NumberFormat _fmtPct = NumberFormat('#,##0.##');
final NumberFormat _fmtTasa = NumberFormat('#,##0.####');

/// Porcentaje sin decimales de relleno: 75.00 → «75», 42.50 → «42.5».
String _porcentaje(num valor) => _fmtPct.format(valor);

/// Tasa de conversión legible: 1 en la misma moneda, si no con sus decimales.
String _tasa(num valor) => valor == 1 ? '1' : _fmtTasa.format(valor.toDouble());

/// Las RPC lanzan `RAISE EXCEPTION` con texto útil en español: se muestra tal
/// cual, sin el envoltorio `PostgrestException(...)`.
String _mensajeError(Object e) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) return e.message;
  final texto = e.toString().replaceFirst('Exception: ', '');
  return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
}

/// Importes tecleados: la coma se trata como separador decimal, igual que en
/// el resto del módulo.
double? _parseImporte(String texto) {
  final limpio = texto.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (limpio.isEmpty) return null;
  final valor = double.tryParse(limpio);
  return (valor != null && valor.isFinite) ? valor : null;
}

String? _textoOpcional(String texto) {
  final limpio = texto.trim();
  return limpio.isEmpty ? null : limpio;
}

String _plural(int n, String singular, String plural) =>
    n == 1 ? '$n $singular' : '$n $plural';

/// Rechaza (no recorta) lo que no sea un número con hasta [decimales]
/// decimales. Recortar cambiaría el dinero en silencio.
class _ImporteAporteFormatter extends TextInputFormatter {
  const _ImporteAporteFormatter({this.decimales = 2});

  final int decimales;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final patron = RegExp('^\\d*([.,]\\d{0,$decimales})?\$');
    return patron.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Ancho del panel a partir del cual el desglose va en tabla y no en tarjetas.
const double _anchoTablaAportes = 700;

/// Ancho a partir del cual la participación va en columna a la derecha.
const double _anchoDosColumnasAportes = 1040;

// ===========================================================================
// Panel
// ===========================================================================

/// Cifras, desglose, participación e historial de los aportes de inversores.
class CompraAportesPanel extends StatefulWidget {
  const CompraAportesPanel({
    super.key,
    required this.idCompra,
    required this.moneda,
    required this.estado,
    required this.modoLiquidacion,
    required this.idTienda,
    this.onCambio,
  });

  final int idCompra;

  /// Moneda del total de la compra; todos los equivalentes ya vienen en ella.
  final String moneda;

  /// Estado de la compra (`creada`, `pagada`, ...).
  final String estado;

  /// `fondo` | `inversores`. El panel solo se monta con `inversores`.
  final String modoLiquidacion;

  final int idTienda;

  /// Avisa a la pantalla de que algo cambió (aporte registrado, aporte
  /// devuelto, compra pagada) para que recargue su detalle.
  final VoidCallback? onCambio;

  @override
  State<CompraAportesPanel> createState() => _CompraAportesPanelState();
}

class _CompraAportesPanelState extends State<CompraAportesPanel> {
  final _servicio = CompraService();
  final _fondo = FondoInversionService();

  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  AportesResumen? _resumen;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Relee las cifras desde el servidor. La pantalla puede llamarla.
  Future<void> recargar() => _cargar();

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = _resumen == null;
        _error = null;
      });
    }
    try {
      final json = await _servicio.aportesCompra(widget.idCompra);
      if (!mounted) return;
      setState(() {
        _resumen = AportesResumen.fromJson(json);
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final mensaje = _mensajeError(e);
      if (_resumen != null) {
        // Ya hay cifras en pantalla: se conservan y se avisa del fallo.
        _snack('No se pudo actualizar el desglose: $mensaje', error: true);
        return;
      }
      setState(() {
        _error = mensaje;
        _cargando = false;
      });
    }
  }

  void _snack(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  /// Tras una escritura: se recarga el panel y se avisa a la pantalla.
  Future<void> _refrescar() async {
    await _cargar();
    widget.onCambio?.call();
  }

  // ==========================================================================
  // Acciones
  // ==========================================================================

  Future<void> _registrarAporte() async {
    final resumen = _resumen;
    if (resumen == null || _ocupado) return;

    List<Map<String, dynamic>> inversores;
    try {
      inversores = await _fondo.listInversores(widget.idTienda);
    } catch (e) {
      _snack(
        'No se pudieron cargar los inversores: ${_mensajeError(e)}',
        error: true,
      );
      return;
    }
    final activos = inversores.where((i) => i['activo'] == true).toList();
    if (!mounted) return;
    if (activos.isEmpty) {
      _snack(
        'La tienda no tiene inversores activos: créalos en Fondo de inversión.',
        error: true,
      );
      return;
    }

    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoAporte(
        idCompra: widget.idCompra,
        monedaCompra: widget.moneda,
        faltante: resumen.faltante,
        inversores: activos,
      ),
    );
    if (datos == null || !mounted) return;

    final equivalente = (datos['monto_eq_total'] as num?)?.toDouble() ?? 0;
    _snack(
      datos['duplicada'] == true
          ? 'Ese aporte ya estaba registrado: no se duplicó.'
          : 'Aporte registrado: '
                '${formatearImporteMoneda(equivalente, widget.moneda)} '
                'comprometidos.',
    );
    await _refrescar();
  }

  Future<void> _devolver(AporteInversor aporte) async {
    if (_ocupado) return;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _DialogoDevolucion(aporte: aporte, monedaCompra: widget.moneda),
    );
    if (r == null || !mounted) return;
    _snack(
      r['duplicada'] == true
          ? 'Ese aporte ya estaba devuelto.'
          : 'Aporte devuelto: vuelve a contar como faltante.',
    );
    await _refrescar();
  }

  /// Paga la compra con los aportes. La RPC es la misma que usa la pantalla
  /// (`fn_fdi_compra_pagar`): en modo inversores tiene una rama propia que no
  /// debita el fondo.
  Future<void> _pagar() async {
    final resumen = _resumen;
    if (resumen == null || !resumen.puedePagar || _ocupado) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pagar la compra'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se paga la compra con los aportes de los inversores: '
                '${formatearImporteMoneda(resumen.aportado, widget.moneda)} '
                'comprometidos. No sale dinero del fondo.',
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              avisoCompras(
                'La compra pasa a «Pagada». Devolver un aporte después deja la '
                'cobertura incompleta otra vez.',
                icono: Icons.account_balance,
                color: AppColors.warning,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.payments, size: 18),
            label: const Text('Pagar compra'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _ocupado = true);
    try {
      final r = await _servicio.pagar(widget.idCompra);
      if (!mounted) return;
      _snack(
        r['duplicada'] == true
            ? 'La compra ya estaba pagada.'
            : 'Compra pagada con los aportes de los inversores.',
      );
      await _refrescar();
    } catch (e) {
      _snack(_mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _editarAporteNoSoportado() {
    _snack(
      'Editar un aporte todavía no está soportado: devuélvelo y registra el '
      'correcto.',
      error: true,
    );
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final resumen = _resumen;
    if (_cargando) {
      return panelCompras(
        children: [
          tituloSeccionCompras(
            'Aportes de inversores',
            trailing: pastillaCompras(
              '100 %',
              denso: true,
              icono: Icons.pie_chart_outline,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      );
    }

    if (resumen == null) {
      return panelCompras(
        children: [
          tituloSeccionCompras('Aportes de inversores'),
          avisoCompras(
            _error ?? 'No se pudo cargar el desglose de aportes.',
            icono: Icons.error_outline,
            color: AppColors.error,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final conTabla = ancho >= _anchoTablaAportes;
        final conLateral = ancho >= _anchoDosColumnasAportes;
        final desglose = _panelDesglose(resumen, conTabla);
        final participacion = _panelParticipacion(resumen);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panelCifras(resumen, ancho),
            ..._bandas(resumen),
            if (conLateral)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: desglose),
                  const SizedBox(width: 12),
                  SizedBox(width: 340, child: participacion),
                ],
              )
            else ...[
              desglose,
              const SizedBox(height: 12),
              participacion,
            ],
            const SizedBox(height: 12),
            _panelHistorial(resumen),
          ],
        );
      },
    );
  }

  /// Bandas de aviso: bloqueo de pago y cobertura incompleta posterior al pago.
  ///
  /// Nunca se inventa el motivo: si el servidor no manda `motivo_bloqueo`, no
  /// hay banda.
  List<Widget> _bandas(AportesResumen r) {
    final motivo = r.motivoBloqueo;
    if (motivo == null) return const [];

    // Caso normal: compra creada que todavía no llega al 100 %.
    if (!r.puedePagar && widget.estado == 'creada') {
      return [
        const SizedBox(height: 10),
        avisoCompras(
          'No se puede pagar todavía: $motivo',
          icono: Icons.lock_clock,
          color: AppColors.warning,
        ),
      ];
    }

    // Cobertura que se rompió después de pagar (se devolvió un aporte). No es
    // un bloqueo nuevo: es un aviso de que la compra quedó descubierta.
    if (r.avisoPostPago) {
      return [
        const SizedBox(height: 10),
        avisoCompras(
          'La compra ya está pagada y su cobertura quedó incompleta: $motivo',
          icono: Icons.info_outline,
          color: AppColors.secondary,
        ),
      ];
    }
    return const [];
  }

  // ==========================================================================
  // 1) Cifras
  // ==========================================================================

  Widget _panelCifras(AportesResumen r, double ancho) {
    final cubierto = r.cubierto;
    final colorFaltante = cubierto ? AppColors.success : AppColors.warning;

    final total = _cifra(
      'TOTAL A CUBRIR',
      formatearImporte(r.total),
      moneda: r.moneda,
      helper: '100 % del importe de compra',
    );
    final aportado = _cifra(
      'APORTADO',
      formatearImporte(r.aportado),
      moneda: r.moneda,
      helper:
          '${_porcentaje(r.pct)} % comprometido por '
          '${_plural(r.inversoresComprometidos, 'inversor', 'inversores')}',
    );
    final faltante = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cubierto ? _fondoVerde : _fondoNaranja,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorFaltante),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'FALTANTE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: colorFaltante,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  formatearImporte(r.faltante),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: colorFaltante,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  r.moneda,
                  style: TextStyle(fontSize: 11, color: colorFaltante),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            cubierto
                ? 'Cubierto al 100 %'
                : '${_porcentaje(r.pctPendiente)} % pendiente de asignación',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: colorFaltante,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    Widget separador() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 64,
        child: VerticalDivider(width: 1, color: AppColors.border),
      ),
    );

    final cuerpo = ancho >= 560
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: total),
              separador(),
              Expanded(child: aportado),
              separador(),
              Expanded(child: faltante),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              total,
              const SizedBox(height: 10),
              aportado,
              const SizedBox(height: 10),
              faltante,
            ],
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Aportes de inversores',
            trailing: pastillaCompras(
              r.moneda.isEmpty ? '—' : r.moneda,
              denso: true,
              icono: Icons.pie_chart_outline,
            ),
          ),
          cuerpo,
        ],
      ),
    );
  }

  Widget _cifra(
    String etiqueta,
    String valor, {
    required String moneda,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                moneda,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textLight,
                ),
              ),
            ),
          ],
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper,
            style: const TextStyle(
              fontSize: 11,
              height: 1.3,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================================================
  // 3) Desglose
  // ==========================================================================

  Widget _panelDesglose(AportesResumen r, bool conTabla) {
    return panelCompras(
      children: [
        tituloSeccionCompras(
          'Desglose de aportes',
          trailing: pastillaCompras(
            _plural(r.aportes.length, 'aporte', 'aportes'),
            denso: true,
            icono: Icons.groups_outlined,
          ),
        ),
        if (r.aportes.isEmpty)
          avisoCompras(
            'Todavía no hay aportes registrados: el total sigue sin cubrir.',
            icono: Icons.info_outline,
            color: AppColors.secondary,
          )
        else if (conTabla)
          _tablaAportes(r)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < r.aportes.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _tarjetaAporte(r, r.aportes[i]),
              ],
            ],
          ),
        const SizedBox(height: 10),
        _pieDesglose(r),
      ],
    );
  }

  Widget _puntoColor(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Color _colorAporte(AportesResumen r, AporteInversor a) {
    final vigentes = r.aportesVigentes;
    final ids = <int>[];
    for (final v in vigentes) {
      if (!ids.contains(v.idInversor)) ids.add(v.idInversor);
    }
    final indice = ids.indexOf(a.idInversor);
    if (indice < 0) return AppColors.secondary;
    return _coloresSegmento[indice % _coloresSegmento.length];
  }

  /// Reparto de anchos de la tabla. [Table] con `FlexColumnWidth` no desborda
  /// nunca: las celdas recortan con puntos suspensivos.
  static const Map<int, TableColumnWidth> _anchosTabla = {
    0: FlexColumnWidth(3.4), // Inversor
    1: FlexColumnWidth(1.5), // % participación
    2: FlexColumnWidth(1.9), // Monto aportado
    3: FlexColumnWidth(1.2), // Moneda
    4: FlexColumnWidth(1.1), // Tasa
    5: FlexColumnWidth(2.0), // Equivalente
    6: FlexColumnWidth(1.5), // Fecha
    7: FlexColumnWidth(1.5), // Estado
    8: FlexColumnWidth(2.1), // Acciones
  };

  Widget _tablaAportes(AportesResumen r) {
    const estiloCabecera = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: AppColors.textSecondary,
    );

    Widget cabecera(String texto, {TextAlign alineacion = TextAlign.left}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(texto, textAlign: alineacion, style: estiloCabecera),
        );

    return Table(
      columnWidths: _anchosTabla,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          children: [
            cabecera('Inversor'),
            cabecera('% participación', alineacion: TextAlign.right),
            cabecera('Monto', alineacion: TextAlign.right),
            cabecera('Moneda', alineacion: TextAlign.center),
            cabecera('Tasa', alineacion: TextAlign.right),
            cabecera('Equivalente', alineacion: TextAlign.right),
            cabecera('Fecha'),
            cabecera('Estado', alineacion: TextAlign.center),
            cabecera('Acciones', alineacion: TextAlign.right),
          ],
        ),
        for (final a in r.aportes) _filaTabla(r, a),
      ],
    );
  }

  TableRow _filaTabla(AportesResumen r, AporteInversor a) {
    final atenuado = a.esDevuelto;
    final motivo = a.motivoDevolucion;

    Widget celda(Widget hijo) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Opacity(opacity: atenuado ? 0.55 : 1, child: hijo),
    );

    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      children: [
        celda(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _puntoColor(_colorAporte(r, a)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      a.inversor.isEmpty ? '—' : a.inversor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (atenuado && motivo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 14),
                  child: Text(
                    motivo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        celda(
          Text(
            '${_porcentaje(a.parteDelTotal(r.total))} %',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        celda(textoImporte(formatearImporte(a.monto), negrita: !atenuado)),
        celda(Center(child: pastillaCompras(a.moneda, denso: true))),
        celda(
          Text(
            _tasa(a.tasaATotal),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        celda(
          textoImporte(formatearImporte(a.montoEqTotal), negrita: !atenuado),
        ),
        celda(
          Text(
            formatearFecha(a.createdAt),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        celda(Center(child: _chipEstadoAporte(a.esDevuelto))),
        celda(
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: _editarAporteNoSoportado,
                icon: const Icon(Icons.edit_outlined, size: 16),
                tooltip: 'Editar aporte',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              TextButton(
                onPressed: atenuado ? null : () => _devolver(a),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Revertir', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tarjetaAporte(AportesResumen r, AporteInversor a) {
    final atenuado = a.esDevuelto;
    final motivo = a.motivoDevolucion;

    Widget dato(String etiqueta, String valor, {bool negrita = false}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: negrita ? FontWeight.w600 : FontWeight.w400,
              color: AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: atenuado ? AppColors.surfaceVariant : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Opacity(
        opacity: atenuado ? 0.65 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _puntoColor(_colorAporte(r, a)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    a.inversor.isEmpty ? '—' : a.inversor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _chipEstadoAporte(a.esDevuelto),
              ],
            ),
            if (atenuado && motivo != null) ...[
              const SizedBox(height: 4),
              Text(
                motivo,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: dato('MONTO APORTADO', formatearImporte(a.monto)),
                ),
                const SizedBox(width: 8),
                Expanded(child: dato('MONEDA', a.moneda)),
                const SizedBox(width: 8),
                Expanded(child: dato('TASA', _tasa(a.tasaATotal))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: dato(
                    'EQUIVALENTE',
                    formatearImporte(a.montoEqTotal),
                    negrita: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: dato(
                    '% PARTICIPACIÓN',
                    '${_porcentaje(a.parteDelTotal(r.total))} %',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: dato('FECHA', formatearFecha(a.createdAt))),
              ],
            ),
            Row(
              children: [
                IconButton(
                  onPressed: _editarAporteNoSoportado,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Editar aporte',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: atenuado ? null : () => _devolver(a),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Revertir', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipEstadoAporte(bool devuelto) => pastillaCompras(
    devuelto ? 'Devuelto' : 'Aportado',
    denso: true,
    color: devuelto ? AppColors.secondary : AppColors.success,
    icono: devuelto ? Icons.undo : Icons.check_circle_outline,
  );

  Widget _pieDesglose(AportesResumen r) {
    final cubierto = r.cubierto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'TOTAL COMPROMETIDO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatearImporte(r.sumaVigente),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      r.moneda,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                'Σ equivalente',
                style: TextStyle(fontSize: 10, color: AppColors.textLight),
              ),
            ],
          ),
          pastillaCompras(
            '${_porcentaje(r.pct)} %',
            denso: true,
            color: cubierto ? AppColors.success : AppColors.primary,
          ),
          pastillaCompras(
            cubierto
                ? 'Completo'
                : 'Parcial (faltan ${_porcentaje(r.pctPendiente)} %)',
            denso: true,
            color: cubierto ? AppColors.success : AppColors.warning,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 4) Participación
  // ==========================================================================

  Widget _panelParticipacion(AportesResumen r) {
    // Un segmento por inversor, con el importe que aporta y su % real sobre el
    // total de la compra (nunca el `porcentaje_inversor` del inversor).
    final segmentos = <_SegmentoParticipacion>[];
    final vistos = <int>{};
    for (final a in r.aportesVigentes) {
      if (!vistos.add(a.idInversor)) continue;
      segmentos.add(
        _SegmentoParticipacion(
          idInversor: a.idInversor,
          nombre: a.inversor.isEmpty ? 'Inversor' : a.inversor,
          pct: r.parteDeInversor(a.idInversor),
          importe: r.importeDeInversor(a.idInversor),
          color: _coloresSegmento[(segmentos.length) % _coloresSegmento.length],
        ),
      );
    }

    // `puedeRegistrar` lo resuelve el servidor: compra en `creada`, con total a
    // financiar y con faltante. `motivoBloqueo` habla del pago, no de aportar.
    final puedeAportar = r.puedeRegistrar;
    final motivoAporte = puedeAportar
        ? null
        : (widget.estado == 'creada'
              ? 'La compra ya está cubierta al 100 %: no queda faltante por aportar.'
              : 'Sólo se aporta a una compra en estado creada.');

    Widget conAyuda(String? ayuda, Widget hijo) =>
        ayuda == null ? hijo : Tooltip(message: ayuda, child: hijo);

    return panelCompras(
      children: [
        tituloSeccionCompras(
          'Participación',
          trailing: pastillaCompras(
            r.cubierto ? 'Completo' : 'Parcial',
            denso: true,
            color: r.cubierto ? AppColors.success : AppColors.warning,
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: segmentos.isEmpty
              ? Container(height: 10, color: AppColors.border)
              : Row(
                  children: [
                    for (final s in segmentos)
                      Expanded(
                        flex: _flex(s.pct),
                        child: Tooltip(
                          message:
                              '${s.nombre}: ${_porcentaje(s.pct)} % del total',
                          child: Container(height: 10, color: s.color),
                        ),
                      ),
                    if (r.pctPendiente > 0)
                      Expanded(
                        flex: _flex(r.pctPendiente),
                        child: Container(height: 10, color: AppColors.border),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        if (segmentos.isEmpty)
          const Text(
            'Sin aportes: todo el importe está pendiente.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else
          for (final s in segmentos)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  _puntoColor(s.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatearImporte(s.importe),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${_porcentaje(s.pct)} %',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        const Divider(height: 14, color: AppColors.border),
        Row(
          children: [
            const _PuntoRestante(),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Restante',
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
            Text(
              formatearImporte(r.faltante),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 48,
              child: Text(
                '${_porcentaje(r.pctPendiente)} %',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          width: double.infinity,
          child: conAyuda(
            motivoAporte,
            FilledButton.icon(
              onPressed: puedeAportar && !_ocupado ? _registrarAporte : null,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Registrar aporte'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          width: double.infinity,
          child: conAyuda(
            r.puedePagar ? null : r.motivoBloqueo,
            OutlinedButton.icon(
              onPressed: r.puedePagar && !_ocupado ? _pagar : null,
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Pagar compra'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ),
        if (!r.puedePagar && r.motivoBloqueo != null) ...[
          const SizedBox(height: 6),
          Text(
            r.motivoBloqueo!,
            style: const TextStyle(
              fontSize: 11,
              height: 1.3,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 10),
        const Text(
          'Los aportes no entran en el fondo ni se acumulan como saldo del '
          'inversor; viven atados a esta compra.',
          style: TextStyle(
            fontSize: 11,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  int _flex(double pct) {
    final valor = (pct * 10).round();
    return valor < 1 ? 1 : valor;
  }

  // ==========================================================================
  // 5) Historial
  // ==========================================================================

  Widget _panelHistorial(AportesResumen r) {
    final eventos = <_EventoAporte>[];
    for (final a in r.aportes) {
      final alta = a.createdAt;
      if (alta != null) {
        eventos.add(
          _EventoAporte(
            fecha: alta,
            titulo:
                'Aporte registrado — ${a.inversor.isEmpty ? '—' : a.inversor}',
            detalle:
                '${formatearImporteMoneda(a.montoEqTotal, r.moneda)} · '
                '${a.naturalezaLegible}',
            esDevolucion: false,
          ),
        );
      }
      final baja = a.devueltoAt;
      if (baja != null) {
        eventos.add(
          _EventoAporte(
            fecha: baja,
            titulo: 'Devolución — ${a.inversor.isEmpty ? '—' : a.inversor}',
            detalle:
                '${formatearImporteMoneda(a.montoEqTotal, r.moneda)} · '
                '${a.motivoDevolucion ?? 'sin motivo registrado'}',
            esDevolucion: true,
          ),
        );
      }
    }
    eventos.sort((x, y) => y.fecha.compareTo(x.fecha));
    final visibles = eventos.take(8).toList();

    return panelCompras(
      children: [
        tituloSeccionCompras(
          'Historial de aportes',
          trailing: pastillaCompras(
            _plural(eventos.length, 'registro', 'registros'),
            denso: true,
            icono: Icons.history,
          ),
        ),
        if (visibles.isEmpty)
          textoMetaCompras('Todavía no hay movimientos de aportes.')
        else
          for (var i = 0; i < visibles.length; i++) ...[
            if (i > 0) const Divider(height: 12, color: AppColors.border),
            _filaHistorial(visibles[i]),
          ],
        if (eventos.length > visibles.length) ...[
          const SizedBox(height: 8),
          Text(
            'Se muestran los últimos ${visibles.length} de ${eventos.length}.',
            style: const TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ],
    );
  }

  Widget _filaHistorial(_EventoAporte evento) {
    final color = evento.esDevolucion ? AppColors.warning : AppColors.success;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            evento.esDevolucion ? Icons.undo : Icons.add_circle_outline,
            size: 14,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                evento.titulo,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              if (evento.detalle != null) ...[
                const SizedBox(height: 1),
                Text(
                  evento.detalle!,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatearFechaHora(evento.fecha),
          style: const TextStyle(fontSize: 11, color: AppColors.textLight),
        ),
      ],
    );
  }
}

/// Un segmento de la barra de participación.
class _SegmentoParticipacion {
  const _SegmentoParticipacion({
    required this.idInversor,
    required this.nombre,
    required this.pct,
    required this.importe,
    required this.color,
  });

  final int idInversor;
  final String nombre;
  final double pct;
  final double importe;
  final Color color;
}

/// Punto gris de la fila «Restante» de la barra segmentada.
class _PuntoRestante extends StatelessWidget {
  const _PuntoRestante();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.border,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.textLight),
      ),
    );
  }
}

/// Un movimiento del historial derivado de los propios aportes.
class _EventoAporte {
  const _EventoAporte({
    required this.fecha,
    required this.titulo,
    this.detalle,
    required this.esDevolucion,
  });

  final DateTime fecha;
  final String titulo;
  final String? detalle;
  final bool esDevolucion;
}

// ===========================================================================
// Diálogo: registrar aporte
// ===========================================================================

/// Alta de un aporte. La llamada vive aquí, no en el panel, para que un error
/// del servidor no cierre el diálogo ni pierda lo tecleado.
class _DialogoAporte extends StatefulWidget {
  const _DialogoAporte({
    required this.idCompra,
    required this.monedaCompra,
    required this.faltante,
    required this.inversores,
  });

  final int idCompra;
  final String monedaCompra;

  /// Lo que falta cubrir hoy, en la moneda de la compra. El servidor es quien
  /// decide de verdad: esto es solo la previsualización.
  final double faltante;

  final List<Map<String, dynamic>> inversores;

  @override
  State<_DialogoAporte> createState() => _DialogoAporteState();
}

class _DialogoAporteState extends State<_DialogoAporte> {
  static const List<String> _monedas = ['USD', 'CUP', 'EUR'];

  final _servicio = CompraService();

  /// Una sola clave por formulario: si el reintento la regenerara, el aporte
  /// se duplicaría.
  late final String _llave;

  final _monto = TextEditingController();
  final _tasa = TextEditingController(text: '1');
  final _interes = TextEditingController();
  final _comprobante = TextEditingController();
  final _observacion = TextEditingController();

  int? _idInversor;
  late String _moneda;
  String _naturaleza = 'anticipo';
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _llave = _servicio.newIdempotencyKey();
    _moneda = _monedas.contains(widget.monedaCompra)
        ? widget.monedaCompra
        : _monedas.first;
    _monto.addListener(_recalcular);
    _tasa.addListener(_recalcular);
  }

  @override
  void dispose() {
    _monto.dispose();
    _tasa.dispose();
    _interes.dispose();
    _comprobante.dispose();
    _observacion.dispose();
    super.dispose();
  }

  void _recalcular() {
    if (mounted) setState(() {});
  }

  bool get _mismaMoneda => _moneda == widget.monedaCompra;

  double? get _montoValor => _parseImporte(_monto.text);

  /// En la moneda de la compra la tasa es 1 por definición (la RPC lo fuerza).
  double? get _tasaValor {
    if (_mismaMoneda) return 1;
    final valor = _parseImporte(_tasa.text);
    return (valor == null || valor <= 0) ? null : valor;
  }

  /// Equivalente en la moneda de la compra. Vista previa: manda el servidor.
  double? get _equivalente {
    final monto = _montoValor;
    final tasa = _tasaValor;
    if (monto == null || tasa == null) return null;
    return redondear2(monto * tasa);
  }

  double get _restante => redondear2(widget.faltante - (_equivalente ?? 0));

  String? get _problemaMonto {
    if (_monto.text.trim().isEmpty) return null;
    final monto = _montoValor;
    if (monto == null || monto <= 0) {
      return 'El monto tiene que ser mayor que cero.';
    }
    // Se valida sobre el texto: multiplicar por 100 en coma flotante produce
    // falsos negativos (800.1 * 100 no es 80010 exacto).
    final partes = _monto.text.trim().replaceAll(',', '.').split('.');
    if (partes.length > 1 && partes.last.length > 2) {
      return 'El monto admite dos decimales como máximo.';
    }
    final equivalente = _equivalente;
    if (equivalente == null) return 'La tasa tiene que ser mayor que cero.';
    if (equivalente - widget.faltante > 0.001) {
      return 'El aporte equivale a '
          '${formatearImporteMoneda(equivalente, widget.monedaCompra)} y sólo '
          'faltan ${formatearImporteMoneda(widget.faltante, widget.monedaCompra)}.';
    }
    return null;
  }

  bool get _puedeGuardar =>
      !_enviando &&
      _idInversor != null &&
      _montoValor != null &&
      widget.faltante > 0 &&
      _problemaMonto == null;

  Future<void> _guardar() async {
    final monto = _montoValor;
    final tasa = _tasaValor;
    final inversor = _idInversor;
    if (monto == null || tasa == null || inversor == null || !_puedeGuardar) {
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await _servicio.registrarAporte(
        idCompra: widget.idCompra,
        idInversor: inversor,
        moneda: _moneda,
        monto: monto,
        tasaATotal: tasa,
        naturaleza: _naturaleza,
        tasaInteres: _naturaleza == 'pasivo'
            ? _parseImporte(_interes.text)
            : null,
        comprobante: _textoOpcional(_comprobante.text),
        observacion: _textoOpcional(_observacion.text),
        idempotencyKey: _llave,
      );
      if (!mounted) return;
      Navigator.pop(context, r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = _mensajeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final equivalente = _equivalente;
    final problema = _problemaMonto;

    return AlertDialog(
      title: const Text('Registrar aporte'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _idInversor,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Inversor *',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Elige el inversor'),
                items: [
                  for (final i in widget.inversores)
                    DropdownMenuItem<int>(
                      value: (i['id'] as num?)?.toInt(),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              i['nombre']?.toString() ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_porcentaje((i['porcentaje'] as num?) ?? 0)} %',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: _enviando
                    ? null
                    : (v) => setState(() => _idInversor = v),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      initialValue: _moneda,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Moneda *',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final m in _monedas)
                          DropdownMenuItem<String>(value: m, child: Text(m)),
                      ],
                      onChanged: _enviando
                          ? null
                          : (v) => setState(() {
                              if (v != null) _moneda = v;
                            }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _monto,
                      enabled: !_enviando,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [_ImporteAporteFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Monto *',
                        suffixText: _moneda,
                        errorText: problema,
                        errorMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tasa,
                enabled: !_enviando && !_mismaMoneda,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [_ImporteAporteFormatter(decimales: 6)],
                decoration: InputDecoration(
                  labelText: 'Tasa a ${widget.monedaCompra}',
                  helperText: _mismaMoneda
                      ? 'Misma moneda: la tasa es 1.'
                      : '1 $_moneda = ? ${widget.monedaCompra}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Naturaleza',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(value: 'anticipo', label: Text('Anticipo')),
                  ButtonSegment(value: 'pasivo', label: Text('Pasivo')),
                  ButtonSegment(value: 'capital', label: Text('Capital')),
                ],
                selected: {_naturaleza},
                onSelectionChanged: _enviando
                    ? null
                    : (s) => setState(() => _naturaleza = s.first),
              ),
              if (_naturaleza == 'pasivo') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _interes,
                  enabled: !_enviando,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [
                    _ImporteAporteFormatter(decimales: 6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Tasa de interés (opcional)',
                    helperText:
                        'Sólo un aporte con naturaleza pasivo devenga '
                        'interés.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _vistaPrevia(equivalente),
              const SizedBox(height: 12),
              TextFormField(
                controller: _comprobante,
                enabled: !_enviando,
                decoration: const InputDecoration(
                  labelText: 'Comprobante (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacion,
                enabled: !_enviando,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observación (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                avisoCompras(
                  _error!,
                  icono: Icons.error_outline,
                  color: AppColors.error,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton.icon(
          onPressed: _puedeGuardar ? _guardar : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          icon: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(_enviando ? 'Registrando...' : 'Guardar aporte'),
        ),
      ],
    );
  }

  /// Vista previa del equivalente y del restante. El servidor manda.
  Widget _vistaPrevia(double? equivalente) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Equivalente: '
            '${equivalente == null ? '—' : formatearImporte(equivalente)} '
            '${widget.monedaCompra}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Restante tras el aporte: '
            '${formatearImporte(_restante)} ${widget.monedaCompra}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Faltan ${formatearImporteMoneda(widget.faltante, widget.monedaCompra)} '
            'para cubrir la compra. El servidor valida el importe final.',
            style: const TextStyle(
              fontSize: 11,
              height: 1.3,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Diálogo: devolver aporte
// ===========================================================================

/// Devolución de un aporte: exige motivo y no mueve dinero del fondo.
class _DialogoDevolucion extends StatefulWidget {
  const _DialogoDevolucion({required this.aporte, required this.monedaCompra});

  final AporteInversor aporte;
  final String monedaCompra;

  @override
  State<_DialogoDevolucion> createState() => _DialogoDevolucionState();
}

class _DialogoDevolucionState extends State<_DialogoDevolucion> {
  final _servicio = CompraService();
  final _motivo = TextEditingController();

  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final motivo = _motivo.text.trim();
    if (motivo.length < 5) {
      setState(() => _error = 'Escribe el motivo (mínimo 5 caracteres).');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await _servicio.devolverAporte(
        idAporte: widget.aporte.id,
        motivo: motivo,
      );
      if (!mounted) return;
      Navigator.pop(context, r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = _mensajeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.aporte;
    return AlertDialog(
      title: const Text('Revertir aporte'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      a.inversor.isEmpty ? '—' : a.inversor,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatearImporteMoneda(a.monto, a.moneda)} · '
                      'equivalente '
                      '${formatearImporteMoneda(a.montoEqTotal, widget.monedaCompra)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              avisoCompras(
                'Devolver el aporte no mueve dinero del fondo: el inversor '
                'deja de estar comprometido y el importe vuelve a contar como '
                'faltante.',
                icono: Icons.info_outline,
                color: AppColors.warning,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motivo,
                autofocus: true,
                enabled: !_enviando,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Motivo * (mínimo 5 caracteres)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                avisoCompras(
                  _error!,
                  icono: Icons.error_outline,
                  color: AppColors.error,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton.icon(
          onPressed: _enviando ? null : _confirmar,
          style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
          icon: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.undo, size: 18),
          label: Text(_enviando ? 'Revirtiendo...' : 'Revertir aporte'),
        ),
      ],
    );
  }
}
