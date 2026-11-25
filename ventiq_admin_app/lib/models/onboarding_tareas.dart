/// Modelo puro del checklist de activación de tienda.
///
/// Fase 3 del plan `docs/plans/alta-tienda-progresiva-go-live.md`: calcula qué
/// tareas le quedan pendientes a una tienda en borrador para poder vender, según
/// el tipo de negocio que declaró.
///
/// El punto central del diseño es el **modelo Stripe**: las tareas se derivan de
/// hechos reales de la base, no se marcan a mano. El estado del checklist es un
/// cálculo, no un contador que el usuario va rellenando. `estadosGuardados` solo
/// existe para las pocas tareas que no tienen un hecho propio todavía.
///
/// Sin `flutter/material`: esto se prueba sin widgets.
///
/// Nota verificada contra la BD de newa: los medios de pago son globales
/// (`app_nom_medio_pago`, catálogo compartido por todas las tiendas), no hay
/// "métodos de pago por tienda" que gatear. Lo que sí impide vender es tener un
/// vendedor asignado a la caja: `fn_abrir_turno_tpv` exige `p_id_vendedor` y sin
/// turno abierto no hay cobro posible.
library;

/// Estado de una tarea del checklist, tal como se guarda en
/// `app_dat_tarea_onboarding.estado`.
enum EstadoTarea {
  pendiente('pendiente'),
  completada('completada'),
  omitida('omitida');

  const EstadoTarea(this.valor);

  /// Valor en la base (`text` con CHECK en la tabla).
  final String valor;

  /// Lectura tolerante: un valor desconocido o nulo cae en [pendiente].
  static EstadoTarea desdeValor(String? valor) {
    return EstadoTarea.values.firstWhere(
      (e) => e.valor == valor,
      orElse: () => EstadoTarea.pendiente,
    );
  }
}

/// Tipos de negocio que acepta `app_dat_tienda.tipo_negocio`.
///
/// Es una columna declarativa: solo elige qué tareas recomendar. La capacidad
/// real de la tienda la siguen decidiendo `modo_restaurante`, `cocina_activa` y
/// `app_dat_tpv.modo_servicentro`.
const List<String> tiposNegocioConocidos = [
  'retail',
  'restaurante',
  'servicentro',
  'catalogo',
];

/// Lo que se consulta de la base para decidir el estado del checklist.
///
/// Es un value object inmutable y todos los campos traen default para que
/// construir uno en pruebas sea trivial (`const HechosTienda()` = tienda vacía).
class HechosTienda {
  const HechosTienda({
    this.tieneAlmacen = false,
    this.tieneZona = false,
    this.tieneTpv = false,
    this.tieneProducto = false,
    this.tieneVendedorAsignado = false,
    this.tienePersonal = false,
    this.tieneCocina = false,
    this.tieneMesa = false,
    this.modoRestaurante = false,
    this.cocinaActiva = false,
    this.almacenesConvertiblesACocina = 0,
    this.tieneNombreTienda = false,
    this.tieneDireccion = false,
    this.tieneUbicacion = false,
  });

  /// `app_dat_almacen` con al menos una fila que no sea cocina.
  final bool tieneAlmacen;

  /// Al menos una zona (`app_dat_layout_almacen`) creada.
  final bool tieneZona;

  /// Al menos un TPV (`app_dat_tpv`).
  final bool tieneTpv;

  /// Al menos un producto en el catálogo.
  final bool tieneProducto;

  /// Al menos un vendedor con `id_tpv` asignado: es lo que permite abrir turno
  /// y, por tanto, cobrar. `app_dat_vendedor.uuid` también es obligatorio.
  final bool tieneVendedorAsignado;

  /// Al menos una persona del equipo (`app_dat_trabajador` / vendedor).
  final bool tienePersonal;

  /// Existe una cocina (`app_dat_almacen.es_cocina`).
  final bool tieneCocina;

  /// Existe al menos una mesa (`app_dat_mesas`). Se crean desde `ventiq_app`.
  final bool tieneMesa;

  /// `app_dat_configuracion_tienda.modo_restaurante`.
  final bool modoRestaurante;

  /// `app_dat_configuracion_tienda.cocina_activa`. Requiere [modoRestaurante].
  final bool cocinaActiva;

  /// Almacenes que no abastecen a ningún TPV, es decir, candidatos válidos para
  /// `fn_crear_cocina`. Si es 0, convertir un almacén en cocina falla con
  /// `ALMACEN_ES_DE_TPV`: con 1 almacén y 1 TPV la lista sale vacía.
  final int almacenesConvertiblesACocina;

  /// El paso 2 del asistente: datos de la tienda. En el alta progresiva el paso
  /// 1 crea la tienda con un nombre provisional y vacía la dirección, así que
  /// sin estas tres tareas el cliente nunca vuelve a rellenarlas.
  final bool tieneNombreTienda;
  final bool tieneDireccion;
  final bool tieneUbicacion;

  /// Copia con los hechos indicados cambiados; el resto se conserva.
  HechosTienda copyWith({
    bool? tieneAlmacen,
    bool? tieneZona,
    bool? tieneTpv,
    bool? tieneProducto,
    bool? tieneVendedorAsignado,
    bool? tienePersonal,
    bool? tieneCocina,
    bool? tieneMesa,
    bool? modoRestaurante,
    bool? cocinaActiva,
    int? almacenesConvertiblesACocina,
    bool? tieneNombreTienda,
    bool? tieneDireccion,
    bool? tieneUbicacion,
  }) {
    return HechosTienda(
      tieneAlmacen: tieneAlmacen ?? this.tieneAlmacen,
      tieneZona: tieneZona ?? this.tieneZona,
      tieneTpv: tieneTpv ?? this.tieneTpv,
      tieneProducto: tieneProducto ?? this.tieneProducto,
      tieneVendedorAsignado:
          tieneVendedorAsignado ?? this.tieneVendedorAsignado,
      tienePersonal: tienePersonal ?? this.tienePersonal,
      tieneCocina: tieneCocina ?? this.tieneCocina,
      tieneMesa: tieneMesa ?? this.tieneMesa,
      modoRestaurante: modoRestaurante ?? this.modoRestaurante,
      cocinaActiva: cocinaActiva ?? this.cocinaActiva,
      almacenesConvertiblesACocina:
          almacenesConvertiblesACocina ?? this.almacenesConvertiblesACocina,
      tieneNombreTienda: tieneNombreTienda ?? this.tieneNombreTienda,
      tieneDireccion: tieneDireccion ?? this.tieneDireccion,
      tieneUbicacion: tieneUbicacion ?? this.tieneUbicacion,
    );
  }
}

/// Una fila del checklist de activación.
class TareaOnboarding {
  const TareaOnboarding({
    required this.clave,
    required this.titulo,
    required this.beneficio,
    required this.obligatoria,
    required this.estado,
    this.motivoBloqueo,
    this.ruta,
    this.enPanel = false,
    this.campoPanel,
  })  : assert(
          !(enPanel && ruta != null),
          'Una tarea se resuelve en el panel o navegando, no las dos cosas',
        ),
        assert(
          !enPanel || campoPanel != null,
          'Una tarea en el panel necesita decir qué campo la resuelve',
        );

  /// Identificador estable: `almacen`, `tpv`, `cocina`, ... Es la clave que se
  /// guarda en `app_dat_tarea_onboarding.clave`.
  final String clave;

  /// Título en lenguaje de mostrador, no de informática.
  final String titulo;

  /// Por qué importa. Nunca regaña ni habla de porcentajes.
  final String beneficio;

  /// `true` = bloquea el Go Live. Las `omitida` de una obligatoria **no**
  /// cuentan como completadas.
  final bool obligatoria;

  final EstadoTarea estado;

  /// Visible cuando la tarea no se puede empezar todavía (por ejemplo, no hay
  /// almacén convertible en cocina). Si no es nulo, [ruta] es nulo.
  final String? motivoBloqueo;

  /// Ruta de navegación para resolverla. `null` si es informativa o si está
  /// bloqueada.
  final String? ruta;

  /// No se puede empezar todavía.
  bool get bloqueada => motivoBloqueo != null;

  /// Tiene una acción concreta que ofrecer ahora mismo: navegar ([ruta]) o
  /// pedir el dato en el propio panel ([enPanel]).
  bool get accionable =>
      (ruta != null || enPanel) && estado != EstadoTarea.completada;

  /// La resuelve el propio panel (un formulario embebido) en vez de navegar a
  /// otra pantalla. Cuando es `true`, [ruta] es nulo.
  ///
  /// Sirve para los datos de la tienda del paso 2 (nombre, dirección, ubicación)
  /// y para el alta de quien cobra: son uno o dos campos, y sacar al usuario del
  /// panel para eso rompe el hilo del checklist.
  final bool enPanel;

  /// Campo del formulario embebido que resuelve la tarea:
  /// `nombre`, `direccion`, `ubicacion` o `cobro`.
  final String? campoPanel;
}

/// Construye el checklist de una tienda, en el orden de la tabla del plan.
///
/// Reglas:
///
/// - [tipoNegocio] `null`, vacío o desconocido se trata como `retail`. Una
///   tienda que nunca declaró su tipo debe poder activarse igualmente: el tipo
///   solo elige qué tareas guiar, no qué se permite.
/// - El estado sale de los hechos ([HechosTienda]); `estadosGuardados` tiene la
///   última palabra cuando trae la clave, para las tareas que la pantalla ya
///   persistió o para las que todavía no tienen hecho propio
///   (`servicentro_tpv`, `inventario`, `moneda`).
/// - Una tarea cuyo hecho ya está satisfecho nace `completada`; si no,
///   `pendiente`.
List<TareaOnboarding> construirTareas({
  required String? tipoNegocio,
  required HechosTienda hechos,
  Map<String, EstadoTarea> estadosGuardados = const {},
}) {
  final tipo = _normalizarTipo(tipoNegocio);

  EstadoTarea estadoDe(String clave, bool satisfecho) =>
      estadosGuardados[clave] ??
      (satisfecho ? EstadoTarea.completada : EstadoTarea.pendiente);

  /// Tarea sin hecho propio todavía: pendiente hasta que la pantalla la guarde.
  EstadoTarea estadoSinHecho(String clave) =>
      estadosGuardados[clave] ?? EstadoTarea.pendiente;

  final tareas = <TareaOnboarding>[];

  // Datos de la tienda: son el paso 2 del asistente de alta. En el alta
  // progresiva la tienda nace con un nombre provisional y sin dirección, y estas
  // tres son la única forma de volver a rellenarlas. No bloquean el Go Live
  // (una tienda sin dirección puede vender), pero sin ellas el cliente no
  // aparecería nunca en los tickets ni en el mapa.
  tareas.add(
    TareaOnboarding(
      clave: 'nombre_tienda',
      titulo: 'Ponle nombre a tu tienda',
      beneficio:
          'Es el nombre que ven tus clientes y tu equipo en la app y en el '
          'ticket. Ahora mismo tiene uno provisional.',
      obligatoria: false,
      estado: estadoDe('nombre_tienda', hechos.tieneNombreTienda),
      enPanel: true,
      campoPanel: 'nombre',
    ),
  );

  tareas.add(
    TareaOnboarding(
      clave: 'direccion',
      titulo: 'La dirección del local',
      beneficio:
          'Sale impresa en cada ticket, para que el cliente sepa dónde '
          'reclamar.',
      obligatoria: false,
      estado: estadoDe('direccion', hechos.tieneDireccion),
      enPanel: true,
      campoPanel: 'direccion',
    ),
  );

  tareas.add(
    TareaOnboarding(
      clave: 'ubicacion',
      titulo: 'Marca tu tienda en el mapa',
      beneficio:
          'Con la ubicación, el reparto y las rutas saben a dónde ir. Sin ella '
          'la tienda no aparece en el mapa.',
      obligatoria: false,
      estado: estadoDe('ubicacion', hechos.tieneUbicacion),
      enPanel: true,
      campoPanel: 'ubicacion',
    ),
  );

  if (tipo != 'catalogo') {
    tareas.add(
      TareaOnboarding(
        clave: 'almacen',
        titulo: 'Tu primer almacén',
        beneficio:
            'Aquí es donde vive tu mercancía. Sin él no hay stock que vender.',
        obligatoria: true,
        estado: estadoDe('almacen', hechos.tieneAlmacen),
        ruta: '/warehouse',
      ),
    );

    tareas.add(
      TareaOnboarding(
        clave: 'zona',
        titulo: 'Ubica cada cosa en su lugar',
        beneficio:
            'Una zona es el estante o la gaveta donde se busca. Si nadie sabe '
            'dónde está, el stock se pierde de vista.',
        obligatoria: false,
        estado: estadoDe('zona', hechos.tieneZona),
        ruta: '/warehouse',
      ),
    );

    tareas.add(
      TareaOnboarding(
        clave: 'tpv',
        titulo: 'Tu punto de venta',
        beneficio:
            'La caja donde se cobra. Sin un TPV no hay venta que registrar.',
        obligatoria: true,
        estado: estadoDe('tpv', hechos.tieneTpv),
        ruta: '/tpv-management',
      ),
    );
  }

  tareas.add(
    TareaOnboarding(
      clave: 'producto',
      titulo: 'Algo que vender',
      beneficio:
          'Tu primer producto con su precio, listo para aparecer en la '
          'pantalla del vendedor.',
      obligatoria: true,
      estado: estadoDe('producto', hechos.tieneProducto),
      ruta: '/add-product',
    ),
  );

  if (tipo != 'catalogo') {
    tareas.add(
      TareaOnboarding(
        clave: 'cobro',
        titulo: 'Quién cobra en tu caja',
        beneficio:
            'Hace falta una persona con usuario de acceso y rol Dependiente, '
            'asignada a la caja. Sin vendedor no se puede abrir turno y, sin '
            'turno, no se cobra.',
        obligatoria: true,
        estado: estadoDe('cobro', hechos.tieneVendedorAsignado),
        // Se resuelve aquí mismo: es un alta de trabajador con el rol ya
        // elegido. Mandar a /tpv-management era el error anterior — allí se
        // crea la caja, no la persona que cobra.
        enPanel: true,
        campoPanel: 'cobro',
      ),
    );

    tareas.add(
      TareaOnboarding(
        clave: 'personal',
        titulo: 'Tu equipo',
        beneficio:
            'Cada persona entra con su propio usuario y cada venta queda a su '
            'nombre.',
        obligatoria: false,
        estado: estadoDe('personal', hechos.tienePersonal),
        ruta: '/workers',
      ),
    );
  }

  if (tipo == 'restaurante') {
    tareas.add(_tareaCocina(hechos, estadoDe('cocina', hechos.cocinaActiva)));

    tareas.add(
      TareaOnboarding(
        clave: 'mesas_restaurante',
        titulo: 'Las mesas de tu salón',
        beneficio:
            'Las mesas se crean desde la app del vendedor (ventiq_app), no '
            'desde el admin: ahí las abres y quedan listas para tomar pedidos '
            'en el salón.',
        obligatoria: false,
        estado: estadoDe('mesas_restaurante', hechos.tieneMesa),
        // Informativa a propósito: no existe pantalla de mesas en el admin.
        ruta: null,
      ),
    );

    tareas.add(
      TareaOnboarding(
        clave: 'modo_restaurante',
        titulo: 'Pon la tienda en modo restaurante',
        beneficio:
            'Así la app sabe que vendes platos y no solo productos de estante: '
            'aparecen comandas, mesas y cocina.',
        obligatoria: false,
        estado: estadoDe('modo_restaurante', hechos.modoRestaurante),
        ruta: '/settings',
      ),
    );
  }

  if (tipo == 'servicentro') {
    tareas.add(
      TareaOnboarding(
        clave: 'servicentro_tpv',
        titulo: 'Marca tu caja como servicentro',
        beneficio:
            'Con el modo servicentro la caja vende por surtidor y lleva el '
            'combustible por manguera, no como producto suelto.',
        obligatoria: false,
        // Sin hecho propio en HechosTienda: `app_dat_tpv.modo_servicentro` es
        // por TPV y aún no se consulta aquí.
        estado: estadoSinHecho('servicentro_tpv'),
        ruta: '/tpv-management',
      ),
    );
  }

  if (tipo != 'catalogo') {
    tareas.add(
      TareaOnboarding(
        clave: 'inventario',
        titulo: 'Carga las existencias',
        beneficio:
            'El stock real de lo que vendes. Así el vendedor no ofrece lo que '
            'ya no hay.',
        obligatoria: false,
        // Tampoco hay hecho de existencias todavía: se cierra al guardarla.
        estado: estadoSinHecho('inventario'),
        ruta: '/inventory',
      ),
    );
  }

  tareas.add(
    TareaOnboarding(
      clave: 'moneda',
      titulo: 'Revisa tu tasa de cambio',
      beneficio:
          'Con la tasa al día los precios en dólares y en pesos cuadran en el '
          'mostrador.',
      obligatoria: false,
      // Las tasas no se consultan todavía en HechosTienda.
      estado: estadoSinHecho('moneda'),
      ruta: '/settings',
    ),
  );

  return tareas;
}

/// `true` cuando **todas** las obligatorias están completadas.
///
/// Una obligatoria `omitida` cuenta como no completada: omitir no es cumplir.
bool puedeActivar(List<TareaOnboarding> tareas) {
  return tareas
      .where((t) => t.obligatoria)
      .every((t) => t.estado == EstadoTarea.completada);
}

/// Progreso del checklist. `total` no cuenta las tareas omitidas, así que
/// omitir una tarea que no aplica no baja el contador.
({int completadas, int total}) progreso(List<TareaOnboarding> tareas) {
  final vivas = tareas.where((t) => t.estado != EstadoTarea.omitida);
  return (
    completadas: vivas.where((t) => t.estado == EstadoTarea.completada).length,
    total: vivas.length,
  );
}

/// Las obligatorias que todavía impiden publicar, para que la pantalla pueda
/// listar cada bloqueo con su enlace en vez de un mensaje genérico.
List<TareaOnboarding> tareasBloqueantes(List<TareaOnboarding> tareas) {
  return tareas
      .where((t) => t.obligatoria && t.estado != EstadoTarea.completada)
      .toList();
}

/// `null`, vacío o un tipo no declarado se tratan como `retail`.
String _normalizarTipo(String? tipoNegocio) {
  final tipo = tipoNegocio?.trim().toLowerCase();
  if (tipo == null || tipo.isEmpty) return 'retail';
  return tiposNegocioConocidos.contains(tipo) ? tipo : 'retail';
}

/// La cocina nace de convertir un almacén, y `fn_crear_cocina` rechaza los
/// almacenes que abastecen a un TPV con `ALMACEN_ES_DE_TPV`. Por eso, cuando no
/// hay ningún almacén convertible, la tarea explica el motivo en vez de ofrecer
/// un desplegable que saldría vacío.
///
/// Caso real verificado: una tienda con 1 almacén y 1 TPV tiene 0 almacenes
/// convertibles, así que la tarea queda bloqueada con el motivo a la vista.
TareaOnboarding _tareaCocina(HechosTienda hechos, EstadoTarea estado) {
  final sinAlmacenConvertible =
      estado != EstadoTarea.completada &&
      hechos.almacenesConvertiblesACocina == 0;

  return TareaOnboarding(
    clave: 'cocina',
    titulo: 'Tu cocina',
    beneficio:
        'Donde se preparan los platos. Las comandas de lo que se cocina llegan '
        'aquí.',
    obligatoria: false,
    estado: estado,
    motivoBloqueo: sinAlmacenConvertible
        ? 'Necesitas un almacén que no abastezca a ningún TPV. Con todos tus '
              'almacenes atados a una caja, la cocina no se puede crear (el '
              'sistema responde ALMACEN_ES_DE_TPV).'
        : null,
    ruta: sinAlmacenConvertible ? null : '/cocinas-management',
  );
}
