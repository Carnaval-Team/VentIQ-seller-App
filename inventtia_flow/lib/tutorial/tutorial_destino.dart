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

  /// Módulo «Locales y servicios» (lista de locales).
  locales,

  /// Detalle del primer local: sus servicios y «Añadir servicio».
  localDetalle,

  /// Configuración del primer servicio vinculado a un local.
  servicioLocal,

  /// Catálogo de servicios (listado).
  servicios,

  /// Catálogo de servicios con el formulario de alta ya abierto.
  serviciosFormulario,

  /// Módulo de reservas.
  reservas,

  /// Módulo de categorías.
  categorias,
}
