import 'tutorial_controller.dart';
import 'tutorial_destino.dart';
import 'tutorial_paso.dart';
import '../services/tutorial_service.dart';

/// Guiones del tutorial guiado.
///
/// Los `id` de cada paso deben coincidir **exactamente** con el `id` del
/// `TutorialAnchor` que se coloca en la pantalla correspondiente, y aparecer una
/// sola vez en toda la app.
///
/// El recorrido cruza pantallas y las navega solo: cada paso declara el
/// `destino` donde vive su elemento y la app lo abre al pulsar «Siguiente» (ver
/// `TutorialNavegacion` y `TutorialController._prepararPaso`). Los pasos que
/// viven dentro de una hoja que solo existe tras tocar el elemento resaltado no
/// declaran destino: ahí navega el propio toque del usuario, y el recorrido
/// avanza solo cuando el ancla de la hoja aparece.
class TutorialFlujos {
  TutorialFlujos._();

  static const String flujoCliente = 'cliente';
  static const String flujoAdmin = 'admin';

  // ── Cliente: crear una reserva o anotarse en la lista ──────────────────
  //
  // v2: el Home cambió. Ahora abre con «Exploración rápida» (cuatro atajos) en
  // vez del riel de categorías, y detrás hay tres pantallas nuevas. El recorrido
  // enseña ese acceso rápido y las tres, y solo después lleva al cliente a
  // reservar. Ver `TutorialService.version` (sube a `v2` para que el recorrido
  // nuevo se muestre una vez a quien ya tenía el viejo marcado).
  //
  // v3: se añade `detalle_pago_adelantado` en la hoja de la reserva, para los
  // locales que cobran por adelantado. Sube a `v3` (ver `TutorialService`).

  static List<TutorialPaso> pasosCliente() => const <TutorialPaso>[
        TutorialPaso(
          id: 'home_buscar',
          titulo: 'Encuentra tu servicio',
          mensaje: 'Escribe aquí el servicio o el local que buscas. Justo debajo '
              'tienes los atajos para explorar todo el catálogo.',
          destino: TutorialDestino.home,
        ),
        TutorialPaso(
          id: 'home_exploracion',
          titulo: 'Exploración rápida',
          mensaje: 'Cuatro atajos: «Categorías» (todos los rubros), «Servicios» '
              '(el catálogo completo), «Establecimientos» (todos los locales) y '
              '«Más populares» (el top 10 de la semana).',
          destino: TutorialDestino.home,
        ),
        TutorialPaso(
          id: 'home_ver_todo',
          titulo: 'Explora el catálogo',
          mensaje: '«Ver catálogo» abre la lista completa de servicios con su '
              'precio, su local y su provincia.',
          destino: TutorialDestino.home,
        ),
        TutorialPaso(
          id: 'home_card_categorias',
          titulo: 'Empieza por un rubro',
          mensaje: 'La tarjeta «Categorías» te enseña todos los rubros y cuántos '
              'establecimientos tiene cada uno.',
          destino: TutorialDestino.home,
        ),
        TutorialPaso(
          id: 'categorias_lista',
          titulo: 'Categorías y subcategorías',
          mensaje: 'Toca «Ver los N establecimientos» para ver ese rubro, o la '
              'flecha del final para desplegar sus subcategorías y afinar la '
              'búsqueda.',
          destino: TutorialDestino.listaCategorias,
        ),
        TutorialPaso(
          id: 'establecimientos_lista',
          titulo: 'Establecimientos',
          mensaje: 'Cada tarjeta enseña la foto del local, su valoración y '
              'cuántos servicios ofrece. Puedes ordenarlos y filtrar por '
              'provincia, valoración o «abierto ahora».',
          destino: TutorialDestino.listaEstablecimientos,
        ),
        TutorialPaso(
          id: 'ficha_local_servicios',
          titulo: 'La ficha del local',
          mensaje: 'Al tocar un establecimiento ves su ficha completa —foto, '
              'horario, contacto— con TODOS sus servicios, igual que en el '
              'espacio patrocinado. Desde ahí reservas el que quieras.',
          // Opcional: sin establecimientos publicados no hay ficha que abrir.
          opcional: true,
          destino: TutorialDestino.fichaEstablecimiento,
        ),
        TutorialPaso(
          id: 'top_servicios',
          titulo: 'El top 10 de la semana',
          mensaje: 'Los servicios con más lugares reservados esta semana, para '
              'saber qué está funcionando ahora mismo.',
          // Opcional: sin reservas esta semana el ranking está vacío y no hay
          // lista que resaltar.
          opcional: true,
          destino: TutorialDestino.topServicios,
        ),
        TutorialPaso(
          id: 'catalogo_tarjeta',
          titulo: 'Abre un servicio',
          mensaje: 'Toca una tarjeta para ver sus turnos, su horario y sus '
              'recursos.',
          destino: TutorialDestino.catalogo,
        ),
        TutorialPaso(
          id: 'detalle_acciones',
          titulo: 'Reserva o anótate',
          mensaje: 'Si hay cupo, toca «Reservar ahora». Si ya no queda, usa '
              '«Anotarme en la lista» y te llamamos por turno.',
          posicion: TutorialPosicion.arriba,
          // El detalle es de un servicio concreto: se abre el primero del
          // catálogo para que el paso tenga dónde resaltar.
          destino: TutorialDestino.servicio,
        ),
        // A partir de aquí los pasos viven en las hojas que se abren al tocar el
        // elemento resaltado (calendario → formulario de la reserva → pago por
        // adelantado), así que no hay destino: navega el toque del usuario y el
        // recorrido lo sigue.
        TutorialPaso(
          id: 'detalle_calendario',
          titulo: 'Elige el día',
          mensaje: 'Toca un día: el número indica los turnos libres. Puedes '
              'cambiar de mes y anotarte en cualquier fecha futura.',
        ),
        TutorialPaso(
          id: 'detalle_datos',
          titulo: 'Completa los datos',
          // Opcional: el formulario de datos adicionales solo se construye si el
          // servicio tiene campos configurados, así que en muchos servicios no
          // hay nada que resaltar aquí.
          mensaje: 'Si el local pide datos extra, los rellenas aquí; también '
              'puedes reservar a nombre de otra persona. El precio se '
              'recalcula solo.',
          opcional: true,
        ),
        TutorialPaso(
          id: 'detalle_pago_adelantado',
          titulo: 'Paga por adelantado',
          mensaje: 'Si el local cobra por adelantado, aquí mismo puedes pagar en '
              'el momento con Transfermóvil. El administrador verifica el pago y '
              'te avisa cuando quede confirmado.',
          // Opcional: solo los locales que han activado el cobro por adelantado
          // ofrecen esta opción.
          opcional: true,
        ),
        TutorialPaso(
          id: 'detalle_continuar',
          titulo: 'Confirma y listo',
          mensaje: 'Toca este botón para cerrar la reserva. La verás en Mis '
              'reservas y podrás cancelarla mientras no haya llegado el día.',
        ),
      ];

  // ── Admin: publicar el primer negocio completo ─────────────────────────

  static List<TutorialPaso> pasosAdmin() => const <TutorialPaso>[
        TutorialPaso(
          id: 'admin_selector_entidad',
          titulo: 'Tu entidad',
          mensaje: 'Todo lo que configures aquí es para la entidad '
              'seleccionada. Si tienes varias, cámbiala desde este selector.',
          destino: TutorialDestino.gestion,
        ),
        TutorialPaso(
          id: 'admin_modulo_locales',
          titulo: '1. Crea tu local',
          mensaje: 'Empieza por el local: es el sitio físico donde atiendes. '
              'Aquí también verás qué servicios ofrece cada uno y su '
              'planificación.',
          destino: TutorialDestino.gestion,
        ),
        TutorialPaso(
          id: 'admin_nuevo_local',
          titulo: 'Nuevo local',
          mensaje: 'Pon nombre, foto, dirección, ubicación y el horario con '
              'apertura y cierre. Activa «Local activo» cuando esté listo.',
          destino: TutorialDestino.locales,
        ),
        TutorialPaso(
          id: 'admin_modulo_servicios',
          titulo: '2. Crea el servicio',
          mensaje: 'El servicio es lo que el cliente reserva: un corte, una '
              'consulta, un viaje… En el catálogo lo defines una vez y luego '
              'lo ofreces en los locales que quieras.',
          destino: TutorialDestino.gestion,
        ),
        TutorialPaso(
          id: 'admin_nuevo_servicio',
          titulo: 'Nuevo servicio',
          mensaje: 'Elige a qué local pertenece, la categoría, la foto y si se '
              'puede reservar directamente.',
          destino: TutorialDestino.servicios,
        ),
        // Los pasos siguientes viven dentro del formulario de alta: el destino
        // lo abre para que no haya que buscarlo.
        TutorialPaso(
          id: 'admin_precio',
          titulo: 'Precio y monedas',
          mensaje: 'Activa las monedas que aceptas, marca la moneda por defecto '
              'y escribe el precio base.',
          destino: TutorialDestino.serviciosFormulario,
        ),
        TutorialPaso(
          id: 'admin_precio_auto',
          titulo: 'Precios automáticos',
          mensaje: 'Escribe un precio y toca «Calcular»: el resto de monedas '
              'sale de la tasa de cambio del día. Puedes revisarlas y '
              'sobrescribirlas antes de guardar.',
          // Opcional: el botón solo aparece con más de una moneda habilitada.
          opcional: true,
          destino: TutorialDestino.serviciosFormulario,
        ),
        TutorialPaso(
          id: 'admin_datos_adicionales',
          titulo: 'Datos adicionales',
          mensaje: 'Pide lo que necesites: texto, número, lista de opciones o '
              'sí/no. Marca «Requerido», mínimo y máximo, valor por defecto y '
              '«Totalizar en reportes» si quieres contar ese dato en los '
              'totales.',
          destino: TutorialDestino.serviciosFormulario,
        ),
        TutorialPaso(
          id: 'admin_reglas_precio',
          titulo: 'Reglas de precio',
          mensaje: 'Puedes cobrar distinto según la opción elegida en un campo '
              'de lista. Si dos reglas coinciden, se aplica la primera.',
          destino: TutorialDestino.serviciosFormulario,
        ),
        TutorialPaso(
          id: 'admin_guardar_servicio',
          titulo: 'Guarda el servicio',
          mensaje: 'Al guardar, el servicio aparece en el catálogo del cliente '
              'con su precio.',
          destino: TutorialDestino.serviciosFormulario,
        ),
        TutorialPaso(
          id: 'admin_anadir_servicio',
          titulo: '3. Ofrécelo en tu local',
          mensaje: 'Dentro de tu local toca «Añadir servicio»: elige uno del '
              'catálogo o créalo en el momento.',
          destino: TutorialDestino.localDetalle,
        ),
        // Lo que sigue vive en la pestaña «Configuración» de un servicio ya
        // ofrecido en un local. Sin ninguno todavía, el destino cae en el
        // detalle del local, que es donde se añade.
        TutorialPaso(
          id: 'admin_reserva_directa',
          titulo: 'Reserva directa',
          // Opcional a propósito: el interruptor solo existe cuando ya hay un
          // servicio ofrecido en algún local.
          mensaje: 'Es un extra: actívala si el cliente puede reservar una hora '
              'exacta. Si la dejas apagada, el cliente se anota en la lista de '
              'espera.',
          opcional: true,
          destino: TutorialDestino.servicioLocal,
        ),
        TutorialPaso(
          id: 'admin_capacidades',
          titulo: 'Capacidades por reserva',
          mensaje: 'Define cuánta gente entra en una misma reserva, para cuando '
              'el cliente pueda reservar para varios.',
          opcional: true,
          destino: TutorialDestino.servicioLocal,
        ),
        // Recursos y turnos y el plan mensual se abren tocando su fila en la
        // misma pestaña: el recorrido espera a que el usuario entre.
        TutorialPaso(
          id: 'admin_recursos_turnos',
          titulo: 'Recursos y turnos',
          mensaje: 'Abre «Recursos y turnos» y crea recursos (sillas, carros, '
              'mesas) y sus turnos con nombre, horario y precio propio. Si no '
              'usas tramos, activa el modo simple.',
          destino: TutorialDestino.servicioLocal,
        ),
        TutorialPaso(
          id: 'admin_config_mensual',
          titulo: 'Publica el mes',
          mensaje: 'Abre «Plan mensual», elige el mes, pon la capacidad por '
              'defecto y toca «Generar planes del mes»: hasta que no lo hagas, '
              'los días no están disponibles para reservar.',
          destino: TutorialDestino.servicioLocal,
        ),
        TutorialPaso(
          id: 'admin_calendario',
          titulo: 'Resumen por calendario',
          mensaje: 'Desde el botón del calendario en la barra de Reservas ves el '
              'resumen del rango: en modo calendario, los días con marcadores de '
              'color; en modo lista, las reservas agrupadas por día con su hora, '
              'cliente y pago.',
          // Opcional: es un acceso extra dentro del módulo de reservas.
          opcional: true,
          destino: TutorialDestino.reservas,
        ),
        TutorialPaso(
          id: 'admin_reservas',
          titulo: 'Gestiona las reservas',
          mensaje: 'Desde esta tarjeta confirmas el consumo, cancelas y filtras '
              'por estado, local o servicio.',
          opcional: true,
          destino: TutorialDestino.reservas,
        ),
        TutorialPaso(
          id: 'admin_categorias',
          titulo: 'Categorías',
          mensaje: 'Las categorías las gestiona el superadmin. Aquí eliges cuáles '
              'ocultas para tus servicios: la categoría sigue en los filtros del '
              'Home, pero tus servicios y locales de esa categoría dejan de '
              'aparecer en el catálogo del cliente.',
          opcional: true,
          destino: TutorialDestino.categorias,
        ),
      ];

  // ── Arranque con persistencia ─────────────────────────────────────────

  /// Lanza el tutorial del cliente y recuerda que ya se mostró al terminar o al
  /// saltar (ambas cosas cuentan: no se vuelve a mostrar).
  ///
  /// [navegador] es lo que permite que «Siguiente» cambie de pestaña o abra una
  /// pantalla; sin él el recorrido se comporta como antes (espera al usuario).
  static void iniciarCliente(
    String uuidUsuario, {
    TutorialNavegador? navegador,
  }) {
    if (uuidUsuario.isEmpty) return;
    TutorialController.instance.iniciar(
      pasosCliente(),
      flujoId: flujoCliente,
      navegador: navegador,
      alCompletar: () => TutorialService.marcarVistoCliente(uuidUsuario),
      alOmitir: () => TutorialService.marcarOmitidoCliente(uuidUsuario),
    );
  }

  /// Igual, pero por entidad: si el admin crea otra entidad, el tutorial vuelve
  /// a mostrarse para esa entidad nueva.
  static void iniciarAdmin(
    String uuidUsuario,
    int idEntidad, {
    TutorialNavegador? navegador,
  }) {
    if (uuidUsuario.isEmpty) return;
    TutorialController.instance.iniciar(
      pasosAdmin(),
      flujoId: flujoAdmin,
      navegador: navegador,
      alCompletar: () =>
          TutorialService.marcarVistoAdmin(uuidUsuario, idEntidad),
      alOmitir: () =>
          TutorialService.marcarOmitidoAdmin(uuidUsuario, idEntidad),
    );
  }

  /// Vuelve a habilitar el tutorial del cliente y lo lanza de inmediato.
  static Future<void> repetirCliente(
    String uuidUsuario, {
    TutorialNavegador? navegador,
  }) async {
    await TutorialService.reiniciarCliente(uuidUsuario);
    iniciarCliente(uuidUsuario, navegador: navegador);
  }

  /// Vuelve a habilitar el tutorial del admin y lo lanza de inmediato.
  static Future<void> repetirAdmin(
    String uuidUsuario,
    int idEntidad, {
    TutorialNavegador? navegador,
  }) async {
    await TutorialService.reiniciarAdmin(uuidUsuario, idEntidad);
    iniciarAdmin(uuidUsuario, idEntidad, navegador: navegador);
  }
}
