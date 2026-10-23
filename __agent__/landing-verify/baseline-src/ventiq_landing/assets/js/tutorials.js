// Tutorials Page JavaScript

document.addEventListener('DOMContentLoaded', function () {
    initTutorialCategories();
    initTutorialCards();
    initTutorialModal();
});

// Tutorial categories switching
function initTutorialCategories() {
    const categoryCards = document.querySelectorAll('.category-card');
    const tutorialSections = document.querySelectorAll('.tutorials-content');

    categoryCards.forEach(card => {
        card.addEventListener('click', function () {
            const category = this.dataset.category;

            // Update active category
            categoryCards.forEach(c => c.classList.remove('active'));
            this.classList.add('active');

            // Show corresponding tutorial section
            tutorialSections.forEach(section => {
                section.classList.remove('active');
                if (section.classList.contains(`${category}-tutorials`)) {
                    section.classList.add('active');
                }
            });
        });
    });
}

// Tutorial cards interaction
function initTutorialCards() {
    const tutorialCards = document.querySelectorAll('.tutorial-card');

    tutorialCards.forEach(card => {
        card.addEventListener('click', function () {
            const tutorialType = this.dataset.tutorial;
            openTutorial(tutorialType);
        });
    });
}

// Tutorial modal functionality
function initTutorialModal() {
    const modal = document.getElementById('tutorialModal');
    const closeBtn = document.getElementById('closeModal');
    const prevBtn = document.getElementById('prevStep');
    const nextBtn = document.getElementById('nextStep');

    if (closeBtn) {
        closeBtn.addEventListener('click', closeTutorialModal);
    }

    if (prevBtn) {
        prevBtn.addEventListener('click', previousStep);
    }

    if (nextBtn) {
        nextBtn.addEventListener('click', nextStep);
    }

    // Close modal when clicking overlay
    if (modal) {
        modal.addEventListener('click', function (e) {
            if (e.target === modal) {
                closeTutorialModal();
            }
        });
    }

    // Keyboard navigation
    document.addEventListener('keydown', function (e) {
        if (modal && modal.classList.contains('active')) {
            if (e.key === 'Escape') {
                closeTutorialModal();
            } else if (e.key === 'ArrowLeft') {
                previousStep();
            } else if (e.key === 'ArrowRight') {
                nextStep();
            }
        }
    });
}

// Tutorial data
const tutorialData = {
    // Seller App Tutorials
    'venta': {
        title: 'Cómo realizar una venta',
        steps: [
            {
                title: 'Seleccionar productos',
                content: 'Navega por las categorías y selecciona los productos que el cliente desea comprar.',
                instructions: [
                    'Abre la aplicación Inventtia Vendedor',
                    'Selecciona una categoría de productos',
                    'Busca el producto deseado',
                    'Toca el producto para ver sus detalles',
                    'Ajusta la cantidad y agrega al carrito'
                ]
            },
            {
                title: 'Revisar el carrito',
                content: 'Verifica que todos los productos y cantidades sean correctos antes de proceder al pago.',
                instructions: [
                    'Toca el ícono del carrito en la parte superior',
                    'Revisa cada producto en la lista',
                    'Modifica cantidades si es necesario',
                    'Verifica el total de la compra',
                    'Procede al checkout'
                ]
            },
            {
                title: 'Procesar el pago',
                content: 'Selecciona el método de pago y completa la transacción.',
                instructions: [
                    'Elige el método de pago (efectivo, tarjeta, etc.)',
                    'Ingresa el monto recibido si es efectivo',
                    'Calcula el cambio automáticamente',
                    'Confirma el pago',
                    'Genera el recibo de venta'
                ]
            },
            {
                title: 'Finalizar la venta',
                content: 'Completa la venta e imprime el ticket si es necesario.',
                instructions: [
                    'Confirma que el pago fue exitoso',
                    'Imprime el ticket de venta',
                    'Entrega el recibo al cliente',
                    'La venta se registra automáticamente',
                    'El inventario se actualiza en tiempo real'
                ]
            }
        ]
    },
    'inventario': {
        title: 'Consultar inventario',
        steps: [
            {
                title: 'Acceder al inventario',
                content: 'Navega a la sección de inventario para ver el stock disponible.',
                instructions: [
                    'Abre el menú principal de la aplicación',
                    'Selecciona "Inventario" o "Stock"',
                    'Espera a que cargue la información',
                    'Verás una lista de todos los productos'
                ]
            },
            {
                title: 'Buscar productos',
                content: 'Utiliza los filtros y búsqueda para encontrar productos específicos.',
                instructions: [
                    'Usa la barra de búsqueda en la parte superior',
                    'Filtra por categoría si es necesario',
                    'Ordena por nombre, stock o precio',
                    'Toca un producto para ver más detalles'
                ]
            },
            {
                title: 'Verificar disponibilidad',
                content: 'Revisa las cantidades disponibles y ubicaciones de los productos.',
                instructions: [
                    'Observa la cantidad disponible de cada producto',
                    'Verifica en qué almacén se encuentra',
                    'Nota los productos con stock bajo',
                    'Reporta cualquier discrepancia encontrada'
                ]
            }
        ]
    },
    'configuracion': {
        title: 'Configurar la aplicación',
        steps: [
            {
                title: 'Acceder a configuración',
                content: 'Abre el menú de configuración de la aplicación.',
                instructions: [
                    'Toca el ícono de menú (☰)',
                    'Selecciona "Configuración" o "Ajustes"',
                    'Verás las diferentes opciones disponibles'
                ]
            },
            {
                title: 'Configurar impresión',
                content: 'Ajusta las opciones de impresión de tickets.',
                instructions: [
                    'Busca la sección "Impresión"',
                    'Habilita o deshabilita la impresión automática',
                    'Configura la impresora si es necesario',
                    'Prueba la impresión con un ticket de ejemplo'
                ]
            },
            {
                title: 'Ajustar notificaciones',
                content: 'Personaliza las notificaciones que recibes.',
                instructions: [
                    'Ve a la sección "Notificaciones"',
                    'Habilita las notificaciones importantes',
                    'Configura los sonidos y vibraciones',
                    'Ajusta la frecuencia de las alertas'
                ]
            },
            {
                title: 'Configurar perfil',
                content: 'Actualiza tu información personal y de trabajo.',
                instructions: [
                    'Accede a "Perfil de usuario"',
                    'Actualiza tu nombre y datos de contacto',
                    'Verifica tu rol y permisos',
                    'Cambia tu contraseña si es necesario'
                ]
            },
            {
                title: 'Sincronización',
                content: 'Configura la sincronización de datos.',
                instructions: [
                    'Ve a "Sincronización"',
                    'Verifica la conexión a internet',
                    'Configura la sincronización automática',
                    'Realiza una sincronización manual si es necesario'
                ]
            }
        ]
    },
    'turnos': {
        title: 'Gestión de Turnos',
        steps: [
            {
                title: 'Apertura de turno',
                content: 'Inicia tu turno registrando el efectivo inicial.',
                instructions: [
                    'Abre Inventtia Vendedor',
                    'Selecciona "Apertura de Turno"',
                    'Registra el dinero inicial',
                    'Confirma la apertura'
                ]
            },
            {
                title: 'Dashboard del turno',
                content: 'Monitorea ventas y estado de caja durante el turno.',
                instructions: [
                    'Observa ventas realizadas',
                    'Revisa transacciones',
                    'Verifica totales del turno',
                    'Monitorea el estado de caja'
                ]
            },
            {
                title: 'Imprimir reporte de productos',
                content: 'Genera un reporte de productos vendidos.',
                instructions: [
                    'Entra a "Reportes del Turno"',
                    'Selecciona "Productos Vendidos"',
                    'Revisa la lista',
                    'Imprime si es necesario'
                ]
            },
            {
                title: 'Preparar cierre',
                content: 'Verifica totales y documentos antes de cerrar.',
                instructions: [
                    'Revisa ventas del turno',
                    'Verifica totales de efectivo',
                    'Cuenta dinero en caja',
                    'Prepara documentos'
                ]
            },
            {
                title: 'Cierre de turno',
                content: 'Finaliza el turno registrando el cierre de caja.',
                instructions: [
                    'Selecciona "Cierre de Turno"',
                    'Ingresa el dinero final',
                    'Verifica contra el sistema',
                    'Confirma el cierre'
                ]
            }
        ]
    },

    'egresos': {
        title: 'Manejo de Egresos',
        steps: [
            {
                title: 'Acceder a egresos',
                content: 'Ingresa a la sección para registrar salidas de dinero.',
                instructions: [
                    'Desde el menú principal',
                    'Selecciona "Egresos" o "Gastos"',
                    'Elige "Nuevo Egreso"',
                    'Inicia el registro'
                ]
            },
            {
                title: 'Registrar egreso parcial',
                content: 'Registra una extracción parcial de efectivo.',
                instructions: [
                    'Selecciona tipo de egreso',
                    'Ingresa el monto',
                    'Especifica el motivo',
                    'Agrega observaciones'
                ]
            },
            {
                title: 'Confirmar egreso',
                content: 'Finaliza y confirma la salida de dinero.',
                instructions: [
                    'Revisa la información',
                    'Verifica el monto',
                    'Confirma el egreso',
                    'El saldo de caja se actualiza automáticamente'
                ]
            }
        ]
    },

    // Admin Web Tutorials
    'registro-empresa': {
        title: 'Registrar una empresa',
        steps: [
            {
                title: 'Crear cuenta de administrador',
                content: 'Registra una nueva cuenta para el administrador de la empresa.',
                instructions: [
                    'Accede a la página de registro de Inventtia Admin',
                    'Ingresa el nombre completo del administrador',
                    'Proporciona un email válido',
                    'Crea una contraseña segura',
                    'Confirma la contraseña'
                ]
            },
            {
                title: 'Información de la empresa',
                content: 'Completa los datos básicos de tu empresa.',
                instructions: [
                    'Ingresa el nombre de la empresa',
                    'Proporciona la dirección física',
                    'Especifica la ubicación (ciudad, país)',
                    'Agrega información de contacto adicional'
                ]
            },
            {
                title: 'Configuración inicial',
                content: 'Configura los elementos básicos necesarios para operar.',
                instructions: [
                    'Crea al menos un punto de venta (TPV)',
                    'Configura al menos un almacén',
                    'Asigna personal con sus respectivos roles',
                    'Verifica que toda la información sea correcta'
                ]
            },
            {
                title: 'Finalizar registro',
                content: 'Completa el proceso de registro y activa tu cuenta.',
                instructions: [
                    'Revisa toda la información ingresada',
                    'Confirma que los datos sean correctos',
                    'Acepta los términos y condiciones',
                    'Finaliza el registro',
                    'Verifica tu email para activar la cuenta'
                ]
            }
        ]
    },
    'configuracion-categorias': {
        title: 'Configuración de Categorías y Subcategorías',
        steps: [
            {
                title: 'Acceder a configuración',
                content: 'Abre la sección de categorías por tienda.',
                instructions: [
                    'Desde el menú admin',
                    'Entra a "Productos"',
                    'Selecciona "Categorías por tienda"',
                    'Carga la vista de categorías'
                ]
            },
            {
                title: 'Ver categorías existentes',
                content: 'Revisa el listado actual de categorías.',
                instructions: [
                    'Observa las categorías existentes',
                    'Revisa su estado y jerarquía',
                    'Identifica las que necesitan ajustes'
                ]
            },
            {
                title: 'Crear nueva categoría',
                content: 'Agrega una nueva categoría.',
                instructions: [
                    'Haz clic en "Nueva Categoría"',
                    'Escribe el nombre y descripción',
                    'Guarda la nueva categoría'
                ]
            },
            {
                title: 'Gestionar subcategorías',
                content: 'Crea o edita subcategorías por tienda.',
                instructions: [
                    'Selecciona una categoría',
                    'Haz clic en "Agregar Subcategoría"',
                    'Completa los datos y guarda',
                    'Verifica la relación con la categoría padre'
                ]
            },
            {
                title: 'Revisar y confirmar',
                content: 'Verifica que los cambios se reflejan en el catálogo.',
                instructions: [
                    'Vuelve al listado principal',
                    'Confirma que aparecen las nuevas categorías/subcategorías',
                    'Comprueba que los productos pueden asignarse correctamente'
                ]
            }
        ]
    },
    'almacenes': {
        title: 'Gestionar almacenes',
        steps: [
            {
                title: 'Abrir módulo de Almacenes',
                content: 'Accede al módulo para gestionar tus almacenes.',
                instructions: [
                    'Desde el menú principal',
                    'Selecciona "Almacenes"',
                    'Espera a que cargue el listado de almacenes'
                ]
            },
            {
                title: 'Listado de almacenes',
                content: 'Consulta y filtra los almacenes existentes.',
                instructions: [
                    'Revisa la lista de almacenes',
                    'Usa búsqueda o filtros si es necesario',
                    'Desde aquí puedes: crear un nuevo almacén o abrir los detalles de uno existente'
                ]
            },
            {
                title: 'Ver detalles de un almacén',
                content: 'Ingresa al detalle de un almacén para gestionar su configuración interna.',
                instructions: [
                    'Selecciona un almacén del listado',
                    'Abre su vista de detalles',
                    'Ubica las secciones de "Zonas", "Capacidades" y "Límites"',
                    'Revisa la configuración actual'
                ]
            },
            {
                title: 'Gestionar zonas y capacidades',
                content: 'Administra las zonas del almacén junto con sus capacidades y límites.',
                instructions: [
                    'Agrega una nueva zona si es necesario',
                    'Define capacidad y límites por zona',
                    'Guarda los cambios',
                    'Nota: En este módulo NO se gestiona inventario de productos ni responsables de almacén'
                ]
            }
        ]
    },
    'productos': {
        title: 'Agregar productos',
        steps: [
            {
                title: 'Abrir módulo de Productos',
                content: 'Accede al módulo para gestionar el clasificador de productos.',
                instructions: [
                    'Desde el menú principal',
                    'Selecciona "Productos"',
                    'Espera a que cargue el listado de productos'
                ]
            },
            {
                title: 'Listado de productos',
                content: 'Consulta y filtra los productos existentes.',
                instructions: [
                    'Revisa la lista de productos',
                    'Usa búsqueda o filtros si es necesario',
                    'Desde aquí puedes: insertar un nuevo producto o editar uno existente'
                ]
            },
            {
                title: 'Insertar nuevo producto',
                content: 'Inicia el registro del producto.',
                instructions: [
                    'Haz clic en "Nuevo Producto"',
                    'Se abrirá el formulario de registro',
                    'Prepárate para completar los datos generales'
                ]
            },
            {
                title: 'Datos generales del producto',
                content: 'Registra la información básica del producto.',
                instructions: [
                    'Escribe el nombre del producto',
                    'Agrega una descripción (opcional)',
                    'Define código/SKU si aplica',
                    'Guarda temporalmente o continúa al siguiente paso'
                ]
            },
            {
                title: 'Categoría y Subcategoría',
                content: 'Clasifica el producto correctamente.',
                instructions: [
                    'Selecciona la categoría',
                    'Selecciona la subcategoría correspondiente',
                    'Verifica que la clasificación es correcta antes de continuar'
                ]
            },
            {
                title: 'Precio de venta y otros datos',
                content: 'Configura precio de venta y metadatos del producto.',
                instructions: [
                    'Registra el precio de venta',
                    'Configura variantes (tallas, colores, etc.) si aplica',
                    'Agrega presentaciones adicionales si aplica',
                    'Para productos elaborados, registra los ingredientes',
                    'Nota: Aquí SOLO se registra el clasificador del producto. NO se registra precio de costo ni cantidad en inventario.'
                ]
            },
            {
                title: 'Confirmar y guardar',
                content: 'Revisa el resumen y guarda el producto.',
                instructions: [
                    'Verifica los datos ingresados',
                    'Confirma el registro del producto',
                    'Regresarás al listado donde podrás ver el nuevo producto'
                ]
            }
        ]
    },
    'recepcion': {
        title: 'Recepcionar productos',
        steps: [
            {
                title: 'Abrir Inventario',
                content: 'Accede al módulo de inventario desde el menú.',
                instructions: [
                    'Desde el menú principal',
                    'Selecciona "Inventario"',
                    'Espera a que cargue el módulo'
                ]
            },
            {
                title: 'Crear nueva operación',
                content: 'Abre el panel de operaciones para iniciar un movimiento.',
                instructions: [
                    'Haz clic en el botón "Crear"',
                    'Revisa las opciones disponibles de operación'
                ]
            },
            {
                title: 'Seleccionar Recepción de productos',
                content: 'Elige el tipo de operación de recepción.',
                instructions: [
                    'Selecciona "Recepción de productos"',
                    'Se abrirá el formulario de recepción'
                ]
            },
            {
                title: 'Seleccionar destino',
                content: 'Define a qué almacén/zona se recepcionarán los productos.',
                instructions: [
                    'Selecciona el almacén o zona de destino',
                    'Confirma la selección'
                ]
            },
            {
                title: 'Seleccionar productos',
                content: 'Elige los productos que vas a recepcionar.',
                instructions: [
                    'Busca y selecciona el/los producto(s)',
                    'Puedes agregar varios productos a la recepción'
                ]
            },
            {
                title: 'Definir cantidad y costo',
                content: 'Registra cantidades y precio de costo unitario por producto.',
                instructions: [
                    'Ingresa la cantidad a recepcionar',
                    'Registra el precio de costo unitario',
                    'Repite por cada producto agregado'
                ]
            },
            {
                title: 'Guardar operación',
                content: 'Guarda la operación como pendiente.',
                instructions: [
                    'Revisa el resumen de la operación',
                    'Guarda la recepción',
                    'La operación queda en estado pendiente'
                ]
            },
            {
                title: 'Buscar operación pendiente',
                content: 'Localiza la operación pendiente para finalizarla.',
                instructions: [
                    'Abre el listado de operaciones',
                    'Filtra por estado "Pendiente" si es necesario',
                    'Selecciona la operación que creaste'
                ]
            },
            {
                title: 'Completar operación',
                content: 'Confirma la recepción para aplicar los cambios.',
                instructions: [
                    'Revisa los datos finales',
                    'Confirma la operación',
                    'La recepción quedará como completada'
                ]
            },
            {
                title: 'Ver inventario actualizado',
                content: 'Retorna al listado y verifica las existencias actualizadas.',
                instructions: [
                    'Vuelve al listado de inventario',
                    'Verifica que las cantidades estén actualizadas'
                ]
            }
        ]
    },
    'transferencias': {
        title: 'Transferencias entre Zonas',
        steps: [
            {
                title: 'Acceder a operaciones',
                content: 'Ve a la sección de operaciones de inventario.',
                instructions: [
                    'Desde el menú principal',
                    'Selecciona "Inventario"',
                    'Ve a "Operaciones"',
                    'Haz clic en "Nueva Transferencia"'
                ]
            },
            {
                title: 'Seleccionar zonas',
                content: 'Define las zonas de origen y destino.',
                instructions: [
                    'Selecciona la zona de origen',
                    'Elige la zona de destino',
                    'Verifica que las zonas sean diferentes',
                    'Confirma la selección'
                ]
            },
            {
                title: 'Elegir productos',
                content: 'Selecciona los productos a transferir.',
                instructions: [
                    'Busca el producto deseado',
                    'Verifica el stock disponible en origen',
                    'Selecciona la cantidad a transferir',
                    'Agrega el producto a la transferencia'
                ]
            },
            {
                title: 'Confirmar cantidades',
                content: 'Revisa y confirma las cantidades seleccionadas.',
                instructions: [
                    'Verifica cada producto en la lista',
                    'Ajusta cantidades si es necesario',
                    'Confirma que no excedas el stock disponible',
                    'Procede con la transferencia'
                ]
            },
            {
                title: 'Ejecutar transferencia',
                content: 'Completa el proceso de transferencia.',
                instructions: [
                    'Revisa el resumen final',
                    'Confirma la operación',
                    'El sistema actualiza automáticamente los inventarios',
                    'Genera el comprobante de transferencia'
                ]
            }
        ]
    },
    'dashboard-ventas': {
        title: 'Dashboard de Ventas',
        steps: [
            {
                title: 'Acceder al dashboard ejecutivo',
                content: 'Navega al panel principal de análisis de ventas.',
                instructions: [
                    'Inicia sesión en Inventtia Admin',
                    'Ve al menú principal',
                    'Selecciona "Dashboard Ejecutivo"',
                    'Observa las métricas generales del negocio'
                ]
            },
            {
                title: 'Analizar ventas generales',
                content: 'Revisa las métricas principales de ventas.',
                instructions: [
                    'Observa el total de ventas del período',
                    'Revisa el número de transacciones',
                    'Analiza las tendencias de crecimiento',
                    'Identifica los picos de ventas'
                ]
            },
            {
                title: 'Ventas por vendedor',
                content: 'Analiza el rendimiento individual de cada vendedor.',
                instructions: [
                    'Ve a la sección "Ventas por Vendedor"',
                    'Compara el rendimiento entre vendedores',
                    'Identifica a los vendedores más productivos',
                    'Revisa las metas y objetivos alcanzados'
                ]
            },
            {
                title: 'Generar reportes',
                content: 'Crea reportes detallados de ventas.',
                instructions: [
                    'Selecciona el período de análisis',
                    'Elige los filtros necesarios',
                    'Genera el reporte de ventas',
                    'Exporta los datos si es necesario'
                ]
            }
        ]
    },

    // Catalogo App Tutorials
    'catalogo-registro': {
        title: 'Registrarse y explorar',
        steps: [
            {
                title: 'Crear tu cuenta',
                content: 'Regístrate en Inventtia Catálogo para empezar a comprar.',
                instructions: [
                    'Descarga la app o accede desde catalogo.inventtia.com',
                    'Toca "Registrarse"',
                    'Ingresa tu nombre, email y contraseña',
                    'Confirma tu email para activar la cuenta'
                ]
            },
            {
                title: 'Explorar tiendas',
                content: 'Descubre las tiendas disponibles y sus productos.',
                instructions: [
                    'En la pantalla principal verás las tiendas destacadas',
                    'Toca cualquier tienda para ver su catálogo',
                    'Explora las categorías de productos',
                    'Usa la barra de búsqueda para encontrar algo específico'
                ]
            },
            {
                title: 'Configurar tu perfil y dirección',
                content: 'Completa tu perfil para agilizar futuras compras.',
                instructions: [
                    'Ve a "Mi Cuenta" desde el menú',
                    'Completa tus datos personales',
                    'Agrega tu dirección de entrega',
                    'Guarda la configuración'
                ]
            }
        ]
    },
    'catalogo-compra': {
        title: 'Buscar productos y comprar',
        steps: [
            {
                title: 'Buscar productos',
                content: 'Encuentra los productos que necesitas rápidamente.',
                instructions: [
                    'Usa la barra de búsqueda para escribir el nombre del producto',
                    'Filtra por categoría si prefieres explorar',
                    'Los resultados muestran precio, tienda y disponibilidad',
                    'Toca un producto para ver sus detalles completos'
                ]
            },
            {
                title: 'Ver detalles del producto',
                content: 'Revisa toda la información antes de comprar.',
                instructions: [
                    'Observa fotos, descripción y precio del producto',
                    'Revisa si tiene descuento o precio especial',
                    'Lee las reseñas de otros compradores',
                    'Verifica el stock disponible'
                ]
            },
            {
                title: 'Agregar al carrito',
                content: 'Añade productos a tu carrito de compras.',
                instructions: [
                    'Selecciona la cantidad deseada',
                    'Toca "Agregar al carrito"',
                    'Puedes seguir comprando y agregar más productos',
                    'El carrito muestra cuántos productos llevas'
                ]
            },
            {
                title: 'Revisar el carrito',
                content: 'Verifica tu selección antes de pagar.',
                instructions: [
                    'Toca el ícono del carrito',
                    'Revisa cada producto y su cantidad',
                    'Modifica cantidades o elimina productos si necesitas',
                    'Verifica el total de la compra'
                ]
            },
            {
                title: 'Confirmar pedido',
                content: 'Finaliza tu compra seleccionando dirección y método de pago.',
                instructions: [
                    'Selecciona tu dirección de entrega',
                    'Revisa el subtotal y costo de envío',
                    'Elige método de pago (transferencia o Tropipay)',
                    'Confirma el pedido'
                ]
            }
        ]
    },
    'catalogo-pedidos': {
        title: 'Pago y seguimiento de pedidos',
        steps: [
            {
                title: 'Realizar el pago',
                content: 'Completa el pago de tu pedido de forma segura.',
                instructions: [
                    'Si elegiste transferencia: realiza la transferencia al número indicado',
                    'Si elegiste Tropipay: completa el pago en línea',
                    'Espera la confirmación del pago',
                    'Recibirás una notificación cuando se verifique'
                ]
            },
            {
                title: 'Seguir el estado del pedido',
                content: 'Monitorea tu pedido en cada etapa.',
                instructions: [
                    'Ve a "Mis Pedidos" desde el menú',
                    'Observa el estado: creado, confirmado, en camino, entregado',
                    'Recibes notificaciones automáticas en cada cambio',
                    'Toca el pedido para ver detalles completos'
                ]
            },
            {
                title: 'Recibir la entrega',
                content: 'Recibe tu pedido en la dirección indicada.',
                instructions: [
                    'Recibirás una notificación cuando el repartidor salga',
                    'Verifica que los productos estén completos',
                    'Confirma la recepción en la app',
                    'Si hay algún problema, contacta soporte por WhatsApp'
                ]
            },
            {
                title: 'Calificar y opinar',
                content: 'Deja tu reseña para ayudar a otros compradores.',
                instructions: [
                    'Después de recibir tu pedido, ve al producto',
                    'Califica con estrellas (1 a 5)',
                    'Escribe un comentario sobre tu experiencia',
                    'Tu opinión ayuda a otros compradores a elegir mejor'
                ]
            }
        ]
    }
};

let currentTutorial = null;
let currentStep = 0;

// Open tutorial
function openTutorial(tutorialType) {
    const tutorial = tutorialData[tutorialType];
    if (!tutorial) return;

    currentTutorial = tutorial;
    currentStep = 0;

    const modal = document.getElementById('tutorialModal');
    const modalTitle = document.getElementById('modalTitle');

    modalTitle.textContent = tutorial.title;

    loadTutorialStep();
    modal.classList.add('active');
}

// Load tutorial step
function loadTutorialStep() {
    if (!currentTutorial) return;

    const step = currentTutorial.steps[currentStep];
    const stepsContainer = document.getElementById('tutorialSteps');
    const currentStepEl = document.getElementById('currentStep');
    const totalStepsEl = document.getElementById('totalSteps');
    const prevBtn = document.getElementById('prevStep');
    const nextBtn = document.getElementById('nextStep');

    // Controles
    currentStepEl.textContent = currentStep + 1;
    totalStepsEl.textContent = currentTutorial.steps.length;
    prevBtn.disabled = currentStep === 0;
    nextBtn.textContent = currentStep === currentTutorial.steps.length - 1 ? 'Finalizar' : 'Siguiente';

    // Obtener screenshot por título del tutorial y paso
    const screenshotSrc = getScreenshotForStep(currentTutorial.title, currentStep);

    // Render
    stepsContainer.innerHTML = `
      <div class="tutorial-step active">
        <div class="step-content">
          <div class="step-text">
            <h4>${step.title}</h4>
            <p>${step.content}</p>
            <ul class="step-list">
              ${step.instructions.map(instruction => `<li>${instruction}</li>`).join('')}
            </ul>
          </div>
          <div class="step-visual">
            <div class="screenshot-container">
              <div class="screenshot-overlay">
                <div class="step-indicator">${currentStep + 1}</div>
                <div class="zoom-hint"><i class="fas fa-search-plus"></i> Click para ampliar</div>
              </div>
              <img
                class="tutorial-screenshot"
                src="${screenshotSrc}"
                alt="Paso ${currentStep + 1} - ${currentTutorial.title}"
                onclick="openLightbox('${screenshotSrc}', '${step.title.replace(/'/g, "\\'")}')"
                onerror="this.src='assets/images/placeholder-screenshot.svg'"
              />
            </div>
          </div>
        </div>
      </div>
    `;
}

// Generate mockup content based on step
function generateMockupContent(stepIndex) {
    const mockupItems = [
        '<div class="mockup-item">📱 Pantalla principal</div>',
        '<div class="mockup-item">📋 Lista de productos</div>',
        '<div class="mockup-item">🛒 Carrito de compras</div>',
        '<div class="mockup-item">💳 Procesando pago</div>',
        '<div class="mockup-item">✅ Venta completada</div>'
    ];

    let content = '';
    for (let i = 0; i <= stepIndex && i < mockupItems.length; i++) {
        content += mockupItems[i];
    }

    if (stepIndex < mockupItems.length - 1) {
        content += '<div class="mockup-button">Continuar</div>';
    }

    return content;
}

// Navigation functions
function previousStep() {
    if (currentStep > 0) {
        currentStep--;
        loadTutorialStep();
    }
}

function nextStep() {
    if (currentStep < currentTutorial.steps.length - 1) {
        currentStep++;
        loadTutorialStep();
    } else {
        // Tutorial completed
        closeTutorialModal();
        showTutorialCompleted();
    }
}

// Close tutorial modal
function closeTutorialModal() {
    const modal = document.getElementById('tutorialModal');
    modal.classList.remove('active');
    currentTutorial = null;
    currentStep = 0;
}

// Show tutorial completed message
function showTutorialCompleted() {
    // Use the notification system from main.js
    if (typeof showNotification === 'function') {
        showNotification(
            '¡Tutorial completado!',
            'Has completado exitosamente el tutorial. ¡Ahora puedes aplicar lo aprendido!',
            'success'
        );
    }
}
// Lightbox (si no existe en este archivo)
function initLightbox() {
    const lightbox = document.createElement('div');
    lightbox.id = 'screenshotLightbox';
    lightbox.className = 'lightbox-overlay';
    lightbox.innerHTML = `
      <div class="lightbox-content">
        <img id="lightboxImage" src="" alt="">
        <button class="lightbox-close">&times;</button>
        <div class="lightbox-caption"></div>
      </div>
    `;
    document.body.appendChild(lightbox);

    const closeBtn = lightbox.querySelector('.lightbox-close');
    closeBtn.addEventListener('click', closeLightbox);
    lightbox.addEventListener('click', function (e) {
        if (e.target === lightbox) closeLightbox();
    });

    document.addEventListener('keydown', function (e) {
        const overlay = document.getElementById('screenshotLightbox');
        if (overlay && overlay.classList.contains('active') && e.key === 'Escape') closeLightbox();
    });
}

function openLightbox(imageSrc, caption) {
    let overlay = document.getElementById('screenshotLightbox');
    if (!overlay) { initLightbox(); overlay = document.getElementById('screenshotLightbox'); }
    const img = document.getElementById('lightboxImage');
    const cap = overlay.querySelector('.lightbox-caption');
    img.src = imageSrc;
    cap.textContent = caption || '';
    overlay.classList.add('active');
    document.body.style.overflow = 'hidden';
}

function closeLightbox() {
    const overlay = document.getElementById('screenshotLightbox');
    if (!overlay) return;
    overlay.classList.remove('active');
    document.body.style.overflow = '';
}

document.addEventListener('DOMContentLoaded', initLightbox);
// FAQ functionality
document.addEventListener('DOMContentLoaded', function () {
    const faqItems = document.querySelectorAll('.faq-item');

    faqItems.forEach(item => {
        const question = item.querySelector('.faq-question');

        question.addEventListener('click', function () {
            const isActive = item.classList.contains('active');

            // Close all other FAQ items
            faqItems.forEach(otherItem => {
                otherItem.classList.remove('active');
            });

            // Toggle current item
            if (!isActive) {
                item.classList.add('active');
            }
        });
    });
});
