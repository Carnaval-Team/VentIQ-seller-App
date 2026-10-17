/// Pantalla que el tutorial debe mostrar al entrar en un paso.
///
/// Cada paso declara el suyo (`TutorialPaso.destino`) y la app lo traduce en
/// pestañas y rutas reales (ver `TutorialNavegacion`). Es lo que hace que
/// «Siguiente» no se quede esperando a que el usuario navegue por su cuenta:
/// el controlador pide el destino del paso nuevo cuando su elemento todavía no
/// está a la vista.
enum TutorialDestino {
  /// Pestaña Home del cliente.
  home,

  /// Pestaña del catálogo (listado de servicios).
  catalogo,

  /// Detalle del primer servicio del catálogo.
  servicio,

  /// Pantalla «Gestión» del admin (raíz de sus módulos).
  gestion,

  /// Módulo de locales.
  locales,

  /// Módulo de servicios (listado).
  servicios,

  /// Módulo de servicios con el formulario de alta ya abierto.
  serviciosFormulario,

  /// Módulo de planificación.
  planificacion,

  /// Módulo de reservas.
  reservas,

  /// Módulo de categorías.
  categorias,
}
