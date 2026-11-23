/// Reportes del Fondo de Inversión → Compras (fase 8): conciliación, caja,
/// compras por estado, costo, cambiario, movimientos, inversores, aging y
/// descuadres.
///
/// Tres subvistas con una tira de pestañas propia y un filtro de fechas
/// global. La sección 1 se baja en vivo con `fn_fdi_conciliacion`; la nota de
/// «última revisión automática» es opcional y nunca rompe la pantalla.
///
/// Navegación: `/reportes`, registrada en `main.dart` y en el menú lateral
/// junto a Compras, con los mismos permisos (dueño y gerente).
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/reportes_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/admin_drawer.dart';
import 'reportes_calculos.dart';
import 'reportes_seccion_compras.dart';
import 'reportes_seccion_conciliacion.dart';
import 'reportes_seccion_movimientos.dart';
import 'reportes_widgets.dart';

/// Ventana de fechas elegida en la cabecera.
enum _ModoFecha { ultimos30, esteMes, personalizado }

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  static const String _kConciliacion = 'conciliacion';
  static const String _kUltima = 'ultima';
  static const String _kCaja = 'caja';
  static const String _kCompras = 'compras';
  static const String _kCosto = 'costo';
  static const String _kCambiario = 'cambiario';
  static const String _kMovimientos = 'movimientos';
  static const String _kInversores = 'inversores';
  static const String _kAging = 'aging';

  final _service = ReportesService();
  final _prefs = UserPreferencesService();

  int? _idTienda;
  String? _tiendaNombre;
  String? _errorTienda;

  int _seccion = 0;
  _ModoFecha _modo = _ModoFecha.ultimos30;
  DateTimeRange? _rango;

  /// Bloques ya cargados (o con error), por clave. La pantalla pinta lo que
  /// hay: un fallo en un bloque no oculta los demás.
  final Map<String, BloqueReporte> _bloques = {};

  /// Subvistas que aún no se cargaron con la ventana actual.
  final Set<int> _sucias = {0, 1, 2};

  bool _cargando = false;
  bool _conciliando = false;
  int? _pendiente;

  @override
  void initState() {
    super.initState();
    _cargar(0);
  }

  // ==========================================================================
  // Ventana de fechas
  // ==========================================================================

  DateTime? get _desde {
    switch (_modo) {
      case _ModoFecha.ultimos30:
        return null;
      case _ModoFecha.esteMes:
        final ahora = DateTime.now();
        return DateTime(ahora.year, ahora.month, 1);
      case _ModoFecha.personalizado:
        return _rango?.start;
    }
  }

  DateTime? get _hasta {
    switch (_modo) {
      case _ModoFecha.ultimos30:
        return null;
      case _ModoFecha.esteMes:
        final ahora = DateTime.now();
        return DateTime(ahora.year, ahora.month + 1, 0);
      case _ModoFecha.personalizado:
        return _rango?.end;
    }
  }

  String get _etiquetaPeriodo {
    switch (_modo) {
      case _ModoFecha.ultimos30:
        return 'Últimos 30 días';
      case _ModoFecha.esteMes:
        return 'Este mes';
      case _ModoFecha.personalizado:
        final rango = _rango;
        if (rango == null) return 'Rango personalizado';
        return '${fechaNumerica(rango.start)} – ${fechaNumerica(rango.end)}';
    }
  }

  Future<void> _cambiarModo(_ModoFecha modo) async {
    if (modo == _ModoFecha.personalizado) {
      final ahora = DateTime.now();
      final elegido = await showDateRangePicker(
        context: context,
        firstDate: DateTime(ahora.year - 4),
        lastDate: DateTime(ahora.year + 2),
        initialDateRange: _rango,
        helpText: 'Periodo del reporte',
        saveText: 'Aplicar',
      );
      if (elegido == null || !mounted) return;
      setState(() {
        _modo = modo;
        _rango = elegido;
      });
    } else {
      setState(() => _modo = modo);
    }
    _sucias.addAll(const {0, 1, 2});
    await _cargar(_seccion);
  }

  // ==========================================================================
  // Carga
  // ==========================================================================

  Future<void> _cargar(int seccion) async {
    if (_cargando) {
      _pendiente = seccion;
      return;
    }

    setState(() {
      _cargando = true;
      _errorTienda = null;
    });

    try {
      _idTienda ??= await _prefs.getIdTienda();
      final idTienda = _idTienda;
      if (idTienda == null) {
        if (!mounted) return;
        setState(() {
          _errorTienda =
              'No se pudo determinar la tienda del usuario. Vuelve a iniciar '
              'sesión o selecciona una tienda.';
        });
        return;
      }
      if (_tiendaNombre == null) {
        try {
          final info = await _prefs.getCurrentStoreInfo();
          _tiendaNombre = textoONulo(info?['denominacion']);
        } catch (_) {
          _tiendaNombre = null;
        }
      }

      final desde = _desde;
      final hasta = _hasta;

      switch (seccion) {
        case 0:
          await Future.wait([
            _cargarBloque(
              _kConciliacion,
              () => _service.conciliacion(idTienda: idTienda),
            ),
            _cargarBloque(
              _kCaja,
              // La firma desplegada es `fn_fdi_reporte_caja(bigint)`: la ventana
              // de 30 días la fija el servidor y la tarjeta muestra la que usó.
              () => _service.caja(idTienda: idTienda),
            ),
          ]);
          // Opcional: si la RPC no existe o no hay ejecuciones, no se pinta
          // nada y la sección sigue funcionando con la conciliación en vivo.
          await _cargarBloque(
            _kUltima,
            () async =>
                (await _service.conciliacionUltima(idTienda)) ??
                const <String, dynamic>{},
          );
          break;
        case 1:
          await Future.wait([
            _cargarBloque(
              _kCompras,
              () => _service.comprasPorEstado(
                idTienda: idTienda,
                desde: desde,
                hasta: hasta,
              ),
            ),
            _cargarBloque(
              _kCosto,
              () => _service.costo(
                idTienda: idTienda,
                desde: desde,
                hasta: hasta,
              ),
            ),
            _cargarBloque(
              _kCambiario,
              () => _service.cambiario(
                idTienda: idTienda,
                desde: desde,
                hasta: hasta,
              ),
            ),
          ]);
          break;
        case 2:
          await Future.wait([
            _cargarBloque(
              _kMovimientos,
              () => _service.movimientos(
                idTienda: idTienda,
                desde: desde,
                hasta: hasta,
              ),
            ),
            _cargarBloque(
              _kInversores,
              () => _service.inversores(idTienda: idTienda),
            ),
            _cargarBloque(_kAging, () => _service.aging(idTienda: idTienda)),
          ]);
          break;
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorTienda = _mensaje(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
          _sucias.remove(seccion);
        });
      }
      final pendiente = _pendiente;
      _pendiente = null;
      if (pendiente != null && pendiente != seccion && mounted) {
        await _cargar(pendiente);
      }
    }
  }

  Future<void> _cargarBloque(
    String clave,
    Future<Map<String, dynamic>> Function() llamada,
  ) async {
    try {
      final datos = await llamada();
      if (!mounted) return;
      setState(() => _bloques[clave] = BloqueReporte(datos: datos));
    } catch (error) {
      if (!mounted) return;
      setState(() => _bloques[clave] = BloqueReporte(error: _mensaje(error)));
    }
  }

  /// `Concilia ahora`: vuelve a ejecutar la conciliación en vivo.
  Future<void> _conciliar() async {
    final idTienda = _idTienda;
    if (idTienda == null || _conciliando) return;
    setState(() => _conciliando = true);
    try {
      await _cargarBloque(
        _kConciliacion,
        () => _service.conciliacion(idTienda: idTienda),
      );
      await _cargarBloque(
        _kUltima,
        () async =>
            (await _service.conciliacionUltima(idTienda)) ??
            const <String, dynamic>{},
      );
    } finally {
      if (mounted) setState(() => _conciliando = false);
    }
  }

  String _mensaje(Object error) {
    final texto = error.toString().replaceFirst('Exception: ', '').trim();
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  BloqueReporte _bloque(String clave) =>
      _bloques[clave] ?? const BloqueReporte.vacio();

  void _seleccionar(int indice) {
    if (indice == _seccion) return;
    setState(() => _seccion = indice);
    if (_sucias.contains(indice)) _cargar(indice);
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
          'Reportes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : () => _cargar(_seccion),
          ),
        ],
      ),
      drawer: const AdminDrawer(),
      body: _errorTienda != null && _idTienda == null
          ? _vistaSinTienda()
          : Column(
              children: [
                _cabecera(),
                _pestanas(),
                if (_cargando) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _cargar(_seccion),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1600),
                          child: _contenido(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _vistaSinTienda() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_outlined, size: 56),
            const SizedBox(height: 12),
            const Text(
              'Sin tienda seleccionada',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorTienda ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _cargar(_seccion),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecera() {
    final tienda = _tiendaNombre ?? 'Tienda #${_idTienda ?? '—'}';
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final texto = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _tituloSeccion,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Fondo de inversión · $tienda · $_etiquetaPeriodo',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [texto, const SizedBox(height: 10), _selectorPeriodo()],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: texto),
              const SizedBox(width: 12),
              _selectorPeriodo(),
            ],
          );
        },
      ),
    );
  }

  String get _tituloSeccion {
    switch (_seccion) {
      case 1:
        return 'Compras, costo y cambiario';
      case 2:
        return 'Movimientos, inversores y pendientes';
      default:
        return 'Conciliación y caja';
    }
  }

  Widget _selectorPeriodo() {
    return PopupMenuButton<_ModoFecha>(
      tooltip: 'Periodo del reporte',
      initialValue: _modo,
      onSelected: (modo) => _cambiarModo(modo),
      itemBuilder: (context) => [
        for (final opcion in _ModoFecha.values)
          PopupMenuItem<_ModoFecha>(
            value: opcion,
            child: Row(
              children: [
                Icon(
                  opcion == _modo
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: opcion == _modo
                      ? AppColors.primary
                      : AppColors.textLight,
                ),
                const SizedBox(width: 8),
                Text(_etiquetaDe(opcion), style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              _etiquetaPeriodo,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  String _etiquetaDe(_ModoFecha modo) {
    switch (modo) {
      case _ModoFecha.ultimos30:
        return 'Últimos 30 días';
      case _ModoFecha.esteMes:
        return 'Este mes';
      case _ModoFecha.personalizado:
        return 'Rango personalizado…';
    }
  }

  Widget _pestanas() {
    const titulos = [
      'Conciliación y caja',
      'Compras, costo y cambiario',
      'Movimientos y pendientes',
    ];
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < titulos.length; i++)
              InkWell(
                onTap: () => _seleccionar(i),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: i == _seccion
                            ? AppColors.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    titulos[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == _seccion
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: i == _seccion
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    if (_seccion == 1) {
      return SeccionComprasCosto(
        compras: _bloque(_kCompras),
        costo: _bloque(_kCosto),
        cambiario: _bloque(_kCambiario),
        onReintentar: () => _cargar(1),
      );
    }
    if (_seccion == 2) {
      return SeccionMovimientos(
        movimientos: _bloque(_kMovimientos),
        inversores: _bloque(_kInversores),
        aging: _bloque(_kAging),
        onReintentar: () => _cargar(2),
      );
    }
    return SeccionConciliacion(
      conciliacion: _bloque(_kConciliacion),
      ultima: _bloque(_kUltima),
      caja: _bloque(_kCaja),
      conciliando: _conciliando,
      onConciliar: _conciliar,
      onReintentar: () => _cargar(0),
    );
  }
}
