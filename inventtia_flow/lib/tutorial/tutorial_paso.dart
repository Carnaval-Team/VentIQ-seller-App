import 'tutorial_destino.dart';

/// Un paso del tutorial guiado.
///
/// El [id] es el identificador del ancla (`TutorialAnchor`) sobre la que se
/// recorta el foco. Un mismo paso puede vivir en una pantalla distinta a la del
/// paso anterior: o bien la app navega sola al entrar en el paso (si declara
/// [destino]), o bien el controlador espera a que el ancla aparezca montada
/// (ver `TutorialController.onAnclaRegistrada`).
class TutorialPaso {
  /// Identificador del ancla que hay que resaltar.
  final String id;

  /// Titular corto de la burbuja.
  final String titulo;

  /// Texto de ayuda. Estilo del proyecto: español, tuteo, frases cortas.
  final String mensaje;

  /// Texto del botón principal. `null` → "Siguiente" ("Entendido" en el último).
  final String? accion;

  /// Pantalla que hay que dejar lista para este paso.
  ///
  /// El controlador la pide al entrar (`TutorialNavegador` de `iniciar`) y solo
  /// si el elemento del paso no está ya a la vista. `null` → el paso vive en la
  /// pantalla donde estamos, o necesita que el usuario haga la acción (una hoja
  /// que se abre al tocar el elemento resaltado).
  final TutorialDestino? destino;

  /// Dónde colocar la burbuja respecto al hueco.
  final TutorialPosicion posicion;

  /// Si es un paso de configuración opcional (el recorrido se puede cortar aquí).
  final bool opcional;

  const TutorialPaso({
    required this.id,
    required this.titulo,
    required this.mensaje,
    this.accion,
    this.destino,
    this.posicion = TutorialPosicion.auto,
    this.opcional = false,
  });
}

enum TutorialPosicion {
  /// Elige arriba o abajo según el hueco.
  auto,

  /// Fuerza la burbuja por encima del elemento resaltado.
  arriba,

  /// Fuerza la burbuja por debajo del elemento resaltado.
  abajo,
}
