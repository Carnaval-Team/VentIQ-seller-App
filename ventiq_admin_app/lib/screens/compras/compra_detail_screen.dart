import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/compra.dart';
import '../../services/compra_service.dart';
import '../../widgets/admin_drawer.dart';
import 'compra_form_screen.dart';
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
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
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

  String _mensajeDe(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '');
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
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
                  child: Row(
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
    final puedeEditar = c.esEditable;
    final puedeCancelar = c.esCancelable;

    if (!puedeEditar && !puedeCancelar) {
      return panelCompras(
        children: [
          avisoCompras(
            'Compra «${c.estadoLegible}»: no admite edición ni cancelación.',
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
        if (puedeEditar)
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _cancelando ? null : _editar,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar compra'),
            ),
          ),
        if (puedeEditar && puedeCancelar) const SizedBox(height: 8),
        if (puedeCancelar)
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _cancelando ? null : _cancelar,
              icon: _cancelando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cancel_outlined, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              label: const Text('Cancelar compra'),
            ),
          ),
        const SizedBox(height: 8),
        textoMetaCompras(
          'Solo se edita y se cancela una compra en estado «Creada» y sin '
          'recepciones. El servidor es quien valida ambas cosas.',
        ),
      ],
    );
  }
}

const TextStyle _estiloCabeceraDetalle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: AppColors.textSecondary,
);
