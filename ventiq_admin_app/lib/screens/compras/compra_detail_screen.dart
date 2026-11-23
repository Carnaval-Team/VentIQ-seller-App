import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/compra.dart';
import '../../services/compra_service.dart';
import '../../services/financial_service.dart';
import '../../widgets/admin_drawer.dart';
import '../../widgets/compra_aportes_panel.dart';
import 'compra_form_screen.dart';
import 'compra_liquidacion_screen.dart';
import 'compras_widgets.dart';

/// Detalle de una compra (`fn_fdi_compra_detalle`).
class CompraDetailScreen extends StatefulWidget {
  const CompraDetailScreen({super.key, required this.idCompra});

  final int idCompra;

  @override
  State<CompraDetailScreen> createState() => _CompraDetailScreenState();
}

class _CompraDetailScreenState extends State<CompraDetailScreen> {
  final _service = CompraService();

  bool _cargando = true;
  bool _cancelando = false;
  String? _error;
  CompraDetalle? _detalle;

  /// Resumen del costo aterrizado (`fn_fdi_compra_costo_resumen`). Es
  /// opcional: si falla, el detalle se muestra igual sin el panel.
  Map<String, dynamic>? _costoResumen;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final detalle = await _service.detalle(widget.idCompra);
      Map<String, dynamic>? costoResumen;
      try {
        costoResumen = await _service.costoResumen(widget.idCompra);
      } catch (_) {
        // El detalle no depende del resumen: si la RPC falla se oculta el panel.
        costoResumen = null;
      }
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
        _costoResumen = costoResumen;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mensajeDe(e);
        _cargando = false;
      });
    }
  }

  String _mensajeDe(Object e) => _mensajeError(e);

  void _snack(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  // ==========================================================================
  // Acciones
  // ==========================================================================

  Future<void> _editar() async {
    final detalle = _detalle;
    if (detalle == null) return;
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CompraFormScreen(detalle: detalle)),
    );
    if (cambio == true && mounted) _cargar();
  }

  /// Abre el asistente de liquidación. El resultado es el mensaje a mostrar:
  /// `null` = se cerró sin reservar.
  Future<void> _reservar() async {
    final detalle = _detalle;
    if (detalle == null) return;
    final mensaje = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CompraLiquidacionScreen(compra: detalle.compra),
      ),
    );
    if (!mounted || mensaje == null) return;
    _snack(mensaje);
    await _cargar();
  }

  Future<void> _pagar() async {
    final detalle = _detalle;
    if (detalle == null) return;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoPago(compra: detalle.compra),
    );
    if (r == null || !mounted) return;
    _snack(
      r['duplicada'] == true
          ? 'La compra ya estaba pagada: no se descontó dos veces.'
          : 'Compra pagada: el dinero salió del fondo.',
    );
    await _cargar();
  }

  Future<void> _liberar() async {
    final detalle = _detalle;
    if (detalle == null) return;
    final c = detalle.compra;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoMotivo(
        titulo: 'Liberar reserva',
        descripcion:
            'Se liberan las reservas de la compra #${c.numeroCompra} '
            '(${formatearImporteMoneda(c.totalFinanciado, c.monedaTotal)}) y la '
            'compra vuelve a «Creada». El disponible regresa a las cuentas del '
            'fondo y no se paga nada.',
        etiquetaConfirmar: 'Liberar reserva',
        colorConfirmar: AppColors.warning,
        pista: 'Escribe el motivo de la liberación.',
        accion: (motivo) => _service.liberar(widget.idCompra, motivo),
      ),
    );
    if (r == null || !mounted) return;
    _snack('Reserva liberada: la compra volvió a «Creada».');
    await _cargar();
  }

  Future<void> _anular() async {
    final detalle = _detalle;
    if (detalle == null) return;
    final c = detalle.compra;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoMotivo(
        titulo: 'Anular compra',
        descripcion:
            'Se anula la compra #${c.numeroCompra} y el importe pagado vuelve '
            'al fondo. La anulación queda en el historial con el motivo.',
        etiquetaConfirmar: 'Anular compra',
        colorConfirmar: AppColors.error,
        pista: 'Escribe el motivo de la anulación.',
        accion: (motivo) => _service.anular(widget.idCompra, motivo),
      ),
    );
    if (r == null || !mounted) return;
    if (r['duplicada'] == true) {
      _snack('La compra ya estaba anulada.');
    } else {
      final devuelto = (r['devuelto'] as num?)?.toDouble() ?? 0;
      _snack(
        devuelto > 0
            ? 'Compra anulada: '
                  '${formatearImporteMoneda(devuelto, c.monedaTotal)} volvió al fondo.'
            : 'Compra anulada.',
      );
    }
    await _cargar();
  }

  Future<void> _cancelar() async {
    final detalle = _detalle;
    if (detalle == null || _cancelando) return;

    final motivo = await _pedirMotivo(detalle);
    if (motivo == null || !mounted) return;

    setState(() => _cancelando = true);
    try {
      final r = await _service.cancelar(widget.idCompra, motivo);
      if (!mounted) return;
      if (r['duplicada'] == true) {
        _snack('La compra ya estaba cancelada.');
      } else {
        _snack('Compra cancelada.');
      }
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      _snack(_mensajeDe(e), error: true);
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  Future<String?> _pedirMotivo(CompraDetalle detalle) async {
    final ctrl = TextEditingController();
    String? error;
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setEstadoDialogo) {
            return AlertDialog(
              title: const Text('Cancelar compra'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'La compra #${detalle.numeroCompra} quedará en estado '
                        '«Cancelada». El motivo es obligatorio y queda en el historial.',
                        style: const TextStyle(fontSize: 13, height: 1.35),
                      ),
                      if (detalle.tieneRecepciones) ...[
                        const SizedBox(height: 10),
                        avisoCompras(
                          'Esta compra ya tiene ${detalle.recepciones.length} '
                          '${detalle.recepciones.length == 1 ? 'recepción' : 'recepciones'}. '
                          'El servidor rechazará la cancelación.',
                          icono: Icons.warning_amber_outlined,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: ctrl,
                        autofocus: true,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Motivo *',
                          errorText: error,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Volver'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed: () {
                    final texto = ctrl.text.trim();
                    if (texto.isEmpty) {
                      setEstadoDialogo(
                        () => error = 'Escribe el motivo de la cancelación.',
                      );
                      return;
                    }
                    Navigator.pop(ctx, texto);
                  },
                  child: const Text('Cancelar compra'),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    return motivo;
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final detalle = _detalle;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Con `drawer` el AppBar muestra hamburguesa y se pierde la vuelta.
        leading: const BackButton(color: Colors.white),
        title: Text(
          detalle == null ? 'Compra' : 'Compra #${detalle.numeroCompra}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      drawer: const AdminDrawer(),
      body: _cuerpo(detalle),
    );
  }

  Widget _cuerpo(CompraDetalle? detalle) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || detalle == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 56, color: Colors.red[300]),
              const SizedBox(height: 12),
              const Text(
                'No se pudo cargar la compra',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tamano = comprasTamanoDe(constraints.maxWidth);
        final conPanel = tamano == ComprasTamano.expandido;

        if (conPanel) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _panelCabecera(detalle),
                        _panelLineas(detalle, tamano),
                        _panelAjustes(detalle),
                        _panelRecepciones(detalle),
                        _panelHistorial(detalle),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _panelTotales(detalle),
                        _panelAportes(detalle),
                        _panelCostoAterrizado(detalle),
                        const SizedBox(height: 12),
                        _panelAcciones(detalle),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panelCabecera(detalle),
              _panelTotales(detalle),
              _panelAportes(detalle),
              _panelCostoAterrizado(detalle),
              const SizedBox(height: 12),
              _panelLineas(detalle, tamano),
              _panelAjustes(detalle),
              _panelRecepciones(detalle),
              _panelHistorial(detalle),
              const SizedBox(height: 4),
              _panelAcciones(detalle),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================================
  // Cabecera
  // ==========================================================================

  Widget _panelCabecera(CompraDetalle detalle) {
    final c = detalle.compra;
    final factura = (c.numeroFactura ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Compra #${c.numeroCompra}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              chipEstadoCompra(c.estado),
              pastillaCompras(
                'Liquidación: ${CompraModoLiquidacion.etiquetaDe(c.modoLiquidacion).toUpperCase()}',
                icono: Icons.account_balance,
                color: AppColors.primary,
              ),
              pastillaCompras(
                'Pago: ${c.politicaPagoLegible}',
                icono: Icons.schedule,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _datoCabecera(
                'Proveedor',
                detalle.proveedorNombre.isEmpty
                    ? '#${c.idProveedor}'
                    : detalle.proveedorNombre,
              ),
              _datoCabecera(
                'Factura',
                factura.isEmpty ? 'Sin número' : factura,
              ),
              _datoCabecera('Fecha factura', formatearFecha(c.fechaFactura)),
              _datoCabecera(
                'Moneda',
                c.monedaTotal.isEmpty ? '—' : c.monedaTotal,
              ),
              _datoCabecera('Creada', formatearFechaHora(c.createdAt)),
            ],
          ),
          const SizedBox(height: 12),
          _chipTasa(c),
        ],
      ),
    );
  }

  Widget _datoCabecera(String etiqueta, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  /// Chip de tasa visible (el doc prohíbe esconderla en un `ExpansionTile`).
  Widget _chipTasa(Compra c) {
    final registrada = c.updatedAt ?? c.createdAt;
    final autor = (c.createdBy ?? '').trim();
    final autorCorto = autor.length > 8 ? autor.substring(0, 8) : autor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(
            Icons.currency_exchange,
            size: 16,
            color: AppColors.primary,
          ),
          Text(
            'Tasa factura: ${formatearCantidad(c.tasaFactura)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            'registrada el ${formatearFechaHora(registrada)}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          if (autorCorto.isNotEmpty)
            Tooltip(
              message: autor,
              child: Text(
                'usuario $autorCorto…',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Totales
  // ==========================================================================

  Widget _panelTotales(CompraDetalle detalle) {
    final c = detalle.compra;
    final totales = TotalesCompra.de(c);
    return panelCompras(
      children: [
        tituloSeccionCompras(
          'Cifras',
          trailing: pastillaCompras(
            c.monedaTotal.isEmpty ? '—' : c.monedaTotal,
            denso: true,
            icono: Icons.payments_outlined,
          ),
        ),
        const SizedBox(height: 6),
        bloqueTotalesCompra(
          totales: totales,
          moneda: c.monedaTotal,
          apilado: true,
          helperAterrizado:
              'Incluye lo pagado por la wallet de importadora y el resto de ajustes.',
        ),
        const SizedBox(height: 10),
        Text(
          'Los cuatro importes son cifras distintas: no se suman entre sí.',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // ==========================================================================
  // Aportes de inversores (fase 7)
  // ==========================================================================

  /// Panel de aportes. Solo se monta con `modo_liquidacion = 'inversores'`: en
  /// modo fondo el total lo paga el fondo y no hay nada que cubrir.
  ///
  /// El panel relee sus cifras con `fn_fdi_compra_aportes` y avisa por
  /// [CompraAportesPanel.onCambio] cuando registra un aporte, lo devuelve o
  /// paga la compra; aquí solo se recarga el detalle, igual que en el resto de
  /// acciones.
  Widget _panelAportes(CompraDetalle detalle) {
    final c = detalle.compra;
    if (c.modoLiquidacion != 'inversores') return const SizedBox.shrink();
    return CompraAportesPanel(
      idCompra: c.id,
      moneda: c.monedaTotal,
      estado: c.estado,
      modoLiquidacion: c.modoLiquidacion,
      idTienda: c.idTienda,
      onCambio: () => _cargar(),
    );
  }

  // ==========================================================================
  // Costo aterrizado (fase 6)
  // ==========================================================================

  /// Cifras que manda el servidor (`fn_fdi_compra_costo_resumen`): valor de
  /// factura vinculado, cargo de importadora con su desvío frente al % pactado,
  /// ajustes globales aplicados y pendientes, y el costo aterrizado por línea.
  /// Es solo lectura: el módulo muestra el desvío, no lo corrige.
  /// Aterriza a mano el cargo de un vínculo que quedó sin costo (por ejemplo,
/// porque la recepción se registró sin compra y se vinculó después). Es la
/// misma RPC que usa la recepción; idempotente por vínculo.
  Future<void> _aterrizarVinculo(int idCompraRecepcion) async {
    try {
      final r = await _service.repartirAterrizaje(idCompraRecepcion);
      final status = r['status']?.toString() ?? '?';
      _snack(
        status == 'ok'
            ? 'Cargo aterrizado en la recepción.'
            : 'No se aterrizó: $status',
        error: status != 'ok',
      );
      await _cargar();
    } catch (e) {
      _snack('No se pudo aterrizar el cargo: $e', error: true);
    }
  }

  /// Un vínculo necesita aterrizaje si todavía no tiene filas de costo, el
  /// cargo es mayor que cero y su origen capitaliza (wallet o externo).
  bool _puedeAterrizar(Map<String, dynamic> vinculo) {
    final filas = num.tryParse('${vinculo['filas_costo']}') ?? 0;
    final cargo = num.tryParse('${vinculo['monto_importadora']}') ?? 0;
    final origen = '${vinculo['origen_pago'] ?? ''}';
    final estado = num.tryParse('${vinculo['estado_operacion']}');
    // Una recepción cancelada (3) o devuelta (4) no se vuelve a aterrizar.
    if (estado != null && (estado == 3 || estado == 4)) return false;
    return filas == 0 &&
        cargo > 0 &&
        (origen == 'wallet_importadora' || origen == 'externo');
  }

  // ==========================================================================
  // Ajustes posteriores al pago (fase 6d)
  // ==========================================================================

  /// Agrega un costo que llega después de pagar. Nace `por_financiar` y no
  /// mueve `total_financiado`; se cubre con el botón «Financiar ahora».
  Future<void> _agregarAjuste() async {
    final detalle = _detalle;
    if (detalle == null) return;
    List<Map<String, dynamic>> tipos;
    try {
      tipos = await FinancialService().getCostTypes();
    } catch (e) {
      _snack('No se pudieron cargar los tipos de costo: $e', error: true);
      return;
    }
    if (!mounted) return;
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoAjusteCompra(
        tipos: tipos,
        moneda: detalle.compra.monedaTotal,
      ),
    );
    if (datos == null || !mounted) return;
    try {
      await _service.agregarAjuste(
        idCompra: widget.idCompra,
        idTipoCosto: datos['id_tipo_costo'] as int,
        base: datos['base'] as String,
        valor: datos['valor'] as double,
      );
      _snack('Ajuste agregado: queda por financiar.');
      await _cargar();
    } catch (e) {
      _snack('No se pudo agregar el ajuste: $e', error: true);
    }
  }

  /// Financia el ajuste con una fuente del fondo en la moneda de la compra.
  /// (El diálogo no convierte monedas: elige una fuente de la misma moneda.)
  Future<void> _financiarAjuste(CompraAjuste ajuste) async {
    final detalle = _detalle;
    if (detalle == null || ajuste.id == null) return;
    final moneda = detalle.compra.monedaTotal;
    try {
      final todos = await _service.disponible(detalle.compra.idTienda);
      final fuentes = todos
          .where((f) =>
              f.moneda == moneda && f.disponible >= ajuste.montoCapitalizado)
          .toList();
      if (!mounted) return;
      if (fuentes.isEmpty) {
        _snack(
          'No hay fuente en $moneda con '
          '${formatearImporteMoneda(ajuste.montoCapitalizado, moneda)} '
          'disponible.',
          error: true,
        );
        return;
      }
      final elegida = await showDialog<DisponibleFondo>(
        context: context,
        builder: (_) => _DialogoFuenteAjuste(ajuste: ajuste, fuentes: fuentes),
      );
      if (elegida == null || !mounted) return;
      final r = await _service.financiarAjuste(
        idAjuste: ajuste.id!,
        fuentes: [
          {
            'id_cuenta': elegida.idCuenta,
            'id_medio_pago': elegida.idMedioPago,
            'moneda': elegida.moneda,
            'monto': ajuste.montoCapitalizado,
            'tasa': 1,
          },
        ],
      );
      _snack(
        r['duplicada'] == true
            ? 'El ajuste ya estaba financiado.'
            : 'Ajuste financiado y repartido en lo recibido.',
      );
      await _cargar();
    } catch (e) {
      _snack('No se pudo financiar el ajuste: $e', error: true);
    }
  }

  Widget _panelCostoAterrizado(CompraDetalle detalle) {
    final resumen = _costoResumen;
    if (resumen == null) return const SizedBox.shrink();
    final moneda = detalle.compra.monedaTotal;

    num numero(String clave) {
      final v = resumen[clave];
      if (v is num) return v;
      return num.tryParse('$v') ?? 0;
    }

    num? opcional(String clave) {
      final v = resumen[clave];
      if (v == null) return null;
      if (v is num) return v;
      return num.tryParse('$v');
    }

    final lineas = (resumen['lineas'] as List?) ?? const [];
    final vinculos = (resumen['vinculos'] as List?) ?? const [];
    final pctDecl = opcional('pct_importadora_declarado');
    final pctEf = opcional('pct_importadora_efectivo');
    final desvio = opcional('desvio_importadora');
    final ajustes = numero('ajustes_globales');

    Widget fila(
      String etiqueta,
      String valor, {
      bool destacada = false,
      Color? color,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              valor,
              style: TextStyle(
                fontSize: destacada ? 18 : 14,
                fontWeight: destacada ? FontWeight.w700 : FontWeight.w600,
                color: color ?? AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Costo aterrizado',
            trailing: textoMetaCompras('${vinculos.length} recepción(es)'),
          ),
          fila(
            'Valor de factura vinculado',
            formatearImporteMoneda(numero('valor_vinculado'), moneda),
          ),
          fila(
            'Cargo de importadora',
            formatearImporteMoneda(numero('cargo_importadora'), moneda),
          ),
          if (pctDecl != null)
            textoMetaCompras(
              'Importadora: declarado ${formatearCantidad(pctDecl)} % · '
              'efectivo ${pctEf == null ? '—' : '${formatearCantidad(pctEf)} %'}',
            ),
          if (desvio != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: avisoCompras(
                desvio == 0
                    ? 'Desvío de importadora: el cargo coincide con lo declarado.'
                    : 'Desvío de importadora: ${desvio > 0 ? '+' : ''}'
                          '${formatearImporteMoneda(desvio, moneda)} '
                          '(${desvio < 0 ? 'el cargo quedó por debajo de lo pactado' : 'el cargo superó lo pactado'}). '
                          'No se corrige solo: decida si reembolsa o ajusta el %.',
                color: desvio == 0 ? AppColors.success : AppColors.warning,
                icono: desvio == 0
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
              ),
            ),
          if (ajustes > 0) ...[
            fila('Ajustes globales', formatearImporteMoneda(ajustes, moneda)),
            fila(
              'Aplicado (${formatearCantidad(numero('pct_recibido') * 100)} % recibido)',
              formatearImporteMoneda(numero('ajustes_aplicados'), moneda),
            ),
            fila(
              'Por asignar',
              formatearImporteMoneda(numero('ajustes_por_asignar'), moneda),
            ),
          ],
          const Divider(height: 20),
          fila(
            'Total aterrizado',
            formatearImporteMoneda(numero('total_aterrizado'), moneda),
            destacada: true,
          ),
          if (lineas.isNotEmpty) ...[
            const SizedBox(height: 10),
            textoMetaCompras('Costo por línea recibida (${lineas.length})'),
            const SizedBox(height: 4),
            for (final linea in lineas.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${linea['producto'] ?? ''} · '
                        '${formatearCantidad(num.tryParse('${linea['cantidad']}') ?? 0)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${formatearImporte(num.tryParse('${linea['costo_factura_unit']}') ?? 0)}'
                      ' → '
                      '${formatearImporte(num.tryParse('${linea['costo_aterrizado_unit']}') ?? 0)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (lineas.length > 8)
              textoMetaCompras('… y ${lineas.length - 8} línea(s) más'),
            const SizedBox(height: 4),
            textoMetaCompras(
              'Unidad: factura → aterrizado, en $moneda. El promedio del '
              'producto lo capitaliza el servidor al completar la recepción.',
            ),
          ],
          if (vinculos.isNotEmpty) ...[
            const SizedBox(height: 10),
            textoMetaCompras('Recepciones vinculadas (${vinculos.length})'),
            for (final v in vinculos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recepción #${v['id_operacion']} · base '
                        '${formatearImporteMoneda(num.tryParse('${v['base_importadora']}') ?? 0, moneda)}'
                        ' · cargo '
                        '${formatearImporteMoneda(num.tryParse('${v['monto_importadora']}') ?? 0, moneda)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if ((num.tryParse('${v['filas_revertidas']}') ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Tooltip(
                          message:
                              'Costo revertido: la recepción se canceló o devolvió',
                          child: Icon(
                            Icons.undo,
                            size: 16,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    if (_puedeAterrizar(v))
                      TextButton(
                        onPressed: () =>
                            _aterrizarVinculo((v['id_compra_recepcion'] as num).toInt()),
                        child: const Text('Aterrizar cargo'),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // Líneas
  // ==========================================================================

  Widget _panelLineas(CompraDetalle detalle, ComprasTamano tamano) {
    final c = detalle.compra;
    final compacto = tamano == ComprasTamano.compacto;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Líneas',
            trailing: pastillaCompras(
              '${detalle.lineas.length} '
              '${detalle.lineas.length == 1 ? 'línea' : 'líneas'}',
              denso: true,
            ),
          ),
          if (detalle.lineas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: textoMetaCompras('La compra no tiene líneas.'),
            )
          else if (compacto)
            for (final l in detalle.lineas) _lineaTarjeta(l, c.monedaTotal)
          else ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text('Producto', style: _estiloCabeceraDetalle),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Cantidad',
                      textAlign: TextAlign.right,
                      style: _estiloCabeceraDetalle,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      'Costo unit.',
                      textAlign: TextAlign.right,
                      style: _estiloCabeceraDetalle,
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: Text(
                      'Costo línea',
                      textAlign: TextAlign.right,
                      style: _estiloCabeceraDetalle,
                    ),
                  ),
                ],
              ),
            ),
            for (final l in detalle.lineas) _lineaFila(l),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 12,
                color: AppColors.textLight,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: textoMetaCompras(
                  'El costo de línea lo calcula la base de datos '
                  '(cantidad × costo unitario): es de solo lectura.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineaFila(CompraLinea l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (l.producto ?? '').trim().isEmpty
                      ? 'Producto #${l.idProducto}'
                      : l.producto!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Producto #${l.idProducto}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              formatearCantidad(l.cantidad),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              formatearImporte(l.costoUnitario),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SizedBox(
            width: 130,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 12,
                  color: AppColors.textLight,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    formatearImporte(l.costoLinea),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaTarjeta(CompraLinea l, String moneda) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (l.producto ?? '').trim().isEmpty
                  ? 'Producto #${l.idProducto}'
                  : l.producto!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatearCantidad(l.cantidad)} × '
                    '${formatearImporte(l.costoUnitario)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  formatearImporteMoneda(l.costoLinea, moneda),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // Ajustes
  // ==========================================================================

  Widget _panelAjustes(CompraDetalle detalle) {
    final moneda = detalle.compra.monedaTotal;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Ajustes',
            trailing: pastillaCompras(
              '${detalle.ajustes.length}',
              denso: true,
              icono: Icons.tune,
            ),
          ),
          if (detalle.ajustes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: textoMetaCompras(
                'Sin ajustes: el aterrizado es igual a la mercancía.',
              ),
            )
          else
            for (final a in detalle.ajustes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            pastillaCompras(
                              a.baseLegible,
                              denso: true,
                              icono: Icons.percent,
                            ),
                            pastillaCompras(
                              a.repartoLegible,
                              denso: true,
                              icono: Icons.call_split,
                            ),
                            pastillaCompras(
                              a.origenPagoLegible,
                              denso: true,
                              icono: Icons.account_balance_wallet_outlined,
                              color:
                                  a.origenPago == OrigenPagoAjuste.fondo.codigo
                                  ? AppColors.primary
                                  : AppColors.secondary,
                            ),
                            if (!a.afectaInventario)
                              pastillaCompras(
                                'No capitaliza',
                                denso: true,
                                color: AppColors.warning,
                                icono: Icons.info_outline,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatearImporteMoneda(a.montoCapitalizado, moneda),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'valor ${formatearCantidad(a.valor)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                      if (a.estado == 'por_financiar')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              pastillaCompras(
                                'Por financiar',
                                denso: true,
                                color: AppColors.warning,
                                icono: Icons.schedule,
                              ),
                              const Spacer(),
                              if (detalle.compra.estado == 'completada')
                                TextButton(
                                  onPressed: () => _financiarAjuste(a),
                                  child: const Text('Financiar ahora'),
                                ),
                            ],
                          ),
                        )
                      else if (a.estado == 'financiado')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: pastillaCompras(
                            'Financiado',
                            denso: true,
                            color: AppColors.success,
                            icono: Icons.check_circle_outline,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Recepciones
  // ==========================================================================

  Widget _panelRecepciones(CompraDetalle detalle) {
    if (!detalle.tieneRecepciones) return const SizedBox.shrink();
    final moneda = detalle.compra.monedaTotal;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: panelCompras(
        children: [
          avisoCompras(
            'Esta compra ya tiene ${detalle.recepciones.length} '
            '${detalle.recepciones.length == 1 ? 'recepción registrada' : 'recepciones registradas'}. '
            'La cancelación la rechazará el servidor mientras existan.',
            icono: Icons.inventory_2_outlined,
          ),
          const SizedBox(height: 8),
          for (final r in detalle.recepciones)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 14,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Recepción #${r['id'] ?? '—'} · operación '
                      '${r['id_operacion'] ?? '—'} · '
                      '${_fechaRecepcion(r)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatearImporteMoneda(
                      (r['monto_valorizado'] as num?)?.toDouble() ?? 0,
                      (r['moneda'] ?? moneda).toString(),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Historial
  // ==========================================================================

  String _fechaRecepcion(Map<String, dynamic> r) {
    final crudo = r['created_at'];
    if (crudo == null) return 'sin fecha';
    return formatearFechaHora(DateTime.tryParse(crudo.toString()));
  }

  Widget _panelHistorial(CompraDetalle detalle) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Historial de estados',
            trailing: pastillaCompras(
              '${detalle.historial.length}',
              denso: true,
              icono: Icons.history,
            ),
          ),
          if (detalle.historial.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: textoMetaCompras('Sin movimientos de estado.'),
            )
          else
            for (var i = 0; i < detalle.historial.length; i++)
              _filaHistorial(
                detalle.historial[i],
                i == detalle.historial.length - 1,
              ),
        ],
      ),
    );
  }

  Widget _filaHistorial(CompraHistorico h, bool esUltimo) {
    final color = colorEstadoCompra(h.estadoNuevo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!esUltimo)
                Container(width: 2, height: 26, color: AppColors.border),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.estadoAnterior == null
                      ? h.estadoNuevoLegible
                      : '${h.estadoAnteriorLegible} → ${h.estadoNuevoLegible}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    formatearFechaHora(h.createdAt),
                    h.origen == 'automatico' ? 'automático' : 'manual',
                    if ((h.motivo ?? '').trim().isNotEmpty) h.motivo!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Acciones
  // ==========================================================================

  Widget _panelAcciones(CompraDetalle detalle) {
    final c = detalle.compra;
    final acciones = <Widget>[];

    if (c.estado == 'creada') {
      // En modo inversores no hay nada que reservar del fondo: el dinero llega
      // por aportes y se paga desde el panel de aportes. Ofrecer «Reservar del
      // fondo» solo producía un error del servidor.
      if (c.modoLiquidacion != 'inversores') {
        acciones.add(
          _botonAccion(
            icono: Icons.lock_open_outlined,
            etiqueta: 'Reservar del fondo',
            onPressed: _reservar,
          ),
        );
      }
      acciones.add(
        _botonAccion(
          icono: Icons.edit_outlined,
          etiqueta: 'Editar compra',
          onPressed: _editar,
          outlined: true,
        ),
      );
      acciones.add(
        _botonAccion(
          icono: Icons.cancel_outlined,
          etiqueta: 'Cancelar compra',
          onPressed: _cancelando ? null : _cancelar,
          outlined: true,
          color: AppColors.error,
        ),
      );
    } else if (c.estado == 'reservada') {
      acciones.add(
        _botonAccion(
          icono: Icons.payments_outlined,
          etiqueta: 'Pagar al proveedor',
          onPressed: _pagar,
        ),
      );
      acciones.add(
        _botonAccion(
          icono: Icons.lock_open_outlined,
          etiqueta: 'Liberar reserva',
          onPressed: _liberar,
          outlined: true,
          color: AppColors.warning,
        ),
      );
    } else if (c.estado == 'pagada') {
      acciones.add(
        _botonAccion(
          icono: Icons.block,
          etiqueta: 'Anular compra',
          onPressed: _anular,
          outlined: true,
          color: AppColors.error,
        ),
      );
    }

    // Costo que llega después de pagar: se agrega y se financia aparte.
    if (c.estado == 'pagada' ||
        c.estado == 'entrega_parcial' ||
        c.estado == 'completada') {
      acciones.add(
        _botonAccion(
          icono: Icons.add_circle_outline,
          etiqueta: 'Agregar costo posterior',
          onPressed: _agregarAjuste,
          outlined: true,
        ),
      );
    }

    if (acciones.isEmpty) {
      return panelCompras(
        children: [
          avisoCompras(
            'Compra «${c.estadoLegible}»: no admite acciones en este estado.',
            icono: Icons.lock_outline,
            color: AppColors.secondary,
          ),
        ],
      );
    }

    return panelCompras(
      children: [
        const Text(
          'Acciones',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < acciones.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          acciones[i],
        ],
        const SizedBox(height: 8),
        textoMetaCompras(_notaAcciones(c.estado, modoLiquidacion: c.modoLiquidacion)),
      ],
    );
  }

  Widget _botonAccion({
    required IconData icono,
    required String etiqueta,
    required VoidCallback? onPressed,
    bool outlined = false,
    Color? color,
  }) {
    if (outlined) {
      return SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icono, size: 18),
          label: Text(etiqueta),
          style: color == null
              ? null
              : OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                ),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icono, size: 18),
        label: Text(etiqueta),
        style: color == null
            ? null
            : FilledButton.styleFrom(backgroundColor: color),
      ),
    );
  }

  /// Qué hace cada acción, en una línea. No se explica el «¿seguro?»: se
  /// explica la consecuencia. En modo inversores el dinero no es del fondo, así
  /// que el texto cambia con el modo.
  String _notaAcciones(String estado, {String modoLiquidacion = 'fondo'}) {
    final inversores = modoLiquidacion == 'inversores';
    switch (estado) {
      case 'creada':
        if (inversores) {
          return 'La compra se cubre con aportes de inversores al 100 %: se '
              'registran en el panel de arriba y no tocan el fondo. Solo se '
              'edita y se cancela en «Creada» y sin recepciones.';
        }
        return 'Reservar congela el disponible del fondo según las fuentes que '
            'elijas. Solo se edita y se cancela en «Creada» y sin recepciones; '
            'el servidor valida ambas cosas.';
      case 'reservada':
        return 'Pagar descuenta el dinero del fondo y deja la compra en '
            '«Pagada». Liberar devuelve el disponible sin pagar y la compra '
            'vuelve a «Creada»; ambas exigen confirmación.';
      case 'pagada':
        if (inversores) {
          return 'Anular exige que los aportes estén devueltos: no se acredita '
              'al fondo dinero que nunca salió de él. Queda en el historial y '
              'no se puede deshacer.';
        }
        return 'Anular devuelve al fondo lo pagado y exige motivo. Queda en el '
            'historial y no se puede deshacer.';
      default:
        return 'El servidor decide qué transiciones están permitidas.';
    }
  }
}

const TextStyle _estiloCabeceraDetalle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: AppColors.textSecondary,
);

/// Las RPC lanzan `RAISE EXCEPTION` con texto útil en español: se muestra tal
/// cual, sin el envoltorio `PostgrestException(...)`.
String _mensajeError(Object e) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) return e.message;
  final texto = e.toString().replaceFirst('Exception: ', '');
  return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
}

// ===========================================================================
// Diálogos de dinero
// ===========================================================================

/// Confirmación del pago: el dinero sale del fondo.
///
/// La llamada la hace el diálogo, no la pantalla: si el servidor falla, el
/// diálogo se queda abierto con el mensaje a la vista en vez de cerrarse y
/// tragarse el error.
class _DialogoPago extends StatefulWidget {
  const _DialogoPago({required this.compra});

  final Compra compra;

  @override
  State<_DialogoPago> createState() => _DialogoPagoState();
}

class _DialogoPagoState extends State<_DialogoPago> {
  final _service = CompraService();
  bool _enviando = false;
  String? _error;

  Future<void> _confirmar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final r = await _service.pagar(widget.compra.id);
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
    final c = widget.compra;
    return AlertDialog(
      title: const Text('Pagar la compra'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El dinero sale del fondo: se descuentan '
                '${formatearImporteMoneda(c.totalFinanciado, c.monedaTotal)} de '
                'las cuentas reservadas y la compra #${c.numeroCompra} pasa a '
                '«Pagada».',
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              avisoCompras(
                'La reserva deja de estar congelada y se convierte en pago. '
                'Esta acción no se deshace: para revertirla hay que anular la '
                'compra, y el importe vuelve al fondo.',
                icono: Icons.account_balance,
                color: AppColors.warning,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
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
          icon: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.payments, size: 18),
          label: Text(_enviando ? 'Pagando…' : 'Pagar y descontar del fondo'),
        ),
      ],
    );
  }
}

/// Liberar y anular: exigen motivo y no dejan confirmar en blanco. Igual que
/// el pago, la llamada vive aquí para no cerrarse ante un error del servidor.
class _DialogoMotivo extends StatefulWidget {
  const _DialogoMotivo({
    required this.titulo,
    required this.descripcion,
    required this.etiquetaConfirmar,
    required this.colorConfirmar,
    required this.pista,
    required this.accion,
  });

  final String titulo;
  final String descripcion;
  final String etiquetaConfirmar;
  final Color colorConfirmar;
  final String pista;
  final Future<Map<String, dynamic>> Function(String motivo) accion;

  @override
  State<_DialogoMotivo> createState() => _DialogoMotivoState();
}

class _DialogoMotivoState extends State<_DialogoMotivo> {
  final _ctrl = TextEditingController();
  bool _enviando = false;
  String? _errorLocal;
  String? _errorServidor;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final motivo = _ctrl.text.trim();
    if (motivo.isEmpty) {
      setState(() => _errorLocal = widget.pista);
      return;
    }
    setState(() {
      _enviando = true;
      _errorLocal = null;
      _errorServidor = null;
    });
    try {
      final r = await widget.accion(motivo);
      if (!mounted) return;
      Navigator.pop(context, r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _errorServidor = _mensajeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.descripcion,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                enabled: !_enviando,
                onChanged: (_) {
                  if (_errorLocal != null) {
                    setState(() => _errorLocal = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Motivo *',
                  errorText: _errorLocal,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_errorServidor != null) ...[
                const SizedBox(height: 10),
                avisoCompras(
                  _errorServidor!,
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
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.colorConfirmar,
          ),
          onPressed: _enviando ? null : _confirmar,
          child: Text(_enviando ? 'Procesando…' : widget.etiquetaConfirmar),
        ),
      ],
    );
  }
}

/// Agregar un costo posterior al pago. El importe lo calcula el servidor a
/// partir de la base y el valor; aquí solo se capturan.
class _DialogoAjusteCompra extends StatefulWidget {
  const _DialogoAjusteCompra({required this.tipos, required this.moneda});

  final List<Map<String, dynamic>> tipos;
  final String moneda;

  @override
  State<_DialogoAjusteCompra> createState() => _DialogoAjusteCompraState();
}

class _DialogoAjusteCompraState extends State<_DialogoAjusteCompra> {
  final _formKey = GlobalKey<FormState>();
  final _valor = TextEditingController();
  int? _tipo;
  String _base = 'global';

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  String get _etiquetaValor => switch (_base) {
    'porcentaje' => 'Porcentaje sobre la mercancía (%)',
    'unidad' => 'Importe por unidad',
    _ => 'Importe (${widget.moneda})',
  };

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    final valor = double.tryParse(_valor.text.replaceAll(',', '.'));
    if (valor == null || valor <= 0 || _tipo == null) return;
    Navigator.pop(context, {
      'id_tipo_costo': _tipo,
      'base': _base,
      'valor': valor,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar costo posterior'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Queda «por financiar»: no cambia el total financiado y se '
                  'cubre con una fuente del fondo cuando la compra esté '
                  'completada.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final t in widget.tipos)
                      DropdownMenuItem(
                        value: (t['id'] as num).toInt(),
                        child: Text(t['denominacion']?.toString() ?? ''),
                      ),
                  ],
                  validator: (v) => v == null ? 'Elija el concepto' : null,
                  onChanged: (v) => setState(() => _tipo = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _base,
                  decoration: const InputDecoration(
                    labelText: 'Base',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'global',
                      child: Text('Importe global'),
                    ),
                    DropdownMenuItem(
                      value: 'porcentaje',
                      child: Text('Porcentaje de la mercancía'),
                    ),
                    DropdownMenuItem(
                      value: 'unidad',
                      child: Text('Importe por unidad'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _base = v ?? 'global'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _valor,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _etiquetaValor,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) {
                    final t = double.tryParse((v ?? '').replaceAll(',', '.'));
                    return t == null || t <= 0 ? 'Mayor que 0' : null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Agregar')),
      ],
    );
  }
}

/// Elegir la fuente del fondo que cubre el ajuste. Solo lista fuentes de la
/// moneda de la compra con disponible suficiente (sin conversión).
class _DialogoFuenteAjuste extends StatefulWidget {
  const _DialogoFuenteAjuste({required this.ajuste, required this.fuentes});

  final CompraAjuste ajuste;
  final List<DisponibleFondo> fuentes;

  @override
  State<_DialogoFuenteAjuste> createState() => _DialogoFuenteAjusteState();
}

class _DialogoFuenteAjusteState extends State<_DialogoFuenteAjuste> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final moneda = widget.fuentes.first.moneda;
    return AlertDialog(
      title: const Text('Financiar ajuste'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se descuentan '
                '${formatearImporteMoneda(widget.ajuste.montoCapitalizado, moneda)} '
                'de la fuente elegida y el costo se reparte sobre lo recibido. '
                'La valoración del producto se actualiza al confirmar.',
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < widget.fuentes.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _sel == i
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _sel == i ? AppColors.primary : AppColors.textLight,
                  ),
                  title: Text(
                    widget.fuentes[i].etiqueta,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    'Disponible '
                    '${formatearImporteMoneda(widget.fuentes[i].disponible, moneda)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => setState(() => _sel = i),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _sel == null
              ? null
              : () => Navigator.pop(context, widget.fuentes[_sel!]),
          child: const Text('Financiar'),
        ),
      ],
    );
  }
}