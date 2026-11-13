import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/muevete_tarifas_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Formato de montos y números (CUP con separador de miles: 1 500 CUP)
// ═══════════════════════════════════════════════════════════════════════════

String _miles(int valor) {
  final negativo = valor < 0;
  final digitos = valor.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digitos[i]);
  }
  return negativo ? '-$buffer' : buffer.toString();
}

/// `1500` → `1 500 CUP`; `null` → `—`.
String fmtCup(num? valor) =>
    valor == null ? '—' : '${_miles(valor.round())} CUP';

/// `15` → `15 %`; `12.5` → `12.50 %`.
String fmtPct(num? valor) {
  if (valor == null) return '—';
  final esEntero = valor == valor.roundToDouble();
  return esEntero
      ? '${valor.toStringAsFixed(0)} %'
      : '${valor.toStringAsFixed(2)} %';
}

String fmtNum(num? valor, {int decimales = 2}) =>
    valor == null ? '—' : valor.toStringAsFixed(decimales);

String fmtKm(num? valor) =>
    valor == null ? '—' : '${valor.toStringAsFixed(2)} km';

String fmtFechaHora(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '—';
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year} $hh:$mi';
}

String modoLabel(String? modo) {
  switch (modo) {
    case 'fijo':
      return 'Fijo';
    case 'fijo_mas_km':
      return 'Fijo + por km';
    case 'por_km':
      return 'Por km';
    default:
      return modo ?? '—';
  }
}

/// Acepta `1 500`, `1500`, `1.500,50` y `1500.50`.
double? parseNumero(String texto) {
  var limpio = texto.trim().replaceAll(' ', '').replaceAll('\u00A0', '');
  if (limpio.isEmpty) return null;
  if (limpio.contains(',') && limpio.contains('.')) {
    // Formato europeo: el punto agrupa miles, la coma es decimal.
    limpio = limpio.replaceAll('.', '').replaceAll(',', '.');
  } else {
    limpio = limpio.replaceAll(',', '.');
  }
  return double.tryParse(limpio);
}

int? parseEntero(String texto) {
  final valor = parseNumero(texto);
  if (valor == null) return null;
  if (valor != valor.roundToDouble()) return null;
  return valor.toInt();
}

// ═══════════════════════════════════════════════════════════════════════════
// Pantalla: Configuración de tarifas + simulador
// ═══════════════════════════════════════════════════════════════════════════

/// H6 (primera mitad): parámetros globales, multiplicadores por tipo,
/// fallback municipal y simulador de cotización.
///
/// El simulador **no recalcula nada en Dart**: pinta el jsonb que devuelve
/// `muevete.fn_cotizar_viaje`, la misma función que cobra la app del cliente.
class MueveteTarifasConfigScreen extends StatefulWidget {
  const MueveteTarifasConfigScreen({super.key});

  @override
  State<MueveteTarifasConfigScreen> createState() =>
      _MueveteTarifasConfigScreenState();
}

class _MueveteTarifasConfigScreenState
    extends State<MueveteTarifasConfigScreen> {
  // ── Configuración global ────────────────────────────────────────────
  bool _cfgCargando = true;
  bool _cfgGuardando = false;
  String? _cfgError;
  Map<String, dynamic>? _cfg;
  bool _permiteDeuda = true;
  bool _taxiActivo = false;
  int _redondeo = 50;

  /// Controladores por clave de `configuracion_tarifas` (se crean al vuelo).
  final Map<String, TextEditingController> _cfgCtrls = {};

  /// Claves numéricas del formulario global.
  static const List<String> _clavesNumericas = [
    'comision_pct',
    'tope_comision_viaje',
    'recarga_pct',
    'limite_deuda_efectivo',
    'dias_max_deuda',
    'precio_minimo_auto',
    'precio_minimo_moto',
    'precio_minimo_microbus',
    'precio_corto_auto',
    'umbral_km_corto',
    'recargo_nocturno_pct',
    'gracia_espera_min',
    'tope_cobro_espera',
    'prima_distancia_cup',
    'umbral_prima_distancia_km',
    'descuento_pago_wallet_pct',
    'monto_fijo_fallback_municipio',
    'precio_km_fallback',
  ];

  // ── Multiplicadores por tipo ────────────────────────────────────────
  bool _tiposCargando = true;
  String? _tiposError;
  List<Map<String, dynamic>> _tipos = [];
  final Set<int> _tiposGuardando = {};
  final Map<int, TextEditingController> _multCtrls = {};
  final Map<int, TextEditingController> _ordenCtrls = {};

  // ── Municipios (fallback) ───────────────────────────────────────────
  bool _munCargando = true;
  String? _munError;
  List<Map<String, dynamic>> _municipios = [];
  final Set<int> _munGuardando = {};
  final Map<int, TextEditingController> _munFijoCtrls = {};
  final Map<int, TextEditingController> _munKmCtrls = {};
  final Map<int, String> _munModo = {};
  final Map<int, bool> _munActivo = {};

  // ── Simulador ───────────────────────────────────────────────────────
  final _simLatOCtrl = TextEditingController(text: '22.40689');
  final _simLonOCtrl = TextEditingController(text: '-79.96450');
  final _simLatDCtrl = TextEditingController(text: '22.41089');
  final _simLonDCtrl = TextEditingController(text: '-79.96050');
  final _simKmCtrl = TextEditingController();
  final _simProvinciaCtrl = TextEditingController();
  final _simMunicipioCtrl = TextEditingController();
  int? _simTipoId;
  bool _simNocturno = false;
  bool _simCargando = false;
  String? _simError;
  Map<String, dynamic>? _simResultado;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
    _cargarTipos();
    _cargarMunicipios();
  }

  @override
  void dispose() {
    for (final c in _cfgCtrls.values) {
      c.dispose();
    }
    for (final c in _multCtrls.values) {
      c.dispose();
    }
    for (final c in _ordenCtrls.values) {
      c.dispose();
    }
    for (final c in _munFijoCtrls.values) {
      c.dispose();
    }
    for (final c in _munKmCtrls.values) {
      c.dispose();
    }
    _simLatOCtrl.dispose();
    _simLonOCtrl.dispose();
    _simLatDCtrl.dispose();
    _simLonDCtrl.dispose();
    _simKmCtrl.dispose();
    _simProvinciaCtrl.dispose();
    _simMunicipioCtrl.dispose();
    super.dispose();
  }

  TextEditingController _cfgCtrl(String clave) =>
      _cfgCtrls.putIfAbsent(clave, TextEditingController.new);

  // ═══════════════════════════════════════════════════════════════════════
  // Carga de datos
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _cargarConfig() async {
    setState(() {
      _cfgCargando = true;
      _cfgError = null;
    });
    try {
      final cfg = await MueveteTarifasService.configuracion();
      if (!mounted) return;
      setState(() {
        _cfg = cfg;
        _cfgCargando = false;
        _permiteDeuda = cfg['permite_deuda'] as bool? ?? true;
        _taxiActivo = cfg['taxi_precio_fijo_activo'] as bool? ?? false;

        final redondeo = (cfg['redondeo_cup'] as num?)?.toInt() ?? 50;
        _redondeo =
            MueveteTarifasService.redondeosPermitidos.contains(redondeo)
                ? redondeo
                : 50;

        for (final clave in _clavesNumericas) {
          _cfgCtrl(clave).text = _textoDe(cfg[clave]);
        }
        _cfgCtrl('moneda').text = (cfg['moneda'] as String?) ?? 'CUP';
        _cfgCtrl('ventana_nocturna_inicio').text = _textoHora(
          cfg['ventana_nocturna_inicio'],
        );
        _cfgCtrl('ventana_nocturna_fin').text = _textoHora(
          cfg['ventana_nocturna_fin'],
        );
      });
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      setState(() {
        _cfgError = e.mensaje;
        _cfgCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cfgError = 'Error inesperado al cargar la configuración: $e';
        _cfgCargando = false;
      });
    }
  }

  Future<void> _cargarTipos() async {
    setState(() {
      _tiposCargando = true;
      _tiposError = null;
    });
    try {
      final tipos = await MueveteTarifasService.listarTiposVehiculo();
      if (!mounted) return;
      setState(() {
        _tipos = tipos;
        _tiposCargando = false;
        for (final t in tipos) {
          final id = (t['id'] as num).toInt();
          _multCtrls.putIfAbsent(id, TextEditingController.new).text = _textoDe(
            t['multiplicador_tarifa'],
          );
          _ordenCtrls
              .putIfAbsent(id, TextEditingController.new)
              .text = _textoDe(t['orden']);
        }
        if (tipos.isNotEmpty) {
          final ids = tipos.map((t) => (t['id'] as num).toInt()).toSet();
          if (_simTipoId == null || !ids.contains(_simTipoId)) {
            _simTipoId = (tipos.first['id'] as num).toInt();
          }
        }
      });
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      setState(() {
        _tiposError = e.mensaje;
        _tiposCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tiposError = 'Error inesperado al cargar los tipos de vehículo: $e';
        _tiposCargando = false;
      });
    }
  }

  Future<void> _cargarMunicipios() async {
    setState(() {
      _munCargando = true;
      _munError = null;
    });
    try {
      final filas = await MueveteTarifasService.listarMunicipios();
      if (!mounted) return;
      setState(() {
        _municipios = filas;
        _munCargando = false;
        for (final m in filas) {
          final id = (m['id'] as num).toInt();
          _munFijoCtrls
              .putIfAbsent(id, TextEditingController.new)
              .text = _textoDe(m['monto_fijo']);
          _munKmCtrls
              .putIfAbsent(id, TextEditingController.new)
              .text = _textoDe(m['precio_km']);
          _munModo[id] = (m['modo'] as String?) ?? 'fijo';
          _munActivo[id] = m['activo'] as bool? ?? true;
        }
      });
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      setState(() {
        _munError = e.mensaje;
        _munCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _munError = 'Error inesperado al cargar las tarifas municipales: $e';
        _munCargando = false;
      });
    }
  }

  Future<void> _recargarTodo() async {
    await Future.wait([_cargarConfig(), _cargarTipos(), _cargarMunicipios()]);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Guardado
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _guardarConfig() async {
    final error = _validarConfig();
    if (error != null) {
      _snack(error, false);
      return;
    }

    final confirmado = await _confirmar(
      titulo: 'Guardar parámetros tarifarios',
      mensaje:
          'Los nuevos valores se aplican a las cotizaciones desde este '
          'momento. ¿Confirmas el cambio?',
      etiqueta: 'Guardar',
    );
    if (confirmado != true) return;

    setState(() => _cfgGuardando = true);
    try {
      final cambios = <String, dynamic>{
        'moneda':
            _cfgCtrl('moneda').text.trim().isEmpty
                ? 'CUP'
                : _cfgCtrl('moneda').text.trim().toUpperCase(),
        'comision_pct': parseNumero(_cfgCtrl('comision_pct').text),
        'tope_comision_viaje': parseNumero(
          _cfgCtrl('tope_comision_viaje').text,
        ),
        'recarga_pct': parseNumero(_cfgCtrl('recarga_pct').text),
        'limite_deuda_efectivo': parseNumero(
          _cfgCtrl('limite_deuda_efectivo').text,
        ),
        'dias_max_deuda': parseEntero(_cfgCtrl('dias_max_deuda').text),
        'permite_deuda': _permiteDeuda,
        'precio_minimo_auto': parseNumero(_cfgCtrl('precio_minimo_auto').text),
        'precio_minimo_moto': parseNumero(_cfgCtrl('precio_minimo_moto').text),
        'precio_minimo_microbus': parseNumero(
          _cfgCtrl('precio_minimo_microbus').text,
        ),
        'precio_corto_auto': parseNumero(_cfgCtrl('precio_corto_auto').text),
        'umbral_km_corto': parseNumero(_cfgCtrl('umbral_km_corto').text),
        'recargo_nocturno_pct': parseNumero(
          _cfgCtrl('recargo_nocturno_pct').text,
        ),
        'ventana_nocturna_inicio':
            _cfgCtrl('ventana_nocturna_inicio').text.trim(),
        'ventana_nocturna_fin': _cfgCtrl('ventana_nocturna_fin').text.trim(),
        'gracia_espera_min': parseEntero(_cfgCtrl('gracia_espera_min').text),
        'tope_cobro_espera': parseNumero(_cfgCtrl('tope_cobro_espera').text),
        'prima_distancia_cup': parseNumero(
          _cfgCtrl('prima_distancia_cup').text,
        ),
        'umbral_prima_distancia_km': parseNumero(
          _cfgCtrl('umbral_prima_distancia_km').text,
        ),
        'redondeo_cup': _redondeo,
        'descuento_pago_wallet_pct': parseNumero(
          _cfgCtrl('descuento_pago_wallet_pct').text,
        ),
        'monto_fijo_fallback_municipio': parseNumero(
          _cfgCtrl('monto_fijo_fallback_municipio').text,
        ),
        'precio_km_fallback': parseNumero(_cfgCtrl('precio_km_fallback').text),
        'taxi_precio_fijo_activo': _taxiActivo,
      }..removeWhere((_, v) => v == null);

      await MueveteTarifasService.actualizarConfiguracion(cambios);
      await _cargarConfig();
      _snack(
        'Parámetros guardados. Ya se aplican a las nuevas cotizaciones.',
        true,
      );
    } on MueveteTarifasException catch (e) {
      _snack(e.mensaje, false);
    } catch (e) {
      _snack('No se pudo guardar la configuración: $e', false);
    } finally {
      if (mounted) setState(() => _cfgGuardando = false);
    }
  }

  /// Devuelve el primer error de validación, o `null` si todo está bien.
  String? _validarConfig() {
    final comision = parseNumero(_cfgCtrl('comision_pct').text);
    if (comision == null || comision < 0 || comision > 30) {
      return 'La comisión debe ser un número entre 0 y 30 %.';
    }
    final tope = parseNumero(_cfgCtrl('tope_comision_viaje').text);
    if (tope == null || tope < 0) {
      return 'El tope de comisión por viaje debe ser ≥ 0 (0 = sin tope).';
    }
    final recarga = parseNumero(_cfgCtrl('recarga_pct').text);
    if (recarga == null || recarga < 0 || recarga > 50) {
      return 'El recargo de recarga debe estar entre 0 y 50 %.';
    }
    final deuda = parseNumero(_cfgCtrl('limite_deuda_efectivo').text);
    if (deuda == null || deuda < 0 || deuda > 5000) {
      return 'El límite de deuda en efectivo debe estar entre 0 y 5 000 CUP.';
    }
    final dias = parseEntero(_cfgCtrl('dias_max_deuda').text);
    if (dias == null || dias < 0) {
      return 'Los días máximos de deuda deben ser un entero ≥ 0.';
    }

    final minimos = <String, String>{
      'precio_minimo_auto': 'El precio mínimo de auto',
      'precio_minimo_moto': 'El precio mínimo de moto',
      'precio_minimo_microbus': 'El precio mínimo de microbús',
      'precio_corto_auto': 'El precio corto de auto',
      'umbral_km_corto': 'El umbral de km para precio corto',
    };
    for (final entry in minimos.entries) {
      final valor = parseNumero(_cfgCtrl(entry.key).text);
      if (valor == null || valor < 0) {
        return '${entry.value} debe ser un número ≥ 0.';
      }
    }

    final nocturno = parseNumero(_cfgCtrl('recargo_nocturno_pct').text);
    if (nocturno == null || nocturno < 0 || nocturno > 50) {
      return 'El recargo nocturno debe estar entre 0 y 50 %.';
    }
    final horaRegExp = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    final inicio = _cfgCtrl('ventana_nocturna_inicio').text.trim();
    final fin = _cfgCtrl('ventana_nocturna_fin').text.trim();
    if (!horaRegExp.hasMatch(inicio) || !horaRegExp.hasMatch(fin)) {
      return 'La ventana nocturna debe tener formato HH:MM (por ejemplo 22:00).';
    }
    if (nocturno > 0 && inicio == fin) {
      return 'Con recargo nocturno mayor que 0, el inicio y el fin de la '
          'ventana no pueden ser iguales.';
    }

    final gracia = parseEntero(_cfgCtrl('gracia_espera_min').text);
    if (gracia == null || gracia < 0 || gracia > 30) {
      return 'La gracia de espera debe ser un entero entre 0 y 30 minutos.';
    }
    final topeEspera = parseNumero(_cfgCtrl('tope_cobro_espera').text);
    if (topeEspera == null || topeEspera < 0) {
      return 'El tope de cobro por espera debe ser ≥ 0.';
    }

    final prima = parseNumero(_cfgCtrl('prima_distancia_cup').text);
    if (prima == null || prima < 0) {
      return 'La prima por distancia debe ser ≥ 0.';
    }
    final umbralPrima = parseNumero(_cfgCtrl('umbral_prima_distancia_km').text);
    if (umbralPrima == null || umbralPrima < 0) {
      return 'El umbral de la prima por distancia debe ser ≥ 0.';
    }

    final descuento = parseNumero(_cfgCtrl('descuento_pago_wallet_pct').text);
    if (descuento == null || descuento < 0 || descuento > 100) {
      return 'El descuento por pago con wallet debe estar entre 0 y 100 %.';
    }

    final fallbackFijo = parseNumero(
      _cfgCtrl('monto_fijo_fallback_municipio').text,
    );
    if (fallbackFijo == null || fallbackFijo < 0 || fallbackFijo > 20000) {
      return 'El monto fijo de respaldo debe estar entre 0 y 20 000 CUP.';
    }
    final fallbackKm = parseNumero(_cfgCtrl('precio_km_fallback').text);
    if (fallbackKm == null || fallbackKm < 0 || fallbackKm > 5000) {
      return 'El precio por km de respaldo debe estar entre 0 y 5 000 CUP.';
    }

    return null;
  }

  Future<void> _guardarTipo(Map<String, dynamic> tipo) async {
    final id = (tipo['id'] as num).toInt();
    final nombre = _nombreTipo(tipo);
    final mult = parseNumero(_multCtrls[id]?.text ?? '');
    final orden = parseEntero(_ordenCtrls[id]?.text ?? '');

    if (mult == null) {
      _snack('El multiplicador de $nombre debe ser un número.', false);
      return;
    }
    if (mult < MueveteTarifasService.multiplicadorMin ||
        mult > MueveteTarifasService.multiplicadorMax) {
      _snack(
        'El multiplicador de $nombre debe estar entre 0.10 y 5.00.',
        false,
      );
      return;
    }
    if (orden == null || orden < 0) {
      _snack(
        'El orden de $nombre debe ser un entero mayor o igual a 0.',
        false,
      );
      return;
    }

    setState(() => _tiposGuardando.add(id));
    try {
      final multActual = (tipo['multiplicador_tarifa'] as num?)?.toDouble();
      final ordenActual = (tipo['orden'] as num?)?.toInt();
      if (multActual == null || mult.compareTo(multActual) != 0) {
        await MueveteTarifasService.actualizarMultiplicador(id, mult);
      }
      if (ordenActual == null || orden != ordenActual) {
        await MueveteTarifasService.actualizarOrden(id, orden);
      }
      _snack(
        '$nombre actualizado: ×${mult.toStringAsFixed(2)} · orden $orden.',
        true,
      );
      await _cargarTipos();
    } on MueveteTarifasException catch (e) {
      _snack(e.mensaje, false);
    } catch (e) {
      _snack('No se pudo guardar $nombre: $e', false);
    } finally {
      if (mounted) setState(() => _tiposGuardando.remove(id));
    }
  }

  Future<void> _guardarMunicipio(Map<String, dynamic> fila) async {
    final id = (fila['id'] as num).toInt();
    final municipio = (fila['municipio'] as String?) ?? '—';
    final monto = parseNumero(_munFijoCtrls[id]?.text ?? '');
    final precioKm = parseNumero(_munKmCtrls[id]?.text ?? '');
    final modo = _munModo[id] ?? 'fijo';

    if (monto == null || monto < 0) {
      _snack('El monto fijo de $municipio debe ser un número ≥ 0.', false);
      return;
    }
    if (precioKm == null || precioKm < 0) {
      _snack('El precio por km de $municipio debe ser un número ≥ 0.', false);
      return;
    }
    if (modo == 'por_km' && precioKm <= 0) {
      _snack(
        'Con modo "por km", el precio por km de $municipio debe ser '
        'mayor que 0.',
        false,
      );
      return;
    }

    setState(() => _munGuardando.add(id));
    try {
      await MueveteTarifasService.guardarMunicipio({
        'provincia': fila['provincia'],
        'municipio': fila['municipio'],
        'modo': modo,
        'monto_fijo': monto,
        'precio_km': precioKm,
        'activo': _munActivo[id] ?? true,
      });
      _snack(
        'Tarifa de $municipio guardada: ${fmtCup(monto)} · '
        '${fmtCup(precioKm)}/km.',
        true,
      );
      await _cargarMunicipios();
    } on MueveteTarifasException catch (e) {
      _snack(e.mensaje, false);
    } catch (e) {
      _snack('No se pudo guardar la tarifa de $municipio: $e', false);
    } finally {
      if (mounted) setState(() => _munGuardando.remove(id));
    }
  }

  Future<void> _marcarPrecioRevisado() async {
    final confirmado = await _confirmar(
      titulo: 'Marcar precio como revisado',
      mensaje:
          'Se actualiza "precio vigente desde" a hoy. No cambia ningún '
          'monto; sólo reinicia el recordatorio de revisión de precio.',
      etiqueta: 'Marcar revisado',
    );
    if (confirmado != true) return;

    setState(() => _cfgGuardando = true);
    try {
      await MueveteTarifasService.actualizarConfiguracion({
        'precio_vigente_desde': DateTime.now().toUtc().toIso8601String(),
      });
      await _cargarConfig();
      _snack('Precio marcado como revisado hoy.', true);
    } on MueveteTarifasException catch (e) {
      _snack(e.mensaje, false);
    } catch (e) {
      _snack('No se pudo actualizar la fecha de vigencia: $e', false);
    } finally {
      if (mounted) setState(() => _cfgGuardando = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Simulador
  // ═══════════════════════════════════════════════════════════════════════

  void _usarCentroSantaClara({required bool origen}) {
    final lat = MueveteTarifasService.santaClaraLat.toStringAsFixed(5);
    final lon = MueveteTarifasService.santaClaraLon.toStringAsFixed(5);
    setState(() {
      if (origen) {
        _simLatOCtrl.text = lat;
        _simLonOCtrl.text = lon;
      } else {
        _simLatDCtrl.text = lat;
        _simLonDCtrl.text = lon;
      }
      _simError = null;
    });
  }

  /// Una fila del trayecto: etiqueta + latitud + longitud + atajo al centro.
  Widget _filaPunto(
    String titulo,
    TextEditingController lat,
    TextEditingController lon, {
    required bool esOrigen,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 66,
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        _campo(lat, 'Latitud', ancho: 150),
        _campo(lon, 'Longitud', ancho: 150),
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            onPressed: () => _usarCentroSantaClara(origen: esOrigen),
            icon: const Icon(Icons.my_location_rounded, size: 16),
            label: const Text(
              'Usar centro de Santa Clara',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.secondary,
              side: BorderSide(
                color: AppColors.secondary.withValues(alpha: 0.4),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _simular() async {
    final latO = parseNumero(_simLatOCtrl.text);
    final lonO = parseNumero(_simLonOCtrl.text);
    final latD = parseNumero(_simLatDCtrl.text);
    final lonD = parseNumero(_simLonDCtrl.text);
    final km =
        _simKmCtrl.text.trim().isEmpty ? null : parseNumero(_simKmCtrl.text);

    if (latO == null || lonO == null) {
      setState(() => _simError = 'Las coordenadas de origen no son válidas.');
      return;
    }
    if (latD == null || lonD == null) {
      setState(() => _simError = 'Las coordenadas de destino no son válidas.');
      return;
    }
    if (_simKmCtrl.text.trim().isNotEmpty && (km == null || km <= 0)) {
      setState(
        () =>
            _simError =
                'Los km deben ser un número mayor que 0, o quedar vacíos.',
      );
      return;
    }
    final idTipo = _simTipoId;
    if (idTipo == null) {
      setState(() => _simError = 'Selecciona un tipo de vehículo.');
      return;
    }

    // Si se fuerza el nocturno se manda un `p_at` a las 23:00 de hoy.
    DateTime? at;
    if (_simNocturno) {
      final ahora = DateTime.now();
      at = DateTime(ahora.year, ahora.month, ahora.day, 23, 0);
    }

    setState(() {
      _simCargando = true;
      _simError = null;
      _simResultado = null;
    });
    try {
      final resultado = await MueveteTarifasService.simular(
        latOrigen: latO,
        lonOrigen: lonO,
        latDestino: latD,
        lonDestino: lonD,
        idTipo: idTipo,
        km: km,
        provincia: _simProvinciaCtrl.text,
        municipio: _simMunicipioCtrl.text,
        at: at,
      );
      if (!mounted) return;
      setState(() {
        _simResultado = resultado;
        _simCargando = false;
      });
    } on MueveteTarifasException catch (e) {
      if (!mounted) return;
      setState(() {
        _simError = e.mensaje;
        _simCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _simError = 'No se pudo simular la cotización: $e';
        _simCargando = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Helpers de UI
  // ═══════════════════════════════════════════════════════════════════════

  void _snack(String mensaje, bool ok) {
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

  String _textoDe(Object? valor) {
    if (valor == null) return '';
    if (valor is num) {
      final d = valor.toDouble();
      if (d == d.roundToDouble()) return d.toStringAsFixed(0);
      return d.toString();
    }
    return valor.toString();
  }

  /// `22:00:00` → `22:00`.
  String _textoHora(Object? valor) {
    final texto = valor?.toString() ?? '';
    if (texto.length >= 5 && texto.contains(':')) return texto.substring(0, 5);
    return texto;
  }

  String _nombreTipo(Map<String, dynamic> tipo) {
    final ui = (tipo['nombre_ui'] as String?)?.trim();
    if (ui != null && ui.isNotEmpty) return ui;
    final t = (tipo['tipo'] as String?) ?? 'Vehículo';
    return t.isEmpty ? 'Vehículo' : t[0].toUpperCase() + t.substring(1);
  }

  IconData _iconoTipo(String? tipo) {
    switch (tipo) {
      case 'auto':
        return Icons.directions_car_rounded;
      case 'minivan':
        return Icons.airport_shuttle_rounded;
      case 'microbus':
        return Icons.directions_bus_rounded;
      case 'moto':
        return Icons.two_wheeler_rounded;
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

  // ═══════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(ancho);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
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
                  Icons.local_taxi_rounded,
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
                      'Tarifas y Zonas',
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
            // Enlace al editor de polígonos (H6, segunda mitad).
            if (isDesktop)
              TextButton.icon(
                onPressed:
                    () => Navigator.of(context).pushNamed('/muevete/zonas'),
                icon: const Icon(Icons.polyline_rounded, size: 17),
                label: const Text(
                  'Editar zonas en el mapa',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              )
            else
              IconButton(
                tooltip: 'Editar zonas en el mapa',
                onPressed:
                    () => Navigator.of(context).pushNamed('/muevete/zonas'),
                icon: const Icon(
                  Icons.polyline_rounded,
                  color: AppColors.primary,
                ),
              ),
            IconButton(
              tooltip: 'Recargar todo',
              onPressed: _recargarTodo,
              icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(height: 44, text: 'Parámetros globales'),
              Tab(height: 44, text: 'Multiplicadores'),
              Tab(height: 44, text: 'Municipios'),
              Tab(height: 44, text: 'Simulador'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tabParametros(isDesktop),
            _tabMultiplicadores(isDesktop),
            _tabMunicipios(isDesktop),
            _tabSimulador(isDesktop),
          ],
        ),
      ),
    );
  }

  String _resumenCabecera() {
    final partes = <String>[];
    if (_cfg != null) {
      partes.add('comisión ${fmtPct(_cfg!['comision_pct'] as num?)}');
    }
    if (!_tiposCargando && _tipos.isNotEmpty) {
      partes.add('${_tipos.length} tipos');
    }
    if (!_munCargando && _municipios.isNotEmpty) {
      partes.add('${_municipios.length} municipios');
    }
    if (_taxiActivo) {
      partes.add('precio fijo ACTIVO');
    } else {
      partes.add('precio fijo apagado');
    }
    return partes.isEmpty ? 'Configuración tarifaria' : partes.join(' · ');
  }

  Widget _contenedor({required List<Widget> hijos, bool isDesktop = true}) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: hijos,
          ),
        ),
      ),
    );
  }

  // ─── Tab 1: parámetros globales ──────────────────────────────────────

  Widget _tabParametros(bool isDesktop) {
    if (_cfgCargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cfgError != null) {
      return _EstadoError(mensaje: _cfgError!, onReintentar: _cargarConfig);
    }
    if (_cfg == null) {
      return const _EstadoVacio(
        icono: Icons.tune_rounded,
        titulo: 'Sin configuración',
        mensaje: 'No se encontró la fila única de configuración tarifaria.',
      );
    }

    return _contenedor(
      isDesktop: isDesktop,
      hijos: [
        _bannerVigencia(),
        const SizedBox(height: 14),
        _seccion('Comisión y topes', Icons.percent_rounded, [
          _campo(
            _cfgCtrl('comision_pct'),
            'Comisión (%)',
            hint: '0 – 30',
            sufijo: '%',
          ),
          _campo(
            _cfgCtrl('tope_comision_viaje'),
            'Tope por viaje',
            hint: '0 = sin tope',
            sufijo: 'CUP',
          ),
          _campo(
            _cfgCtrl('recarga_pct'),
            'Recargo por recarga (%)',
            hint: '11',
            sufijo: '%',
          ),
          _campo(
            _cfgCtrl('descuento_pago_wallet_pct'),
            'Descuento wallet (%)',
            hint: '5',
            sufijo: '%',
          ),
          _campo(_cfgCtrl('moneda'), 'Moneda', hint: 'CUP'),
        ]),
        _seccion('Precios mínimos y viaje corto', Icons.price_change_rounded, [
          _campo(_cfgCtrl('precio_minimo_auto'), 'Mínimo auto', sufijo: 'CUP'),
          _campo(_cfgCtrl('precio_minimo_moto'), 'Mínimo moto', sufijo: 'CUP'),
          _campo(
            _cfgCtrl('precio_minimo_microbus'),
            'Mínimo microbús',
            sufijo: 'CUP',
          ),
          _campo(
            _cfgCtrl('precio_corto_auto'),
            'Precio corto (auto)',
            sufijo: 'CUP',
          ),
          _campo(
            _cfgCtrl('umbral_km_corto'),
            'Umbral viaje corto',
            sufijo: 'km',
          ),
        ]),
        _seccion('Nocturno y espera', Icons.nightlight_round, [
          _campo(
            _cfgCtrl('recargo_nocturno_pct'),
            'Recargo nocturno (%)',
            sufijo: '%',
          ),
          _campo(
            _cfgCtrl('ventana_nocturna_inicio'),
            'Inicio ventana',
            hint: '22:00',
          ),
          _campo(
            _cfgCtrl('ventana_nocturna_fin'),
            'Fin ventana',
            hint: '06:00',
          ),
          _campo(
            _cfgCtrl('gracia_espera_min'),
            'Gracia de espera',
            sufijo: 'min',
          ),
          _campo(
            _cfgCtrl('tope_cobro_espera'),
            'Tope de espera',
            sufijo: 'CUP',
          ),
        ]),
        _seccion('Distancia y redondeo', Icons.straighten_rounded, [
          _campo(
            _cfgCtrl('prima_distancia_cup'),
            'Prima por distancia',
            sufijo: 'CUP',
          ),
          _campo(
            _cfgCtrl('umbral_prima_distancia_km'),
            'Umbral de la prima',
            sufijo: 'km',
          ),
          _dropdownRedondeo(),
        ]),
        _seccion('Respaldo municipal (fallback)', Icons.location_city_rounded, [
          _campo(
            _cfgCtrl('monto_fijo_fallback_municipio'),
            'Monto fijo',
            sufijo: 'CUP',
          ),
          _campo(
            _cfgCtrl('precio_km_fallback'),
            'Precio por km',
            sufijo: 'CUP/km',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Se usa sólo cuando el origen no cae en ninguna zona activa y el '
              'municipio tampoco tiene fila en la tabla de municipios.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ]),
        _seccion('Deuda y estado del servicio', Icons.toggle_on_rounded, [
          _switchCampo(
            titulo: 'Permitir deuda del chofer',
            subtitulo:
                'Si está apagado, el chofer se bloquea al llegar a saldo 0.',
            valor: _permiteDeuda,
            onChanged: (v) => setState(() => _permiteDeuda = v),
          ),
          _campo(
            _cfgCtrl('limite_deuda_efectivo'),
            'Límite de deuda',
            hint: '500 al lanzar, 1 000 después',
            sufijo: 'CUP',
          ),
          _campo(_cfgCtrl('dias_max_deuda'), 'Días máximos de deuda'),
          _switchCampo(
            titulo: 'Cobro con precio fijo activo',
            subtitulo:
                _taxiActivo
                    ? 'Encendido: se cobra con tarifa fija y el cliente no negocia.'
                    : 'Apagado: la app nueva muestra "servicio en mantenimiento".',
            valor: _taxiActivo,
            color: _taxiActivo ? AppColors.success : AppColors.warning,
            onChanged: _cambiarInterruptorCorte,
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 220,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _cfgGuardando ? null : _cargarConfig,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Descartar cambios'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 260,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _cfgGuardando ? null : _guardarConfig,
                icon:
                    _cfgGuardando
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  _cfgGuardando ? 'Guardando…' : 'Guardar parámetros',
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _cambiarInterruptorCorte(bool valor) async {
    final confirmado = await _confirmar(
      titulo: valor ? 'Activar cobro con precio fijo' : 'Apagar precio fijo',
      mensaje:
          valor
              ? 'Al encenderlo, todas las cotizaciones nuevas se cobran con tarifa '
                  'fija y las apps viejas dejan de poder negociar. ¿Confirmas el '
                  'corte?'
              : 'Al apagarlo, la app nueva mostrará "servicio en mantenimiento" y '
                  'vuelve el modo anterior. ¿Confirmas apagarlo?',
      etiqueta: valor ? 'Activar' : 'Apagar',
      destructivo: !valor,
    );
    if (confirmado == true) {
      setState(() => _taxiActivo = valor);
    }
  }

  Widget _bannerVigencia() {
    final actualizado = fmtFechaHora(_cfg?['updated_at'] as String?);
    final vigente = DateTime.tryParse(
      (_cfg?['precio_vigente_desde'] as String?) ?? '',
    );
    final dias =
        vigente == null
            ? null
            : DateTime.now().difference(vigente.toLocal()).inDays;
    final vencido = dias != null && dias > 30;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (vencido ? AppColors.warning : AppColors.info).withValues(
          alpha: 0.06,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (vencido ? AppColors.warning : AppColors.info).withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            vencido ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            size: 18,
            color: vencido ? AppColors.warning : AppColors.info,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Precio vigente desde ${fmtFechaHora(_cfg?['precio_vigente_desde'] as String?)}'
                  ' · última edición $actualizado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  vencido
                      ? 'Han pasado $dias días desde la última revisión de precio '
                          '(el plan recomienda revisar cada 30 días).'
                      : 'Revisa los montos cada 30 días; los cambios aplican sin '
                          'recompilar las apps.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _cfgGuardando ? null : _marcarPrecioRevisado,
            child: const Text('Marcar revisado'),
          ),
        ],
      ),
    );
  }

  // ─── Tab 2: multiplicadores ──────────────────────────────────────────

  Widget _tabMultiplicadores(bool isDesktop) {
    if (_tiposCargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tiposError != null) {
      return _EstadoError(mensaje: _tiposError!, onReintentar: _cargarTipos);
    }
    if (_tipos.isEmpty) {
      return const _EstadoVacio(
        icono: Icons.directions_car_rounded,
        titulo: 'Sin tipos de vehículo activos',
        mensaje:
            'Activa al menos un tipo de vehículo (status = true) para '
            'poder tarifarlo.',
      );
    }

    return _contenedor(
      isDesktop: isDesktop,
      hijos: [
        _bannerComision(),
        const SizedBox(height: 14),
        ..._tipos.map(_tarjetaTipo),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _bannerComision() {
    final comision = _cfg?['comision_pct'] as num?;
    final tope = _cfg?['tope_comision_viaje'] as num?;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.percent_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comisión vigente: ${fmtPct(comision)}'
                  '${tope != null && tope > 0 ? ' · tope ${fmtCup(tope)} por viaje' : ' · sin tope'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'El multiplicador escala la tarifa de la zona o del municipio '
                  'antes de calcular la comisión. 1.00 = tarifa base.',
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

  Widget _tarjetaTipo(Map<String, dynamic> tipo) {
    final id = (tipo['id'] as num).toInt();
    final guardando = _tiposGuardando.contains(id);
    final mult = (tipo['multiplicador_tarifa'] as num?)?.toDouble() ?? 1.0;
    final pasajeros = (tipo['pasajeros_max'] as num?)?.toInt();

    return Container(
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
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconoTipo(tipo['tipo'] as String?),
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nombreTipo(tipo),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${tipo['tipo'] ?? '—'}'
                      '${pasajeros != null ? ' · $pasajeros pasajeros' : ''}'
                      ' · comisión ${fmtPct(_cfg?['comision_pct'] as num?)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
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
                  '×${mult.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _campo(
                _multCtrls[id]!,
                'Multiplicador',
                ancho: 150,
                sufijo: '×',
                habilitado: !guardando,
              ),
              _campo(
                _ordenCtrls[id]!,
                'Orden',
                ancho: 110,
                habilitado: !guardando,
              ),
              SizedBox(
                height: 46,
                width: 150,
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
            ],
          ),
        ],
      ),
    );
  }

  // ─── Tab 3: municipios ───────────────────────────────────────────────

  Widget _tabMunicipios(bool isDesktop) {
    if (_munCargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_munError != null) {
      return _EstadoError(mensaje: _munError!, onReintentar: _cargarMunicipios);
    }
    if (_municipios.isEmpty) {
      return const _EstadoVacio(
        icono: Icons.location_city_rounded,
        titulo: 'Sin tarifas municipales',
        mensaje:
            'No hay filas en la tabla de municipios. Se usará el respaldo '
            'global hasta que crees alguna.',
      );
    }

    return _contenedor(
      isDesktop: isDesktop,
      hijos: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'El fallback municipal se aplica cuando el origen no cae en '
                  'ninguna zona activa. Santa Clara arranca en 1 500 CUP fijos y '
                  '400 CUP/km.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cabeceraMunicipios(),
                ..._municipios.map(_filaMunicipio),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  static const double _wProvincia = 150;
  static const double _wMunicipio = 160;
  static const double _wModo = 180;
  static const double _wMonto = 150;
  static const double _wKm = 140;
  static const double _wActivo = 90;
  static const double _wAccion = 130;

  Widget _cabeceraMunicipios() {
    Widget celda(String texto, double ancho) => SizedBox(
      width: ancho,
      child: Text(
        texto.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textSecondary,
        ),
      ),
    );

    return Container(
      color: AppColors.surfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          celda('Provincia', _wProvincia),
          celda('Municipio', _wMunicipio),
          celda('Modo', _wModo),
          celda('Monto fijo', _wMonto),
          celda('Precio / km', _wKm),
          celda('Activo', _wActivo),
          celda('', _wAccion),
        ],
      ),
    );
  }

  Widget _filaMunicipio(Map<String, dynamic> fila) {
    final id = (fila['id'] as num).toInt();
    final guardando = _munGuardando.contains(id);
    final activo = _munActivo[id] ?? true;
    final modo = _munModo[id] ?? 'fijo';

    Widget celda(Widget hijo, double ancho) => SizedBox(
      width: ancho,
      child: Padding(padding: const EdgeInsets.only(right: 12), child: hijo),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: activo ? Colors.white : AppColors.surfaceVariant,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          celda(
            Text(
              (fila['provincia'] as String?) ?? '—',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            _wProvincia,
          ),
          celda(
            Text(
              (fila['municipio'] as String?) ?? '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            _wMunicipio,
          ),
          celda(
            DropdownButtonFormField<String>(
              // La clave fuerza a re-inicializar el campo cuando cambia el modo
              // guardado (por ejemplo, tras recargar la tabla).
              key: ValueKey('mun-modo-$id-$modo'),
              initialValue:
                  MueveteTarifasService.modosTarifa.contains(modo)
                      ? modo
                      : 'fijo',
              isExpanded: true,
              isDense: true,
              decoration: _decoracionCampo(null),
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              items:
                  MueveteTarifasService.modosTarifa
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m,
                          child: Text(
                            modoLabel(m),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
              onChanged:
                  guardando
                      ? null
                      : (v) => setState(() => _munModo[id] = v ?? 'fijo'),
            ),
            _wModo,
          ),
          celda(
            _campo(
              _munFijoCtrls[id]!,
              'Monto fijo',
              ancho: _wMonto - 12,
              habilitado: !guardando,
            ),
            _wMonto,
          ),
          celda(
            _campo(
              _munKmCtrls[id]!,
              'Precio / km',
              ancho: _wKm - 12,
              habilitado: !guardando,
            ),
            _wKm,
          ),
          celda(
            Switch(
              value: activo,
              activeThumbColor: AppColors.primary,
              onChanged:
                  guardando ? null : (v) => setState(() => _munActivo[id] = v),
            ),
            _wActivo,
          ),
          celda(
            SizedBox(
              height: 38,
              child: ElevatedButton(
                onPressed: guardando ? null : () => _guardarMunicipio(fila),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  guardando ? '…' : 'Guardar',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _wAccion,
          ),
        ],
      ),
    );
  }

  // ─── Tab 4: simulador ────────────────────────────────────────────────

  Widget _tabSimulador(bool isDesktop) {
    return _contenedor(
      isDesktop: isDesktop,
      hijos: [
        _seccion('Trayecto', Icons.route_rounded, [
          _filaPunto('Origen', _simLatOCtrl, _simLonOCtrl, esOrigen: true),
          _filaPunto('Destino', _simLatDCtrl, _simLonDCtrl, esOrigen: false),
        ]),
        _seccion('Vehículo y contexto', Icons.directions_car_filled_rounded, [
          _dropdownTipoVehiculo(),
          _campo(
            _simKmCtrl,
            'Km (opcional)',
            hint: 'vacío = haversine',
            ancho: 170,
          ),
          _campo(
            _simProvinciaCtrl,
            'Provincia (opcional)',
            hint: 'Villa Clara',
            ancho: 180,
          ),
          _campo(
            _simMunicipioCtrl,
            'Municipio (opcional)',
            hint: 'Santa Clara',
            ancho: 180,
          ),
          _switchCampo(
            titulo: 'Probar horario nocturno',
            subtitulo: 'Fuerza la cotización a las 23:00 de hoy.',
            valor: _simNocturno,
            onChanged: (v) => setState(() => _simNocturno = v),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          children: [
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _simCargando ? null : _simular,
                icon:
                    _simCargando
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.calculate_rounded, size: 18),
                label: Text(
                  _simCargando ? 'Simulando…' : 'Simular',
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
          ],
        ),
        const SizedBox(height: 16),
        if (_simError != null) _tarjetaErrorSimulacion(_simError!),
        if (_simResultado != null) _tarjetaResultado(_simResultado!),
        if (_simResultado == null && _simError == null && !_simCargando)
          const _EstadoVacio(
            icono: Icons.calculate_rounded,
            titulo: 'Sin simulación',
            mensaje:
                'Ajusta el trayecto y pulsa "Simular". El resultado viene '
                'calculado por el servidor (fn_cotizar_viaje).',
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _dropdownTipoVehiculo() {
    final items =
        _tipos
            .map(
              (t) => DropdownMenuItem<int>(
                value: (t['id'] as num).toInt(),
                child: Text(
                  '${_nombreTipo(t)} (×${((t['multiplicador_tarifa'] as num?) ?? 1).toStringAsFixed(2)})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            )
            .toList();

    return SizedBox(
      width: 240,
      child: DropdownButtonFormField<int>(
        key: ValueKey('sim-tipo-$_simTipoId'),
        initialValue:
            items.any((i) => i.value == _simTipoId) ? _simTipoId : null,
        isExpanded: true,
        isDense: true,
        decoration: _decoracionCampo('Tipo de vehículo'),
        style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
        hint: const Text('Selecciona un tipo', style: TextStyle(fontSize: 12)),
        items: items,
        onChanged: items.isEmpty ? null : (v) => setState(() => _simTipoId = v),
      ),
    );
  }

  Widget _tarjetaErrorSimulacion(String mensaje) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Lectura del jsonb de la cotización ─────────────────────────────

  /// Busca la clave en la raíz del jsonb y, si no está, dentro de `detalle`.
  Object? _valorCotizacion(Map<String, dynamic> cotizacion, String clave) {
    final directo = cotizacion[clave];
    if (directo != null) return directo;
    final detalle = cotizacion['detalle'];
    if (detalle is Map) return detalle[clave];
    return null;
  }

  num? _numCotizacion(Map<String, dynamic> c, String clave) {
    final valor = _valorCotizacion(c, clave);
    if (valor is num) return valor;
    if (valor is String) return double.tryParse(valor);
    return null;
  }

  String? _strCotizacion(Map<String, dynamic> c, String clave) {
    final valor = _valorCotizacion(c, clave);
    return valor?.toString();
  }

  bool? _boolCotizacion(Map<String, dynamic> c, String clave) {
    final valor = _valorCotizacion(c, clave);
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;
    if (valor is String) return valor.toLowerCase() == 'true';
    return null;
  }

  String _etiquetaZona(Map<String, dynamic> c) {
    final fallback = _boolCotizacion(c, 'fallback_municipio') ?? false;
    final dentro = _boolCotizacion(c, 'dentro_de_zona');
    final nombre = _strCotizacion(c, 'zona_nombre');
    final municipio = _strCotizacion(c, 'municipio_aplicado');

    if (fallback) {
      return 'Tarifa municipal de respaldo'
          '${municipio != null && municipio != 'null' ? ' ($municipio)' : ''}';
    }
    if (dentro == false) return 'Tarifa municipal (fuera de zona)';
    if (nombre != null && nombre != 'null' && nombre.isNotEmpty) return nombre;
    return 'Tarifa municipal';
  }

  Widget _tarjetaResultado(Map<String, dynamic> r) {
    final precio = _numCotizacion(r, 'precio_plataforma');
    final comisionPct = _numCotizacion(r, 'comision_pct');
    final comisionMonto = _numCotizacion(r, 'comision_monto');
    final chofer = _numCotizacion(r, 'precio_chofer');
    final modo = _strCotizacion(r, 'tarifa_modo');
    final kmTotal = _numCotizacion(r, 'km_total');
    final kmFuente = _strCotizacion(r, 'km_fuente');
    final esNocturno = _boolCotizacion(r, 'es_nocturno') ?? false;
    final recargoNocturno = _numCotizacion(r, 'recargo_nocturno');
    final precioCorto =
        _boolCotizacion(r, 'precio_corto_aplicado') ??
        _boolCotizacion(r, 'precio_corto') ??
        false;
    final redondeo = _numCotizacion(r, 'redondeo_cup');
    final antesRedondeo = _numCotizacion(r, 'precio_antes_redondeo');
    final multiplicador = _numCotizacion(r, 'multiplicador_tipo');
    final moneda = _strCotizacion(r, 'moneda') ?? 'CUP';
    final tipo = _strCotizacion(r, 'tipo_vehiculo');
    final calculadoAt = _strCotizacion(r, 'calculado_at');
    final fallback = _boolCotizacion(r, 'fallback_municipio') ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera con el precio grande
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Cotización del servidor',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        moneda,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'El cliente paga',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                Text(
                  precio == null ? '—' : '${_miles(precio.round())} CUP',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (tipo != null)
                  Text(
                    'Vehículo: $tipo',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),

          if (fallback)
            Container(
              color: AppColors.warning.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Se aplicó la tarifa municipal de respaldo: el origen no '
                      'cayó en ninguna zona de tarifa.',
                      style: TextStyle(fontSize: 11, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Column(
              children: [
                _filaResultado(
                  'Comisión',
                  fmtPct(comisionPct),
                  detalle:
                      comisionMonto == null
                          ? null
                          : '-${fmtCup(comisionMonto)}',
                  color: AppColors.warning,
                ),
                _filaResultado(
                  'Neto del chofer',
                  fmtCup(chofer),
                  detalle: 'lo que recibe al completar el viaje',
                  color: AppColors.success,
                  destacado: true,
                ),
                Divider(height: 20, color: AppColors.divider),
                _filaResultado('Modo de tarifa', modoLabel(modo)),
                _filaResultado(
                  'Zona aplicada',
                  _etiquetaZona(r),
                  detalle:
                      _boolCotizacion(r, 'dentro_de_zona') ?? false
                          ? 'origen dentro de la zona'
                          : 'origen fuera de las zonas activas',
                ),
                _filaResultado(
                  'Km aplicados',
                  fmtKm(kmTotal),
                  detalle:
                      kmFuente == null
                          ? null
                          : kmFuente == 'ruta'
                          ? 'distancia de la ruta'
                          : 'distancia en línea recta (haversine)',
                ),
                _filaResultado(
                  'Recargo nocturno',
                  esNocturno ? fmtCup(recargoNocturno) : '—',
                  detalle:
                      esNocturno
                          ? 'cotización dentro de la ventana nocturna'
                          : 'no aplica a esta hora',
                ),
                _filaResultado(
                  'Precio corto',
                  precioCorto ? 'Sí' : 'No',
                  detalle:
                      precioCorto ? 'viaje por debajo del umbral corto' : null,
                ),
                _filaResultado(
                  'Redondeo',
                  redondeo == null || redondeo == 0
                      ? 'Sin redondeo'
                      : '${_miles(redondeo.round())} CUP',
                  detalle:
                      antesRedondeo == null
                          ? null
                          : 'antes: ${fmtCup(antesRedondeo)}',
                ),
                _filaResultado(
                  'Multiplicador del tipo',
                  '×${fmtNum(multiplicador)}',
                  detalle: 'escala la tarifa base antes de la comisión',
                ),
                Divider(height: 20, color: AppColors.divider),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Calculado por fn_cotizar_viaje · ${fmtFechaHora(calculadoAt)}',
                    style: TextStyle(fontSize: 10, color: AppColors.textHint),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaResultado(
    String etiqueta,
    String valor, {
    String? detalle,
    Color? color,
    bool destacado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                    fontSize: destacado ? 13 : 12,
                    fontWeight: destacado ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (detalle != null)
                  Text(
                    detalle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            valor,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: destacado ? 16 : 13,
              fontWeight: destacado ? FontWeight.w800 : FontWeight.w700,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Piezas reutilizables
  // ═══════════════════════════════════════════════════════════════════════

  InputDecoration _decoracionCampo(String? label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
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
    );
  }

  Widget _campo(
    TextEditingController controller,
    String label, {
    String? hint,
    String? sufijo,
    double ancho = 190,
    bool habilitado = true,
  }) {
    return SizedBox(
      width: ancho,
      child: TextField(
        controller: controller,
        enabled: habilitado,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        decoration: _decoracionCampo(label).copyWith(
          hintText: hint,
          suffixText: sufijo,
          hintStyle: TextStyle(fontSize: 11, color: AppColors.textHint),
          suffixStyle: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _dropdownRedondeo() {
    final items =
        MueveteTarifasService.redondeosPermitidos
            .map(
              (v) => DropdownMenuItem<int>(
                value: v,
                child: Text(
                  v == 0 ? 'Sin redondeo' : '${_miles(v)} CUP',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            )
            .toList();

    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<int>(
        key: ValueKey('redondeo-$_redondeo'),
        initialValue: items.any((i) => i.value == _redondeo) ? _redondeo : 50,
        isExpanded: true,
        isDense: true,
        decoration: _decoracionCampo('Redondeo del precio'),
        style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
        items: items,
        onChanged: (v) => setState(() => _redondeo = v ?? 50),
      ),
    );
  }

  Widget _seccion(String titulo, IconData icono, List<Widget> hijos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icono, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: hijos,
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchCampo({
    required String titulo,
    required String subtitulo,
    required bool valor,
    required ValueChanged<bool> onChanged,
    Color? color,
  }) {
    final activo = color ?? AppColors.primary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitulo,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: valor, activeThumbColor: activo, onChanged: onChanged),
        ],
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
