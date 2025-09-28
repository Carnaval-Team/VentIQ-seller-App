// Tutorials Page JavaScript

document.addEventListener('DOMContentLoaded', function() {
    initTutorialCategories();
    initTutorialCards();
    initTutorialModal();
});

// Tutorial categories switching
function initTutorialCategories() {
    const categoryCards = document.querySelectorAll('.category-card');
    const tutorialSections = document.querySelectorAll('.tutorials-content');
    
    categoryCards.forEach(card => {
        card.addEventListener('click', function() {
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
        card.addEventListener('click', function() {
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
        modal.addEventListener('click', function(e) {
            if (e.target === modal) {
                closeTutorialModal();
            }
        });
    }
    
    // Keyboard navigation
    document.addEventListener('keydown', function(e) {
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
                    'Abre la aplicación VentIQ Seller',
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
    
    // Admin Web Tutorials
    'registro-empresa': {
        title: 'Registrar una empresa',
        steps: [
            {
                title: 'Crear cuenta de administrador',
                content: 'Registra una nueva cuenta para el administrador de la empresa.',
                instructions: [
                    'Accede a la página de registro de Vendedor Cuba Admin',
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
    'almacenes': {
        title: 'Gestionar almacenes',
        steps: [
            {
                title: 'Acceder a almacenes',
                content: 'Navega a la sección de gestión de almacenes.',
                instructions: [
                    'Inicia sesión en Vendedor Cuba Admin',
                    'Ve al menú principal',
                    'Selecciona "Almacenes" o "Inventario"',
                    'Verás la lista de almacenes existentes'
                ]
            },
            {
                title: 'Crear nuevo almacén',
                content: 'Agrega un nuevo almacén a tu sistema.',
                instructions: [
                    'Haz clic en "Agregar Almacén"',
                    'Ingresa el nombre del almacén',
                    'Proporciona la dirección física',
                    'Especifica la ubicación',
                    'Define el tipo de almacén'
                ]
            },
            {
                title: 'Configurar almacén',
                content: 'Establece las configuraciones específicas del almacén.',
                instructions: [
                    'Asigna un responsable del almacén',
                    'Configura las zonas de almacenamiento',
                    'Establece los niveles de stock mínimo',
                    'Define los permisos de acceso',
                    'Configura las notificaciones'
                ]
            },
            {
                title: 'Gestionar inventario',
                content: 'Administra el inventario dentro del almacén.',
                instructions: [
                    'Agrega productos al almacén',
                    'Establece ubicaciones específicas',
                    'Configura niveles de reorden',
                    'Realiza conteos de inventario',
                    'Genera reportes de stock'
                ]
            },
            {
                title: 'Monitorear operaciones',
                content: 'Supervisa las operaciones diarias del almacén.',
                instructions: [
                    'Revisa los movimientos de inventario',
                    'Monitorea las entradas y salidas',
                    'Verifica los niveles de stock',
                    'Analiza los reportes de productividad',
                    'Toma acciones correctivas si es necesario'
                ]
            }
        ]
    },
    'productos': {
        title: 'Agregar productos',
        steps: [
            {
                title: 'Acceder a productos',
                content: 'Ve a la sección de gestión de productos.',
                instructions: [
                    'Desde el dashboard principal',
                    'Selecciona "Productos" en el menú',
                    'Verás el catálogo actual de productos',
                    'Haz clic en "Agregar Producto"'
                ]
            },
            {
                title: 'Información básica',
                content: 'Completa los datos básicos del producto.',
                instructions: [
                    'Ingresa el nombre del producto',
                    'Agrega una descripción detallada',
                    'Selecciona la categoría correspondiente',
                    'Sube una imagen del producto',
                    'Asigna un código SKU único'
                ]
            },
            {
                title: 'Precios y costos',
                content: 'Establece los precios de venta y costos del producto.',
                instructions: [
                    'Define el precio de costo',
                    'Establece el precio de venta',
                    'Configura diferentes presentaciones si aplica',
                    'Agrega descuentos o promociones',
                    'Verifica los márgenes de ganancia'
                ]
            },
            {
                title: 'Inventario inicial',
                content: 'Configura el stock inicial del producto.',
                instructions: [
                    'Selecciona el almacén donde se guardará',
                    'Ingresa la cantidad inicial',
                    'Establece el stock mínimo',
                    'Configura alertas de reorden',
                    'Guarda el producto en el sistema'
                ]
            }
        ]
    },
    'recepcion': {
        title: 'Recepcionar productos',
        steps: [
            {
                title: 'Crear recepción',
                content: 'Inicia el proceso de recepción de mercancía.',
                instructions: [
                    'Ve a "Inventario" > "Recepciones"',
                    'Haz clic en "Nueva Recepción"',
                    'Selecciona el proveedor',
                    'Ingresa el número de orden de compra'
                ]
            },
            {
                title: 'Agregar productos',
                content: 'Registra los productos que están llegando.',
                instructions: [
                    'Busca y selecciona cada producto',
                    'Ingresa la cantidad recibida',
                    'Verifica el estado de los productos',
                    'Anota cualquier observación importante',
                    'Confirma cada item recibido'
                ]
            },
            {
                title: 'Finalizar recepción',
                content: 'Completa el proceso de recepción.',
                instructions: [
                    'Revisa el resumen de productos recibidos',
                    'Verifica que las cantidades sean correctas',
                    'Confirma la recepción completa',
                    'El inventario se actualiza automáticamente',
                    'Genera el reporte de recepción'
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
    
    // Update step counter
    currentStepEl.textContent = currentStep + 1;
    totalStepsEl.textContent = currentTutorial.steps.length;
    
    // Update navigation buttons
    prevBtn.disabled = currentStep === 0;
    nextBtn.textContent = currentStep === currentTutorial.steps.length - 1 ? 'Finalizar' : 'Siguiente';
    
    // Create step content
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
                    <div class="mockup-phone">
                        <div class="mockup-screen">
                            <div class="mockup-header">VentIQ ${currentTutorial.title.includes('Admin') ? 'Admin' : 'Seller'}</div>
                            <div class="mockup-content">
                                ${generateMockupContent(currentStep)}
                            </div>
                        </div>
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

// FAQ functionality
document.addEventListener('DOMContentLoaded', function() {
    const faqItems = document.querySelectorAll('.faq-item');
    
    faqItems.forEach(item => {
        const question = item.querySelector('.faq-question');
        
        question.addEventListener('click', function() {
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
