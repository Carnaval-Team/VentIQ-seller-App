import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tutorial_destino.dart';
import 'tutorial_paso.dart';
import 'tutorial_registry.dart';

/// Pide a la app que muestre la pantalla donde vive un paso.
///
/// Lo implementa quien lanza el recorrido (el shell, la pantalla de «Gestión»),
/// porque es quien puede cambiar de pestaña y empujar rutas. Devolver un
/// `Future` deja cerrar el estado de "navegando" cuando termina la transición.
typedef TutorialNavegador = Future<void> Function(TutorialDestino destino);

/// Estado del tutorial guiado activo.
///
/// Singleton a propósito: el overlay se monta por encima del `Navigator`
/// (`MaterialApp.builder`) y las pantallas que disparan el recorrido están
/// dentro de rutas distintas, sin un ancestro común que pueda proveerlo.
class TutorialController extends ChangeNotifier {
  TutorialController._() {
    // Engancha el registro de anclas con el estado del recorrido: es lo que
    // permite que el tutorial siga al usuario de una pantalla a la siguiente.
    TutorialAnchorCallbacks.onRegistrada = (_) => evaluarAvance();
    TutorialAnchorCallbacks.onDesregistrada = (_) => evaluarAvance();
  }

  static final TutorialController instance = TutorialController._();

  /// Instancia suelta para tests (no toca los callbacks globales del singleton).
  @visibleForTesting
  static TutorialController aisladoParaPruebas() => TutorialController._();

  List<TutorialPaso> _pasos = const <TutorialPaso>[];
  List<TutorialPaso> _ultimoRecorrido = const <TutorialPaso>[];

  /// Pasos que el usuario llegó a tener a la vista. Sirve para no dar por
  /// terminado el tutorial cuando el último paso nunca se llegó a alcanzar.
  final Set<String> _alcanzados = <String>{};
  int _indice = 0;
  bool _activo = false;
  String? _flujoId;
  VoidCallback? _alCompletar;
  VoidCallback? _alOmitir;

  /// Navegación que la app sabe hacer para cada destino del recorrido.
  TutorialNavegador? _navegador;

  bool _navegando = false;
  Timer? _timerNavegacion;

  bool get activo => _activo;
  int get indice => _indice;
  int get total => _pasos.length;
  String? get flujoId => _flujoId;
  List<TutorialPaso> get pasos => List<TutorialPaso>.unmodifiable(_pasos);

  /// `true` mientras se acaba de pedir una navegación y todavía no se ha
  /// alcanzado el elemento del paso: en ese hueco la burbuja no le pide nada al
  /// usuario (sería un parpadeo de medio segundo durante la transición).
  bool get navegando => _navegando;

  /// Último recorrido lanzado: permite repetirlo desde "Ver tutorial otra vez".
  List<TutorialPaso> get ultimoRecorrido =>
      List<TutorialPaso>.unmodifiable(_ultimoRecorrido);

  TutorialPaso? get pasoActual {
    if (!_activo || _indice < 0 || _indice >= _pasos.length) return null;
    return _pasos[_indice];
  }

  /// Arranca un recorrido. [alCompletar] y [alOmitir] permiten persistir que ya
  /// se ha visto: el que termina y el que salta cuentan igual, no se repite.
  void iniciar(
    List<TutorialPaso> pasos, {
    String? flujoId,
    VoidCallback? alCompletar,
    VoidCallback? alOmitir,
    TutorialNavegador? navegador,
  }) {
    if (pasos.isEmpty) return;
    _pasos = List<TutorialPaso>.unmodifiable(pasos);
    _ultimoRecorrido = _pasos;
    _indice = 0;
    _activo = true;
    _flujoId = flujoId;
    _alCompletar = alCompletar;
    _alOmitir = alOmitir;
    _navegador = navegador;
    // Si el primer elemento ya está a la vista, se anota de entrada: es la
    // condición para poder avanzar solo cuando desaparezca.
    _marcarSiVisible();
    // Y si vive en otra pantalla, se pide ya (el primer paso también navega).
    _prepararPaso();
    notifyListeners();
  }

  void siguiente() {
    if (!_activo) return;
    if (_indice >= _pasos.length - 1) {
      terminar();
      return;
    }
    _indice++;
    _marcarSiVisible();
    // El paso nuevo puede vivir en otra pantalla: se pide su destino.
    _prepararPaso();
    notifyListeners();
  }

  void anterior() {
    if (!_activo || _indice == 0) return;
    _indice--;
    _marcarSiVisible();
    // Volver atrás también puede caer en otra pantalla (p. ej. salir del
    // detalle de un servicio al listado).
    _prepararPaso();
    notifyListeners();
  }

  void irA(int indice) {
    if (!_activo || indice < 0 || indice >= _pasos.length) return;
    _indice = indice;
    _marcarSiVisible();
    _prepararPaso();
    notifyListeners();
  }

  /// Anota el paso actual como "alcanzado" si su elemento está a la vista.
  ///
  /// Ojo: **no** busca el paso siguiente. Si al pulsar "Siguiente" el elemento
  /// del nuevo paso todavía no existe, primero se le pide a la app que navegue
  /// ([_prepararPaso]) y, si aun así no aparece, el recorrido se queda
  /// esperándolo; es [evaluarAvance] —que solo corre cuando un ancla aparece o
  /// desaparece— el que decide saltar.
  void _marcarSiVisible() {
    final paso = _pasos[_indice];
    if (TutorialRegistry.instance.estaVisible(paso.id)) {
      _alcanzados.add(paso.id);
      // Ya está a la vista: la navegación pedida llegó a su destino.
      _terminarNavegacion();
    }
  }

  /// Cierra el tutorial marcándolo como completado.
  void terminar() {
    if (!_activo) return;
    final cb = _alCompletar;
    _cerrar();
    cb?.call();
  }

  /// Cierra el tutorial marcándolo como omitido (tampoco se vuelve a mostrar).
  void omitir() {
    if (!_activo) return;
    final cb = _alOmitir ?? _alCompletar;
    _cerrar();
    cb?.call();
  }

  /// Relanza el último recorrido con los mismos callbacks de persistencia.
  void repetir() {
    if (_ultimoRecorrido.isEmpty) return;
    iniciar(
      _ultimoRecorrido,
      flujoId: _flujoId,
      alCompletar: _alCompletar,
      alOmitir: _alOmitir,
      navegador: _navegador,
    );
  }

  void _cerrar() {
    _activo = false;
    _pasos = const <TutorialPaso>[];
    _alcanzados.clear();
    _indice = 0;
    _timerNavegacion?.cancel();
    _timerNavegacion = null;
    _navegando = false;
    // Los callbacks NO se limpian: `repetir()` tiene que poder volver a marcar
    // el tutorial como visto/omitido cuando el usuario lo relanza desde Perfil.
    // El navegador tampoco: es de la app (pestañas y rutas), no del recorrido.
    notifyListeners();
  }

  /// Recoloca el recorrido cuando el elemento del paso actual está (o deja de
  /// estar) a la vista. Se llama en cada frame mientras hay tutorial activo —
  /// ver `_revisar` en el overlay— y también cuando un ancla se da de alta.
  ///
  /// Reglas:
  ///
  ///  1. Si el elemento del paso actual está a la vista, no se toca nada: el
  ///     usuario todavía no ha hecho la acción que pide el paso. Además el paso
  ///     se anota como *alcanzado*.
  ///  2. Solo se avanza solo desde un paso **alcanzado** (que el usuario llegó a
  ///     ver). Así, si el usuario pulsa "Siguiente" hacia un paso cuyo elemento
  ///     todavía no existe, se le pide antes a la app que navegue
  ///     ([_prepararPaso]) y, si aun así no aparece, el recorrido lo espera en
  ///     vez de saltar a un paso posterior ya visible: no se pueden comer pasos
  ///     intermedios.
  ///  3. Cuando el elemento del paso actual ya no está a la vista se salta al
  ///     **primer** paso posterior visible (en orden, no "el más lejano").
  ///  4. Si el último paso ya se había alcanzado y su elemento desaparece, el
  ///     recorrido se da por terminado (el usuario completó la acción: p. ej.
  ///     cerró la reserva).
  void evaluarAvance() {
    if (!_activo) return;
    final actual = _pasos[_indice];

    if (TutorialRegistry.instance.estaVisible(actual.id)) {
      _alcanzados.add(actual.id);
      _terminarNavegacion();
      return;
    }

    if (!_alcanzados.contains(actual.id)) return;

    for (var i = _indice + 1; i < _pasos.length; i++) {
      if (TutorialRegistry.instance.estaVisible(_pasos[i].id)) {
        _indice = i;
        _alcanzados.add(_pasos[i].id);
        // El salto puede caer en otra pantalla (p. ej. el usuario tocó la
        // tarjeta y se abrió el detalle): se pide su destino si hace falta.
        _prepararPaso();
        notifyListeners();
        return;
      }
    }

    if (_indice == _pasos.length - 1) terminar();
  }

  /// Deja la pantalla lista para el paso actual.
  ///
  /// Solo navega si el paso declara `destino` y su elemento todavía no está a la
  /// vista. Va diferido a un microtask porque [evaluarAvance] puede llegar desde
  /// el post-frame de un alta de ancla, y navegar (empujar rutas, cambiar de
  /// pestaña) no puede ocurrir a mitad de la fase de build.
  void _prepararPaso() {
    if (!_activo || _pasos.isEmpty) return;
    final paso = _pasos[_indice];
    final destino = paso.destino;
    if (destino == null) return;
    if (TutorialRegistry.instance.estaVisible(paso.id)) return;
    final navegador = _navegador;
    if (navegador == null) return;

    _empezarNavegacion();
    scheduleMicrotask(() async {
      // El recorrido pudo cambiar mientras se programaba la navegación.
      if (!_activo || _pasos.isEmpty) return;
      if (_pasos[_indice].destino != destino) return;
      try {
        await navegador(destino);
      } catch (_) {
        // Navegar es "best effort": si falla, el tutorial se queda en el paso y
        // el usuario siempre puede tocar el elemento resaltado.
        _terminarNavegacion();
      }
    });
  }

  /// Marca que se acaba de pedir una navegación.
  ///
  /// El aviso se apaga solo cuando el elemento del paso se ve (el caso normal,
  /// ver [_marcarSiVisible]) o, como red de seguridad, a los 1,5 s: si el destino
  /// no se pudo abrir, la burbuja vuelve a pedirle al usuario la acción del paso.
  void _empezarNavegacion() {
    _navegando = true;
    _timerNavegacion?.cancel();
    _timerNavegacion = Timer(const Duration(milliseconds: 1500), () {
      if (!_activo) return;
      _navegando = false;
      notifyListeners();
    });
  }

  void _terminarNavegacion() {
    _timerNavegacion?.cancel();
    _timerNavegacion = null;
    if (!_navegando) return;
    _navegando = false;
    notifyListeners();
  }

  @visibleForTesting
  void resetParaPruebas() {
    _pasos = const <TutorialPaso>[];
    _ultimoRecorrido = const <TutorialPaso>[];
    _alcanzados.clear();
    _indice = 0;
    _activo = false;
    _flujoId = null;
    _alCompletar = null;
    _alOmitir = null;
    _navegador = null;
    _navegando = false;
    _timerNavegacion?.cancel();
    _timerNavegacion = null;
  }
}
