/// Panel de pendientes de recepción (fase 9 de Compras).
///
/// Lee `fn_fdi_pendientes_panel(id_tienda, orden)` y pinta:
///  · cabecera con la tienda, el orden (que **vuelve a pedir al servidor**),
///    la exportación y el acceso a Facturas;
///  · una franja de resumen con las compras abiertas, el monto pendiente por
///    moneda (bloques separados, nunca un total combinado) y la más antigua;
///  · una tabla densa en ancho y tarjetas apiladas en estrecho. Cada fila abre
///    el detalle de faltantes.
///
/// «Sin importes»: si el rol no ve dinero (almacenero), las columnas de monto
/// desaparecen —no quedan huecos— y los bloques de la franja pasan a conteos.
/// El booleano llega ya resuelto en [PendientesScreen.puedeVerImportes] o se
/// deriva del rol en `PermissionsService.canViewImportesCompras()`.
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/pendientes.dart';
import '../../services/pendientes_export_service.dart';
import '../../services/pendientes_service.dart';
import '../../services/permissions_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/admin_drawer.dart';
import 'compras_widgets.dart';
import 'facturas_screen.dart';
import 'pendiente_detalle_screen.dart';
import 'pendientes_widgets.dart';

/// Panel de compras abiertas.
class PendientesScreen extends StatefulWidget {
  const PendientesScreen({
    super.key,
    this.idTienda,
    this.puedeVerImportes,
    this.nombreTienda,
    this.panelInicial,
  });

  /// Tienda a consultar. Si es `null` se usa la tienda de la sesión.
  final int? idTienda;

  /// Permiso de importes ya derivado del rol. Si es `null` se resuelve con
  /// `PermissionsService.canViewImportesCompras()`.
  final bool? puedeVerImportes;

  /// Nombre visible de la tienda (solo cabecera).
  final String? nombreTienda;

  /// Panel ya cargado: permite montar la pantalla sin Supabase (humo de
  /// widget). No se usa en la app.
  final PendientesPanel? panelInicial;

  @override
  State<PendientesScreen> createState() => _PendientesScreenState();
}

class _PendientesScreenState extends State<PendientesScreen> {
  final _service = PendientesService();
  final _exportService = PendientesExportService();
  final _prefs = UserPreferencesService();

  int? _idTienda;
  String? _nombreTienda;
  bool? _puedeVerImportes;

  PendientesOrden _orden = PendientesOrden.antiguedad;
  PendientesPanel? _panel;

  bool _cargando = false;
  bool _exportando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final inicial = widget.panelInicial;
    if (inicial != null) {
      // Montaje sin backend (humo de widget): no se toca Supabase ni
      // preferencias. Sin permiso explícito, la vista segura es «sin importes».
      _panel = inicial;
      _orden = inicial.orden;
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

  /// Resuelve tienda, nombre y permiso de importes una sola vez.
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
        // El nombre es decorativo: si falla, la cabecera usa «Tienda #id».
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
      // El orden se pide al servidor: la pantalla no reordena en cliente.
      final panel = await _service.panel(idTienda: idTienda, orden: _orden);
      if (!mounted) return;
      setState(() {
        _panel = panel;
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

  Future<void> _cambiarOrden(PendientesOrden orden) async {
    if (orden == _orden) return;
    setState(() => _orden = orden);
    await _cargar();
  }

  String _mensajeDe(Object e) {
    final texto = e
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('PostgrestException(message: ', '')
        .trim();
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  // ==========================================================================
  // Navegación
  // ==========================================================================

  Future<void> _abrirDetalle(PendienteCompra compra) async {
    final idTienda = _idTienda ?? _panel?.idTienda;
    if (idTienda == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PendienteDetalleScreen(
          idTienda: idTienda,
          idCompra: compra.idCompra,
          puedeVerImportes: _puedeVerImportes ?? false,
          nombreTienda: _nombreTienda,
        ),
      ),
    );
    // Una recepción registrada cambia el panel: al volver siempre se relee.
    if (mounted) await _cargar();
  }

  Future<void> _abrirFacturas() async {
    final idTienda = _idTienda ?? _panel?.idTienda;
    if (idTienda == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FacturasScreen(
          idTienda: idTienda,
          puedeVerImportes: _puedeVerImportes ?? false,
          nombreTienda: _nombreTienda,
        ),
      ),
    );
  }

  Future<void> _abrirExportacion() async {
    if (_panel == null || _exportando) return;
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
                'Exportar pendientes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on, color: AppColors.success),
              title: const Text('Excel'),
              subtitle: const Text(
                'Una fila por compra y una hoja con los totales por moneda',
              ),
              onTap: () => Navigator.pop(ctx, 'excel'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: AppColors.error),
              title: const Text('PDF'),
              subtitle: const Text(
                'Cabecera de tienda, fecha de generación y totales por moneda',
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
      final panel = _panel!;
      final tienda = _nombreTienda ?? 'Tienda ${panel.idTienda}';
      if (formato == 'excel') {
        await _exportService.exportarPanelExcel(
          context: context,
          panel: panel,
          nombreTienda: tienda,
        );
      } else {
        await _exportService.exportarPanelPdf(
          context: context,
          panel: panel,
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

  void _avisar(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Título corto en la barra: el completo va en la cabecera del cuerpo,
        // que sí tiene ancho para leerlo.
        title: const Text(
          'Pendientes',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Facturas',
            onPressed: _abrirFacturas,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      drawer: const AdminDrawer(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tamano = comprasTamanoDe(constraints.maxWidth);
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
                    _cabecera(tamano, constraints.maxWidth),
                    const SizedBox(height: 14),
                    ..._contenido(tamano),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================================================
  // Cabecera
  // ==========================================================================

  Widget _cabecera(ComprasTamano tamano, double ancho) {
    final panel = _panel;
    final compacto = tamano == ComprasTamano.compacto;
    // Por debajo de 900 px la cabecera va apilada: el título y las acciones
    // (orden + exportar + facturas) no caben en la misma línea sin cortarse.
    final apilada = ancho < 900;
    final tienda = _nombreTienda ?? 'Tienda ${_idTienda ?? '—'}';

    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compacto ? 'Pendientes' : 'Pendientes de recepción',
          style: TextStyle(
            fontSize: compacto ? 20 : 24,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _subtituloCabecera(panel, tienda),
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
        selectorOrdenPendientes(
          valor: _orden,
          onCambio: _cambiarOrden,
          habilitado: !_cargando,
        ),
        if (_puedeVerImportes ?? false)
          OutlinedButton.icon(
            onPressed: _panel == null || _exportando ? null : _abrirExportacion,
            icon: _exportando
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              backgroundColor: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            label: const Text('Exportar'),
          ),
        FilledButton.icon(
          onPressed: _abrirFacturas,
          icon: const Icon(Icons.receipt_long, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          label: const Text('Facturas'),
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

  String _subtituloCabecera(PendientesPanel? panel, String tienda) {
    final partes = <String>[tienda];
    if (panel != null) {
      partes.add(
        panel.comprasAbiertas == 1
            ? '1 compra abierta'
            : '${panel.comprasAbiertas} compras abiertas',
      );
      final generado = panel.generadoAt;
      if (generado != null) {
        partes.add('actualizado ${formatearFechaHora(generado)}');
      }
    }
    return partes.join(' · ');
  }

  // ==========================================================================
  // Contenido
  // ==========================================================================

  List<Widget> _contenido(ComprasTamano tamano) {
    final panel = _panel;

    if (_error != null) {
      return [
        const SizedBox(height: 4),
        errorPendientes(mensaje: _error!, onReintentar: _cargar),
      ];
    }
    if (panel == null) {
      return [const SizedBox(height: 12), cargandoPendientes()];
    }

    final puedeVerImportes = _puedeVerImportes ?? false;
    final compras = panel.compras;
    final compacto = tamano == ComprasTamano.compacto;

    if (compras.isEmpty) {
      return [
        franjaResumenPendientes(
          panel: panel,
          puedeVerImportes: puedeVerImportes,
        ),
        const SizedBox(height: 14),
        estadoVacioPendientes(),
      ];
    }

    return [
      franjaResumenPendientes(
        panel: panel,
        puedeVerImportes: puedeVerImportes,
      ),
      const SizedBox(height: 14),
      if (compacto)
        tarjetasPendientes(
          compras: compras,
          puedeVerImportes: puedeVerImportes,
          onAbrir: _abrirDetalle,
        )
      else
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: tablaPendientes(
              compras: compras,
              puedeVerImportes: puedeVerImportes,
              onAbrir: _abrirDetalle,
              compacta: tamano == ComprasTamano.medio,
            ),
          ),
        ),
      const SizedBox(height: 10),
      _pie(panel),
    ];
  }

  Widget _pie(PendientesPanel panel) {
    final total = panel.comprasAbiertas;
    final sobre = panel.sobreUmbral;
    final partes = <String>[
      total == 1 ? '1 compra abierta' : '$total compras abiertas',
      if (sobre > 0)
        sobre == 1
            ? '1 supera el umbral de $umbralAntiguedadDias días'
            : '$sobre superan el umbral de $umbralAntiguedadDias días',
      if (!(_puedeVerImportes ?? false))
        'vista sin importes: solo cantidades y avance',
    ];
    return Text(
      'Mostrando ${partes.join(' · ')}.',
      style: const TextStyle(
        fontSize: 11,
        height: 1.4,
        color: AppColors.textSecondary,
      ),
    );
  }
}