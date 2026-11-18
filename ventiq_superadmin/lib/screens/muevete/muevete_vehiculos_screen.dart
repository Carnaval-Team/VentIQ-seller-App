import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_colors.dart';
import '../../services/muevete_vehiculos_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Pantalla: Catálogo de Vehículos (H1)
//
// `vehicle_type` es la lista que pinta la app del cliente. Aquí se cambia el
// nombre visible, el orden, la capacidad y la visibilidad **sin recompilar**
// la app del cliente; el multiplicador tarifario se edita en Tarifas y Zonas.
// ═══════════════════════════════════════════════════════════════════════════

class MueveteVehiculosScreen extends StatefulWidget {
  const MueveteVehiculosScreen({super.key});

  @override
  State<MueveteVehiculosScreen> createState() => _MueveteVehiculosScreenState();
}

class _MueveteVehiculosScreenState extends State<MueveteVehiculosScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _tipos = [];

  /// Controladores por id de `vehicle_type`.
  final Map<int, TextEditingController> _nombreCtrls = {};
  final Map<int, TextEditingController> _ordenCtrls = {};
  final Map<int, TextEditingController> _pasajerosCtrls = {};

  final Set<int> _guardando = {};
  bool _reordenando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _nombreCtrls.values) {
      c.dispose();
    }
    for (final c in _ordenCtrls.values) {
      c.dispose();
    }
    for (final c in _pasajerosCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Datos
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final tipos = await MueveteVehiculosService.listarTipos();
      if (!mounted) return;
      _sincronizarControladores(tipos);
      setState(() {
        _tipos = tipos;
        _cargando = false;
        _error = null;
      });
    } on MueveteVehiculosException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los tipos de vehículo: $e';
      });
    }
  }

  /// Crea/actualiza los controladores de texto sin perder lo que el usuario
  /// estuviera escribiendo en otra tarjeta.
  void _sincronizarControladores(List<Map<String, dynamic>> tipos) {
    final ids = tipos.map((t) => (t['id'] as num).toInt()).toSet();
    for (final id in _nombreCtrls.keys.toList()) {
      if (!ids.contains(id)) {
        _nombreCtrls.remove(id)?.dispose();
        _ordenCtrls.remove(id)?.dispose();
        _pasajerosCtrls.remove(id)?.dispose();
      }
    }
    for (final t in tipos) {
      final id = (t['id'] as num).toInt();
      _nombreCtrls.putIfAbsent(id, () => TextEditingController());
      _ordenCtrls.putIfAbsent(id, () => TextEditingController());
      _pasajerosCtrls.putIfAbsent(id, () => TextEditingController());
      _escribirSiDistinto(
        _nombreCtrls[id]!,
        (t['nombre_ui'] as String?) ?? (t['tipo'] as String?) ?? '',
      );
      _escribirSiDistinto(_ordenCtrls[id]!, _texto(t['orden']));
      _escribirSiDistinto(_pasajerosCtrls[id]!, _texto(t['pasajeros_max']));
    }
  }

  void _escribirSiDistinto(TextEditingController c, String valor) {
    if (c.text != valor) c.text = valor;
  }

  String _texto(Object? valor) {
    if (valor == null) return '';
    if (valor is num) {
      final d = valor.toDouble();
      if (d == d.roundToDouble()) return d.toStringAsFixed(0);
      return d.toString();
    }
    return valor.toString();
  }

  int _ordenDe(Map<String, dynamic> t) =>
      (t['orden'] as num?)?.toInt() ?? MueveteVehiculosService.ordenMax;

  int get _visibles =>
      _tipos.where((t) => t['status'] == true).length;

  // ═══════════════════════════════════════════════════════════════════════
  // Acciones
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _guardarTipo(Map<String, dynamic> tipo) async {
    final id = (tipo['id'] as num).toInt();
    final nombre = _nombreCtrls[id]?.text.trim() ?? '';
    final orden = int.tryParse((_ordenCtrls[id]?.text ?? '').trim());
    final pasajeros = int.tryParse((_pasajerosCtrls[id]?.text ?? '').trim());

    if (nombre.isEmpty) {
      _avisar('El nombre visible no puede quedar vacío.', error: true);
      return;
    }
    if (pasajeros == null) {
      _avisar('La capacidad debe ser un número entero.', error: true);
      return;
    }
    if (pasajeros < MueveteVehiculosService.pasajerosMin ||
        pasajeros > MueveteVehiculosService.pasajerosMax) {
      _avisar(
        'La capacidad debe estar entre ${MueveteVehiculosService.pasajerosMin} '
        'y ${MueveteVehiculosService.pasajerosMax} pasajeros.',
        error: true,
      );
      return;
    }
    if (orden == null) {
      _avisar('El orden debe ser un número entero.', error: true);
      return;
    }

    setState(() => _guardando.add(id));
    try {
      await MueveteVehiculosService.guardarTipo(
        id,
        nombreUi: nombre,
        pasajerosMax: pasajeros,
        orden: orden,
      );
      await _cargar(silencioso: true);
      _avisar('${nombre.isNotEmpty ? nombre : 'Tipo'} actualizado.');
    } on MueveteVehiculosException catch (e) {
      _avisar(e.mensaje, error: true);
    } catch (e) {
      _avisar('No se pudo guardar el tipo de vehículo: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando.remove(id));
    }
  }

  Future<void> _cambiarVisibilidad(
    Map<String, dynamic> tipo,
    bool visible,
  ) async {
    final id = (tipo['id'] as num).toInt();
    final nombre = _nombreDe(tipo);

    // Regla de negocio: nunca dejar el catálogo del cliente sin tipos.
    if (!visible && _visibles <= 1) {
      await showDialog<void>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'No puedes ocultar el último tipo visible',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              content: Text(
                'La app del cliente se quedaría sin vehículos que ofrecer. '
                'Enciende otro tipo antes de ocultar «$nombre».',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ],
            ),
      );
      return;
    }

    setState(() => _guardando.add(id));
    try {
      await MueveteVehiculosService.cambiarVisibilidad(id, visible);
      final frescos = await MueveteVehiculosService.listarTipos();
      await _persistirOrden(_ordenar(frescos), recargar: false);
      await _cargar(silencioso: true);
      _avisar(visible ? '«$nombre» visible' : '«$nombre» oculto');
    } on MueveteVehiculosException catch (e) {
      _avisar(e.mensaje, error: true);
      await _cargar(silencioso: true);
    } catch (e) {
      _avisar('No se pudo cambiar la visibilidad: $e', error: true);
      await _cargar(silencioso: true);
    } finally {
      if (mounted) setState(() => _guardando.remove(id));
    }
  }

  /// Mueve un tipo visible una posición arriba (delta = -1) o abajo (+1).
  Future<void> _mover(Map<String, dynamic> tipo, int delta) async {
    if (_reordenando) return;
    final visibles =
        _tipos.where((t) => t['status'] == true).toList()
          ..sort((a, b) => _ordenDe(a).compareTo(_ordenDe(b)));
    final ocultos =
        _tipos.where((t) => t['status'] != true).toList()
          ..sort((a, b) => _ordenDe(a).compareTo(_ordenDe(b)));

    final i = visibles.indexWhere((t) => t['id'] == tipo['id']);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= visibles.length) return;

    final movido = visibles[i];
    visibles[i] = visibles[j];
    visibles[j] = movido;

    setState(() => _reordenando = true);
    try {
      await MueveteVehiculosService.guardarOrden([...visibles, ...ocultos]);
      await _cargar(silencioso: true);
      _avisar('Orden actualizado');
    } on MueveteVehiculosException catch (e) {
      _avisar(e.mensaje, error: true);
      await _cargar(silencioso: true);
    } catch (e) {
      _avisar('No se pudo guardar el orden: $e', error: true);
    } finally {
      if (mounted) setState(() => _reordenando = false);
    }
  }

  /// Visibles en su orden actual y ocultos detrás, en su orden actual.
  List<Map<String, dynamic>> _ordenar(List<Map<String, dynamic>> base) {
    final visibles =
        base.where((t) => t['status'] == true).toList()
          ..sort((a, b) => _ordenDe(a).compareTo(_ordenDe(b)));
    final ocultos =
        base.where((t) => t['status'] != true).toList()
          ..sort((a, b) => _ordenDe(a).compareTo(_ordenDe(b)));
    return [...visibles, ...ocultos];
  }

  Future<void> _persistirOrden(
    List<Map<String, dynamic>> ordenados, {
    bool recargar = true,
  }) async {
    await MueveteVehiculosService.guardarOrden(ordenados);
    if (recargar) await _cargar(silencioso: true);
  }

  String _nombreDe(Map<String, dynamic> tipo) {
    final ui = (tipo['nombre_ui'] as String?)?.trim();
    if (ui != null && ui.isNotEmpty) return ui;
    return (tipo['tipo'] as String?) ?? 'Vehículo';
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(ancho);

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
                Icons.directions_car_rounded,
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
                    'Catálogo de Vehículos',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    _resumenCabecera(),
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
          if (isDesktop)
            TextButton.icon(
              onPressed:
                  () => Navigator.of(context).pushNamed('/muevete/tarifas'),
              icon: const Icon(Icons.percent_rounded, size: 17),
              label: const Text(
                'Ajustar multiplicadores',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            )
          else
            IconButton(
              tooltip: 'Ajustar multiplicadores en Tarifas',
              onPressed:
                  () => Navigator.of(context).pushNamed('/muevete/tarifas'),
              icon: const Icon(Icons.percent_rounded, color: AppColors.primary),
            ),
          IconButton(
            tooltip: 'Recargar',
            onPressed: _cargando ? null : () => _cargar(),
            icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _cuerpo(isDesktop),
    );
  }

  String _resumenCabecera() {
    if (_cargando) return 'Cargando catálogo…';
    if (_error != null) return 'Error al cargar';
    final ocultos = _tipos.length - _visibles;
    return '$_visibles visibles · $ocultos ocultos · '
        'cambios sin recompilar la app del cliente';
  }

  Widget _cuerpo(bool isDesktop) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _EstadoError(mensaje: _error!, onReintentar: () => _cargar());
    }
    if (_tipos.isEmpty) {
      return const _EstadoVacio(
        icono: Icons.directions_car_rounded,
        titulo: 'Sin tipos de vehículo',
        mensaje:
            'La tabla vehicle_type está vacía. Aplica el seed del catálogo '
            'antes de configurar la lista que verá el cliente.',
      );
    }

    final visibles =
        _tipos.where((t) => t['status'] == true).toList()
          ..sort((a, b) => _ordenDe(a).compareTo(_ordenDe(b)));
    final ocultos =
        _tipos.where((t) => t['status'] != true).toList()
          ..sort((a, b) => _ordenDe(a).compareTo(_ordenDe(b)));

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bannerAviso(),
              if (_visibles == 0) ...[
                const SizedBox(height: 12),
                _bannerSinVisibles(),
              ],
              const SizedBox(height: 16),
              _tituloSeccion(
                'Visibles para el cliente',
                '${visibles.length} tipos · este es el orden de la lista',
                Icons.visibility_rounded,
              ),
              const SizedBox(height: 10),
              ...visibles.map(
                (t) => _tarjeta(t, indice: visibles.indexOf(t),
                    totalVisibles: visibles.length),
              ),
              if (ocultos.isNotEmpty) ...[
                const SizedBox(height: 18),
                _tituloSeccion(
                  'Ocultos',
                  '${ocultos.length} tipos apagados · no se borran, '
                      'se pueden volver a encender',
                  Icons.visibility_off_rounded,
                ),
                const SizedBox(height: 10),
                ...ocultos.map((t) => _tarjeta(t, oculto: true)),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bannerAviso() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cambiar el orden o el nombre no requiere recompilar la app '
                  'del cliente',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'La app pide la lista a la base de datos al abrir la '
                  'pantalla de viaje. El multiplicador de tarifa se edita en '
                  'Tarifas y Zonas y sí afecta el precio cotizado.',
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
    );
  }

  Widget _bannerSinVisibles() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18,
              color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No hay ningún tipo visible: el cliente no puede pedir viajes. '
              'Enciende al menos uno.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tituloSeccion(String titulo, String subtitulo, IconData icono) {
    return Row(
      children: [
        Icon(icono, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitulo,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  // ─── Tarjeta de un tipo ───────────────────────────────────────────────

  Widget _tarjeta(
    Map<String, dynamic> tipo, {
    bool oculto = false,
    int? indice,
    int? totalVisibles,
  }) {
    final id = (tipo['id'] as num).toInt();
    final guardando = _guardando.contains(id);
    final visible = tipo['status'] == true;
    final mult = (tipo['multiplicador_tarifa'] as num?)?.toDouble();
    final primero = indice == 0;
    final ultimo = indice != null && totalVisibles != null
        ? indice == totalVisibles - 1
        : false;

    return Opacity(
      opacity: oculto ? 0.62 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (oculto ? AppColors.textSecondary : AppColors.primary)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconoTipo(tipo['tipo'] as String?),
                    size: 20,
                    color:
                        oculto ? AppColors.textSecondary : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: TextField(
                      controller: _nombreCtrls[id],
                      enabled: !guardando,
                      maxLength: MueveteVehiculosService.nombreMax,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      decoration: _decoracion('Nombre visible').copyWith(
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    mult == null ? '×—' : '×${mult.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Switch(
                  value: visible,
                  onChanged:
                      guardando
                          ? null
                          : (v) => _cambiarVisibilidad(tipo, v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _chip(
                    'vehicle_type.tipo: ${tipo['tipo'] ?? '—'}',
                    AppColors.textSecondary,
                  ),
                  if (tipo['categoria'] != null)
                    _chip('${tipo['categoria']}', AppColors.textSecondary),
                  if (oculto) _chip('Oculto', AppColors.warning),
                  if (!oculto && tipo['pasajeros_max'] != null)
                    _chip(
                      'máx. ${tipo['pasajeros_max']} pasajeros',
                      AppColors.textSecondary,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _ordenCtrls[id],
                    enabled: !guardando,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    decoration: _decoracion('Orden').copyWith(isDense: true),
                  ),
                ),
                if (!oculto)
                  _botonesOrden(tipo, primero: primero, ultimo: ultimo),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _pasajerosCtrls[id],
                    enabled: !guardando,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    decoration: _decoracion('Capacidad')
                        .copyWith(isDense: true, suffixText: 'pax'),
                  ),
                ),
                Text(
                  'capacidad ${MueveteVehiculosService.pasajerosMin}–'
                  '${MueveteVehiculosService.pasajerosMax}',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: guardando ? null : () => _guardarTipo(tipo),
                    icon:
                        guardando
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.save_rounded, size: 16),
                    label: Text(
                      guardando ? 'Guardando…' : 'Guardar',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                if (mult != null)
                  TextButton.icon(
                    onPressed:
                        () =>
                            Navigator.of(context).pushNamed('/muevete/tarifas'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text(
                      'Multiplicador en Tarifas',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _botonesOrden(
    Map<String, dynamic> tipo, {
    required bool primero,
    required bool ultimo,
  }) {
    final activo = !_reordenando && !_guardando.contains(tipo['id']);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Subir',
            visualDensity: VisualDensity.compact,
            onPressed: (activo && !primero) ? () => _mover(tipo, -1) : null,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
          ),
          Container(width: 1, height: 22, color: AppColors.divider),
          IconButton(
            tooltip: 'Bajar',
            visualDensity: VisualDensity.compact,
            onPressed: (activo && !ultimo) ? () => _mover(tipo, 1) : null,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      labelStyle: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      suffixStyle: TextStyle(fontSize: 11, color: AppColors.textSecondary),
    );
  }

  IconData _iconoTipo(String? tipo) {
    switch (tipo) {
      case 'auto':
        return Icons.directions_car_rounded;
      case 'moto':
        return Icons.two_wheeler_rounded;
      case 'microbus':
        return Icons.airport_shuttle_rounded;
      case 'minivan':
        return Icons.directions_car_filled_rounded;
      case 'tuktuk':
        return Icons.electric_rickshaw_rounded;
      case 'camioneta':
        return Icons.local_shipping_rounded;
      case 'bicicleta':
        return Icons.pedal_bike_rounded;
      default:
        return Icons.commute_rounded;
    }
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
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No se pudieron cargar los datos',
              style: TextStyle(
                fontSize: 16,
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

  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.mensaje,
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
              child: Icon(icono, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}