/// Detalle de faltantes de una compra (fase 9 de Compras).
///
/// Lee `fn_fdi_pendientes_detalle(id_tienda, id_compra)` —las mismas cifras
/// que la fila del panel, que es el invariante del contrato— y el histórico de
/// recepciones (`fn_fdi_recepciones_historial`), filtrado en cliente por número
/// de compra porque el histórico no devuelve `id_compra`.
///
/// Acciones: **una sola pareja** `Ir a recepción` / `Ver factura`. La primera
/// abre la pantalla de recepción de inventario que ya existe en la app; la
/// segunda, el detalle completo de la compra (documento de factura).
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pendientes.dart';
import '../../services/pendientes_export_service.dart';
import '../../services/pendientes_service.dart';
import '../../services/permissions_service.dart';
import '../../services/user_preferences_service.dart';
import '../inventory_reception_screen.dart';
import 'compra_detail_screen.dart';
import 'compras_widgets.dart';
import 'pendientes_widgets.dart';

/// Detalle de faltantes por producto y línea de una compra.
class PendienteDetalleScreen extends StatefulWidget {
  const PendienteDetalleScreen({
    super.key,
    required this.idCompra,
    this.idTienda,
    this.puedeVerImportes,
    this.nombreTienda,
    this.detalleInicial,
    this.recepcionesIniciales,
  });

  /// Argumentos de la ruta `/compras/pendientes/detalle`.
  ///
  /// Acepta un `int` (id de compra) o un `Map` con `id_compra`/`idCompra`,
  /// `id_tienda`/`idTienda` y `puede_ver_importes`/`puedeVerImportes`. Si no
  /// hay id de compra, devuelve `null` y la ruta cae al panel.
  static PendienteDetalleScreen? desdeArgumentos(dynamic argumentos) {
    if (argumentos is int) {
      return PendienteDetalleScreen(idCompra: argumentos);
    }
    if (argumentos is! Map) return null;
    final mapa = Map<String, dynamic>.from(argumentos);
    final id = mapa['id_compra'] ?? mapa['idCompra'];
    final idCompra = id is num ? id.toInt() : int.tryParse('$id');
    if (idCompra == null) return null;
    final tienda = mapa['id_tienda'] ?? mapa['idTienda'];
    final importes = mapa['puede_ver_importes'] ?? mapa['puedeVerImportes'];
    return PendienteDetalleScreen(
      idCompra: idCompra,
      idTienda: tienda is num ? tienda.toInt() : int.tryParse('$tienda'),
      puedeVerImportes: importes is bool ? importes : null,
    );
  }

  final int idCompra;

  /// Tienda de la sesión si es `null`.
  final int? idTienda;

  /// Permiso de importes ya derivado del rol (se resuelve si es `null`).
  final bool? puedeVerImportes;

  final String? nombreTienda;

  /// Datos ya cargados: montaje sin Supabase para el humo de widget.
  final PendienteDetalle? detalleInicial;
  final List<RecepcionHistorial>? recepcionesIniciales;

  @override
  State<PendienteDetalleScreen> createState() => _PendienteDetalleScreenState();
}

class _PendienteDetalleScreenState extends State<PendienteDetalleScreen> {
  final _service = PendientesService();
  final _exportService = PendientesExportService();
  final _prefs = UserPreferencesService();

  int? _idTienda;
  String? _nombreTienda;
  bool? _puedeVerImportes;

  PendienteDetalle? _detalle;
  List<RecepcionHistorial> _recepciones = const [];
  bool _errorRecepciones = false;

  bool _cargando = false;
  bool _exportando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final inicial = widget.detalleInicial;
    if (inicial != null) {
      _detalle = inicial;
      _recepciones = widget.recepcionesIniciales ?? const [];
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
      final detalle = await _service.detalle(
        idTienda: idTienda,
        idCompra: widget.idCompra,
      );
      // El bloque de recepciones es informativo: si el histórico falla, el
      // detalle de faltantes se sigue mostrando.
      var recepciones = const <RecepcionHistorial>[];
      var errorRecepciones = false;
      try {
        final historico = await _service.recepciones(idTienda: idTienda);
        recepciones = historico.deCompra(detalle.compra.numeroCompra);
      } catch (_) {
        errorRecepciones = true;
      }
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
        _recepciones = recepciones;
        _errorRecepciones = errorRecepciones;
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

  void _avisar(String texto, {bool error = false}) {
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

  /// `Ir a recepción`: abre la pantalla de recepción de inventario de la app.
  ///
  /// No hay una ruta nombrada para recepción, así que se navega a la pantalla
  /// existente con `MaterialPageRoute`; si el push falla, se avisa en lugar de
  /// dejar un botón que no hace nada.
  Future<void> _irARecepcion() async {
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const InventoryReceptionScreen()),
      );
      if (mounted) await _cargar();
    } catch (e) {
      if (mounted) {
        _avisar('No se pudo abrir la recepción: ${_mensajeDe(e)}', error: true);
      }
    }
  }

  /// `Ver factura`: abre el detalle completo de la compra (documento).
  Future<void> _verFactura() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CompraDetailScreen(idCompra: widget.idCompra),
      ),
    );
    if (mounted) await _cargar();
  }

  Future<void> _abrirExportacion() async {
    final detalle = _detalle;
    if (detalle == null || _exportando) return;
    final formato = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Exportar faltantes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on, color: AppColors.success),
              title: const Text('Excel'),
              subtitle: const Text('Una fila por línea, más totales por moneda'),
              onTap: () => Navigator.pop(ctx, 'excel'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: AppColors.error),
              title: const Text('PDF'),
              subtitle: const Text(
                'Cabecera de la compra, líneas y totales por moneda',
              ),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (formato == null || !mounted) return;

    setState(() => _exportando = true);
    try {
      final tienda = _nombreTienda ?? 'Tienda ${detalle.idTienda}';
      if (formato == 'excel') {
        await _exportService.exportarDetalleExcel(
          context: context,
          detalle: detalle,
          nombreTienda: tienda,
        );
      } else {
        await _exportService.exportarDetallePdf(
          context: context,
          detalle: detalle,
          nombreTienda: tienda,
        );
      }
    } catch (e) {
      if (mounted) {
        _avisar('No se pudo generar el archivo: ${_mensajeDe(e)}', error: true);
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final puedeVerImportes = _puedeVerImportes ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _detalle == null
              ? 'Compra #${widget.idCompra}'
              : 'Compra ${_detalle!.compra.etiquetaCompra}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (puedeVerImportes)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Exportar',
              onPressed: _detalle == null || _exportando
                  ? null
                  : _abrirExportacion,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 38,
                ),
                child: _contenido(constraints.maxWidth, puedeVerImportes),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _contenido(double ancho, bool puedeVerImportes) {
    if (_error != null) {
      return errorPendientes(
        mensaje: _error!,
        onReintentar: _cargar,
        titulo: 'No se pudo cargar el detalle de la compra',
      );
    }
    final detalle = _detalle;
    if (detalle == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: cargandoPendientes(texto: 'Cargando faltantes...'),
      );
    }

    final compra = detalle.compra;
    final compacto = ancho < comprasAnchoCompacto;
    final conLateral = ancho >= comprasAnchoPanelLateral;

    final izquierda = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabeceraCompra(compra, compacto: compacto),
        const SizedBox(height: 12),
        avanceCompraPendiente(
          compra: compra,
          puedeVerImportes: puedeVerImportes,
        ),
        const SizedBox(height: 12),
        _panelLineas(detalle, puedeVerImportes, compacto: compacto),
        const SizedBox(height: 10),
        Text(
          'Pendiente por línea = cantidad − recibido, acotado a 0. Los días sin '
          'movimiento se cuentan desde la última recepción de la línea o, si '
          'nunca se recibió, desde la emisión de la compra.',
          style: const TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );

    final lateral = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelRecepciones(puedeVerImportes),
        const SizedBox(height: 12),
        _acciones(puedeVerImportes),
      ],
    );

    if (!conLateral) {
      // Una sola columna: la pareja de acciones va al final del contenido.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          izquierda,
          const SizedBox(height: 14),
          lateral,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: izquierda),
        const SizedBox(width: 16),
        SizedBox(width: 340, child: lateral),
      ],
    );
  }

  // ==========================================================================
  // Cabecera
  // ==========================================================================

  Widget _cabeceraCompra(
    CompraPendienteCabecera compra, {
    required bool compacto,
  }) {
    final titulo = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            'Compra ${compra.etiquetaCompra}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compacto ? 19 : 22,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (compra.proveedor != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '· ${compra.proveedor}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compacto ? 16 : 19,
                height: 1.15,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );

    final chips = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        chipEstadoCompra(compra.estado, denso: true),
        chipAntiguedad(compra.diasAntiguedad),
      ],
    );

    final meta = Text(
      [
        if (compra.numeroFactura != null) 'Factura ${compra.numeroFactura}',
        'emitida ${formatearFecha(compra.fechaFactura)}',
        if (_nombreTienda != null) _nombreTienda!,
      ].join(' · '),
      style: const TextStyle(
        fontSize: 12,
        height: 1.35,
        color: AppColors.textSecondary,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titulo,
        const SizedBox(height: 6),
        meta,
        const SizedBox(height: 8),
        chips,
      ],
    );
  }

  // ==========================================================================
  // Faltantes
  // ==========================================================================

  Widget _panelLineas(
    PendienteDetalle detalle,
    bool puedeVerImportes, {
    required bool compacto,
  }) {
    final compra = detalle.compra;
    final subtitulo = [
      '${detalle.lineas.length} '
          '${detalle.lineas.length == 1 ? 'línea' : 'líneas'}',
      if (detalle.lineasSinRecepcion > 0)
        '${detalle.lineasSinRecepcion} sin recibir',
      if (puedeVerImportes)
        'total pendiente '
            '${formatearImporteMoneda(compra.montoPendiente, compra.moneda)}',
    ].join(' · ');

    if (detalle.lineas.isEmpty) {
      return panelCompras(
        children: [
          tituloSeccionCompras('Faltantes por producto y línea'),
          avisoCompras(
            'La compra no tiene líneas registradas, así que no hay nada que '
            'recibir ni cantidades que comparar.',
            icono: Icons.info_outline,
            color: AppColors.warning,
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Faltantes por producto y línea',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitulo,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            tablaLineasPendientes(
              lineas: detalle.lineas,
              moneda: compra.moneda,
              puedeVerImportes: puedeVerImportes,
              compacta: compacto,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pendiente por línea = comprado − recibido. '
                      '${detalle.lineasConPendiente} '
                      '${detalle.lineasConPendiente == 1 ? 'línea con pendiente' : 'líneas con pendiente'}.',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (puedeVerImportes) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Total pendiente '
                      '${formatearImporteMoneda(compra.montoPendiente, compra.moneda)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // Recepciones de esta compra
  // ==========================================================================

  Widget _panelRecepciones(bool puedeVerImportes) {
    final compra = _detalle?.compra;
    final montoRecibido = compra == null
        ? 0.0
        : (compra.montoTotal - compra.montoPendiente);
    final subtitulo = compra == null
        ? ''
        : [
            '${_recepciones.length} '
                '${_recepciones.length == 1 ? 'operación' : 'operaciones'}',
            if (puedeVerImportes)
              '${formatearImporteMoneda(montoRecibido < 0 ? 0 : montoRecibido, compra.moneda)} vinculados',
          ].join(' · ');

    return panelCompras(
      children: [
        tituloSeccionCompras(
          'Recepciones de esta compra',
          trailing: _recepciones.isEmpty
              ? null
              : pastillaCompras(
                  '${_recepciones.length}',
                  color: AppColors.secondary,
                  denso: true,
                ),
        ),
        if (subtitulo.isNotEmpty) ...[
          textoMetaCompras(subtitulo),
          const SizedBox(height: 10),
        ],
        if (_errorRecepciones)
          avisoCompras(
            'No se pudo leer el histórico de recepciones. El detalle de '
            'faltantes sigue siendo válido.',
            icono: Icons.info_outline,
          )
        else if (_recepciones.isEmpty)
          textoMetaCompras(
            'Esta compra todavía no tiene recepciones vinculadas.',
          )
        else
          for (final recepcion in _recepciones)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _filaRecepcion(recepcion, puedeVerImportes),
            ),
      ],
    );
  }

  Widget _filaRecepcion(RecepcionHistorial recepcion, bool puedeVerImportes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  recepcion.fecha == null
                      ? 'Sin fecha'
                      : formatearFecha(recepcion.fecha),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (recepcion.idOperacion != null)
                      'OPE-${recepcion.idOperacion}',
                    if (recepcion.productos != null) recepcion.productos!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (puedeVerImportes)
                Text(
                  formatearImporteMoneda(
                    recepcion.montoValorizado,
                    recepcion.moneda,
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              if (recepcion.estadoOperacionNombre != null) ...[
                const SizedBox(height: 3),
                pastillaCompras(
                  recepcion.estadoOperacionNombre!,
                  color: _colorEstadoOperacion(
                    recepcion.estadoOperacionNombre,
                  ),
                  denso: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Color del estado de la operación de recepción. Se deriva del nombre que
  /// devuelve el servidor (`estado_operacion_nombre`); el texto siempre
  /// acompaña al color.
  Color _colorEstadoOperacion(String? nombre) {
    final texto = (nombre ?? '').toLowerCase();
    if (texto.contains('anul') ||
        texto.contains('cancel') ||
        texto.contains('rechaz')) {
      return AppColors.error;
    }
    if (texto.contains('confirm') ||
        texto.contains('aprob') ||
        texto.contains('complet')) {
      return AppColors.success;
    }
    return AppColors.secondary;
  }

  // ==========================================================================
  // Acciones: una sola pareja
  // ==========================================================================

  Widget _acciones(bool puedeVerImportes) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _irARecepcion,
          icon: const Icon(Icons.inventory_outlined, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          label: const Text('Ir a recepción'),
        ),
        OutlinedButton.icon(
          onPressed: _verFactura,
          icon: const Icon(Icons.receipt_long, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.border),
            backgroundColor: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          label: const Text('Ver factura'),
        ),
      ],
    );
  }
}