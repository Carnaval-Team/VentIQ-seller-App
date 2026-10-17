import 'package:flutter/material.dart';

/// Registro global de anclas del tutorial.
///
/// Un `TutorialAnchor` montado registra aquí su `GlobalKey`; el overlay pide el
/// rectángulo en coordenadas globales para recortar el foco. Es un singleton
/// porque el overlay vive por encima del `Navigator` (`MaterialApp.builder`) y
/// necesita localizar widgets que están dentro de rutas y de hojas modales.
///
/// [version] se incrementa en cada alta/baja para que el overlay se reposicione
/// cuando el layout cambia (por ejemplo, al abrirse una hoja).
class TutorialRegistry {
  TutorialRegistry._();

  static final TutorialRegistry instance = TutorialRegistry._();

  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};
  final Map<String, ModalRoute<dynamic>> _rutas = <String, ModalRoute<dynamic>>{};

  /// Notifica altas, bajas y cambios de layout.
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  void registrar(String id, GlobalKey key) {
    final anterior = _keys[id];
    if (identical(anterior, key)) return;
    _keys[id] = key;
    version.value++;

    // El controlador decide si con esta ancla le toca avanzar de paso.
    TutorialAnchorCallbacks.onRegistrada?.call(id);
  }

  /// Guarda la ruta que contiene el ancla.
  ///
  /// `ModalRoute.isCurrent` es un campo que el `Navigator` mantiene al día, así
  /// que se puede consultar después sin volver a tocar `ModalRoute.of`. Es la
  /// clave para saber que un elemento "sigue montado pero tapado" por una hoja
  /// modal o por otra pantalla apilada.
  void registrarRuta(String id, ModalRoute<dynamic>? ruta) {
    if (ruta == null) {
      _rutas.remove(id);
    } else {
      _rutas[id] = ruta;
    }
  }

  void desregistrar(String id, GlobalKey key) {
    if (!identical(_keys[id], key)) return;
    _keys.remove(id);
    _rutas.remove(id);
    version.value++;

    // Si el ancla que se va era la de un paso pendiente, el controlador puede
    // reajustar el recorrido (ver `TutorialController.evaluarAvance`).
    TutorialAnchorCallbacks.onDesregistrada?.call(id);
  }

  /// Útil para tests y para reiniciar el recorrido.
  void limpiar() {
    if (_keys.isEmpty && _rutas.isEmpty) return;
    _keys.clear();
    _rutas.clear();
    version.value++;
  }

  /// ¿Está el ancla montada **y** a la vista?
  bool estaVisible(String id) {
    if (rectDe(id) == null) return false;
    final ruta = _rutas[id];
    if (ruta != null && !ruta.isCurrent) return false;
    return _sinAncestrosOcultos(id);
  }

  /// Rectángulo del ancla en coordenadas globales, o `null` si no está montada
  /// (o su `RenderBox` todavía no tiene tamaño).
  Rect? rectDe(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }

  /// Detecta el caso "montado pero no pintado": el `IndexedStack` del shell
  /// envuelve cada pestaña en `Visibility.maintain`, así que un ancla del
  /// catálogo sigue en el árbol (y con rectángulo) mientras el usuario está en
  /// el Home. Sin esta comprobación el tutorial saltaría de paso solo.
  bool _sinAncestrosOcultos(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return false;
    var visible = true;
    ctx.visitAncestorElements((el) {
      final w = el.widget;
      if (w is Visibility && !w.visible) {
        visible = false;
        return false;
      }
      if (w is Offstage && w.offstage) {
        visible = false;
        return false;
      }
      if (w is Opacity && w.opacity < 0.05) {
        visible = false;
        return false;
      }
      return true;
    });
    return visible;
  }
}

/// Enlace mínimo para que el registro no dependa del controlador (evita un
/// ciclo de imports) y el controlador pueda suscribirse a las altas y bajas.
class TutorialAnchorCallbacks {
  TutorialAnchorCallbacks._();

  static void Function(String id)? onRegistrada;
  static void Function(String id)? onDesregistrada;
}