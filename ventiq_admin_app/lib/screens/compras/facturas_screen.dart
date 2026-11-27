/// Vista de facturas con su estado de recepción (fase 9 de Compras).
///
/// Lee `fn_fdi_facturas(id_tienda, desde, hasta)`: es el listado **documental**
/// e incluye las compras cerradas (`completada`, `cancelada`, `anulada`), no
/// solo las abiertas del panel de trabajo. Cada fila abre la compra.
///
/// Los totales van **por moneda**. Sin permiso de importes, las columnas de
/// dinero desaparecen y el resumen cuenta facturas en lugar de sumar.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pendientes.dart';
import '../../services/pendientes_service.dart';
import '../../services/permissions_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/admin_drawer.dart';
import '../reportes/reportes_widgets.dart'
    show
        ColumnaReporte,
        FilaReporte,
        TablaReporte,
        celdaChip,
        celdaCifra,
        celdaDoble,
        celdaTexto,
        cifraKpi,
        mensajeVacioReporte,
        notaReporte;
import 'compras_widgets.dart';
import 'pendiente_detalle_screen.dart';
import 'pendientes_widgets.dart';

/// Listado de facturas con su estado de recepción.
class FacturasScreen extends StatefulWidget {
  const FacturasScreen({
    super.key,
    this.idTienda,
    this.puedeVerImportes,
    this.nombreTienda,
    this.vistaInicial,
  });

  final int? idTienda;
  final bool? puedeVerImportes;
  final String? nombreTienda;

  /// Datos ya cargados: montaje sin Supabase para el humo de widget.
  final FacturasVista? vistaInicial;

  @override
  State<FacturasScreen> createState() => _FacturasScreenState();
}

class _FacturasScreenState extends State<FacturasScreen> {
  final _service = PendientesService();
  final _prefs = UserPreferencesService();

  int? _idTienda;
  String? _nombreTienda;
  bool? _puedeVerImportes;

  FacturasVista? _vista;
  DateTimeRange? _rango;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final inicial = widget.vistaInicial;
    if (inicial != null) {
      _vista = inicial;
      _idTienda = widget.idTienda ?? inicial.idTienda;
      _nombreTienda = widget.nombreTienda;
      _puedeVerImportes = widget.puedeVerImportes ?? false;
      return;
    }
    _cargar();
  }

  // ==========================================================================
  // Datos
  // ==========================================================================

  Future<void> _resolverContexto() async {
    _idTienda ??= widget.idTienda ?? await _prefs.getIdTienda();
    if (widget.puedeVerImportes != null) {
      _puedeVerImportes = widget.puedeVerImportes;
    } else if (_puedeVerImportes == null) {
      try {
        _puedeVerImportes = await PermissionsService().canViewImportesCompras();
      } catch (_) {
        // Si el rol no se puede resolver, la vista segura es «sin importes».
        _puedeVerImportes = false;
      }
    }
    if (widget.nombreTienda != null) {
      _nombreTienda = widget.nombreTienda;
    } else if (_nombreTienda == null) {
      try {
        final info = await _prefs.getCurrentStoreInfo();
        final nombre = info?['denominacion']?.toString().trim();
        if (nombre != null && nombre.isNotEmpty) _nombreTienda = nombre;
      } catch (_) {
        _nombreTienda = null;
      }
    }
  }

  Future<void> _cargar() async {
    if (_cargando) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await _resolverContexto();
      final idTienda = _idTienda;
      if (idTienda == null) {
        throw Exception(
          'No se pudo determinar la tienda del usuario. Vuelve a iniciar '
          'sesión o selecciona una tienda.',
        );
      }
      final vista = await _service.facturas(
        idTienda: idTienda,
        desde: _rango?.start,
        hasta: _rango?.end,
      );
      if (!mounted) return;
      setState(() {
        _vista = vista;
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
    final texto = e
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('PostgrestException(message: ', '')
        .trim();
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(ahora.year - 4),
      lastDate: DateTime(ahora.year + 2),
      initialDateRange: _rango,
      helpText: 'Filtrar por fecha de factura',
      saveText: 'Aplicar',
    );
    if (rango == null || !mounted) return;
    setState(() => _rango = rango);
    await _cargar();
  }

  Future<void> _limpiarRango() async {
    setState(() => _rango = null);
    await _cargar();
  }

  // ==========================================================================
  // Navegación
  // ==========================================================================

  Future<void> _abrirCompra(FacturaResumen factura) async {
    final idTienda = _idTienda ?? _vista?.idTienda;
    if (idTienda == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PendienteDetalleScreen(
          idTienda: idTienda,
          idCompra: factura.idCompra,
          puedeVerImportes: _puedeVerImportes ?? false,
          nombreTienda: _nombreTienda,
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Facturas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          const EndDrawerButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      endDrawer: const AdminDrawer(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < comprasAnchoCompacto;
          return RefreshIndicator(
            onRefresh: _cargar,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 38,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _cabecera(compacto: compacto, ancho: constraints.maxWidth),
                    const SizedBox(height: 14),
                    ..._contenido(compacto: compacto, ancho: constraints.maxWidth),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cabecera({required bool compacto, required double ancho}) {
    // Cabecera apilada por debajo de 900 px: título y filtro de fechas no
    // caben en una línea sin recortarse.
    final apilada = ancho < 900;
    final vista = _vista;
    final partes = <String>[
      _nombreTienda ?? 'Tienda ${_idTienda ?? '—'}',
      if (vista != null)
        vista.total == 1 ? '1 factura' : '${vista.total} facturas',
      if (_rango != null)
        '${formatearFecha(_rango!.start)} – ${formatearFecha(_rango!.end)}'
      else
        'todas las fechas',
    ];

    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compacto ? 'Facturas' : 'Facturas y recepción',
          style: TextStyle(
            fontSize: compacto ? 20 : 24,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          partes.join(' · '),
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );

    final acciones = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _elegirRango,
          icon: const Icon(Icons.date_range, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            backgroundColor: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          label: Text(
            _rango == null
                ? 'Fecha de factura'
                : '${formatearFecha(_rango!.start)} – ${formatearFecha(_rango!.end)}',
          ),
        ),
        if (_rango != null)
          TextButton.icon(
            onPressed: _limpiarRango,
            icon: const Icon(Icons.filter_alt_off, size: 16),
            label: const Text('Quitar fechas'),
          ),
      ],
    );

    if (apilada) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titulo, const SizedBox(height: 10), acciones],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: titulo),
        const SizedBox(width: 12),
        acciones,
      ],
    );
  }

  List<Widget> _contenido({required bool compacto, required double ancho}) {
    if (_error != null) {
      return [
        errorPendientes(
          mensaje: _error!,
          onReintentar: _cargar,
          titulo: 'No se pudieron cargar las facturas',
        ),
      ];
    }
    final vista = _vista;
    if (vista == null) {
      return [cargandoPendientes(texto: 'Cargando facturas...')];
    }

    final puedeVerImportes = _puedeVerImportes ?? false;
    if (vista.vacio) {
      return [
        _franja(vista, puedeVerImportes),
        const SizedBox(height: 14),
        mensajeVacioReporte(
          titulo: _rango == null
              ? 'Todavía no hay facturas registradas'
              : 'Ninguna factura en el rango de fechas',
          detalle: _rango == null
              ? 'Registra una compra con su factura para verla aquí, con su '
                    'estado de recepción.'
              : 'Prueba con otro rango: el filtro va sobre la fecha de la '
                    'factura y deja fuera las compras sin fecha.',
          icono: Icons.receipt_long_outlined,
        ),
      ];
    }

    final conTablaMedia = ancho >= 760;
    return [
      _franja(vista, puedeVerImportes),
      const SizedBox(height: 14),
      if (!compacto && conTablaMedia)
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _tabla(
              vista,
              puedeVerImportes,
              compacta: ancho < comprasAnchoPanelLateral,
            ),
          ),
        )
      else
        _listaTarjetas(vista, puedeVerImportes),
      const SizedBox(height: 10),
      notaReporte(
        puedeVerImportes
            ? 'El total de factura, el aterrizado y lo pagado están en la '
                  'moneda de cada compra: no se suman monedas distintas.'
            : 'Vista sin importes: se muestra la fecha, el avance recibido y el '
                  'estado de cada factura.',
      ),
    ];
  }

  Widget _franja(FacturasVista vista, bool puedeVerImportes) {
    return panelCompras(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final anchoBloque = constraints.maxWidth < 640
                ? (constraints.maxWidth - 24) / 2
                : null;
            final bloques = <Widget>[
              cifraKpi(
                'Facturas',
                '${vista.total}',
                apoyo: _rango == null ? 'todas las fechas' : 'en el rango',
              ),
              cifraKpi(
                'Sin recibir',
                '${vista.sinRecibir}',
                apoyo: 'de ${vista.total}',
              ),
              cifraKpi('Parciales', '${vista.parciales}'),
              cifraKpi('Completas', '${vista.completas}'),
              if (puedeVerImportes)
                for (final total in vista.totalesPorMoneda)
                  cifraKpi(
                    'Facturado ${total.moneda.isEmpty ? 's/moneda' : total.moneda}',
                    formatearImporte(total.totalFactura),
                    apoyo: '${total.compras} '
                        '${total.compras == 1 ? 'factura' : 'facturas'} · '
                        'pagado ${formatearImporte(total.pagado)}',
                  ),
            ];
            return Wrap(
              spacing: 24,
              runSpacing: 14,
              children: [
                for (final bloque in bloques)
                  SizedBox(width: anchoBloque, child: bloque),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        notaReporte(
          puedeVerImportes
              ? (vista.totalesPorMoneda.length <= 1
                    ? 'Los totales están en la moneda de cada factura.'
                    : '${vista.totalesPorMoneda.map((t) => t.moneda.isEmpty ? 's/moneda' : t.moneda).toSet().join(' y ')} '
                          'no se suman: cada moneda va en su bloque.')
              : 'Vista sin importes.',
        ),
      ],
    );
  }

  Widget _tabla(
    FacturasVista vista,
    bool puedeVerImportes, {
    required bool compacta,
  }) {
    final columnas = <ColumnaReporte>[
      const ColumnaReporte('Factura', 130),
      const ColumnaReporte('Compra', 96),
      ColumnaReporte('Proveedor', compacta ? 160 : 190),
      const ColumnaReporte('Fecha', 92),
      const ColumnaReporte('Estado compra', 128),
      const ColumnaReporte('Recepción', 110),
      const ColumnaReporte('% recibido', 116),
      if (puedeVerImportes)
        const ColumnaReporte('Total factura', 118, derecha: true),
      if (puedeVerImportes)
        const ColumnaReporte('Aterrizado', 110, derecha: true),
      if (puedeVerImportes)
        const ColumnaReporte('Pagado', 104, derecha: true),
      if (!compacta) const ColumnaReporte('Últ. recep.', 100),
    ];
    final filas = <FilaReporte>[
      for (final f in vista.facturas)
        FilaReporte(
          [
            celdaTexto(
              f.numeroFactura ?? 'Sin factura',
              negrita: true,
              color: f.numeroFactura == null ? AppColors.textSecondary : null,
            ),
            celdaTexto(f.etiquetaCompra),
            celdaTexto(f.proveedor ?? '—'),
            celdaTexto(formatearFecha(f.fechaFactura)),
            celdaChip(chipEstadoCompra(f.estado, denso: true)),
            celdaChip(chipEstadoRecepcion(f.estadoRecepcion.codigo, denso: true)),
            celdaRecibido(f.recibidoPct),
            if (puedeVerImportes)
              celdaCifra(formatearImporteMoneda(f.totalFactura, f.moneda)),
            if (puedeVerImportes)
              celdaCifra(formatearImporteMoneda(f.aterrizado, f.moneda)),
            if (puedeVerImportes)
              celdaCifra(formatearImporteMoneda(f.pagado, f.moneda)),
            if (!compacta)
              celdaTexto(
                f.ultimaRecepcion == null
                    ? 'Sin recepción'
                    : formatearFecha(f.ultimaRecepcion),
                color: f.ultimaRecepcion == null
                    ? AppColors.textSecondary
                    : null,
              ),
          ],
          onTap: () => _abrirCompra(f),
        ),
    ];
    return TablaReporte(columnas: columnas, filas: filas);
  }

  Widget _listaTarjetas(FacturasVista vista, bool puedeVerImportes) {
    return Column(
      children: [
        for (final f in vista.facturas)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _abrirCompra(f),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: celdaDoble(
                              f.numeroFactura ?? 'Sin factura',
                              '${f.etiquetaCompra} · ${f.proveedor ?? '—'}',
                            ),
                          ),
                          const SizedBox(width: 8),
                          chipEstadoRecepcion(
                            f.estadoRecepcion.codigo,
                            denso: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatearFecha(f.fechaFactura),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          barraRecibido(f.recibidoPct, ancho: 88),
                        ],
                      ),
                      if (puedeVerImportes) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Factura ${formatearImporteMoneda(f.totalFactura, f.moneda)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              'Pagado ${formatearImporteMoneda(f.pagado, f.moneda)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}