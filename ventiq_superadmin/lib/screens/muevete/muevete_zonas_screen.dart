import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_colors.dart';
import '../../services/muevete_tarifas_service.dart';
import '../../utils/muevete_geometria.dart';
import '../../widgets/app_drawer.dart';
import 'muevete_tarifas_config_screen.dart'
    show fmtCup, parseEntero, parseNumero;
import 'muevete_zona_editor_screen.dart';

/// H6 (segunda mitad): lista de zonas tarifarias del taxi y acceso al editor de
/// polígonos sobre mapa.
///
/// La pantalla es deliberadamente "maestra-detalle": a la izquierda la lista de
/// zonas (con su tarifa legible, prioridad y estado) y a la derecha un mapa de
/// resumen con todos los polígonos; al tocar una zona el mapa se encuadra en
/// ella y se resalta. El dibujo real ocurre en [MueveteZonaEditorScreen].
///
/// Una zona nueva **no se crea aquí**: se capturan sus datos de tarifa, se abre
/// el editor y sólo cuando el polígono es válido se hace el `INSERT`
/// (`crearZona`). Así nunca quedan zonas sin geometría válida, porque
/// `muevete.zonas_tarifa.geometria` es `NOT NULL`.
class MueveteZonasScreen extends StatefulWidget {
  const MueveteZonasScreen({super.key});

  @override
  State<MueveteZonasScreen> createState() => _MueveteZonasScreenState();
}

class _MueveteZonasScreenState extends State<MueveteZonasScreen> {
  final MapController _mapaCtrl = MapController();

  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _zonas = <Map<String, dynamic>>[];

  Map<String, dynamic>? _config;
  String? _errorConfig;

  bool _soloActivas = false;
  int? _seleccionada;
  bool _verMapa = false;
  bool _mapaListo = false;
  final Set<int> _ocupadas = <int>{};

  @override
  void initState() {
    super.initState();
    _cargarZonas();
    _cargarConfig();
  }

  @override
  void dispose() {
    _mapaCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Carga
  // ═══════════════════════════════════════════════════════════════════════

  /// Recarga la lista. `silencioso` evita el spinner de pantalla completa y el
  /// re-encuadre del mapa cuando la recarga viene de una acción puntual (switch,
  /// edición de tarifa): así no se pierde la posición del scroll ni del mapa.
  Future<void> _cargarZonas({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final zonas = await MueveteTarifasService.listarZonas();
      if (!mounted) return;
      setState(() {
        _zonas = zonas;
        _cargando = false;
        _error = null;
        final ids = zonas.map(_idDe).toSet();
        if (_seleccionada == null || !ids.contains(_seleccionada)) {
          _seleccionada = zonas.isEmpty ? null : _idDe(zonas.first);
        }
      });
      if (!silencioso) _programarEncuadre();
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las zonas: $e';
        _cargando = false;
      });
    }
  }

  Future<void> _cargarConfig() async {
    try {
      final config = await MueveteTarifasService.configuracion();
      if (!mounted) return;
      setState(() {
        _config = config;
        _errorConfig = null;
      });
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      setState(() => _errorConfig = e.mensaje);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorConfig = 'No se pudo leer la configuración: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers de datos
  // ═══════════════════════════════════════════════════════════════════════

  int _idDe(Map<String, dynamic> zona) => (zona['id'] as num).toInt();

  double? _numero(Object? valor) {
    if (valor is num) return valor.toDouble();
    if (valor is String) return double.tryParse(valor.replaceAll(',', '.'));
    return null;
  }

  static String _etiquetaModo(String? modo) {
    switch (modo) {
      case 'fijo_mas_km':
        return 'Fijo + km';
      case 'por_km':
        return 'Por km';
      default:
        return 'Fijo';
    }
  }

  static Color _colorModo(String? modo) {
    switch (modo) {
      case 'fijo_mas_km':
        return AppColors.secondary;
      case 'por_km':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  static IconData _iconoModo(String? modo) {
    switch (modo) {
      case 'fijo_mas_km':
        return Icons.route_rounded;
      case 'por_km':
        return Icons.straighten_rounded;
      default:
        return Icons.attach_money_rounded;
    }
  }

  /// `800 CUP + 250 CUP/km`, `1 500 CUP`, `250 CUP/km`.
  String _aritmetica(Map<String, dynamic> zona) {
    final monto = _numero(zona['monto_fijo']);
    final precioKm = _numero(zona['precio_km']);
    switch (zona['modo']?.toString()) {
      case 'fijo_mas_km':
        return '${fmtCup(monto)} + ${fmtCup(precioKm)}/km';
      case 'por_km':
        return '${fmtCup(precioKm)}/km';
      default:
        return fmtCup(monto);
    }
  }

  String _ubicacion(Map<String, dynamic> zona) {
    final municipio = (zona['municipio'] as String?)?.trim() ?? '';
    final provincia = (zona['provincia'] as String?)?.trim() ?? '';
    final partes = <String>[
      if (municipio.isNotEmpty) municipio,
      if (provincia.isNotEmpty) provincia,
    ];
    return partes.isEmpty ? 'Sin provincia ni municipio' : partes.join(' · ');
  }

  List<Map<String, dynamic>> get _zonasVisibles =>
      _soloActivas
          ? _zonas.where((z) => z['activo'] as bool? ?? false).toList()
          : _zonas;

  int get _totalActivas =>
      _zonas.where((z) => z['activo'] as bool? ?? false).length;

  Map<String, dynamic>? get _zonaSeleccionada {
    for (final zona in _zonas) {
      if (_idDe(zona) == _seleccionada) return zona;
    }
    return null;
  }

  Set<String> _codigosExistentes({int? excepto}) {
    final codigos = <String>{};
    for (final zona in _zonas) {
      if (excepto != null && _idDe(zona) == excepto) continue;
      final codigo = (zona['codigo'] as String?)?.trim().toUpperCase();
      if (codigo != null && codigo.isNotEmpty) codigos.add(codigo);
    }
    return codigos;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Encuadre del mapa de resumen
  // ═══════════════════════════════════════════════════════════════════════

  void _programarEncuadre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _encuadrar();
    });
  }

  void _encuadrar() {
    if (!_mapaListo) return;
    final puntos = <LatLng>[];

    final seleccionada = _zonaSeleccionada;
    if (seleccionada != null) {
      final poligono = PoligonoZona.desdeGeoJson(seleccionada['geometria']);
      if (poligono != null) puntos.addAll(poligono.exterior);
    }
    if (puntos.isEmpty) {
      for (final zona in _zonas) {
        final poligono = PoligonoZona.desdeGeoJson(zona['geometria']);
        if (poligono != null) puntos.addAll(poligono.exterior);
      }
    }
    if (puntos.length < 3) return;

    try {
      final tamano = _mapaCtrl.camera.nonRotatedSize;
      if (!tamano.x.isFinite || !tamano.y.isFinite) return;
      if (tamano.x < 2 || tamano.y < 2) return;
      _mapaCtrl.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(puntos),
          padding: const EdgeInsets.all(48),
        ),
      );
    } catch (e) {
      // El controlador puede estar desacoplado si el mapa no está montado
      // (vista de lista en pantallas estrechas); el encuadre es cosmético.
      debugPrint('[MueveteZonasScreen] no se pudo encuadrar el mapa: $e');
    }
  }

  void _seleccionar(int id) {
    setState(() => _seleccionada = id);
    _programarEncuadre();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Acciones
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _nuevaZona() async {
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoZona(codigosExistentes: _codigosExistentes()),
    );
    if (datos == null || !mounted) return;

    final geometria = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MueveteZonaEditorScreen(datosIniciales: datos),
      ),
    );
    if (!mounted || geometria == null) return;
    _avisar('Zona "${datos['nombre']}" creada con su polígono.', ok: true);
    await _cargarZonas();
  }

  Future<void> _editarTarifa(Map<String, dynamic> zona) async {
    final id = _idDe(zona);
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (_) => _DialogoZona(
            zona: zona,
            codigosExistentes: _codigosExistentes(excepto: id),
          ),
    );
    if (datos == null || !mounted) return;

    setState(() => _ocupadas.add(id));
    try {
      await MueveteTarifasService.actualizarZona(id, datos);
      if (!mounted) return;
      _avisar('Tarifa de "${zona['nombre']}" actualizada.', ok: true);
      await _cargarZonas(silencioso: true);
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      _avisar(e.mensaje, ok: false);
    } catch (e) {
      if (!mounted) return;
      _avisar('No se pudo guardar la tarifa: $e', ok: false);
    } finally {
      if (mounted) setState(() => _ocupadas.remove(id));
    }
  }

  Future<void> _editarPoligono(Map<String, dynamic> zona) async {
    final geometria = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => MueveteZonaEditorScreen(zona: zona)),
    );
    if (!mounted || geometria == null) return;
    _avisar('Polígono de "${zona['nombre']}" actualizado.', ok: true);
    await _cargarZonas(silencioso: true);
    _programarEncuadre();
  }

  Future<void> _cambiarActivo(Map<String, dynamic> zona, bool valor) async {
    final id = _idDe(zona);
    setState(() => _ocupadas.add(id));
    try {
      await MueveteTarifasService.toggleZona(id, valor);
      if (!mounted) return;
      _avisar(
        valor
            ? '"${zona['nombre']}" queda activa y vuelve a cotizar.'
            : '"${zona['nombre']}" queda inactiva y deja de cotizar.',
        ok: true,
      );
      await _cargarZonas(silencioso: true);
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      _avisar(e.mensaje, ok: false);
    } catch (e) {
      if (!mounted) return;
      _avisar('No se pudo cambiar el estado: $e', ok: false);
    } finally {
      if (mounted) setState(() => _ocupadas.remove(id));
    }
  }

  Future<void> _eliminar(Map<String, dynamic> zona) async {
    final confirmado = await _confirmar(
      titulo: 'Eliminar "${zona['nombre']}"',
      mensaje:
          'La zona no se borra físicamente: queda inactiva (baja lógica) para '
          'conservar el historial de viajes que la referencian. Deja de '
          'cotizar de inmediato.',
      etiqueta: 'Eliminar',
      destructivo: true,
    );
    if (confirmado != true || !mounted) return;

    final id = _idDe(zona);
    setState(() => _ocupadas.add(id));
    try {
      await MueveteTarifasService.eliminarZona(id);
      if (!mounted) return;
      _avisar('Zona "${zona['nombre']}" eliminada (baja lógica).', ok: true);
      await _cargarZonas(silencioso: true);
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      _avisar(e.mensaje, ok: false);
    } catch (e) {
      if (!mounted) return;
      _avisar('No se pudo eliminar la zona: $e', ok: false);
    } finally {
      if (mounted) setState(() => _ocupadas.remove(id));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════

  void _avisar(String mensaje, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: ok ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool?> _confirmar({
    required String titulo,
    required String mensaje,
    required String etiqueta,
    bool destructivo = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              titulo,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: Text(
              mensaje,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      destructivo ? AppColors.error : AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  etiqueta,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final anchoLista = ancho >= 1300 ? 480.0 : 420.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.polyline_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zonas y Polígonos',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${_zonas.length} zonas · $_totalActivas activas',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Recargar zonas',
            onPressed: _cargarZonas,
            icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          ),
          IconButton(
            tooltip: 'Nueva zona',
            onPressed: _nuevaZona,
            icon: const Icon(Icons.add_location_alt_rounded),
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _cabecera(),
          Expanded(
            child:
                _cargando
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _EstadoError(mensaje: _error!, onReintentar: _cargarZonas)
                    : _contenido(ancho, anchoLista),
          ),
        ],
      ),
    );
  }

  Widget _contenido(double ancho, double anchoLista) {
    if (_zonas.isEmpty) {
      return _EstadoVacio(
        icono: Icons.polyline_rounded,
        titulo: 'Todavía no hay zonas tarifarias',
        mensaje:
            'Crea la primera zona, dibuja su polígono sobre el mapa y empieza a '
            'cotizar por área en Santa Clara.',
        accion: FilledButton.icon(
          onPressed: _nuevaZona,
          icon: const Icon(Icons.add_location_alt_rounded, size: 18),
          label: const Text('Crear la primera zona'),
        ),
      );
    }

    if (ancho >= 900) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: anchoLista, child: _lista()),
          Container(width: 1, color: AppColors.divider),
          Expanded(child: _mapaResumen()),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('Lista'),
                icon: Icon(Icons.list_rounded, size: 16),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Mapa'),
                icon: Icon(Icons.map_rounded, size: 16),
              ),
            ],
            selected: {_verMapa},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            onSelectionChanged: (valor) {
              setState(() => _verMapa = valor.first);
              if (valor.first) _programarEncuadre();
            },
          ),
        ),
        Expanded(child: _verMapa ? _mapaResumen() : _lista()),
      ],
    );
  }

  // ─── Cabecera con el estado del cobro fijo ────────────────────────────

  Widget _cabecera() {
    final activo = _config?['taxi_precio_fijo_activo'] as bool?;
    final color =
        activo == null
            ? AppColors.textSecondary
            : (activo ? AppColors.success : AppColors.warning);
    final titulo =
        activo == null
            ? 'Cobro con precio fijo: sin datos'
            : (activo
                ? 'Cobro con precio fijo: ACTIVO'
                : 'Cobro con precio fijo: APAGADO');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    activo == true
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      Text(
                        _errorConfig ??
                            'El precio fijo del taxi se cambia en la '
                                'configuración tarifaria; aquí sólo se muestra.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed:
                              () => Navigator.of(
                                context,
                              ).pushNamed('/muevete/tarifas'),
                          icon: const Icon(Icons.tune_rounded, size: 15),
                          label: const Text(
                            'Abrir configuración de tarifas',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_zonas.length} zonas · $_totalActivas activas',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              FilledButton.icon(
                onPressed: _nuevaZona,
                icon: const Icon(Icons.add_location_alt_rounded, size: 17),
                label: const Text(
                  'Nueva zona',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Lista ────────────────────────────────────────────────────────────

  Widget _lista() {
    final visibles = _zonasVisibles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                visibles.length == _zonas.length
                    ? 'Todas las zonas'
                    : 'Sólo activas (${visibles.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              FilterChip(
                label: const Text(
                  'Sólo activas',
                  style: TextStyle(fontSize: 11),
                ),
                selected: _soloActivas,
                onSelected: (valor) => setState(() => _soloActivas = valor),
                visualDensity: VisualDensity.compact,
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                checkmarkColor: AppColors.primary,
              ),
            ],
          ),
        ),
        Expanded(
          child:
              visibles.isEmpty
                  ? _EstadoVacio(
                    icono: Icons.filter_alt_off_rounded,
                    titulo: 'Ninguna zona activa',
                    mensaje:
                        'Todas las zonas están desactivadas. Quita el filtro '
                        '"Sólo activas" para verlas y volver a activarlas.',
                    accion: TextButton(
                      onPressed: () => setState(() => _soloActivas = false),
                      child: const Text('Quitar filtro'),
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visibles.length,
                    itemBuilder: (_, indice) => _tarjetaZona(visibles[indice]),
                  ),
        ),
      ],
    );
  }

  Widget _tarjetaZona(Map<String, dynamic> zona) {
    final id = _idDe(zona);
    final activa = zona['activo'] as bool? ?? false;
    final seleccionada = id == _seleccionada;
    final ocupada = _ocupadas.contains(id);
    final modo = zona['modo']?.toString();
    final colorModo = _colorModo(modo);
    final poligono = PoligonoZona.desdeGeoJson(zona['geometria']);
    final vertices = poligono?.totalVertices ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              seleccionada
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.divider,
          width: seleccionada ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _seleccionar(id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colorModo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(_iconoModo(modo), size: 18, color: colorModo),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                (zona['nombre'] ?? 'Zona sin nombre')
                                    .toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if ((zona['codigo'] as String?)
                                    ?.trim()
                                    .isNotEmpty ??
                                false) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  (zona['codigo'] as String).trim(),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          _ubicacion(zona),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (ocupada)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    SizedBox(
                      height: 32,
                      child: Switch(
                        value: activa,
                        activeThumbColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (valor) => _cambiarActivo(zona, valor),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _chip(
                    texto: _etiquetaModo(modo),
                    color: colorModo,
                    icono: _iconoModo(modo),
                  ),
                  _chip(
                    texto: 'Prioridad ${zona['prioridad'] ?? 0}',
                    color: AppColors.textSecondary,
                    icono: Icons.sort_rounded,
                  ),
                  _chip(
                    texto: activa ? 'Activa' : 'Inactiva',
                    color: activa ? AppColors.success : AppColors.textSecondary,
                    icono:
                        activa
                            ? Icons.check_circle_rounded
                            : Icons.pause_circle_rounded,
                  ),
                  _chip(
                    texto: vertices > 0 ? '$vertices vértices' : 'Sin polígono',
                    color: vertices > 0 ? AppColors.info : AppColors.warning,
                    icono:
                        vertices > 0
                            ? Icons.polyline_rounded
                            : Icons.warning_amber_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _aritmetica(zona),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _editarTarifa(zona),
                    icon: const Icon(Icons.edit_rounded, size: 15),
                    label: const Text(
                      'Editar tarifa',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondary,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editarPoligono(zona),
                    icon: const Icon(Icons.polyline_rounded, size: 15),
                    label: const Text(
                      'Editar polígono',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Más acciones',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 19,
                      color: AppColors.textSecondary,
                    ),
                    onSelected: (valor) {
                      switch (valor) {
                        case 'activar':
                          _cambiarActivo(zona, true);
                          break;
                        case 'desactivar':
                          _cambiarActivo(zona, false);
                          break;
                        case 'eliminar':
                          _eliminar(zona);
                          break;
                      }
                    },
                    itemBuilder:
                        (_) => [
                          PopupMenuItem<String>(
                            value: activa ? 'desactivar' : 'activar',
                            child: Row(
                              children: [
                                Icon(
                                  activa
                                      ? Icons.pause_circle_outline_rounded
                                      : Icons.play_circle_outline_rounded,
                                  size: 17,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  activa ? 'Desactivar' : 'Activar',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'eliminar',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 17,
                                  color: AppColors.error,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Eliminar',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Mapa de resumen ──────────────────────────────────────────────────

  Widget _mapaResumen() {
    final poligonos = <Polygon>[];
    final marcadores = <Marker>[];

    for (final zona in _zonasVisibles) {
      final poligono = PoligonoZona.desdeGeoJson(zona['geometria']);
      if (poligono == null || poligono.exterior.length < 3) continue;
      final id = _idDe(zona);
      final activa = zona['activo'] as bool? ?? false;
      final seleccionada = id == _seleccionada;
      final color =
          seleccionada
              ? AppColors.primary
              : (activa ? AppColors.secondary : AppColors.textHint);

      poligonos.add(
        Polygon(
          points: poligono.exterior,
          holePointsList: poligono.huecos.isEmpty ? null : poligono.huecos,
          color: color.withValues(alpha: seleccionada ? 0.24 : 0.07),
          borderColor: color.withValues(alpha: seleccionada ? 0.95 : 0.45),
          borderStrokeWidth: seleccionada ? 2.5 : 1.2,
        ),
      );

      final etiqueta =
          ((zona['codigo'] as String?)?.trim().isNotEmpty ?? false)
              ? (zona['codigo'] as String).trim()
              : (zona['nombre'] ?? '').toString();

      marcadores.add(
        Marker(
          point: poligono.centroide,
          width: seleccionada ? 130 : 100,
          height: 26,
          child: GestureDetector(
            onTap: () => _seleccionar(id),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      seleccionada
                          ? AppColors.primary
                          : Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color:
                        seleccionada
                            ? AppColors.primary
                            : color.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: seleccionada ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapaCtrl,
            options: MapOptions(
              initialCenter: const LatLng(
                MueveteZonaGeometria.santaClaraLat,
                MueveteZonaGeometria.santaClaraLon,
              ),
              initialZoom: 12,
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: const Color(0xFFDDE6EE),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                _mapaListo = true;
                _encuadrar();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: MueveteZonaGeometria.urlTilesOsm,
                userAgentPackageName: 'com.inventtia.superadmin',
                maxZoom: 19,
              ),
              PolygonLayer(polygons: poligonos, simplificationTolerance: 0),
              if (marcadores.isNotEmpty) MarkerLayer(markers: marcadores),
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [TextSourceAttribution('© OpenStreetMap')],
              ),
            ],
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Material(
            color: Colors.white.withValues(alpha: 0.95),
            elevation: 2,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.layers_rounded,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${poligonos.length} polígonos dibujados',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Piezas pequeñas ──────────────────────────────────────────────────

  Widget _chip({
    required String texto,
    required Color color,
    required IconData icono,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Diálogo de datos de tarifa
// ═══════════════════════════════════════════════════════════════════════════

/// Formulario de alta/edición de los datos de tarifa (sin geometría).
///
/// Devuelve un `Map` listo para `crearZona` (zona nueva) o `actualizarZona`
/// (zona existente). La geometría la aporta siempre el editor de polígonos.
class _DialogoZona extends StatefulWidget {
  const _DialogoZona({this.zona, required this.codigosExistentes});

  final Map<String, dynamic>? zona;
  final Set<String> codigosExistentes;

  @override
  State<_DialogoZona> createState() => _DialogoZonaState();
}

class _DialogoZonaState extends State<_DialogoZona> {
  late final TextEditingController _nombre;
  late final TextEditingController _codigo;
  late final TextEditingController _provincia;
  late final TextEditingController _municipio;
  late final TextEditingController _monto;
  late final TextEditingController _precio;
  late final TextEditingController _prioridad;

  late String _modo;
  late bool _activo;
  late DateTime _vigenteDesde;
  String? _error;

  bool get _esNueva => widget.zona == null;

  @override
  void initState() {
    super.initState();
    final zona = widget.zona;
    _nombre = TextEditingController(text: (zona?['nombre'] ?? '').toString());
    _codigo = TextEditingController(text: (zona?['codigo'] ?? '').toString());
    _provincia = TextEditingController(
      text: (zona?['provincia'] ?? 'Villa Clara').toString(),
    );
    _municipio = TextEditingController(
      text: (zona?['municipio'] ?? 'Santa Clara').toString(),
    );
    _monto = TextEditingController(text: _texto(zona?['monto_fijo']));
    _precio = TextEditingController(text: _texto(zona?['precio_km']));
    _prioridad = TextEditingController(text: _texto(zona?['prioridad'] ?? 0));
    _modo = (zona?['modo'] ?? 'fijo').toString();
    _activo = zona?['activo'] as bool? ?? true;
    _vigenteDesde =
        DateTime.tryParse(
          (zona?['vigente_desde'] ?? '').toString(),
        )?.toLocal() ??
        DateTime.now();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _codigo.dispose();
    _provincia.dispose();
    _municipio.dispose();
    _monto.dispose();
    _precio.dispose();
    _prioridad.dispose();
    super.dispose();
  }

  String _texto(Object? valor) {
    if (valor == null) return '';
    if (valor is num) {
      final doble = valor.toDouble();
      if (doble == doble.roundToDouble()) return doble.toStringAsFixed(0);
      return doble.toString();
    }
    return valor.toString();
  }

  // ─── Código ───────────────────────────────────────────────────────────

  /// `Z6 · Aeropuerto` → `Z6-AEROPUERTO`; si ya existe, sufija `-2`, `-3`...
  String _generarCodigo(String nombre) {
    const reemplazos = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      'à': 'a',
      'è': 'e',
      'ì': 'i',
      'ò': 'o',
      'ù': 'u',
      'ç': 'c',
    };
    final buffer = StringBuffer();
    for (final rune in nombre.toLowerCase().runes) {
      final caracter = String.fromCharCode(rune);
      buffer.write(reemplazos[caracter] ?? caracter);
    }
    var limpio = buffer.toString().replaceAll(RegExp('[^a-z0-9]+'), '-');
    limpio = limpio
        .replaceAll(RegExp('^-+'), '')
        .replaceAll(RegExp('-+\$'), '');
    if (limpio.isEmpty) limpio = 'zona';
    if (limpio.length > 24) {
      limpio = limpio.substring(0, 24).replaceAll(RegExp('-+\$'), '');
    }
    if (limpio.isEmpty) limpio = 'zona';

    final base = limpio.toUpperCase();
    var codigo = base;
    var intento = 2;
    while (widget.codigosExistentes.contains(codigo)) {
      codigo = '$base-$intento';
      intento++;
    }
    return codigo;
  }

  String? _codigoFinal(String nombre) {
    final manual = _codigo.text.trim();
    if (manual.isNotEmpty) return manual.toUpperCase();
    if (!_esNueva) return null;
    return _generarCodigo(nombre);
  }

  // ─── Fecha de vigencia ────────────────────────────────────────────────

  String _fechaTexto(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _vigenteDesde.isAfter(ahora) ? ahora : _vigenteDesde,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Vigente desde',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (elegida == null || !mounted) return;
    setState(() {
      _vigenteDesde = DateTime(elegida.year, elegida.month, elegida.day);
    });
  }

  // ─── Validación y datos ───────────────────────────────────────────────

  void _aceptar() {
    final nombre = _nombre.text.trim();
    final monto = parseNumero(_monto.text);
    final precioKm = parseNumero(_precio.text);
    final prioridad = parseEntero(_prioridad.text);

    String? error;
    if (nombre.isEmpty) {
      error = 'El nombre de la zona es obligatorio.';
    } else if (_monto.text.trim().isNotEmpty && (monto == null || monto < 0)) {
      error = 'El monto fijo debe ser un número mayor o igual a 0.';
    } else if (_precio.text.trim().isNotEmpty &&
        (precioKm == null || precioKm < 0)) {
      error = 'El precio por km debe ser un número mayor o igual a 0.';
    } else if (prioridad == null || prioridad < 0) {
      error = 'La prioridad debe ser un entero mayor o igual a 0.';
    } else {
      switch (_modo) {
        case 'fijo':
          if (monto == null || monto <= 0) {
            error = 'El modo "Fijo" exige un monto fijo mayor que 0.';
          }
          break;
        case 'por_km':
          if (precioKm == null || precioKm <= 0) {
            error = 'El modo "Por km" exige un precio por km mayor que 0.';
          }
          break;
        case 'fijo_mas_km':
          if (monto == null || monto <= 0) {
            error = 'El modo "Fijo + km" exige un monto fijo mayor que 0.';
          } else if (precioKm == null || precioKm <= 0) {
            error = 'El modo "Fijo + km" exige un precio por km mayor que 0.';
          }
          break;
      }
    }

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final codigo = _codigoFinal(nombre);
    if (codigo != null && widget.codigosExistentes.contains(codigo)) {
      setState(() => _error = 'Ya existe otra zona con el código $codigo.');
      return;
    }

    final provincia = _provincia.text.trim();
    final municipio = _municipio.text.trim();

    Navigator.of(context).pop(<String, dynamic>{
      'nombre': nombre,
      'codigo': codigo,
      'provincia': provincia.isEmpty ? null : provincia,
      'municipio': municipio.isEmpty ? null : municipio,
      'modo': _modo,
      'monto_fijo': monto,
      'precio_km': precioKm,
      'prioridad': prioridad,
      'activo': _activo,
      'vigente_desde': _vigenteDesde.toUtc().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final montoHabilitado = _modo != 'por_km';
    final precioHabilitado = _modo != 'fijo';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.local_taxi_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _esNueva ? 'Nueva zona' : 'Editar tarifa',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _esNueva
                      ? 'Después de estos datos se abre el mapa para dibujar '
                          'el polígono.'
                      : 'Cambia montos y prioridad. El polígono se edita aparte.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _campo(_nombre, 'Nombre de la zona', hint: 'Z10 · Aeropuerto'),
              const SizedBox(height: 10),
              _campo(
                _codigo,
                'Código',
                hint: 'Opcional',
                helper:
                    _esNueva
                        ? 'Si lo dejas vacío se genera del nombre.'
                        : 'Vacío = sin código.',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _campo(_provincia, 'Provincia', hint: 'Villa Clara'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _campo(_municipio, 'Municipio', hint: 'Santa Clara'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Modo de tarifa',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'fijo',
                      label: Text('Fijo', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<String>(
                      value: 'fijo_mas_km',
                      label: Text('Fijo + km', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<String>(
                      value: 'por_km',
                      label: Text('Por km', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {_modo},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged:
                      (seleccion) => setState(() {
                        _modo = seleccion.first;
                        _error = null;
                      }),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _campo(
                      _monto,
                      'Monto fijo',
                      sufijo: 'CUP',
                      habilitado: montoHabilitado,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _campo(
                      _precio,
                      'Precio por km',
                      sufijo: 'CUP/km',
                      habilitado: precioHabilitado,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _campo(_prioridad, 'Prioridad', hint: '0')),
                  const SizedBox(width: 10),
                  Expanded(child: _selectorFecha()),
                ],
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                value: _activo,
                activeThumbColor: AppColors.primary,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Zona activa',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _activo
                      ? 'Cotiza en cuanto su polígono sea válido.'
                      : 'Se guarda apagada; no cotiza.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                onChanged: (valor) => setState(() => _activo = valor),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _aceptar,
          icon: Icon(
            _esNueva ? Icons.map_rounded : Icons.save_rounded,
            size: 17,
          ),
          label: Text(
            _esNueva ? 'Continuar al mapa' : 'Guardar',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      ],
    );
  }

  Widget _campo(
    TextEditingController controller,
    String label, {
    String? hint,
    String? sufijo,
    String? helper,
    bool habilitado = true,
  }) {
    return TextField(
      controller: controller,
      enabled: habilitado,
      keyboardType:
          label.startsWith('Prioridad')
              ? TextInputType.number
              : const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
      decoration: _decoracion(label).copyWith(
        hintText: hint,
        suffixText: sufijo,
        helperText: helper,
        helperMaxLines: 2,
        hintStyle: TextStyle(fontSize: 11, color: AppColors.textHint),
        suffixStyle: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
        helperStyle: TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _selectorFecha() {
    return InkWell(
      onTap: _elegirFecha,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _decoracion('Vigente desde'),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _fechaTexto(_vigenteDesde),
                style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      floatingLabelStyle: const TextStyle(
        fontSize: 11.5,
        color: AppColors.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Estados de carga / error / vacío
// ═══════════════════════════════════════════════════════════════════════════

class _EstadoError extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;

  const _EstadoError({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 38,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No se pudieron cargar las zonas',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String mensaje;
  final Widget? accion;

  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 38, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (accion != null) ...[const SizedBox(height: 16), accion!],
          ],
        ),
      ),
    );
  }
}
