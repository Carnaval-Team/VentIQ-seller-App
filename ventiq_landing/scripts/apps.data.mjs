/**
 * ============================================================================
 * CATÁLOGO DE APPS DE INVENTTIA
 * ----------------------------------------------------------------------------
 * Fuente única de verdad para:
 *   · apps/<slug>.html          (página de presentación de cada app)
 *   · apps/index.html           (índice de todas las apps)
 *   · descargas.html            (todos los APK en un solo lugar)
 *   · sitemap.xml
 *
 * Los APK viven en el bucket público `apk` del Supabase de producción.
 * Verificado el 2026-11-16: todas las URLs de `downloads` responden 200.
 * Si subes una build nueva, cambia aquí el nombre del archivo y vuelve a
 * ejecutar `node scripts/build-pages.mjs`.
 * ============================================================================
 */

export const SITE = {
  name: 'Inventtia',
  url: 'https://inventtia.com',
  email: 'soporteinventtia@gmail.com',
  phone: '+53 53765120',
  whatsapp: 'https://wa.me/5353765120',
  apkBase: 'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/',
};

export const apk = (file) => SITE.apkBase + encodeURIComponent(file);

/** Catálogo principal. El orden aquí es el orden del índice y del pager. */
export const APPS = [
  /* ------------------------------------------------------------------ CAJA */
  {
    slug: 'caja',
    name: 'Inventtia Caja',
    shortName: 'Caja',
    category: 'Punto de venta',
    tone: 'vendedor',
    icon: 'fa-cash-register',
    tagline: 'Cobra, imprime el ticket y cuadra la caja sin soltar el mostrador.',
    summary:
      'El punto de venta de Inventtia para tiendas que venden todos los días. Órdenes, preórdenes, inventario en vivo, caja y turnos en una app que responde al instante — incluso sin internet.',
    badges: ['Android', 'Web', 'Funciona sin conexión', 'Impresión Bluetooth'],
    facts: [
      { value: '1 toque', label: 'para cobrar' },
      { value: 'Offline', label: 'sigue vendiendo' },
      { value: 'Multi-pago', label: 'efectivo · transferencia' },
      { value: 'Ticket 58/80', label: 'impresora térmica' },
    ],
    heroShot: 'assets/images/images_tutorial_seller/main_categorias_tienda.jpg',
    what: [
      'Órdenes de venta con carrito, cantidades y descuentos',
      'Preórdenes y pedidos apartados por cliente',
      'Consulta de inventario por categoría en tiempo real',
      'Apertura, movimientos y cierre de turno de caja',
      'Impresión de tickets por Bluetooth y reimpresión',
      'Resumen de ventas del turno y por vendedor',
    ],
    features: [
      {
        icon: 'fa-bolt',
        title: 'Cobro en segundos',
        text: 'Flujo pensado para pantalla táctil: categoría, producto, cantidad y cobrar. Sin menús escondidos ni pasos de más.',
      },
      {
        icon: 'fa-wifi',
        title: 'Vende sin internet',
        text: 'La caja sigue registrando ventas cuando se cae la red y reconcilia sola al recuperar la conexión.',
      },
      {
        icon: 'fa-barcode',
        title: 'Escáner y atajos',
        text: 'Compatible con lector de código de barras y atajos de teclado para quien prefiere no levantar la mano del teclado.',
      },
      {
        icon: 'fa-cash-register',
        title: 'Caja y turnos',
        text: 'Fondo inicial, extracciones parciales, egresos y cierre con arqueo. Cada movimiento queda firmado por su responsable.',
      },
      {
        icon: 'fa-print',
        title: 'Tickets de verdad',
        text: 'Impresora térmica por Bluetooth, formato 58 mm y 80 mm, con reimpresión del último ticket cuando el cliente lo pide.',
      },
      {
        icon: 'fa-tags',
        title: 'Promociones',
        text: 'Aplica rebajas y precios especiales sin tocar el catálogo maestro: la venta guarda el precio real cobrado.',
      },
    ],
    steps: [
      {
        title: 'Abre el turno',
        text: 'Indica el fondo con el que arranca la caja. Queda registrado quién abrió y a qué hora.',
      },
      {
        title: 'Cobra la venta',
        text: 'Elige productos, ajusta cantidades, aplica descuento si toca y confirma. El stock se descuenta al instante.',
      },
      {
        title: 'Cierra y cuadra',
        text: 'Al final del turno la app suma ventas, egresos y extracciones, y compara contra el efectivo contado.',
      },
    ],
    pricing: {
      model: 'Incluido en todos los planes de Inventtia',
      intro:
        'La caja no se vende aparte: cualquier plan de la suite la incluye. Estos son los planes vigentes, por tienda y en USD al mes.',
      plans: [
        {
          name: 'Gratis',
          price: '0',
          period: 'USD / mes',
          desc: 'Para probar la suite 30 días con una tienda.',
          items: ['1 tienda', '5 usuarios', 'Ventas e inventario', 'Clientes'],
          cta: { label: 'Empezar gratis', href: 'https://venta.inventtia.com' },
        },
        {
          name: 'Básico',
          price: '10',
          period: 'USD / mes',
          desc: 'La operación diaria de una tienda.',
          items: ['1 tienda', '5 usuarios', 'Ventas, inventario y clientes', 'Marketing y promociones'],
          cta: { label: 'Contratar Básico', href: 'https://venta.inventtia.com' },
        },
        {
          name: 'Pro',
          price: '20',
          period: 'USD / mes',
          desc: 'Para negocios que ya quieren números, no solo ventas.',
          featured: true,
          items: [
            'Todo lo de Básico',
            'Contabilidad y costos',
            'Multi-tienda',
            'Soporte por acuerdo con admin',
          ],
          cta: { label: 'Contratar Pro', href: 'https://venta.inventtia.com' },
        },
        {
          name: 'Avanzado',
          price: '30',
          period: 'USD / mes',
          desc: 'Varias tiendas y consignación.',
          items: ['Todo lo de Pro', 'Hasta 5 tiendas', 'Gestión de consignaciones', '30 días de prueba'],
          cta: { label: 'Contratar Avanzado', href: 'https://venta.inventtia.com' },
        },
      ],
      note:
        'Precios de referencia del plan vigente en la base de datos de Inventtia; pueden variar por campaña o contrato. La app es la misma en todos los planes: lo que cambia son los límites y los módulos habilitados.',
    },
    downloads: [
      {
        label: 'Descargar APK',
        kind: 'apk',
        href: apk('inventtia caja.apk'),
        meta: 'Android 8+ · 95,9 MB',
        primary: true,
      },
      {
        label: 'Abrir versión web',
        kind: 'web',
        href: 'https://venta.inventtia.com',
        meta: 'Sin instalar · funciona en el navegador',
      },
    ],
    shots: [
      { src: 'assets/images/images_tutorial_seller/main_categorias_tienda.jpg', alt: 'Categorías de la tienda en Inventtia Caja' },
      { src: 'assets/images/images_tutorial_seller/order_list.jpg', alt: 'Listado de órdenes del turno' },
      { src: 'assets/images/images_tutorial_seller/resumen_ventas.jpg', alt: 'Resumen de ventas del turno' },
      { src: 'assets/images/images_tutorial_seller/apertura_turno_caja.jpg', alt: 'Apertura de turno de caja' },
      { src: 'assets/images/images_tutorial_seller/order_confirm_print.jpg', alt: 'Confirmación e impresión de ticket' },
    ],
    faq: [
      {
        q: '¿Necesito internet para cobrar?',
        a: 'No. La caja funciona sin conexión y sincroniza cuando vuelve la red. Lo único que requiere conexión es lo que depende del servidor: consultar catálogo central por primera vez y ver reportes de otras tiendas.',
      },
      {
        q: '¿Qué impresoras funcionan?',
        a: 'Impresoras térmicas Bluetooth de 58 mm y 80 mm con protocolo ESC/POS, que es lo que usan casi todas las que se venden en Cuba.',
      },
      {
        q: '¿Puedo tener varias cajas en la misma tienda?',
        a: 'Sí. Cada dispositivo abre su propio turno y el administrador ve todas las ventas juntas en el panel de Gestión.',
      },
      {
        q: '¿La app es la misma para Android y para web?',
        a: 'Sí, es la misma aplicación. El APK es para tablets o teléfonos Android; la versión web se abre desde cualquier navegador moderno.',
      },
      {
        q: '¿Cómo actualizo el APK?',
        a: 'Descarga el archivo nuevo desde esta página e instálalo encima: Android conserva los datos locales. Si el sistema pide permiso para "instalar apps desconocidas", actívalo solo para el navegador o el gestor de archivos con el que abras el APK.',
      },
    ],
  },

  /* ----------------------------------------------------------------- ADMIN */
  {
    slug: 'admin',
    name: 'Inventtia Gestión',
    shortName: 'Gestión',
    category: 'Administración',
    tone: 'admin',
    icon: 'fa-chart-pie',
    tagline: 'Todo el negocio en una consola: tiendas, almacenes, equipo y dinero.',
    summary:
      'El cerebro de la suite. Gestión concentra inventario, almacenes, productos, ventas del TPV, finanzas y equipo. Lo que se cobra en la caja aparece aquí antes de que el cliente guarde el ticket.',
    badges: ['Android', 'Web', 'Multi-tienda', 'Roles y permisos'],
    facts: [
      { value: 'Tiempo real', label: 'ventas y stock' },
      { value: 'Multi-tienda', label: 'sin migrar datos' },
      { value: 'Roles', label: 'por equipo' },
      { value: 'Reportes', label: 'exportables' },
    ],
    heroShot: 'assets/images/images_tutorial_admin/ejecutive_dash_general.jpg',
    what: [
      'Dashboard ejecutivo con KPIs del negocio',
      'Inventario por almacén y zona',
      'Recepción, transferencia y ajuste de stock',
      'Productos, categorías y subcategorías',
      'Monitorización de ventas del TPV en vivo',
      'Costos, márgenes y gestión financiera',
      'CRM de clientes y marketing',
      'Configuración multi-tienda y usuarios',
    ],
    features: [
      {
        icon: 'fa-gauge-high',
        title: 'Dashboard que decide',
        text: 'Ventas del día, ticket medio, productos que rotan y stock crítico en una sola pantalla. Sin exportar nada a Excel.',
      },
      {
        icon: 'fa-warehouse',
        title: 'Almacenes y zonas',
        text: 'Cada tienda puede tener varios almacenes o zonas. El stock se mueve entre ellos con recepciones y transferencias trazables.',
      },
      {
        icon: 'fa-boxes-stacked',
        title: 'Inventario con historia',
        text: 'Cada entrada y salida deja un registro con quién, cuándo y a qué costo. El inventario valorado sale de esos movimientos, no de una hoja aparte.',
      },
      {
        icon: 'fa-user-shield',
        title: 'Permisos por rol',
        text: 'Un cajero ve su caja; un almacenero ve su almacén; el dueño lo ve todo. Los permisos se configuran por equipo, no por teléfono.',
      },
      {
        icon: 'fa-file-invoice-dollar',
        title: 'Finanzas claras',
        text: 'Costos, precios y márgenes por producto y por tienda. Sabes qué te deja dinero y qué solo ocupa estante.',
      },
      {
        icon: 'fa-store',
        title: 'Crece sin migrar',
        text: 'De una sucursal a varias sin cambiar de sistema ni perder el histórico: la segunda tienda se crea en minutos.',
      },
    ],
    steps: [
      {
        title: 'Crea la tienda',
        text: 'Nombre, moneda, categorías y almacenes. Queda lista para que el equipo entre con su usuario.',
      },
      {
        title: 'Carga el catálogo',
        text: 'Productos con costo, precio y stock mínimo. Puedes importar y ajustar después sin perder ventas ya registradas.',
      },
      {
        title: 'Opera y mide',
        text: 'El TPV vende, Gestión recibe. Cada mañana el dashboard dice qué pasó ayer sin pedirle un reporte a nadie.',
      },
    ],
    pricing: {
      model: 'Mismo plan que la caja: la suite es una',
      intro:
        'Caja y Gestión se contratan juntas: el plan define cuántas tiendas y usuarios puedes tener. Precios por tienda en USD al mes.',
      plans: [
        {
          name: 'Gratis',
          price: '0',
          period: 'USD / mes',
          desc: 'Prueba de 30 días con una tienda.',
          items: ['1 tienda', '5 usuarios', 'Ventas e inventario', 'Clientes'],
          cta: { label: 'Empezar gratis', href: 'https://admin.inventtia.com' },
        },
        {
          name: 'Básico',
          price: '10',
          period: 'USD / mes',
          desc: 'Operación diaria de una tienda.',
          items: ['1 tienda', '5 usuarios', 'Inventario y ventas', 'Marketing'],
          cta: { label: 'Contratar Básico', href: 'https://admin.inventtia.com' },
        },
        {
          name: 'Pro',
          price: '20',
          period: 'USD / mes',
          desc: 'Contabilidad y varias tiendas.',
          featured: true,
          items: ['Todo lo de Básico', 'Contabilidad y costos', 'Multi-tienda', 'Soporte acordado'],
          cta: { label: 'Contratar Pro', href: 'https://admin.inventtia.com' },
        },
        {
          name: 'Avanzado',
          price: '30',
          period: 'USD / mes',
          desc: 'Hasta 5 tiendas y consignación.',
          items: ['Todo lo de Pro', 'Hasta 5 tiendas', 'Consignaciones', '30 días de prueba'],
          cta: { label: 'Contratar Avanzado', href: 'https://admin.inventtia.com' },
        },
      ],
      note:
        'Precios de referencia del plan vigente en la base de datos de Inventtia. Para varias tiendas o facturación especial se puede acordar un contrato a medida.',
    },
    downloads: [
      {
        label: 'Descargar APK',
        kind: 'apk',
        href: apk('vendedor admin.apk'),
        meta: 'Android 8+ · 114,4 MB',
        primary: true,
      },
      {
        label: 'Abrir versión web',
        kind: 'web',
        href: 'https://admin.inventtia.com',
        meta: 'Recomendado en PC y tablet',
      },
    ],
    shots: [
      { src: 'assets/images/images_tutorial_admin/ejecutive_dash_general.jpg', alt: 'Dashboard ejecutivo de Inventtia Gestión' },
      { src: 'assets/images/images_tutorial_admin/inventario_listado.jpg', alt: 'Inventario por almacén' },
      { src: 'assets/images/images_tutorial_admin/listado_productos.jpg', alt: 'Listado de productos' },
      { src: 'assets/images/images_tutorial_admin/dash_ventas.jpg', alt: 'Dashboard de ventas' },
      { src: 'assets/images/images_tutorial_admin/inventario_transferencia_entre_zonas.jpg', alt: 'Transferencia entre zonas' },
    ],
    faq: [
      {
        q: '¿Puedo usar Gestión sin la caja?',
        a: 'Sí. Gestión funciona sola para inventario y administración, pero el plan es el mismo: cuando quieras cobrar, instalas Caja y los datos ya están ahí.',
      },
      {
        q: '¿Cuántos usuarios puedo crear?',
        a: 'Los planes actuales permiten 5 usuarios por tienda. Cada usuario tiene su rol y su propio historial de acciones.',
      },
      {
        q: '¿Sirve desde el teléfono?',
        a: 'Sí, el APK está pensado para tablet y teléfono. Para trabajo de escritorio recomendamos la versión web, que aprovecha mejor la pantalla.',
      },
      {
        q: '¿Dónde veo los reportes?',
        a: 'En el dashboard ejecutivo y en las pantallas de ventas e inventario. Los listados se pueden exportar para contabilidad.',
      },
    ],
  },

  /* --------------------------------------------------------------- CATÁLOGO */
  {
    slug: 'catalogo',
    name: 'Inventtia Catálogo',
    shortName: 'Catálogo',
    category: 'Tienda en línea',
    tone: 'catalogo',
    icon: 'fa-store',
    tagline: 'Tu tienda en línea, conectada al mismo inventario que la caja.',
    summary:
      'Una vitrina pública con tus productos, buscador, carrito y pedidos. Tus clientes compran desde el móvil y tú recibes el pedido en el mismo sistema donde llevas el stock.',
    badges: ['Web', 'Android', 'Pagos en línea', 'Pedidos conectados'],
    facts: [
      { value: '1 tarde', label: 'para publicarla' },
      { value: 'Mismo stock', label: 'que la tienda' },
      { value: 'Carrito', label: 'y pedidos' },
      { value: 'Compartible', label: 'por WhatsApp' },
    ],
    heroShot: 'assets/images/catalogo.jpg',
    what: [
      'Vitrina pública con tu marca y tu enlace propio',
      'Buscador y filtros por categoría',
      'Carrito y confirmación de pedido',
      'Precios siempre iguales a los de la tienda',
      'Pedidos que entran al mismo panel de administración',
      'Entrega a domicilio con seguimiento',
    ],
    features: [
      {
        icon: 'fa-link',
        title: 'Se publica sola',
        text: 'No hay que volver a subir productos: el catálogo lee el inventario de la tienda y muestra lo que está disponible.',
      },
      {
        icon: 'fa-magnifying-glass',
        title: 'Se encuentra rápido',
        text: 'Buscador, categorías y filtros. El cliente que sabe lo que quiere llega en dos toques.',
      },
      {
        icon: 'fa-cart-shopping',
        title: 'Carrito y pedido',
        text: 'El pedido llega con nombre, teléfono y dirección. Nada de capturas de pantalla por WhatsApp que se pierden.',
      },
      {
        icon: 'fa-credit-card',
        title: 'Pago en línea',
        text: 'Integración con pasarela de pago para cobrar sin efectivo, con el estado de cada transacción guardado.',
      },
      {
        icon: 'fa-truck-fast',
        title: 'Delivery con seguimiento',
        text: 'El cliente ve el estado de su pedido y tú ves qué falta por entregar y quién lo lleva.',
      },
      {
        icon: 'fa-star',
        title: 'Reseñas',
        text: 'Los clientes valoran productos y la tienda. Lo que dicen se queda en tu panel, no en un grupo de mensajes.',
      },
    ],
    steps: [
      {
        title: 'Conecta la tienda',
        text: 'El catálogo usa los productos y precios de tu tienda en Inventtia. Si el producto está agotado, no se muestra.',
      },
      {
        title: 'Personaliza',
        text: 'Logo, portada, colores y mensaje de bienvenida. El enlace es tuyo y se comparte por WhatsApp o redes.',
      },
      {
        title: 'Recibe pedidos',
        text: 'Cada pedido entra al panel, se prepara, se entrega y se cierra. El stock se ajusta con la venta.',
      },
    ],
    pricing: {
      model: 'Plan Catálogo',
      intro:
        'El catálogo tiene su propio plan, separado de la caja. Es para tiendas que quieren vender en línea sin cambiar su forma de cobrar en el mostrador.',
      plans: [
        {
          name: 'Catálogo',
          price: '6.000',
          period: 'CUP · según contrato',
          desc: 'Vitrina en línea conectada al inventario de la tienda.',
          featured: true,
          items: [
            '1 tienda con catálogo público',
            'Hasta 5 usuarios',
            'Productos sincronizados con la caja',
            'Pedidos y delivery',
            '30 días de prueba',
          ],
          cta: { label: 'Activar catálogo', href: 'https://catalogo.inventtia.com' },
        },
      ],
      note:
        'Precio de referencia del plan Catálogo registrado en la base de datos de Inventtia (6.000 CUP). Confirma con soporte si tu contrato es mensual o anual. Si ya tienes un plan Pro o Avanzado, pregunta si tu catálogo va incluido antes de pagar dos veces.',
    },
    downloads: [
      {
        label: 'Descargar APK',
        kind: 'apk',
        href: apk('inventtia marketplace.apk'),
        meta: 'Android 8+ · 23,6 MB',
        primary: true,
      },
      {
        label: 'Abrir catálogo web',
        kind: 'web',
        href: 'https://catalogo.inventtia.com',
        meta: 'Sin instalar',
      },
    ],
    shots: [{ src: 'assets/images/catalogo.jpg', alt: 'Catálogo de productos de Inventtia' }],
    faq: [
      {
        q: '¿Necesito tener la caja para usar el catálogo?',
        a: 'Sí, el catálogo se alimenta del inventario de la tienda. Si todavía no usas Inventtia en el mostrador, el catálogo no tiene de dónde leer.',
      },
      {
        q: '¿Mis clientes tienen que instalar algo?',
        a: 'No. Entran desde el navegador con el enlace de tu tienda. El APK es una opción para quienes prefieren tenerla instalada.',
      },
      {
        q: '¿Puedo cobrar en línea?',
        a: 'Sí, hay integración con pasarela de pago. También puedes dejar el pedido para pago contra entrega si prefieres.',
      },
    ],
  },

  /* ------------------------------------------------------------------ FLOW */
  {
    slug: 'flow',
    name: 'Inventtia GoReserva',
    shortName: 'GoReserva',
    category: 'Colas y turnos',
    tone: 'flow',
    icon: 'fa-list-ol',
    tagline: 'Saca tu número sin hacer fila. Llega justo a tu turno.',
    summary:
      'Gestión de colas y turnos para negocios de servicios: barberías, consultorios, gestores, talleres. El cliente reserva desde el móvil, ve su posición en vivo y el negocio organiza la cola sin gritar nombres.',
    badges: ['Android', 'Turnos en vivo', 'Recordatorios', 'Panel para negocios'],
    facts: [
      { value: '0 filas', label: 'físicas' },
      { value: 'En vivo', label: 'posición del turno' },
      { value: 'Avisos', label: 'antes del turno' },
      { value: 'Panel', label: 'para el negocio' },
    ],
    logo: 'assets/images/flow-logo.png',
    heroPhone: { logo: 'assets/images/flow-logo.png', title: 'GoReserva', tag: 'Turnos · Colas · Reservas', tone: 'teal' },
    what: [
      'Servicios y negocios cerca de ti',
      'Sala de espera virtual',
      'Posición del turno en tiempo real',
      'Reserva de turnos por horario',
      'Avisos antes de que llegue tu turno',
      'Panel de capacidad y atención para el negocio',
    ],
    features: [
      {
        icon: 'fa-location-dot',
        title: 'Servicios cerca',
        text: 'El cliente ve qué negocios tienen turnos disponibles ahora mismo, ordenados por cercanía.',
      },
      {
        icon: 'fa-hourglass-half',
        title: 'Sala de espera virtual',
        text: 'Puede esperar desde casa o desde el trabajo. La app le avisa cuándo acercarse.',
      },
      {
        icon: 'fa-bell',
        title: 'Avisos de turno',
        text: 'Notificación cuando faltan pocos turnos. Menos plantones, menos "ya voy para allá".',
      },
      {
        icon: 'fa-scale-balanced',
        title: 'Cola justa',
        text: 'Un bot ordena la cola por orden de llegada y prioridad configurada; nadie se cuela sin que quede registro.',
      },
      {
        icon: 'fa-calendar-check',
        title: 'Reservas',
        text: 'Turnos para una hora concreta, no solo para hoy. El negocio decide cuántos acepta por franja.',
      },
      {
        icon: 'fa-gauge-high',
        title: 'Panel del negocio',
        text: 'Cuántos esperan, cuánto tarda cada servicio y dónde se atasca el día. Datos para decidir turnos de personal.',
      },
    ],
    steps: [
      {
        title: 'Busca el servicio',
        text: 'El cliente abre la app, elige el negocio y ve los servicios con su duración y disponibilidad.',
      },
      {
        title: 'Toma el turno',
        text: 'Saca número para hoy o reserva una hora. Recibe su posición y el tiempo estimado de espera.',
      },
      {
        title: 'Llega a tiempo',
        text: 'La app avisa cuando se acerca su turno. El negocio lo atiende y la cola avanza sola para el resto.',
      },
    ],
    pricing: {
      model: 'Gratis para el cliente final',
      intro:
        'Quien saca turno no paga nada. El costo es del negocio, según cuántos puestos de atención y cuánto volumen maneja.',
      plans: [
        {
          name: 'Cliente',
          price: '0',
          period: 'siempre',
          desc: 'Para la persona que saca su turno.',
          featured: true,
          items: ['Turnos ilimitados', 'Sala de espera virtual', 'Avisos de turno', 'Reservas'],
          cta: { label: 'Descargar la app', href: '#descargas' },
        },
        {
          name: 'Negocio',
          price: 'A medida',
          period: 'según puestos y volumen',
          desc: 'Para barberías, consultorios, talleres y gestores.',
          items: [
            'Panel de cola y capacidad',
            'Configuración de servicios y duraciones',
            'Varios puestos de atención',
            'Acompañamiento en la puesta en marcha',
          ],
          cta: { label: 'Pedir una demo', href: 'contact.html' },
        },
      ],
      note:
        'GoReserva se implanta acompañado: primero se configuran los servicios y los puestos, después se abre al público. Escríbenos y lo vemos con tus números reales.',
    },
    downloads: [
      {
        label: 'Descargar APK',
        kind: 'apk',
        href: apk('goreservas.apk'),
        meta: 'Android 8+ · 79,5 MB',
        primary: true,
      },
      {
        label: 'Hablar con el equipo',
        kind: 'web',
        href: 'contact.html',
        meta: 'Para negocios que quieren implantarlo',
      },
    ],
    shots: [],
    faq: [
      {
        q: '¿El cliente tiene que instalar la app?',
        a: 'Para sacar turno sí, hoy la experiencia completa está en la app Android. Para el negocio, el panel se opera desde el mismo APK o desde el equipo de atención.',
      },
      {
        q: '¿Funciona para varios puestos en el mismo local?',
        a: 'Sí. El negocio define cuántos puestos atienden en paralelo y la cola se reparte entre ellos.',
      },
      {
        q: '¿Qué pasa si el cliente no llega?',
        a: 'Transcurrido el margen que configure el negocio, el turno se libera y pasa al siguiente. Queda registrado como ausencia.',
      },
    ],
  },

  /* ---------------------------------------------------------------- MUEVETE */
  {
    slug: 'muevete',
    name: 'Muevete',
    shortName: 'Muevete',
    category: 'Transporte',
    tone: 'muevete',
    icon: 'fa-car-side',
    tagline: 'Muévete por Santa Clara con la tarifa clara desde el primer toque.',
    summary:
      'La app de transporte de Inventtia: pides un carro, ves el precio antes de aceptar y sigues el viaje en el mapa. Tarifa fija en el casco de Santa Clara y precio por kilómetro cuando sales de él. También gestiona cargas y envíos.',
    badges: ['Android', 'Web', 'Tarifa antes de pedir', 'Botón de pánico'],
    facts: [
      { value: '1.500 CUP', label: 'base en el casco' },
      { value: '120 CUP', label: 'por km adicional' },
      { value: 'En vivo', label: 'mapa y conductor' },
      { value: '15 %', label: 'comisión de plataforma' },
    ],
    logo: 'assets/images/inventtia_icon.jpg',
    heroPhone: { logo: '', title: 'Muevete', tag: 'Viajes · Cargas · Envíos', tone: 'cyan', icon: 'fa-car-side' },
    what: [
      'Pedir un viaje y ver el precio antes de confirmar',
      'Mapa con la posición del conductor en vivo',
      'Tarifa fija dentro del casco de Santa Clara',
      'Precio por kilómetro fuera del casco e intermunicipal',
      'Billetera con saldo y métodos de pago',
      'Botón de pánico y contactos de emergencia',
      'Envíos y cargas con seguimiento',
      'Verificación de conductores y documentos',
    ],
    features: [
      {
        icon: 'fa-tag',
        title: 'Precio antes de pedir',
        text: 'La cotización se calcula con la distancia real y se muestra antes de confirmar. Nada de "al llegar te digo".',
      },
      {
        icon: 'fa-map-location-dot',
        title: 'Mapa en vivo',
        text: 'Ves dónde está el carro, cuánto tarda y por dónde va el viaje. El conductor ve lo mismo que tú.',
      },
      {
        icon: 'fa-shield-halved',
        title: 'Seguridad del viaje',
        text: 'Botón de pánico, contactos de emergencia y viaje compartido con quien tú elijas.',
      },
      {
        icon: 'fa-wallet',
        title: 'Billetera',
        text: 'Saldo a favor, recargas y comisión de plataforma transparente. El conductor sabe cuánto gana antes de aceptar.',
      },
      {
        icon: 'fa-box',
        title: 'Cargas y envíos',
        text: 'No solo pasajeros: paquetes y cargas con tipo de vehículo, peso y seguimiento.',
      },
      {
        icon: 'fa-id-card',
        title: 'Conductores verificados',
        text: 'Documentos, licencia y vehículo revisados antes de que el conductor pueda tomar viajes.',
      },
    ],
    steps: [
      {
        title: 'Marca el destino',
        text: 'Origen y destino en el mapa. La app calcula kilómetros y te muestra el precio final.',
      },
      {
        title: 'Confirma el viaje',
        text: 'Aceptas el precio y se asigna un conductor. Puedes seguir su llegada en el mapa.',
      },
      {
        title: 'Paga y valora',
        text: 'Efectivo, transferencia o saldo de la billetera. Al terminar, calificas el viaje.',
      },
    ],
    pricing: {
      model: 'Tarifa por viaje · sin cuota mensual para el pasajero',
      intro:
        'El pasajero paga solo su viaje. El precio se calcula en el servidor antes de confirmar, con la distancia real, y el conductor ve exactamente lo mismo que tú.',
      fare: {
        title: 'Cómo se calcula el precio',
        rows: [
          { label: 'Base dentro del casco de Santa Clara', value: '1.500 CUP' },
          { label: 'Kilómetro adicional', value: '120 CUP / km' },
          { label: 'Recogida fuera del casco (ej. Placetas)', value: 'km de ida + km del viaje' },
          { label: 'Comisión de la plataforma', value: '15 % del viaje' },
          { label: 'Recargo nocturno (22:00 – 06:00)', value: '+20 %' },
        ],
        formula:
          'Casco SC:  precio = 1.500 CUP\nFuera del casco:  precio = 1.500 + 120 × (km de recogida + km del viaje)\nEjemplo Placetas → Santa Clara (≈34 km de recogida + 40 km de viaje):  1.500 + 120 × 74 ≈ 10.400 CUP',
        note:
          'El casco cubre el centro de Santa Clara alrededor del Parque Vidal (4,3 km), e incluye la zona de la universidad José Martí y el reparto Arco Iris. Fuera de ese radio se cobra el kilómetro, y si el carro tiene que salir a buscarte, esos kilómetros también cuentan.',
      },
      plans: [],
      note:
        'Para empresas de transporte y flotas hay planes de gestión: gratis para empezar, 20 USD/mes el plan básico de transportista y hasta 199 USD/mes para centrales con varios despachadores. El pasajero nunca paga cuota: solo su viaje.',
    },
    downloads: [
      {
        label: 'Descargar APK',
        kind: 'apk',
        href: apk('muevete.apk'),
        meta: 'Android 8+ · 187,3 MB',
        primary: true,
      },
      {
        label: 'Abrir versión web',
        kind: 'web',
        href: 'https://muevete.inventtia.com',
        meta: 'Sin instalar · misma cuenta',
      },
    ],
    shots: [],
    faq: [
      {
        q: '¿Cuánto cuesta un viaje dentro de Santa Clara?',
        a: 'Dentro del casco (alrededor del Parque Vidal) la tarifa base es 1.500 CUP. Si el recorrido sale de ese radio, se suman 120 CUP por cada kilómetro.',
      },
      {
        q: '¿Y si estoy en otro municipio?',
        a: 'Se cobra la base de 1.500 CUP más los kilómetros: los de ir a recogerte y los del viaje. Un Placetas → Santa Clara ronda los 10.400 CUP por unos 74 km cobrables.',
      },
      {
        q: '¿El conductor puede cambiar el precio?',
        a: 'No. El precio se calcula en el servidor antes de que aceptes y el conductor lo ve igual que tú. Si algo no cuadra, se reporta desde el viaje.',
      },
      {
        q: '¿Puedo pagar con saldo?',
        a: 'Sí. La billetera permite recargar saldo y pagar con él; también puedes pagar en efectivo o por transferencia.',
      },
    ],
  },

  /* --------------------------------------------------------------- CARNAVAL */
  {
    slug: 'carnaval',
    name: 'Carnaval',
    shortName: 'Carnaval',
    category: 'Comercio y delivery',
    tone: 'carnaval',
    icon: 'fa-bag-shopping',
    tagline: 'Compra, come y envía sin salir del celular.',
    summary:
      'La plataforma para clientes finales: productos de tiendas, comida con delivery y envíos entre provincias. Tres apps que comparten la misma cuenta: la tuya para comprar, la del repartidor para entregar y la del proveedor para vender.',
    badges: ['Play Store', 'App Store', 'Android', 'Delivery'],
    facts: [
      { value: '3 apps', label: 'cliente · delivery · proveedor' },
      { value: 'Pagos', label: 'en línea' },
      { value: 'En vivo', label: 'seguimiento' },
      { value: 'Gratis', label: 'para el cliente' },
    ],
    logo: 'assets/images/carnaval-logo.png',
    heroPhone: { logo: 'assets/images/carnaval-logo.png', title: 'Carnaval', tag: 'Compras · Comida · Envíos', tone: 'red' },
    what: [
      'Compras en tiendas de la plataforma',
      'Comida a domicilio (Carnaval Food)',
      'Envío de paquetes entre provincias',
      'Pagos en línea y contra entrega',
      'Seguimiento del pedido en vivo',
      'Reseñas verificadas de comercios',
      'App del repartidor para tomar entregas',
      'App del proveedor para publicar su catálogo',
    ],
    features: [
      {
        icon: 'fa-utensils',
        title: 'Comida a domicilio',
        text: 'Restaurantes y cafeterías con menú, horario y zona de entrega. El pedido se sigue desde que se cocina hasta que llega.',
      },
      {
        icon: 'fa-box',
        title: 'Envíos entre provincias',
        text: 'Paquetes con dirección de recogida y entrega, peso y precio calculado antes de confirmar.',
      },
      {
        icon: 'fa-credit-card',
        title: 'Pago en línea',
        text: 'Pago con pasarela o contra entrega. El comercio ve el estado del cobro en su panel.',
      },
      {
        icon: 'fa-motorcycle',
        title: 'App del repartidor',
        text: 'Quien reparte tiene su propia app: ve las entregas disponibles, las acepta y las cierra con evidencia.',
      },
      {
        icon: 'fa-store',
        title: 'App del proveedor',
        text: 'El comercio publica productos, precios y stock desde el móvil, sin depender de un administrador.',
      },
      {
        icon: 'fa-star',
        title: 'Reseñas',
        text: 'Las valoraciones se hacen después de la entrega, así que reflejan pedidos reales.',
      },
    ],
    steps: [
      {
        title: 'Elige qué necesitas',
        text: 'Productos, comida o un envío. Cada categoría tiene su propio flujo de precio y entrega.',
      },
      {
        title: 'Confirma y paga',
        text: 'La app muestra el total con la entrega incluida antes de confirmar el pedido.',
      },
      {
        title: 'Sigue la entrega',
        text: 'Ves el estado y quién lleva tu pedido. Al recibirlo puedes valorar al comercio y al repartidor.',
      },
    ],
    pricing: {
      model: 'Gratis para el cliente',
      intro:
        'Descargar y comprar en Carnaval no cuesta nada: pagas el producto y la entrega, igual que en cualquier tienda. Los comercios pagan comisión por venta.',
      plans: [
        {
          name: 'Cliente',
          price: '0',
          period: 'siempre',
          desc: 'Comprar, pedir comida y enviar.',
          featured: true,
          items: ['Sin cuota ni suscripción', 'Pago en línea o contra entrega', 'Seguimiento en vivo', 'Reseñas'],
          cta: { label: 'Descargar Carnaval', href: '#descargas' },
        },
        {
          name: 'Comercio / proveedor',
          price: 'Comisión',
          period: 'por venta',
          desc: 'Para tiendas, restaurantes y proveedores.',
          items: ['Publica tu catálogo', 'Recibe pedidos en el móvil', 'Panel de ventas', 'Soporte de la plataforma'],
          cta: { label: 'Quiero vender', href: 'contact.html' },
        },
      ],
      note:
        'El porcentaje de comisión se acuerda con cada comercio según volumen y categoría. Escríbenos y lo revisamos con tu caso.',
    },
    downloads: [
      {
        label: 'Google Play',
        kind: 'store',
        href: 'https://play.google.com/store/apps/details?id=com.carnaval24',
        meta: 'Recomendado · actualizaciones automáticas',
        primary: true,
      },
      {
        label: 'App Store',
        kind: 'store',
        href: 'https://apps.apple.com/es/app/carnaval-tienda/id6742862060',
        meta: 'iPhone y iPad',
      },
      {
        label: 'APK Carnaval',
        kind: 'apk',
        href: apk('carnaval_new.apk'),
        meta: 'Android 8+ · 93,0 MB',
      },
      {
        label: 'APK Delivery',
        kind: 'apk',
        href: apk('carnaval-delivery.apk'),
        meta: 'Repartidores · 58,5 MB',
      },
      {
        label: 'APK Proveedores',
        kind: 'apk',
        href: apk('carnaval proveedores.apk'),
        meta: 'Comercios · 85,4 MB',
      },
    ],
    shots: [{ src: 'assets/images/carnaval-banner.jpg', alt: 'Carnaval, compras y delivery' }],
    faq: [
      {
        q: '¿Qué diferencia hay entre las tres apps de Carnaval?',
        a: 'La principal es para quien compra. La de Delivery es para el repartidor que toma y entrega pedidos. La de Proveedores es para el comercio que publica su catálogo.',
      },
      {
        q: '¿Cuánto cuesta usar la app?',
        a: 'Nada para el cliente. Pagas el producto y la entrega. La comisión la paga el comercio.',
      },
      {
        q: '¿Hay versión para iPhone?',
        a: 'Sí, está en el App Store. En Android puedes instalarla desde Google Play o con el APK de esta página.',
      },
    ],
  },

  /* ------------------------------------------------------------- SUPERADMIN */
  {
    slug: 'superadmin',
    name: 'Inventtia Super Admin',
    shortName: 'Super Admin',
    category: 'Interno',
    tone: 'admin',
    icon: 'fa-user-gear',
    tagline: 'La consola de operación de la plataforma. Solo para el equipo Inventtia.',
    summary:
      'No es un producto que se venda: es la herramienta con la que Inventtia administra tiendas, licencias y soporte de toda la red. Se documenta aquí por transparencia y para que el equipo tenga un punto de descarga.',
    badges: ['Acceso restringido', 'Android', 'Uso interno'],
    facts: [
      { value: 'Global', label: 'todas las tiendas' },
      { value: 'Licencias', label: 'y suscripciones' },
      { value: 'Soporte', label: 'a tiendas' },
      { value: 'Restringido', label: 'por credenciales' },
    ],
    logo: 'assets/images/inventtia_icon.jpg',
    heroPhone: { logo: '', title: 'Super Admin', tag: 'Operación · Licencias · Soporte', tone: 'cyan', icon: 'fa-user-gear' },
    what: [
      'Alta y administración global de tiendas',
      'Control de licencias y suscripciones',
      'Soporte a tiendas y usuarios',
      'Parámetros globales de la plataforma',
      'Auditoría de operaciones',
    ],
    features: [
      {
        icon: 'fa-globe',
        title: 'Visión global',
        text: 'Todas las tiendas de la red en una sola lista, con su estado y su plan.',
      },
      {
        icon: 'fa-key',
        title: 'Licencias',
        text: 'Altas, renovaciones y bloqueos de licencia sin tocar la base de datos a mano.',
      },
      {
        icon: 'fa-headset',
        title: 'Soporte',
        text: 'Impersonar una tienda para reproducir un problema es más rápido que pedirle capturas al cliente.',
      },
    ],
    steps: [
      {
        title: 'Credenciales del equipo',
        text: 'El acceso se entrega al personal de Inventtia con doble verificación.',
      },
      {
        title: 'Operación diaria',
        text: 'Altas, licencias, incidencias y parámetros globales de la plataforma.',
      },
    ],
    pricing: {
      model: 'No se comercializa',
      intro:
        'Super Admin es parte de la operación interna de Inventtia. No tiene precio de venta ni se instala en tiendas de clientes.',
      plans: [
        {
          name: 'Uso interno',
          price: '—',
          period: 'equipo Inventtia',
          desc: 'Acceso restringido a operadores de la plataforma.',
          items: ['Sin costo para clientes', 'Acceso por credenciales internas', 'Auditoría de acciones'],
          cta: { label: 'Contactar soporte', href: 'contact.html' },
        },
      ],
      note: 'Si eres cliente y necesitas soporte, escríbenos por WhatsApp o desde la página de contacto. No necesitas esta app.',
    },
    downloads: [
      {
        label: 'Descargar APK',
        kind: 'apk',
        href: apk('superadmin.apk'),
        meta: 'Android 8+ · 69,1 MB · uso interno',
        primary: true,
      },
    ],
    shots: [],
    faq: [
      {
        q: '¿Puedo descargar Super Admin si soy cliente?',
        a: 'Puedes descargar el APK, pero sin credenciales internas no hace nada. Para gestionar tu tienda usa Inventtia Gestión.',
      },
      {
        q: '¿Dónde está la versión web?',
        a: 'El panel web de superadministración es de acceso interno y no se publica en esta web.',
      },
    ],
  },
];

/** Builds de APK que existen en el bucket pero no son la descarga recomendada. */
export const EXTRA_APKS = [
  {
    file: 'inventtia catalogo.apk',
    name: 'Inventtia Catálogo (build anterior)',
    note: 'Build previa del catálogo. Usa la de la página de Catálogo salvo que soporte te pida esta.',
    size: '26,2 MB',
  },
  {
    file: 'vendedor cuba.apk',
    name: 'Inventtia Caja (build Cuba)',
    note: 'Misma build que la caja actual, publicada con el nombre anterior.',
    size: '95,9 MB',
  },
  {
    file: 'flow.apk',
    name: 'GoReserva (build alternativa)',
    note: 'Misma versión que goreservas.apk, publicada con otro nombre.',
    size: '79,5 MB',
  },
  {
    file: 'carnaval.apk',
    name: 'Carnaval (build anterior)',
    note: 'Build anterior a carnaval_new.apk. Solo si soporte lo indica.',
    size: '94,5 MB',
  },
];