import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../config/app_colors.dart';
import '../../services/muevete_tarifas_service.dart';
import '../../utils/muevete_geometria.dart';
import 'muevete_tarifas_config_screen.dart' show fmtCup;

/// Editor de polígonos de las zonas tarifarias de Muévete (H6, segunda mitad).
///
/// Recibe una zona existente ([zona]) **o** los datos de una zona nueva
/// ([datosIniciales], capturados en el formulario de la lista) y dibuja el
/// `geometria` (GeoJSON Polygon) con el que se guarda.
///
/// Responsabilidades:
///
/// * dibujar el anillo exterior y los huecos tocando el mapa;
/// * permitir arrastrar cada vértice para corregir;
/// * validar antes de guardar (≥ 3 vértices, sin duplicados consecutivos y sin
///   auto-intersecciones) y no llamar al servicio si el polígono es inválido;
/// * persistir con [MueveteTarifasService.actualizarZona] (zona existente) o
///   [MueveteTarifasService.crearZona] (zona nueva);
/// * devolver por `Navigator.pop` la `geometria` guardada (Map GeoJSON) cuando
///   el guardado fue correcto, o `null` si se canceló.
class MueveteZonaEditorScreen extends StatefulWidget {
  const MueveteZonaEditorScreen({super.key, this.zona, this.datosIniciales});

  /// Fila de `muevete.zonas_tarifa` cuando se edita una zona existente.
  final Map<String, dynamic>? zona;

  /// Datos de tarifa de una zona nueva (aún sin `id` ni `geometria`).
  final Map<String, dynamic>? datosIniciales;

  @override
  State<MueveteZonaEditorScreen> createState() =>
      _MueveteZonaEditorScreenState();
}

class _MueveteZonaEditorScreenState extends State<MueveteZonaEditorScreen> {
  final MapController _controlador = MapController();

  // ── Anillos en edición (siempre abiertos: el cierre es un flag) ───────
  List<LatLng> _exterior = <LatLng>[];
  bool _exteriorCerrado = false;
  final List<List<LatLng>> _huecos = <List<LatLng>>[];
  final List<bool> _huecosCerrados = <bool>[];

  /// `null` = se está dibujando el anillo exterior.
  int? _huecoActivo;

  // ── Estado de pantalla ────────────────────────────────────────────────
  bool _cargandoContexto = true;
  String? _errorContexto;
  List<Map<String, dynamic>> _otrasZonas = <Map<String, dynamic>>[];
  bool _previsualizar = false;
  bool _guardando = false;
  bool _mapaListo = false;
  bool _cambios = false;

  bool get _esNueva => widget.zona == null;

  int? get _idZona {
    final id = widget.zona?['id'];
    return id is num ? id.toInt() : null;
  }

  Map<String, dynamic> get _datos =>
      widget.zona ?? widget.datosIniciales ?? const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _cargarGeometriaInicial();
    _cargarZonasDeContexto();
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Carga inicial
  // ═══════════════════════════════════════════════════════════════════════

  void _cargarGeometriaInicial() {
    final poligono = PoligonoZona.desdeGeoJson(widget.zona?['geometria']);
    if (poligono == null || poligono.exterior.length < 3) return;
    _exterior = List<LatLng>.of(poligono.exterior);
    _exteriorCerrado = true;
    for (final hueco in poligono.huecos) {
      if (hueco.length < 3) continue;
      _huecos.add(List<LatLng>.of(hueco));
      _huecosCerrados.add(true);
    }
  }

  Future<void> _cargarZonasDeContexto() async {
    try {
      final zonas = await MueveteTarifasService.listarZonas(soloActivas: true);
      if (!mounted) return;
      final id = _idZona;
      setState(() {
        _otrasZonas =
            zonas
                .where(
                  (z) =>
                      id == null ||
                      z['id'] is! num ||
                      (z['id'] as num).toInt() != id,
                )
                .toList();
        _cargandoContexto = false;
      });
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorContexto = e.mensaje;
        _cargandoContexto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorContexto = 'No se pudieron cargar las zonas de referencia: $e';
        _cargandoContexto = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Estado derivado
  // ═══════════════════════════════════════════════════════════════════════

  /// Polígono actual ignorando los huecos todavía vacíos.
  PoligonoZona get _poligono => PoligonoZona(
    exterior: _exterior,
    huecos: [
      for (final hueco in _huecos)
        if (hueco.isNotEmpty) hueco,
    ],
  );

  String? get _errorValidacion {
    if (_exterior.isEmpty) return null;
    return _poligono.validar();
  }

  String? get _motivoBloqueo {
    if (_exterior.isEmpty) {
      return 'Dibuja el polígono: toca el mapa para ir añadiendo vértices.';
    }
    return _errorValidacion;
  }

  String get _etiquetaModo {
    switch (_datos['modo']?.toString()) {
      case 'fijo_mas_km':
        return 'Fijo + km';
      case 'por_km':
        return 'Por km';
      default:
        return 'Fijo';
    }
  }

  String get _aritmetica {
    final monto = _numero(_datos['monto_fijo']);
    final precioKm = _numero(_datos['precio_km']);
    switch (_datos['modo']?.toString()) {
      case 'fijo_mas_km':
        return '${fmtCup(monto)} + ${fmtCup(precioKm)}/km';
      case 'por_km':
        return '${fmtCup(precioKm)}/km';
      default:
        return fmtCup(monto);
    }
  }

  double? _numero(Object? valor) {
    if (valor is num) return valor.toDouble();
    if (valor is String) return double.tryParse(valor.replaceAll(',', '.'));
    return null;
  }

  bool get _activa => _datos['activo'] as bool? ?? false;

  // ═══════════════════════════════════════════════════════════════════════
  // Dibujo
  // ═══════════════════════════════════════════════════════════════════════

  void _alTocarMapa(TapPosition posicion, LatLng punto) {
    if (_previsualizar) return;

    final toque = posicion.relative;
    final indiceHueco = _huecoActivo;
    if (indiceHueco != null) {
      if (_huecosCerrados[indiceHueco]) {
        _avisar(
          'Ese hueco ya está cerrado. Pulsa "Añadir hueco" para empezar otro.',
          ok: false,
        );
        return;
      }
      final hueco = _huecos[indiceHueco];
      if (toque != null && _tocaPrimerVertice(toque, hueco)) {
        _cerrarAnilloActivo();
        return;
      }
      setState(() {
        hueco.add(punto);
        _cambios = true;
      });
      return;
    }

    if (_exteriorCerrado) {
      _avisar(
        'El polígono ya está cerrado. Usa "Deshacer" o arrastra un vértice '
        'para corregirlo.',
        ok: false,
      );
      return;
    }
    if (toque != null && _tocaPrimerVertice(toque, _exterior)) {
      _cerrarAnilloActivo();
      return;
    }
    setState(() {
      _exterior.add(punto);
      _cambios = true;
    });
  }

  /// Cierra el anillo si el toque cae sobre su primer vértice (~14 px).
  bool _tocaPrimerVertice(Offset posicion, List<LatLng> anillo) {
    if (!_mapaListo || anillo.length < 3) return false;
    final pantalla = _controlador.camera.latLngToScreenPoint(anillo.first);
    final dx = pantalla.x - posicion.dx;
    final dy = pantalla.y - posicion.dy;
    return math.sqrt(dx * dx + dy * dy) <= 14;
  }

  void _moverVertice(int? indiceHueco, int indice, LatLng nuevo) {
    setState(() {
      if (indiceHueco == null) {
        if (indice < _exterior.length) _exterior[indice] = nuevo;
      } else if (indiceHueco < _huecos.length &&
          indice < _huecos[indiceHueco].length) {
        _huecos[indiceHueco][indice] = nuevo;
      }
      _cambios = true;
    });
  }

  void _cerrarAnilloActivo() {
    final indiceHueco = _huecoActivo;
    if (indiceHueco == null) {
      if (_exterior.length < 3) {
        _avisar(
          'Necesitas al menos 3 vértices para cerrar el polígono.',
          ok: false,
        );
        return;
      }
      final error = PoligonoZona.validarAnillo(
        _exterior,
        'El polígono exterior',
      );
      if (error != null) {
        _avisar(error, ok: false);
        return;
      }
      setState(() {
        _exteriorCerrado = true;
        _cambios = true;
      });
      return;
    }

    final hueco = _huecos[indiceHueco];
    if (hueco.length < 3) {
      _avisar('El hueco necesita al menos 3 vértices.', ok: false);
      return;
    }
    final error = PoligonoZona.validarAnillo(
      hueco,
      'El hueco ${indiceHueco + 1}',
    );
    if (error != null) {
      _avisar(error, ok: false);
      return;
    }
    setState(() {
      _huecosCerrados[indiceHueco] = true;
      _huecoActivo = null;
      _cambios = true;
    });
  }

  void _anadirHueco() {
    if (_exterior.length < 3) {
      _avisar('Dibuja primero el polígono exterior.', ok: false);
      return;
    }
    if (!_exteriorCerrado) {
      _avisar(
        'Cierra el polígono exterior con "Cerrar polígono" antes de añadir '
        'un hueco.',
        ok: false,
      );
      return;
    }
    setState(() {
      _huecos.add(<LatLng>[]);
      _huecosCerrados.add(false);
      _huecoActivo = _huecos.length - 1;
      _cambios = true;
    });
  }

  void _quitarHuecoActivo() {
    final indice = _huecoActivo;
    if (indice == null) return;
    setState(() {
      _huecos.removeAt(indice);
      _huecosCerrados.removeAt(indice);
      _huecoActivo = null;
      _cambios = true;
    });
  }

  void _deshacer() {
    final indice = _huecoActivo;
    if (indice != null) {
      final hueco = _huecos[indice];
      if (hueco.isEmpty) {
        setState(() {
          _huecos.removeAt(indice);
          _huecosCerrados.removeAt(indice);
          _huecoActivo = null;
          _cambios = true;
        });
        return;
      }
      setState(() {
        if (_huecosCerrados[indice]) {
          _huecosCerrados[indice] = false;
        } else {
          hueco.removeLast();
        }
        _cambios = true;
      });
      return;
    }

    if (_exterior.isEmpty) {
      _avisar('No hay vértices que deshacer.', ok: false);
      return;
    }
    setState(() {
      if (_exteriorCerrado) {
        _exteriorCerrado = false;
      } else {
        _exterior.removeLast();
      }
      _cambios = true;
    });
  }

  Future<void> _borrarTodo() async {
    if (_exterior.isEmpty && _huecos.isEmpty) return;
    final confirmado = await _confirmar(
      titulo: 'Borrar el polígono',
      mensaje:
          'Se quitan todos los vértices del mapa. La zona no se guarda ni se '
          'borra de la base de datos hasta que vuelvas a guardar.',
      etiqueta: 'Borrar todo',
      destructivo: true,
    );
    if (confirmado != true || !mounted) return;
    setState(() {
      _exterior = <LatLng>[];
      _exteriorCerrado = false;
      _huecos.clear();
      _huecosCerrados.clear();
      _huecoActivo = null;
      _previsualizar = false;
      _cambios = true;
    });
  }

  void _alternarVistaPrevia() {
    if (!_previsualizar && _exterior.length < 3) {
      _avisar(
        'Necesitas al menos 3 vértices para ver la vista previa.',
        ok: false,
      );
      return;
    }
    setState(() => _previsualizar = !_previsualizar);
  }

  void _centrar() {
    if (!_mapaListo) return;
    final puntos = <LatLng>[
      ..._exterior,
      for (final hueco in _huecos) ...hueco,
    ];
    if (puntos.length >= 3) {
      _encuadrar(puntos);
      return;
    }
    _controlador.move(
      const LatLng(
        MueveteZonaGeometria.santaClaraLat,
        MueveteZonaGeometria.santaClaraLon,
      ),
      13,
    );
  }

  void _encuadrar(List<LatLng> puntos) {
    if (!_mapaListo || puntos.length < 2) return;
    try {
      final tamano = _controlador.camera.nonRotatedSize;
      // Si el mapa aún no tiene tamaño real, CameraFit produciría una cámara
      // inválida; se reintenta en la siguiente acción del usuario.
      if (!tamano.x.isFinite || !tamano.y.isFinite) return;
      if (tamano.x < 2 || tamano.y < 2) return;
      _controlador.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(puntos),
          padding: const EdgeInsets.all(48),
        ),
      );
    } catch (e) {
      debugPrint('[MueveteZonaEditor] no se pudo encuadrar el mapa: $e');
    }
  }

  void _alMapaListo() {
    _mapaListo = true;
    final puntos = <LatLng>[
      ..._exterior,
      for (final hueco in _huecos) ...hueco,
    ];
    if (puntos.length >= 3) {
      // El primer frame del mapa aún no tiene tamaño: se encuadra después.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _encuadrar(puntos);
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Guardado
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _guardar() async {
    if (_guardando) return;

    if (_esNueva && widget.datosIniciales == null) {
      _avisar(
        'Faltan los datos de la zona. Vuelve a la lista y crea la zona otra vez.',
        ok: false,
      );
      return;
    }

    final poligono = _poligono;
    final error = poligono.validar();
    if (error != null) {
      setState(() {
        _previsualizar = false;
        _huecoActivo = null;
      });
      _avisar(error, ok: false);
      return;
    }

    setState(() {
      _guardando = true;
      // El polígono se entrega siempre cerrado, aunque no se pulsara el botón.
      _exteriorCerrado = true;
      for (var i = 0; i < _huecosCerrados.length; i++) {
        _huecosCerrados[i] = true;
      }
    });

    try {
      final geometria = poligono.aGeoJson();
      final id = _idZona;
      if (id == null) {
        final datos = Map<String, dynamic>.from(widget.datosIniciales!);
        datos['geometria'] = geometria;
        await MueveteTarifasService.crearZona(datos);
      } else {
        await MueveteTarifasService.actualizarZona(id, {
          'geometria': geometria,
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop(geometria);
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      _avisar(e.mensaje, ok: false);
    } catch (e) {
      if (!mounted) return;
      _avisar('No se pudo guardar el polígono: $e', ok: false);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cancelar() async {
    if (_cambios) {
      final descartar = await _confirmar(
        titulo: 'Descartar cambios',
        mensaje:
            'Los vértices dibujados en este editor se pierden. La zona queda '
            'como estaba en la base de datos.',
        etiqueta: 'Descartar',
        destructivo: true,
      );
      if (descartar != true || !mounted) return;
    }
    if (!mounted) return;
    // `null` = cancelado: la lista no recarga ni avisa nada.
    Navigator.of(context).pop();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers de UI
  // ═══════════════════════════════════════════════════════════════════════

  void _avisar(String mensaje, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: ok ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: ok ? 3 : 6),
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

  // ═══════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final horizontal = tamano.width >= 900;
    final double altoPanel =
        horizontal ? 0 : (tamano.height * 0.36).clamp(200.0, 300.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.polyline_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _esNueva ? 'Nuevo polígono de zona' : 'Editor de polígono',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${_datos['nombre'] ?? 'Zona sin nombre'} · $_etiquetaModo',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '${_poligono.totalVertices} vértices',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body:
          horizontal
              ? Row(
                children: [
                  SizedBox(
                    width: tamano.width >= 1280 ? 360 : 320,
                    child: _panel(),
                  ),
                  Container(width: 1, color: AppColors.divider),
                  Expanded(child: _mapa(compacto: false)),
                ],
              )
              : Column(
                children: [
                  Expanded(child: _mapa(compacto: true)),
                  Container(height: 1, color: AppColors.divider),
                  SizedBox(height: altoPanel, child: _panel()),
                ],
              ),
    );
  }

  // ─── Mapa ─────────────────────────────────────────────────────────────

  Widget _mapa({required bool compacto}) {
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _controlador,
            options: MapOptions(
              initialCenter: const LatLng(
                MueveteZonaGeometria.santaClaraLat,
                MueveteZonaGeometria.santaClaraLon,
              ),
              initialZoom: 13,
              minZoom: 3,
              maxZoom: 19,
              backgroundColor: const Color(0xFFDDE6EE),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: _previsualizar ? null : _alTocarMapa,
              onMapReady: _alMapaListo,
            ),
            children: [
              TileLayer(
                urlTemplate: MueveteZonaGeometria.urlTilesOsm,
                userAgentPackageName: 'com.inventtia.superadmin',
                maxZoom: 19,
              ),
              if (_otrasZonas.isNotEmpty)
                PolygonLayer(
                  polygons: _poligonosDeContexto(),
                  simplificationTolerance: 0,
                ),
              PolygonLayer(
                polygons: _poligonosEnEdicion(),
                simplificationTolerance: 0,
              ),
              if (!_previsualizar) PolylineLayer(polylines: _lineasAbiertas()),
              if (!_previsualizar && _exterior.isNotEmpty)
                MarkerLayer(markers: _marcadoresDeVertices()),
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
          right: 12,
          child: _barraHerramientas(compacto),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _barraGuardado(compacto),
        ),
      ],
    );
  }

  List<Polygon> _poligonosDeContexto() {
    final poligonos = <Polygon>[];
    for (var i = 0; i < _otrasZonas.length; i++) {
      final geometria = PoligonoZona.desdeGeoJson(_otrasZonas[i]['geometria']);
      if (geometria == null || geometria.exterior.length < 3) continue;
      final color = AppColors.chartColors[i % AppColors.chartColors.length];
      poligonos.add(
        Polygon(
          points: geometria.exterior,
          holePointsList: geometria.huecos.isEmpty ? null : geometria.huecos,
          color: color.withValues(alpha: 0.07),
          borderColor: color.withValues(alpha: 0.35),
          borderStrokeWidth: 1,
        ),
      );
    }
    return poligonos;
  }

  List<Polygon> _poligonosEnEdicion() {
    if (_exterior.length < 3) return const [];
    final huecosCerrados = <List<LatLng>>[
      for (var i = 0; i < _huecos.length; i++)
        if (_huecos[i].length >= 3 && (_huecosCerrados[i] || _previsualizar))
          _huecos[i],
    ];
    return [
      Polygon(
        points: _exterior,
        holePointsList: huecosCerrados.isEmpty ? null : huecosCerrados,
        color: AppColors.primary.withValues(alpha: _previsualizar ? 0.3 : 0.16),
        borderColor: AppColors.primary,
        borderStrokeWidth: _previsualizar ? 3 : 2,
      ),
    ];
  }

  List<Polyline> _lineasAbiertas() {
    final lineas = <Polyline>[];
    final trazo = StrokePattern.dashed(segments: const [10, 6]);
    if (_exterior.length >= 2 && !_exteriorCerrado) {
      lineas.add(
        Polyline(
          points: _exterior,
          color: AppColors.primary,
          strokeWidth: 3,
          pattern: trazo,
        ),
      );
    }
    for (var i = 0; i < _huecos.length; i++) {
      if (_huecos[i].length >= 2 && !_huecosCerrados[i]) {
        lineas.add(
          Polyline(
            points: _huecos[i],
            color: AppColors.error,
            strokeWidth: 2.5,
            pattern: trazo,
          ),
        );
      }
    }
    return lineas;
  }

  List<Marker> _marcadoresDeVertices() {
    final marcadores = <Marker>[];
    for (var i = 0; i < _exterior.length; i++) {
      final indice = i;
      marcadores.add(
        Marker(
          point: _exterior[i],
          width: 32,
          height: 32,
          child: _VerticeArrastrable(
            key: ValueKey<String>('vertice-exterior-$indice'),
            punto: _exterior[i],
            color: AppColors.primary,
            onMover: (punto) => _moverVertice(null, indice, punto),
          ),
        ),
      );
    }
    for (var h = 0; h < _huecos.length; h++) {
      for (var i = 0; i < _huecos[h].length; i++) {
        final indiceHueco = h;
        final indice = i;
        marcadores.add(
          Marker(
            point: _huecos[h][i],
            width: 32,
            height: 32,
            child: _VerticeArrastrable(
              key: ValueKey<String>('vertice-hueco-$h-$i'),
              punto: _huecos[h][i],
              color: AppColors.error,
              onMover: (punto) => _moverVertice(indiceHueco, indice, punto),
            ),
          ),
        );
      }
    }
    return marcadores;
  }

  // ─── Barras flotantes ─────────────────────────────────────────────────

  Widget _barraHerramientas(bool compacto) {
    if (_previsualizar) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _tarjetaFlotante(
          wrap: true,
          children: [
            const Icon(
              Icons.visibility_rounded,
              size: 16,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Vista previa del polígono',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _alternarVistaPrevia,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text(
                'Volver a editar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      );
    }

    final activo = _huecoActivo;
    final colorAnillo = activo == null ? AppColors.primary : AppColors.error;
    final etiquetaAnillo =
        activo == null ? 'Anillo exterior' : 'Hueco ${activo + 1}';

    return Align(
      alignment: Alignment.centerLeft,
      child: _tarjetaFlotante(
        wrap: true,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: colorAnillo.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 9, color: colorAnillo),
                const SizedBox(width: 6),
                Text(
                  etiquetaAnillo,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colorAnillo,
                  ),
                ),
              ],
            ),
          ),
          _herramienta(
            icono: Icons.check_circle_outline_rounded,
            etiqueta: activo == null ? 'Cerrar polígono' : 'Cerrar hueco',
            compacto: compacto,
            onPressed: _cerrarAnilloActivo,
          ),
          _herramienta(
            icono: Icons.undo_rounded,
            etiqueta: 'Deshacer',
            compacto: compacto,
            onPressed: _deshacer,
          ),
          _herramienta(
            icono: Icons.delete_sweep_outlined,
            etiqueta: 'Borrar todo',
            compacto: compacto,
            onPressed: _borrarTodo,
          ),
          _herramienta(
            icono: Icons.remove_circle_outline_rounded,
            etiqueta: 'Añadir hueco',
            compacto: compacto,
            onPressed: _anadirHueco,
          ),
          if (activo != null)
            _herramienta(
              icono: Icons.close_rounded,
              etiqueta: 'Quitar hueco',
              compacto: compacto,
              onPressed: _quitarHuecoActivo,
            ),
          _herramienta(
            icono: Icons.center_focus_strong_rounded,
            etiqueta: 'Centrar',
            compacto: compacto,
            onPressed: _centrar,
          ),
        ],
      ),
    );
  }

  Widget _barraGuardado(bool compacto) {
    return Align(
      alignment: Alignment.bottomRight,
      child: _tarjetaFlotante(
        wrap: true,
        children: [
          if (!compacto)
            _accionSecundaria(
              icono:
                  _previsualizar
                      ? Icons.edit_rounded
                      : Icons.visibility_rounded,
              etiqueta: _previsualizar ? 'Volver a editar' : 'Vista previa',
              onPressed: _guardando ? null : _alternarVistaPrevia,
            )
          else
            _botonIcono(
              icono:
                  _previsualizar
                      ? Icons.edit_rounded
                      : Icons.visibility_rounded,
              tooltip: _previsualizar ? 'Volver a editar' : 'Vista previa',
              onPressed: _guardando ? null : _alternarVistaPrevia,
            ),
          if (!compacto)
            _accionSecundaria(
              icono: Icons.close_rounded,
              etiqueta: 'Cancelar',
              onPressed: _guardando ? null : _cancelar,
            )
          else
            _botonIcono(
              icono: Icons.close_rounded,
              tooltip: 'Cancelar',
              onPressed: _guardando ? null : _cancelar,
            ),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon:
                  _guardando
                      ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.save_rounded, size: 17),
              label: Text(
                _guardando
                    ? 'Guardando...'
                    : (compacto ? 'Guardar' : 'Guardar zona'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaFlotante({required List<Widget> children, bool wrap = false}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child:
            wrap
                ? Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: children,
                )
                : Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _herramienta({
    required IconData icono,
    required String etiqueta,
    required bool compacto,
    required VoidCallback? onPressed,
  }) {
    if (compacto) {
      return IconButton(
        tooltip: etiqueta,
        onPressed: onPressed,
        icon: Icon(icono, size: 19),
        color: AppColors.textPrimary,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icono, size: 16),
      label: Text(
        etiqueta,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _accionSecundaria({
    required IconData icono,
    required String etiqueta,
    required VoidCallback? onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icono, size: 17),
      label: Text(
        etiqueta,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _botonIcono({
    required IconData icono,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icono, size: 19),
      color: AppColors.textSecondary,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }

  // ─── Panel lateral ────────────────────────────────────────────────────

  Widget _panel() {
    final poligono = _poligono;
    final error = _motivoBloqueo;

    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.polyline_rounded,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (_datos['nombre'] ?? 'Zona sin nombre').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _ubicacion(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                texto: _etiquetaModo,
                color: AppColors.secondary,
                icono: Icons.local_taxi_rounded,
              ),
              _chip(
                texto: _activa ? 'Activa' : 'Inactiva',
                color: _activa ? AppColors.success : AppColors.textSecondary,
                icono:
                    _activa
                        ? Icons.toggle_on_rounded
                        : Icons.toggle_off_rounded,
              ),
              _chip(
                texto: 'Prioridad ${_datos['prioridad'] ?? 0}',
                color: AppColors.textSecondary,
                icono: Icons.sort_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _aritmetica,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _esNueva
                ? 'Zona nueva: los datos de tarifa ya se capturaron. Falta el '
                    'polígono para poder crearla.'
                : 'Los datos de tarifa se editan desde la lista de zonas.',
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Text(
            'Geometría',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _filaDato('Vértices', '${poligono.totalVertices}'),
          _filaDato(
            'Anillos',
            '1 exterior'
                '${_huecos.isEmpty ? '' : ' + ${_huecos.length} hueco(s)'}',
          ),
          _filaDato(
            'Área aprox.',
            poligono.tieneVerticesSuficientes
                ? '${poligono.areaKm2.toStringAsFixed(2)} km²'
                : '—',
          ),
          _filaDato(
            'Perímetro',
            poligono.tieneVerticesSuficientes
                ? '${poligono.perimetroKm.toStringAsFixed(2)} km'
                : '—',
          ),
          _filaDato(
            'Centroide',
            poligono.tieneVerticesSuficientes
                ? MueveteZonaGeometria.formatearCoordenada(poligono.centroide)
                : '—',
          ),
          const SizedBox(height: 10),
          _cajaValidacion(error),
          if (_cargandoContexto) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cargando zonas de referencia...',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (_errorContexto != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorContexto!,
              style: const TextStyle(fontSize: 10.5, color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 10),
          Text(
            'Toca el mapa para añadir vértices. Arrastra un vértice para '
            'corregirlo y toca el primer vértice (o pulsa "Cerrar polígono") '
            'para cerrar el anillo. El polígono se guarda siempre cerrado, con '
            'el orden [longitud, latitud].',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _ubicacion() {
    final municipio = (_datos['municipio'] as String?)?.trim();
    final provincia = (_datos['provincia'] as String?)?.trim();
    final partes = <String>[
      if (municipio != null && municipio.isNotEmpty) municipio,
      if (provincia != null && provincia.isNotEmpty) provincia,
    ];
    return partes.isEmpty ? 'Sin municipio asignado' : partes.join(' · ');
  }

  Widget _chip({
    required String texto,
    required Color color,
    required IconData icono,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaDato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              etiqueta,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cajaValidacion(String? error) {
    final Color color;
    final IconData icono;
    final String titulo;
    final String detalle;

    if (_exterior.isEmpty) {
      color = AppColors.textSecondary;
      icono = Icons.gesture_rounded;
      titulo = 'Sin polígono todavía';
      detalle = error ?? 'Toca el mapa para empezar a dibujar.';
    } else if (error != null) {
      color = AppColors.error;
      icono = Icons.error_outline_rounded;
      titulo = 'Polígono inválido';
      detalle = error;
    } else {
      color = AppColors.success;
      icono = Icons.check_circle_outline_rounded;
      titulo = 'Polígono válido';
      detalle = 'Listo para guardar.';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detalle,
                  style: TextStyle(
                    fontSize: 10.5,
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
}

// ═══════════════════════════════════════════════════════════════════════════
// Vértice arrastrable
// ═══════════════════════════════════════════════════════════════════════════

/// Punto del polígono que se puede arrastrar sobre el mapa.
///
/// `flutter_map 7` no trae `DragMarkers` (era del paquete
/// `flutter_map_dragmarker`), así que el arrastre se resuelve con
/// `GestureDetector` + [MapCamera]: al empezar se guarda la posición en
/// pantalla del vértice y cada `onPanUpdate` acumula el delta para volver a
/// proyectarlo a `LatLng`. Así el vértice no "huye" del dedo cuando el mapa se
/// reconstruye con la nueva posición.
class _VerticeArrastrable extends StatefulWidget {
  const _VerticeArrastrable({
    super.key,
    required this.punto,
    required this.color,
    required this.onMover,
  });

  /// Posición actual del vértice, la que pinta el padre.
  final LatLng punto;
  final Color color;
  final ValueChanged<LatLng> onMover;

  @override
  State<_VerticeArrastrable> createState() => _VerticeArrastrableState();
}

class _VerticeArrastrableState extends State<_VerticeArrastrable> {
  math.Point<double>? _inicioPantalla;
  Offset _arrastre = Offset.zero;
  bool _arrastrando = false;

  void _alEmpezar(DragStartDetails detalles) {
    final camara = MapCamera.of(context);
    _inicioPantalla = camara.latLngToScreenPoint(widget.punto);
    _arrastre = Offset.zero;
    setState(() => _arrastrando = true);
  }

  void _alArrastrar(DragUpdateDetails detalles) {
    final inicio = _inicioPantalla;
    if (inicio == null) return;
    _arrastre += detalles.delta;
    final camara = MapCamera.of(context);
    final destino = camara.pointToLatLng(
      math.Point<double>(inicio.x + _arrastre.dx, inicio.y + _arrastre.dy),
    );
    widget.onMover(destino);
  }

  void _alSoltar() {
    if (!_arrastrando && _inicioPantalla == null) return;
    _inicioPantalla = null;
    if (mounted) setState(() => _arrastrando = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onPanStart: _alEmpezar,
        onPanUpdate: _alArrastrar,
        onPanEnd: (_) => _alSoltar(),
        onPanCancel: _alSoltar,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: _arrastrando ? 20 : 15,
            height: _arrastrando ? 20 : 15,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color,
                width: _arrastrando ? 3.5 : 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
