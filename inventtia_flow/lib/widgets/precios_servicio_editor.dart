// Editor de precios compartido por el formulario de servicio y la pestaña
// «Precios» de `LocalServicioAdminScreen`.
//
// Este bloque vivía dentro de `ServicioFormSheetState`
// (`screens/admin/gestion_servicios_screen.dart`, sección «Precio del
// servicio»). Se extrajo aquí **sin cambios de comportamiento** porque dos
// pantallas necesitan exactamente lo mismo: monedas habilitadas, precio base
// por moneda, cálculo automático con la tasa del día y reglas de precio por
// dato adicional. Mantener dos copias habría garantizado que se separaran a la
// primera corrección (y el cálculo de precios cobra: una diferencia entre la
// copia del formulario y la de la pestaña es un precio mal guardado).
//
// La API pública de [PreciosServicioControlador] y [PreciosServicioEditor] es
// un CONTRATO con los dos hosts: no cambiar nombres, firmas ni orden de
// parámetros. Los helpers privados son libres.

import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/config_precio.dart';
import '../models/precio_config.dart';
import '../models/tasa_cambio.dart';
import '../services/tasa_cambio_service.dart';
import '../tutorial/tutorial_anchor.dart';
import '../utils/conversion_precio.dart';
import '../utils/parse_monto.dart';

/// Campo seleccionable del servicio que puede llevar reglas de precio.
///
/// `slug` es el slug base de la etiqueta (lo que se guarda como `si_clave`
/// mientras se edita, igual que hoy) y `clave` la clave **final** del campo en
/// `campos_adicionales` (la que va al `config_precio` guardado).
typedef CampoSelectPrecio = ({
  String slug,
  String clave,
  String etiqueta,
  List<String> opciones,
});

/// Estado y lógica del bloque de precios de un servicio.
///
/// Es un [ChangeNotifier] porque lo comparten dos hosts distintos:
///
///  * el formulario de alta/edición (`ServicioFormSheet`), donde el bloque de
///    precios es una sección más del formulario;
///  * la pestaña «Precios» de `LocalServicioAdminScreen`, donde el bloque es
///    toda la pantalla y solo se guardan precios.
///
/// El host crea el controlador (y lo `dispose()`a); el editor le engancha
/// [avisar], [mostrarCartelExtraccion] y [cerrarCartelExtraccion] al montarse.
class PreciosServicioControlador extends ChangeNotifier {
  PreciosServicioControlador({
    ConfigPrecio? configInicial,
    List<CampoSelectPrecio> camposSelect = const [],
    PrecioConfig configEntidad = const PrecioConfig(),
    bool configEntidadLista = false,
    bool proponerMonedaOrigen = false,
  }) : _camposSelect = [...camposSelect],
       _precioConfig = configEntidad,
       _configCargada = configEntidadLista,
       _proponeMonedaBase = proponerMonedaOrigen,
       _monedasHabilitadas = _monedasDe(configInicial),
       _monedaDefault = _monedaDefaultDe(configInicial) {
    // Se parte SIEMPRE de lo guardado en el servicio (o de los valores por
    // defecto del modelo). Nada de esto toca la red: el controlador se puede
    // construir y probar sin Supabase.
    final cfg = configInicial ?? ConfigPrecio();
    _aplicaPrecioIdaVueltaTodos = cfg.aplicaPrecioIdaVueltaTodos;
    for (final m in _monedasHabilitadas) {
      _precioBaseCtrls[m] = TextEditingController(
        text: _fmtPrecio(cfg.preciosBase[m]),
      );
    }
    // Las reglas arrancan con las claves guardadas como opciones; el tile las
    // resincroniza con las opciones reales del campo en cuanto se pinta (ver
    // `_ReglaPrecioTile`), que es lo que permite enseñar opciones nuevas sin
    // perder los precios que ya tenían valor.
    _reglasPrecio.addAll(
      cfg.reglas.map(
        (r) => _ReglaPrecioEditable.fromModel(r, monedas: _monedasHabilitadas),
      ),
    );
    // Si el host ya trae leída la configuración de la entidad, se aprovecha
    // para proponer la moneda base. A propósito NO se programa aquí el cálculo
    // automático: en el constructor todavía no hay nada tecleado y un `Timer`
    // suelto dispararía una llamada de red (o un Timer pendiente en las
    // pruebas); el host que la aplica más tarde usa
    // [actualizarConfigEntidad], que sí reprograma el cálculo.
    if (_configCargada) _proponerMonedaDeEntidad();
  }

  /// Monedas habilitadas al abrir: las guardadas o, si no hay ninguna, USD.
  static List<String> _monedasDe(ConfigPrecio? cfg) {
    final monedas = cfg?.monedas ?? const <String>[];
    return monedas.isEmpty ? ['USD'] : [...monedas];
  }

  /// Moneda base al abrir.
  ///
  /// Un `moneda_default` que no está en la lista (p. ej. CUP se deshabilitó en
  /// otro dispositivo) dejaría el desplegable sin opción válida: el
  /// `DropdownButtonFormField` revienta si su valor no está entre los items, así
  /// que se cae a la primera moneda.
  static String _monedaDefaultDe(ConfigPrecio? cfg) {
    final monedas = _monedasDe(cfg);
    final guardada = cfg?.monedaDefault ?? 'USD';
    return monedas.contains(guardada) ? guardada : monedas.first;
  }

  /// Aviso corto al admin (SnackBar). Lo implementa el editor: el controlador
  /// no conoce `BuildContext`.
  void Function(String mensaje, Color? color)? avisar;

  /// Cartel modal, no descartable, mientras se extrae la tasa a mano.
  Future<void> Function()? mostrarCartelExtraccion;

  /// Cierra el cartel de [mostrarCartelExtraccion].
  void Function()? cerrarCartelExtraccion;

  /// ¿El servicio es de transporte en ómnibus?
  ///
  /// No cambia ningún cálculo —los precios y el `config_precio` se guardan
  /// igual—, pero sí qué ofrece la entidad: solo el transporte cobra «ida y
  /// vuelta», así que el editor pinta u oculta la casilla según este valor. Lo
  /// fija [PreciosServicioEditor] desde su propio parámetro: el editor es quien
  /// sabe si el host pidió la variante de transporte.
  bool esTransporteOmnibus = false;

  // ── Monedas y precios base ───────────────────────────────────────────────
  final List<String> _monedasHabilitadas;
  String _monedaDefault;
  final Map<String, TextEditingController> _precioBaseCtrls = {};
  final List<_ReglaPrecioEditable> _reglasPrecio = [];
  bool _aplicaPrecioIdaVueltaTodos = false;

  // ── Configuración de la entidad y cálculo automático ─────────────────────
  /// Configuración de redondeo de la entidad (y su moneda preferida, que solo
  /// se usa para **proponerla** al crear un servicio nuevo).
  PrecioConfig _precioConfig;

  /// La configuración ya se leyó (o falló): el cálculo automático no se dispara
  /// antes, para no usar valores por defecto que el admin no eligió.
  bool _configCargada;

  /// ¿La entidad propone su moneda de origen como base? Solo en el alta.
  final bool _proponeMonedaBase;

  /// Hay un cálculo de precios en curso (y el cartel de extracción abierto).
  bool _calculandoPrecios = false;

  /// Se está extrayendo la tasa: banner discreto dentro del formulario (el
  /// diálogo modal se reserva para el botón de recalcular a mano).
  bool _extrayendoTasa = false;

  /// Tasa con la que se calcularon los precios que hay ahora en el formulario.
  TasasDia? _tasasUsadas;

  /// Último valor YA calculado, por origen: «base|CUP» → 17000,
  /// «regla:0|USD» → 18.
  ///
  /// Es un mapa y no una única firma global (que es lo que había): con una sola
  /// firma, el cálculo de una moneda **bloqueaba** el de otra si coincidía el
  /// patrón, y por eso editar CUP después de haber editado USD no recalculaba
  /// nada. Ahora cada origen se compara consigo mismo.
  final Map<String, double> _ultimoCalculado = {};

  /// Monedas cuyo precio lo puso el cálculo automático: se pintan **en verde y
  /// con su icono**. Al editar ese campo a mano deja de estar marcado, porque el
  /// valor ya no lo calculó la app.
  final Set<String> _calculadas = {};

  /// El aviso de «no hay tasa» se da una vez por formulario: si no, escribir
  /// tres cifras seguidas sin red lanzaría tres avisos seguidos.
  bool _avisoTasaMostrado = false;

  /// Debounce del cálculo automático mientras el admin escribe.
  Timer? _debounceAuto;

  /// ¿Hay algo tocado desde el último [marcarComoGuardado]?
  bool _hayCambios = false;

  /// Mensaje del último [construir] fallido.
  String? _error;

  /// Campos seleccionables disponibles, ya resueltos por el host.
  List<CampoSelectPrecio> _camposSelect;

  /// El controlador ya se `dispose()`ó: cualquier callback diferido (el
  /// `Timer` del debounce, una respuesta de red que llega tarde) que siga vivo
  /// tiene que salir sin tocar el objeto, o `notifyListeners()` lanzaría.
  bool _disposeado = false;

  /// ¿Hay algo tocado desde el último [marcarComoGuardado]?
  bool get hayCambios => _hayCambios;

  /// Mensaje del último [construir] fallido; `null` si salió bien.
  String? get error => _error;

  /// Texto actual del precio base de [moneda] (`''` si no hay precio o la
  /// moneda no está habilitada).
  ///
  /// Es el mismo texto que pinta el `TextField` del editor; existe como API
  /// para que los hosts (y las pruebas del controlador) puedan leer lo que hay
  /// escrito sin depender del widget.
  String textoPrecioBase(String moneda) => _precioBaseCtrls[moneda]?.text ?? '';

  /// El admin escribió [texto] en el precio base de [moneda].
  ///
  /// El editor la llama desde el `onChanged` del campo (con el texto que ya
  /// tiene el controlador) y las pruebas la usan para escribir. Si el texto es
  /// el mismo no se reasigna el controlador: asignar `.text` siempre deja la
  /// selección al final y saltaría el cursor mientras se teclea.
  void editarPrecioBase(String moneda, String texto) {
    if (_disposeado) return;
    final ctrl = _precioBaseCtrls[moneda];
    if (ctrl == null) return;
    if (ctrl.text != texto) ctrl.text = texto;
    // Escrito a mano ⇒ este campo deja de ser «calculado» y pierde el verde.
    _calculadas.remove(moneda);
    _hayCambios = true;
    _notificar();
    // El gate de `autoActivo` vive dentro de `_programarCalculoAutomatico`,
    // que además no crea el Timer si el cálculo no podría correr.
    _programarCalculoAutomatico(moneda);
  }

  /// Activa o desactiva [moneda] en el servicio.
  ///
  /// Nunca deja la lista vacía: sin ninguna moneda no habría precios que
  /// guardar. Si se quita la moneda que era la base, la base pasa a ser la
  /// primera que quede (el desplegable no admite un valor fuera de la lista).
  void toggleMoneda(String moneda, bool on) {
    if (_disposeado) return;
    var cambio = false;
    if (on) {
      if (!_monedasHabilitadas.contains(moneda)) {
        _monedasHabilitadas.add(moneda);
        cambio = true;
      }
    } else if (_monedasHabilitadas.length > 1 &&
        _monedasHabilitadas.remove(moneda)) {
      if (_monedaDefault == moneda) _monedaDefault = _monedasHabilitadas.first;
      cambio = true;
    }
    if (!cambio) return;
    _syncPrecioCtrls();
    _hayCambios = true;
    _notificar();
    // Al habilitar una moneda, su precio se rellena solo con la tasa del día
    // (si ya hay un precio escrito y el cálculo automático está activo).
    if (on) _programarCalculoAutomatico(_origenEfectivo);
  }

  /// `config_precio` listo para persistir, o `null` si algún precio escrito no
  /// se puede leer (entonces [error] trae el motivo).
  ///
  /// Misma lógica que el antiguo `_configPrecioToJson`: un precio vacío se
  /// omite (no se guarda `0`, que en esta app significa «sin precio») y una
  /// regla sin ningún precio se descarta entera.
  ConfigPrecio? construir() {
    final base = <String, double>{};
    for (final m in _monedasHabilitadas) {
      final t = _precioBaseCtrls[m]?.text.trim() ?? '';
      if (t.isNotEmpty) {
        // `parseMonto` entiende es-CU y en-US: "1.500" → 1500 (antes se
        // guardaba como 1,5) y "1,50" → 1,5.
        final v = parseMonto(t);
        if (v == null) {
          _error = 'Precio base inválido para $m';
          return null;
        }
        base[m] = v;
      }
    }

    final reglasOut = <ReglaPrecio>[];
    for (final r in _reglasPrecio) {
      if (r.siClave == null || r.siClave!.isEmpty) continue;

      final preciosOpcion = <String, Map<String, double>>{};
      for (final opcion in r.preciosPorOpcion.keys) {
        final pmap = <String, double>{};
        for (final m in _monedasHabilitadas) {
          final t = r.preciosPorOpcion[opcion]?[m]?.text.trim() ?? '';
          if (t.isEmpty) continue;
          // Mismo parseo que el precio base: admite "1.500" y "1,50".
          final v = parseMonto(t);
          if (v == null) {
            _error = 'Precio inválido para "$opcion"';
            return null;
          }
          pmap[m] = v;
        }
        if (pmap.isNotEmpty) preciosOpcion[opcion] = pmap;
      }
      if (preciosOpcion.isEmpty) continue;

      reglasOut.add(
        ReglaPrecio(
          // La regla apunta al slug que se eligió en su día; el guardado tiene
          // que llevar la clave FINAL del campo (el slug puede llevar sufijo
          // `_2` si dos etiquetas colisionan).
          siClave: _claveFinalDeRegla(r.siClave!),
          preciosOpcion: preciosOpcion,
        ),
      );
    }

    _error = null;
    return ConfigPrecio(
      monedaDefault: _monedaDefault,
      // Copia: el `ConfigPrecio` que devolvemos no puede cambiar por debajo
      // cuando el admin siga tocando monedas (el host lo usa para guardar).
      monedas: [..._monedasHabilitadas],
      preciosBase: base,
      reglas: reglasOut,
      aplicaPrecioIdaVueltaTodos: _aplicaPrecioIdaVueltaTodos,
    );
  }

  /// Lo llama el host cuando el guardado terminó bien.
  void marcarComoGuardado() {
    if (_disposeado) return;
    _hayCambios = false;
    _notificar();
  }

  /// Llega la configuración de precios de la entidad (redondeo + automático).
  ///
  /// Con [proponerMonedaOrigen] (solo al **crear** un servicio) la moneda
  /// preferida de la entidad propone la moneda base si está habilitada.
  void actualizarConfigEntidad(PrecioConfig config) {
    if (_disposeado) return;
    _precioConfig = config;
    _configCargada = true;
    _proponerMonedaDeEntidad();
    _notificar();
    // Si el admin ya había escrito un precio mientras se leía la configuración,
    // ahora que se conoce la moneda base y el redondeo se calcula.
    _programarCalculoAutomatico(_origenEfectivo);
  }

  /// Nuevos campos seleccionables disponibles (el host acaba de cambiar los
  /// datos adicionales). No notifica: se llama dentro de un `setState` del host.
  void actualizarCamposSelect(List<CampoSelectPrecio> campos) {
    if (_disposeado) return;
    _camposSelect = [...campos];
    // Se resincronizan las reglas con las opciones reales de su campo: si el
    // host no lo hiciera, una regla mostraría opciones viejas (o ninguna) hasta
    // que se repintara su tile.
    for (final r in _reglasPrecio) {
      r.syncCampo(_opcionesDeCampo(r.siClave), _monedasHabilitadas);
    }
  }

  /// ¿El servicio es de transporte en ómnibus? Lo usa el editor para decidir si
  /// muestra la casilla de ida y vuelta; no cambia lo que se guarda.
  void marcarEditado() {
    if (_disposeado) return;
    _hayCambios = true;
    _notificar();
  }

  @override
  void dispose() {
    _disposeado = true;
    _debounceAuto?.cancel();
    _debounceAuto = null;
    for (final c in _precioBaseCtrls.values) {
      c.dispose();
    }
    _precioBaseCtrls.clear();
    for (final r in _reglasPrecio) {
      r.dispose();
    }
    _reglasPrecio.clear();
    // Los callbacks apuntan a un `State` que puede estar ya desmontado (el host
    // vive más que el editor): se sueltan para que nadie llame a un contexto
    // muerto.
    avisar = null;
    mostrarCartelExtraccion = null;
    cerrarCartelExtraccion = null;
    super.dispose();
  }

  // ── Helpers de presentación y lectura ────────────────────────────────────

  /// Notifica solo si el controlador sigue vivo: un `notifyListeners()` sobre un
  /// `ChangeNotifier` ya dispuesto lanza en modo debug.
  void _notificar() {
    if (_disposeado) return;
    notifyListeners();
  }

  /// Texto inicial de un precio ya guardado.
  ///
  /// Se limita a [Redondeo.maxDecimales]: un valor viejo con 3 decimales
  /// (`18.375`) se releería como **18375** al guardar, porque `parseMonto`
  /// interpreta tres dígitos tras el separador como millares.
  String _fmtPrecio(double? v) {
    if (v == null || v == 0) return '';
    return Redondeo.texto(v, Redondeo.maxDecimales);
  }

  /// Moneda **base** del servicio: la que elige el desplegable «Moneda por
  /// defecto». Es la que el admin escribe y de la que sale todo lo demás.
  ///
  /// OJO: antes mandaba `precio_config.moneda_origen` (la preferencia de la
  /// entidad) y por eso, al elegir MLC en el desplegable, el sello BASE seguía
  /// en USD. Esa preferencia ahora solo se usa para **proponerla** al crear un
  /// servicio nuevo ([actualizarConfigEntidad]).
  String get _origenEfectivo {
    if (_monedasHabilitadas.contains(_monedaDefault)) return _monedaDefault;
    return _monedasHabilitadas.isNotEmpty
        ? _monedasHabilitadas.first
        : _monedaDefault;
  }

  /// Monedas habilitadas con la **base primero**: es la que el admin escribe y
  /// de la que sale todo lo demás, así que va arriba del bloque de precios.
  List<String> get _monedasOrdenadas => [
    _origenEfectivo,
    ..._monedasHabilitadas.where((m) => m != _origenEfectivo),
  ];

  /// Sella la moneda base o el precio calculado, sin confundir las dos señales.
  ///
  ///  * **moneda base** → etiqueta con el sello «BASE» y borde/fondo de marca;
  ///  * **precio calculado** → borde y fondo **verdes** con un icono dentro del
  ///    cuadro. Al editarlo a mano deja de estar verde, porque ya no lo calculó
  ///    la app.
  InputDecoration _decoracionPrecio(String m) {
    final esBase = m == _origenEfectivo;
    final calculada = _calculadas.contains(m);
    final color = calculada
        ? AppTheme.success
        : (esBase ? AppTheme.primary : null);

    return InputDecoration(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Precio base (${MonedasApp.simbolo(m)})'),
          if (esBase) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'BASE',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      isDense: true,
      // `null` deja el relleno del tema; solo se tiñe cuando hay color.
      fillColor: color?.withValues(alpha: 0.07),
      border: const OutlineInputBorder(),
      enabledBorder: color == null
          ? null
          : OutlineInputBorder(
              borderSide: BorderSide(color: color, width: 1.5),
            ),
      focusedBorder: color == null
          ? null
          : OutlineInputBorder(
              borderSide: BorderSide(color: color, width: 1.8),
            ),
      suffixIcon: calculada
          ? const Tooltip(
              message: 'Calculado con la tasa del día',
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppTheme.success,
              ),
            )
          : null,
    );
  }

  /// Lee un precio escrito a mano. `null` si no hay número o no es positivo:
  /// en esta app `0` significa «sin precio».
  double? _precioEscrito(TextEditingController? ctrl) {
    final valor = parseMonto(ctrl?.text ?? '');
    if (valor == null || valor <= 0) return null;
    return valor;
  }

  /// De dónde sale el precio que se convierte: el de la moneda de origen o, si
  /// está vacío, el de la primera moneda habilitada con precio.
  ({String moneda, double valor})? _baseParaCalcular(String origen) {
    final propio = _precioEscrito(_precioBaseCtrls[origen]);
    if (propio != null) return (moneda: origen, valor: propio);
    for (final m in _monedasHabilitadas) {
      final valor = _precioEscrito(_precioBaseCtrls[m]);
      if (valor != null) return (moneda: m, valor: valor);
    }
    return null;
  }

  void _snack(String mensaje, {Color? color}) {
    avisar?.call(mensaje, color);
  }

  /// Aplica la preferencia de moneda de la entidad, solo cuando corresponde.
  void _proponerMonedaDeEntidad() {
    if (!_proponeMonedaBase) return;
    final origen = _precioConfig.monedaOrigen;
    if (_monedasHabilitadas.contains(origen)) _monedaDefault = origen;
  }

  /// Clave final del campo al que apunta una regla.
  ///
  /// La regla guarda el **slug**; el `config_precio` tiene que guardar la clave
  /// final del campo. Si el campo ya no existe (se borró el dato adicional) se
  /// deja el slug tal cual, que es lo que hacía el formulario.
  String _claveFinalDeRegla(String siClave) {
    for (final c in _camposSelect) {
      if (c.slug == siClave || c.clave == siClave) return c.clave;
    }
    return siClave;
  }

  /// Opciones del campo al que apunta una regla; vacío si ya no existe.
  List<String> _opcionesDeCampo(String? siClave) {
    if (siClave == null || siClave.isEmpty) return const [];
    for (final c in _camposSelect) {
      if (c.slug == siClave || c.clave == siClave) return c.opciones;
    }
    return const [];
  }

  // ── Cálculo automático (punto 4 del plan) ────────────────────────────────

  /// Calcula el resto de monedas (precio base y reglas por opción) con la tasa
  /// del día, tomando como base el precio de la moneda de origen.
  ///
  /// Sin tasa **no se toca ningún precio**: se avisa y el admin sigue como
  /// estaba.
  Future<void> _calcularRestoDesdeOrigen({bool avisar = true}) async {
    if (_disposeado || _calculandoPrecios) return;
    if (_monedasHabilitadas.length < 2) {
      if (avisar) {
        _snack('Habilita más de una moneda para calcular el resto.');
      }
      return;
    }

    _calculandoPrecios = true;
    _notificar();
    await mostrarCartelExtraccion?.call();

    TasasDia? tasas;
    try {
      tasas = await TasaCambioService.obtener();
    } finally {
      cerrarCartelExtraccion?.call();
      if (!_disposeado) {
        _calculandoPrecios = false;
        _notificar();
      }
    }
    if (_disposeado) return;

    if (tasas == null) {
      _snack(
        'No se pudo obtener la tasa de cambio. Los precios no se han '
        'modificado.',
        color: AppTheme.error,
      );
      return;
    }

    _escribirPreciosCalculados(tasas);
  }

  /// Vuelca los precios convertidos en los controladores, formateados con los
  /// decimales configurados. Se redondea y se usa `Redondeo.texto` porque
  /// `parseMonto` lee tres decimales como millares (`18.375` → 18375).
  void _escribirPreciosCalculados(
    TasasDia tasas, {
    String? origen,
    bool avisar = true,
  }) {
    final base = _baseParaCalcular(origen ?? _origenEfectivo);
    if (base == null) {
      _snack(
        'Escribe primero un precio en $_origenEfectivo (o en cualquier '
        'moneda) para calcular el resto.',
      );
      return;
    }

    String formatear(String moneda, double valor) =>
        Redondeo.texto(valor, _precioConfig.decimalesDe(moneda));

    // Escribir de verdad un precio cambia lo que se guardará: eso cuenta como
    // editado (si el texto calculado coincide con el que ya había, no).
    var escribio = false;

    // Precio base. Se marca lo que ESCRIBE el cálculo: esas monedas salen en
    // verde con su icono. La moneda desde la que se calculó conserva lo que
    // tecleó el admin, así que no se marca.
    _calculadas.clear();
    final convertidos = convertirVarios(
      precios: {base.moneda: base.valor},
      origen: base.moneda,
      monedas: _monedasHabilitadas,
      tasas: tasas,
      decimalesDe: _precioConfig.decimalesDe,
    );
    for (final entrada in convertidos.entries) {
      if (entrada.key == base.moneda) continue;
      final valor = entrada.value;
      if (valor == null) continue; // sin tasa para esa moneda: no se toca
      final texto = formatear(entrada.key, valor);
      final ctrl = _precioBaseCtrls[entrada.key];
      if (ctrl == null) continue;
      // El valor lo puso el cálculo aunque coincida con el que ya había (ahí
      // sigue siendo verde); lo que cuenta para «hay cambios» es que el texto
      // del campo cambie de verdad.
      if (ctrl.text != texto) {
        ctrl.text = texto;
        escribio = true;
      }
      _calculadas.add(entrada.key);
    }

    // Reglas de precio por opción: se convierten las que ya tienen precio en
    // la moneda de origen.
    for (final regla in _reglasPrecio) {
      regla.syncMonedas(_monedasHabilitadas);
      regla.calculadas.clear();
      for (final opcion in regla.preciosPorOpcion.entries) {
        final ctrls = opcion.value;
        final precioBase = _precioEscrito(ctrls[base.moneda]);
        if (precioBase == null) continue;
        for (final m in _monedasHabilitadas) {
          if (m == base.moneda) continue;
          final valor = convertirPrecio(
            valor: precioBase,
            origen: base.moneda,
            destino: m,
            tasas: tasas,
            decimales: _precioConfig.decimalesDe(m),
          );
          if (valor == null) continue;
          final texto = formatear(m, valor);
          final ctrl = ctrls[m];
          if (ctrl == null) continue;
          if (ctrl.text != texto) {
            ctrl.text = texto;
            escribio = true;
          }
          regla.calculadas.add('${opcion.key}|$m');
        }
      }
    }

    _tasasUsadas = tasas;
    if (escribio) _hayCambios = true;
    _notificar();

    // El aviso solo lo pide el botón: al teclear sería un SnackBar por pausa.
    if (avisar) {
      _snack(
        'Precios calculados con la tasa del ${tasas.fechaTexto}.',
        color: AppTheme.success,
      );
    }
  }

  /// Programa el cálculo automático mientras el admin escribe (debounce de
  /// 700 ms).
  ///
  /// **No** es «solo la primera vez»: cada vez que cambia un precio se
  /// recalculan las demás monedas, que es lo que se espera al teclear. El botón
  /// «Calcular desde ...» queda para forzar el refresco de la tasa.
  ///
  /// El `Timer` solo se crea si el cálculo podría llegar a correr (config de la
  /// entidad leída, automático activo y al menos dos monedas): si no, sería un
  /// timer que a los 700 ms no hace nada, y en las pruebas un timer pendiente
  /// sin cancelar.
  void _programarCalculoAutomatico(
    String moneda, {
    _ReglaPrecioEditable? regla,
  }) {
    _debounceAuto?.cancel();
    _debounceAuto = null;
    if (_disposeado) return;
    if (!_configCargada ||
        !_precioConfig.autoActivo ||
        _monedasHabilitadas.length < 2) {
      return;
    }
    _debounceAuto = Timer(const Duration(milliseconds: 700), () {
      _debounceAuto = null;
      if (_disposeado) return;
      _calcularAutomatico(moneda, regla: regla);
    });
  }

  /// Cálculo disparado por el tecleo: sin diálogo y sin avisos repetidos.
  ///
  /// Si ya hay una tasa de hoy en memoria no se llama a la red (instantáneo);
  /// si no, se extrae mostrando el banner discreto del formulario.
  Future<void> _calcularAutomatico(
    String moneda, {
    _ReglaPrecioEditable? regla,
  }) async {
    if (_disposeado || _calculandoPrecios) return;
    if (!_precioConfig.autoActivo) return;
    // Si el admin empezó a escribir antes de que llegara la config de la
    // entidad, el cálculo se reprograma al cargarla (ver
    // [actualizarConfigEntidad]).
    if (!_configCargada) return;
    if (_monedasHabilitadas.length < 2) return;

    // Se calcula desde la moneda que el admin acaba de tocar (da igual cuál sea
    // la «de origen» de la entidad): así escribir en CUP también rellena USD.
    final origen = _monedasHabilitadas.contains(moneda)
        ? moneda
        : _origenEfectivo;

    final valor = regla == null
        ? _precioEscrito(_precioBaseCtrls[origen])
        : _primerPrecioDeRegla(regla, origen);
    if (valor == null || valor <= 0) return;

    final firma =
        '${regla == null ? 'base' : 'regla:${_reglasPrecio.indexOf(regla)}'}|$origen';
    if (_ultimoCalculado[firma] == valor) return;
    _ultimoCalculado[firma] = valor;

    var tasas = _tasasUsadas;
    if (tasas == null || !tasas.vigente) {
      _extrayendoTasa = true;
      _notificar();
      try {
        tasas = await TasaCambioService.obtener();
      } finally {
        if (!_disposeado) {
          _extrayendoTasa = false;
          _notificar();
        }
      }
      if (_disposeado) return;
    }

    if (tasas == null) {
      _avisarSinTasaUnaVez();
      return;
    }

    if (regla != null) {
      _convertirRegla(regla, origen, tasas);
    } else {
      _escribirPreciosCalculados(tasas, origen: origen, avisar: false);
    }
  }

  /// Traduce «no hay tasa» una sola vez por formulario.
  void _avisarSinTasaUnaVez() {
    if (_avisoTasaMostrado) return;
    _avisoTasaMostrado = true;
    _snack(
      'No se pudo obtener la tasa de cambio. Los precios no se han modificado.',
      color: AppTheme.error,
    );
  }

  /// Primer precio escrito en la moneda [moneda] dentro de una regla.
  double? _primerPrecioDeRegla(_ReglaPrecioEditable regla, String moneda) {
    for (final ctrls in regla.preciosPorOpcion.values) {
      final valor = _precioEscrito(ctrls[moneda]);
      if (valor != null && valor > 0) return valor;
    }
    return null;
  }

  /// Convierte **una** regla desde [origen] (la casilla que se acaba de
  /// teclear), sin tocar el precio base ni las demás reglas.
  void _convertirRegla(
    _ReglaPrecioEditable regla,
    String origen,
    TasasDia tasas,
  ) {
    var escribio = false;
    regla.syncMonedas(_monedasHabilitadas);
    regla.calculadas.clear();
    for (final opcion in regla.preciosPorOpcion.entries) {
      final ctrls = opcion.value;
      final base = _precioEscrito(ctrls[origen]);
      if (base == null) continue;
      for (final m in _monedasHabilitadas) {
        if (m == origen) continue;
        final valor = convertirPrecio(
          valor: base,
          origen: origen,
          destino: m,
          tasas: tasas,
          decimales: _precioConfig.decimalesDe(m),
        );
        if (valor == null) continue;
        final texto = Redondeo.texto(valor, _precioConfig.decimalesDe(m));
        final ctrl = ctrls[m];
        if (ctrl == null) continue;
        if (ctrl.text != texto) {
          ctrl.text = texto;
          escribio = true;
        }
        regla.calculadas.add('${opcion.key}|$m');
      }
    }
    _tasasUsadas = tasas;
    if (escribio) _hayCambios = true;
    _notificar();
  }

  void _syncPrecioCtrls() {
    for (final m in List<String>.from(_precioBaseCtrls.keys)) {
      if (!_monedasHabilitadas.contains(m)) {
        _precioBaseCtrls.remove(m)?.dispose();
      }
    }
    for (final m in _monedasHabilitadas) {
      _precioBaseCtrls.putIfAbsent(m, () => TextEditingController());
    }
    for (final r in _reglasPrecio) {
      r.syncMonedas(_monedasHabilitadas);
    }
  }

  /// Cambia la moneda base desde el desplegable.
  void cambiarMonedaDefault(String moneda) {
    if (_disposeado) return;
    if (!_monedasHabilitadas.contains(moneda)) return;
    if (_monedaDefault == moneda) return;
    _monedaDefault = moneda;
    _hayCambios = true;
    _notificar();
    // Al cambiar la moneda base, el resto se recalcula desde ella de inmediato
    // (antes había que tocar el campo de USD para que pasara algo).
    _programarCalculoAutomatico(moneda);
  }

  /// Casilla de ida y vuelta (solo transporte en ómnibus).
  void editarIdaVuelta(bool valor) {
    if (_disposeado || _aplicaPrecioIdaVueltaTodos == valor) return;
    _aplicaPrecioIdaVueltaTodos = valor;
    _hayCambios = true;
    _notificar();
  }

  /// Añade una regla vacía; sus opciones las resolverá su tile al pintarse.
  void agregarRegla() {
    if (_disposeado) return;
    _reglasPrecio.add(_ReglaPrecioEditable.nueva());
    _hayCambios = true;
    _notificar();
  }

  /// Quita la regla en la posición [indice] y libera sus controladores.
  ///
  /// Recibe la posición (y no la regla) para no exponer `_ReglaPrecioEditable`
  /// en la API pública: es un detalle interno del editor.
  void quitarRegla(int indice) {
    if (_disposeado) return;
    if (indice < 0 || indice >= _reglasPrecio.length) return;
    final regla = _reglasPrecio.removeAt(indice);
    regla.dispose();
    _hayCambios = true;
    _notificar();
  }
}

/// UI del bloque de precios del servicio.
///
/// Renderiza una `Column` con `mainAxisSize.min` (no scrollea ni impone
/// padding): cada host decide el contenedor.
class PreciosServicioEditor extends StatefulWidget {
  const PreciosServicioEditor({
    super.key,
    required this.controlador,
    this.esTransporteOmnibus = false,
    this.conAnchorsTutorial = false,
  });

  final PreciosServicioControlador controlador;

  /// Servicio de transporte: muestra la casilla de «ida y vuelta».
  final bool esTransporteOmnibus;

  /// Registra los `TutorialAnchor` `admin_precio`, `admin_precio_auto` y
  /// `admin_reglas_precio` (los usa el tutorial del formulario).
  final bool conAnchorsTutorial;

  @override
  State<PreciosServicioEditor> createState() => _PreciosServicioEditorState();
}

class _PreciosServicioEditorState extends State<PreciosServicioEditor> {
  /// Contexto del diálogo de extracción, para poder cerrarlo sin tocar el resto
  /// de la pila de navegación (debajo vive la hoja modal del formulario).
  BuildContext? _cartelCtx;

  @override
  void initState() {
    super.initState();
    _enganchar(widget.controlador);
  }

  @override
  void didUpdateWidget(covariant PreciosServicioEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controlador != widget.controlador) {
      _desenganchar(oldWidget.controlador);
      _enganchar(widget.controlador);
    } else {
      widget.controlador.esTransporteOmnibus = widget.esTransporteOmnibus;
    }
  }

  @override
  void dispose() {
    // El controlador lo `dispose()`a el host: aquí solo se sueltan los
    // callbacks y el listener, o la próxima notificación llamaría a un `State`
    // ya desmontado.
    _desenganchar(widget.controlador);
    super.dispose();
  }

  /// Engancha los callbacks del controlador al `State` que los puede resolver.
  ///
  /// El controlador no conoce `BuildContext` ni `Navigator`, así que el editor
  /// le presta los suyos mientras está montado.
  void _enganchar(PreciosServicioControlador c) {
    c.avisar = _avisar;
    c.mostrarCartelExtraccion = _mostrarCartelExtraccion;
    c.cerrarCartelExtraccion = _cerrarCartelExtraccion;
    c.esTransporteOmnibus = widget.esTransporteOmnibus;
    // El editor se repinta con cada cambio del controlador: así los dos hosts
    // (uno con `setState`, el otro con `provider`) no tienen que acordarse de
    // escuchar. Un rebuild de más es inofensivo.
    c.addListener(_alCambiarControlador);
  }

  void _desenganchar(PreciosServicioControlador c) {
    c.removeListener(_alCambiarControlador);
    // Solo se sueltan si siguen siendo los nuestros: si dos editores
    // compartieran controlador, el que se desmonta no debe dejar sin voz al
    // otro.
    if (c.avisar == _avisar) c.avisar = null;
    if (c.mostrarCartelExtraccion == _mostrarCartelExtraccion) {
      c.mostrarCartelExtraccion = null;
    }
    if (c.cerrarCartelExtraccion == _cerrarCartelExtraccion) {
      c.cerrarCartelExtraccion = null;
    }
  }

  void _alCambiarControlador() {
    if (mounted) setState(() {});
  }

  void _avisar(String mensaje, Color? color) {
    if (!mounted) return;
    // `floating` + margen como en el resto del admin: el SnackBar pegado abajo
    // tapa los botones del formulario, que viven en una hoja modal.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: color ?? AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }

  /// Cartel no descartable con el aviso obligatorio mientras se pide la tasa.
  ///
  /// El `await` de un frame garantiza que el diálogo ya está construido (y su
  /// contexto guardado) antes de que empiece la petición: así el cierre siempre
  /// encuentra la ruta correcta y nunca se lleva por delante la hoja modal.
  Future<void> _mostrarCartelExtraccion() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        _cartelCtx = ctx;
        return const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text('Extrayendo los precios automáticamente...'),
                ),
              ],
            ),
          ),
        );
      },
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  void _cerrarCartelExtraccion() {
    final ctx = _cartelCtx;
    _cartelCtx = null;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).pop();
  }

  /// Envuelve [child] con el ancla del tutorial solo si el host las pidió.
  ///
  /// La pestaña «Precios» las desactiva porque el tutorial de precios pertenece
  /// al formulario: las dos pantallas pueden estar vivas a la vez y no deben
  /// registrarse dos anclas con el mismo id.
  Widget _conAnchor(String id, Widget child) =>
      widget.conAnchorsTutorial ? TutorialAnchor(id: id, child: child) : child;

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Precio del servicio ───────────────────────
        _conAnchor(
          'admin_precio',
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Precio del servicio',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                'Monedas disponibles',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final m in MonedasApp.todas)
                    FilterChip(
                      label: Text(
                        MonedasApp.etiqueta(m),
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: c._monedasHabilitadas.contains(m),
                      onSelected: (v) => c.toggleMoneda(m, v),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: c._monedaDefault,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Moneda por defecto',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: c._monedasHabilitadas
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(MonedasApp.etiqueta(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  c.cambiarMonedaDefault(v);
                },
              ),
              const SizedBox(height: 4),
              const Text(
                'Esta es la moneda base: es la que escribes y de la que se '
                'calculan las demás.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              // Punto 4: con un solo precio, la app calcula el resto con la
              // tasa del día. El ancla es la del paso del tutorial.
              _conAnchor(
                'admin_precio_auto',
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Precio base',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: c._calculandoPrecios
                          ? null
                          : () => c._calcularRestoDesdeOrigen(),
                      icon: const Icon(Icons.calculate_outlined, size: 16),
                      label: Text(
                        'Calcular desde ${c._origenEfectivo}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Banner discreto: el cálculo automático se dispara al teclear,
              // así que no puede abrir el diálogo modal cada vez.
              if (c._extrayendoTasa)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Extrayendo los precios automáticamente...',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (c._precioConfig.autoActivo &&
                  c._monedasHabilitadas.length < 2)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Habilita otra moneda y el resto se calculará solo con '
                    'la tasa del día.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              // La moneda base va SIEMPRE primera y, al cambiarla en el
              // desplegable, la lista se reordena con animación: se ve moverse
              // en vez de cambiar de golpe.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.08),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Column(
                  // La clave depende de la base: al cambiarla, Flutter ve otro
                  // hijo y anima el cambio de orden.
                  key: ValueKey('precios-base-${c._origenEfectivo}'),
                  children: [
                    for (final m in c._monedasOrdenadas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: TextField(
                          controller: c._precioBaseCtrls[m],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: c._decoracionPrecio(m),
                          // Cálculo automático: se dispara en CUALQUIERA de las
                          // monedas (la que el admin esté escribiendo, incluida
                          // la base) y recalcula el resto, sin pulsar nada.
                          onChanged: (texto) => c.editarPrecioBase(m, texto),
                        ),
                      ),
                  ],
                ),
              ),
              if (c._tasasUsadas != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Precios calculados con la tasa del '
                          '${c._tasasUsadas!.fechaTexto}. Revísalos antes '
                          'de guardar: puedes cambiarlos a mano.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // La bandera la pone este widget en el controlador (initState /
        // didUpdateWidget) y la lee de ahí: el tipo de servicio no es estado del
        // editor, es un dato del host que el controlador también necesita.
        if (c.esTransporteOmnibus) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: c._aplicaPrecioIdaVueltaTodos,
            onChanged: (v) => c.editarIdaVuelta(v ?? false),
            title: const Text(
              'Aplica precio de Ida y vuelta para todos los pasajes',
              style: TextStyle(fontSize: 13.5),
            ),
            subtitle: const Text(
              'Si está desactivado (recomendado), el precio del turno '
              'combinado solo aplica cuando ida y vuelta son el mismo día. '
              'En fechas distintas se cobran ida + vuelta por separado.',
              style: TextStyle(fontSize: 12),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
        const SizedBox(height: 8),
        // ── Reglas de precio por dato adicional ───────
        _conAnchor(
          'admin_reglas_precio',
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Reglas de precio por dato adicional',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: c.agregarRegla,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Regla'),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Configura un precio distinto para cada opción del campo '
                  'seleccionable. Si dos reglas coinciden, se aplica la primera.',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
              // Los campos seleccionables los resuelve el host (él conoce los
              // datos adicionales del servicio) y llegan ya con slug y clave
              // final; aquí solo se pintan.
              if (c._camposSelect.isEmpty && c._reglasPrecio.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Agrega campos tipo seleccionable para definir reglas.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < c._reglasPrecio.length; i++)
                      _ReglaPrecioTile(
                        regla: c._reglasPrecio[i],
                        camposSelect: c._camposSelect,
                        monedas: c._monedasHabilitadas,
                        // Tocar el campo o sus precios es una edición más: el
                        // host lo usa para saber si hay algo sin guardar.
                        onChanged: c.marcarEditado,
                        // Al teclear el precio de una opción, sus demás
                        // monedas se calculan con la tasa del día.
                        onPrecioCambiado: (moneda) =>
                            c._programarCalculoAutomatico(
                              moneda,
                              regla: c._reglasPrecio[i],
                            ),
                        onRemove: () => c.quitarRegla(i),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Regla editable: un campo select con precio por cada opción y moneda.
class _ReglaPrecioEditable {
  String? siClave;

  /// opción → moneda → controlador
  final Map<String, Map<String, TextEditingController>> preciosPorOpcion = {};

  /// Claves `'opcion|moneda'` cuyo precio escribió el cálculo automático: esos
  /// campos se pintan en verde con su icono. Se limpia al recalcular y al
  /// editar el campo a mano.
  final Set<String> calculadas = {};

  _ReglaPrecioEditable({this.siClave});

  /// Regla recién añadida: sin campo elegido (su tile lo pedirá) y sin precios.
  factory _ReglaPrecioEditable.nueva() => _ReglaPrecioEditable();

  factory _ReglaPrecioEditable.fromModel(
    ReglaPrecio r, {
    required List<String> monedas,
    List<String>? opcionesCampo,
  }) {
    final editable = _ReglaPrecioEditable(siClave: r.siClave);
    final opciones = opcionesCampo ?? r.preciosOpcion.keys.toList();
    editable.syncCampo(opciones, monedas);
    for (final opcion in r.preciosOpcion.entries) {
      for (final precio in opcion.value.entries) {
        final ctrl = editable.preciosPorOpcion[opcion.key]?[precio.key];
        if (ctrl == null) continue;
        final v = precio.value;
        // Mismo motivo que `_fmtPrecio`: nunca `v.toString()` (3 decimales se
        // releen como millares).
        ctrl.text = v == 0 ? '' : Redondeo.texto(v, Redondeo.maxDecimales);
      }
    }
    return editable;
  }

  void syncCampo(List<String> opciones, List<String> monedas) {
    for (final o in List<String>.from(preciosPorOpcion.keys)) {
      if (!opciones.contains(o)) {
        for (final c in preciosPorOpcion[o]!.values) {
          c.dispose();
        }
        preciosPorOpcion.remove(o);
        calculadas.removeWhere((k) => k.startsWith('$o|'));
      }
    }
    for (final o in opciones) {
      preciosPorOpcion.putIfAbsent(o, () => {});
      final map = preciosPorOpcion[o]!;
      for (final m in List<String>.from(map.keys)) {
        if (!monedas.contains(m)) map.remove(m)?.dispose();
      }
      for (final m in monedas) {
        map.putIfAbsent(m, () => TextEditingController());
      }
    }
  }

  void syncMonedas(List<String> monedas) {
    syncCampo(preciosPorOpcion.keys.toList(), monedas);
  }

  void dispose() {
    for (final map in preciosPorOpcion.values) {
      for (final c in map.values) {
        c.dispose();
      }
    }
    preciosPorOpcion.clear();
  }
}

class _ReglaPrecioTile extends StatefulWidget {
  final _ReglaPrecioEditable regla;
  final List<CampoSelectPrecio> camposSelect;
  final List<String> monedas;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  /// Se llama al teclear un precio de la regla, con la moneda tocada: así el
  /// cálculo automático también rellena las demás monedas de esa regla.
  final ValueChanged<String>? onPrecioCambiado;

  const _ReglaPrecioTile({
    required this.regla,
    required this.camposSelect,
    required this.monedas,
    required this.onChanged,
    required this.onRemove,
    this.onPrecioCambiado,
  });

  @override
  State<_ReglaPrecioTile> createState() => _ReglaPrecioTileState();
}

class _ReglaPrecioTileState extends State<_ReglaPrecioTile> {
  CampoSelectPrecio? _campoActual() {
    for (final c in widget.camposSelect) {
      if (c.slug == widget.regla.siClave || c.clave == widget.regla.siClave) {
        return c;
      }
    }
    return null;
  }

  void _syncOpciones() {
    final campo = _campoActual();
    widget.regla.syncCampo(campo?.opciones ?? [], widget.monedas);
  }

  /// Igual que en el precio base: si el precio de esta opción lo puso el cálculo
  /// automático, el cuadro sale en verde con el icono dentro.
  InputDecoration _decoracionPrecio(String opcion, String m) {
    final calculada = widget.regla.calculadas.contains('$opcion|$m');
    return InputDecoration(
      labelText: 'Precio (${MonedasApp.simbolo(m)})',
      isDense: true,
      fillColor: calculada ? AppTheme.success.withValues(alpha: 0.07) : null,
      border: const OutlineInputBorder(),
      enabledBorder: calculada
          ? const OutlineInputBorder(
              borderSide: BorderSide(color: AppTheme.success, width: 1.5),
            )
          : null,
      focusedBorder: calculada
          ? const OutlineInputBorder(
              borderSide: BorderSide(color: AppTheme.success, width: 1.8),
            )
          : null,
      suffixIcon: calculada
          ? const Tooltip(
              message: 'Calculado con la tasa del día',
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppTheme.success,
              ),
            )
          : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _syncOpciones();
  }

  @override
  void didUpdateWidget(covariant _ReglaPrecioTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOpciones();
  }

  @override
  Widget build(BuildContext context) {
    final campoActual = _campoActual();
    final opcionesDisp = campoActual?.opciones ?? const <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue:
                      widget.camposSelect.any(
                        (c) => c.slug == widget.regla.siClave,
                      )
                      ? widget.regla.siClave
                      : (widget.camposSelect.any(
                              (c) => c.clave == widget.regla.siClave,
                            )
                            ? widget.camposSelect
                                  .firstWhere(
                                    (c) => c.clave == widget.regla.siClave,
                                  )
                                  .slug
                            : null),
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Campo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: widget.camposSelect
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.slug,
                          child: Text(
                            c.etiqueta,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    widget.regla.siClave = v;
                    _syncOpciones();
                    widget.onChanged();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppTheme.error),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          if (opcionesDisp.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Selecciona un campo con opciones definidas.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            )
          else
            for (final opcion in opcionesDisp) ...[
              const Divider(height: 16),
              Text(
                opcion,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (final m in widget.monedas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TextField(
                    controller: widget.regla.preciosPorOpcion[opcion]?[m],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoracionPrecio(opcion, m),
                    onChanged: (_) {
                      // Escrito a mano ⇒ deja de estar «calculado».
                      widget.regla.calculadas.remove('$opcion|$m');
                      widget.onChanged();
                      widget.onPrecioCambiado?.call(m);
                    },
                  ),
                ),
            ],
        ],
      ),
    );
  }
}
