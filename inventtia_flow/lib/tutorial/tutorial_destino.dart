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

  /// Pantalla dedicada de cobro por adelantado (configuración del cobro y
  /// pagos por verificar). Se abre desde el cuadrito «Pagos por adelantado» del
  /// home del admin, no desde «Mi suscripción».
  cobros,

  /// Pantalla «Mi suscripción» (planes, pago del plan e historial). Se abre
  /// desde el icono de suscripción de la cabecera de Gestión.
  suscripcion,

  // ── Destinos del CLIENTE que no son pestañas del shell ──────────────────
  // Los resuelve `TutorialNavegacion.irACliente`, que empuja las pantallas de
  // «Exploración rápida» con `ExploracionNavegacion` (la misma fuente que usan
  // las tarjetas del Home).

  /// Listado de categorías con contadores.
  listaCategorias,

  /// Listado de establecimientos.
  listaEstablecimientos,

  /// Ficha de un establecimiento (la misma vista del espacio patrocinado).
  fichaEstablecimiento,

  /// Top 10 de servicios de la semana.
  topServicios,
}
