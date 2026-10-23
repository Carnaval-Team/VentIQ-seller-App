# VentIQ Landing Page

Landing page promocional para las aplicaciones VentIQ Seller App y Inventtia Admin Web.

## 🚀 Características

### Páginas Incluidas
- **Página Principal (index.html)**: Landing page con información de las aplicaciones
- **Tutoriales (tutorials.html)**: Guías interactivas paso a paso
- **Contacto (contact.html)**: Formulario de contacto y información

### Funcionalidades Implementadas

#### 🎨 Diseño Moderno
- **Responsive Design**: Adaptable a todos los dispositivos
- **Gradientes VentIQ**: Colores consistentes con las aplicaciones
- **Animaciones Suaves**: Efectos hover y transiciones
- **Cards Interactivas**: Elementos visuales atractivos

#### 📱 Navegación Inteligente
- **Navbar Fijo**: Con efectos de scroll
- **Menú Hamburguesa**: Para dispositivos móviles
- **Smooth Scrolling**: Navegación suave entre secciones
- **Breadcrumbs**: Navegación clara entre páginas

#### 🎯 Secciones Principales

##### Hero Section
- Título impactante con gradiente
- Estadísticas del sistema
- Botones de descarga prominentes
- Mockup de la aplicación móvil

##### Características
- Comparación entre Seller App y Admin Web
- Features específicas de cada aplicación
- Iconos representativos
- Diseño en cards

##### Beneficios
- Grid responsivo de beneficios
- Iconos animados
- Descripciones claras
- Call-to-action integrado

#### 📚 Sistema de Tutoriales

##### Categorías Interactivas
- **VentIQ Seller App**: Tutoriales para vendedores
- **Inventtia Admin Web**: Tutoriales para administradores
- Switching dinámico entre categorías

##### Tutoriales Implementados

**Seller App:**
- Cómo realizar una venta (4 pasos)
- Consultar inventario (3 pasos)
- Configurar la aplicación (5 pasos)

**Admin Web:**
- Registrar una empresa (4 pasos)
- Gestionar almacenes (5 pasos)
- Agregar productos (4 pasos)
- Recepcionar productos (3 pasos)

##### Modal Interactivo
- Navegación paso a paso
- Mockups visuales
- Instrucciones detalladas
- Teclado shortcuts (←/→/Esc)

#### 📞 Sistema de Contacto

##### Formulario Completo
- Validación en tiempo real
- Campos requeridos marcados
- Auto-guardado en localStorage
- Estados de loading y éxito

##### Métodos de Contacto
- Email: contacto@ventiq.com
- Teléfono: +1 (555) 123-4567
- Chat en vivo (próximamente)
- Oficina física con cita previa

##### FAQ Interactivo
- 6 preguntas frecuentes
- Acordeón animado
- Respuestas detalladas

#### 🔧 Funcionalidades JavaScript

##### Sistema de Descargas
- Modal de descarga inteligente
- Detección de tipo de app
- Links a stores (simulados)
- Notificaciones informativas

##### Notificaciones
- Sistema de toast messages
- Diferentes tipos (success, error, warning, info)
- Auto-hide configurable
- Diseño consistente

##### Animaciones
- Intersection Observer para fade-in
- Floating cards animadas
- Hover effects en web
- Smooth transitions

## 🛠️ Estructura del Proyecto

```
ventiq_landing/
├── index.html              # Página principal
├── tutorials.html          # Página de tutoriales
├── contact.html            # Página de contacto
├── README.md               # Este archivo
└── assets/
    ├── css/
    │   ├── styles.css       # Estilos principales
    │   ├── tutorials.css    # Estilos de tutoriales
    │   └── contact.css      # Estilos de contacto
    ├── js/
    │   ├── main.js          # JavaScript principal
    │   ├── tutorials.js     # Funcionalidad de tutoriales
    │   └── contact.js       # Funcionalidad de contacto
    └── images/
        ├── logo.svg         # Logo de VentIQ
        └── ventas.png       # Screenshot de la app
```

## 🎨 Paleta de Colores

Basada en los colores de las aplicaciones VentIQ:

```css
--primary: #4A90E2        /* Azul principal */
--primary-dark: #357ABD   /* Azul oscuro */
--secondary: #6B7280      /* Gris secundario */
--success: #10B981        /* Verde éxito */
--warning: #FF6B35        /* Naranja advertencia */
--background: #F8F9FA     /* Fondo claro */
--surface: #FFFFFF        /* Superficie blanca */
```

## 📱 Responsividad

### Breakpoints Implementados
- **Mobile**: ≤480px
- **Tablet**: 481px - 768px
- **Desktop**: 769px - 1200px
- **Large Desktop**: >1200px

### Adaptaciones por Dispositivo
- **Mobile**: Menú hamburguesa, cards apiladas, texto optimizado
- **Tablet**: Grid 2 columnas, navegación híbrida
- **Desktop**: Grid completo, efectos hover, espaciado amplio

## 🚀 Características Técnicas

### Performance
- **CSS Optimizado**: Variables CSS, selectores eficientes
- **JavaScript Modular**: Funciones separadas por página
- **Lazy Loading**: Animaciones bajo demanda
- **Debounced Events**: Scroll optimizado

### Accesibilidad
- **Semantic HTML**: Estructura semántica correcta
- **Keyboard Navigation**: Navegación por teclado
- **ARIA Labels**: Etiquetas de accesibilidad
- **Color Contrast**: Contraste adecuado

### SEO
- **Meta Tags**: Título y descripción optimizados
- **Open Graph**: Metadatos para redes sociales
- **Structured Data**: Datos estructurados
- **Sitemap Ready**: Estructura preparada para sitemap

## 🔧 Instalación y Uso

### Requisitos
- Navegador web moderno
- Servidor web local (opcional)

### Instalación
1. Clonar o descargar los archivos
2. Abrir `index.html` en el navegador
3. O servir desde un servidor web local

### Desarrollo Local
```bash
# Con Python
python -m http.server 8000

# Con Node.js
npx serve .

# Con PHP
php -S localhost:8000
```

## 🔗 Enlaces y Recursos

### Dependencias Externas
- **Font Awesome 6.0.0**: Iconos
- **Google Fonts**: Fuente Inter
- **CSS Variables**: Compatibilidad moderna

### Recursos Utilizados
- Colores basados en `app_colors.dart` de Inventtia Admin
- Iconos y assets copiados de las aplicaciones
- Estructura inspirada en las pantallas existentes

## 🎯 Próximas Mejoras

### Funcionalidades Pendientes
- [ ] Integración con backend real
- [ ] Sistema de analytics
- [ ] Blog/noticias
- [ ] Testimonios de clientes
- [ ] Galería de screenshots
- [ ] Videos demostrativos

### Optimizaciones
- [ ] Compresión de imágenes
- [ ] Minificación de CSS/JS
- [ ] Service Worker para PWA
- [ ] Lazy loading de imágenes

## 📞 Soporte

Para soporte técnico o consultas sobre la landing page:
- **Email**: contacto@ventiq.com
- **Documentación**: Ver archivos de código fuente
- **Issues**: Reportar en el repositorio del proyecto

## 📄 Licencia

Este proyecto es parte del ecosistema VentIQ. Todos los derechos reservados.

---

**VentIQ Landing Page** - Promocionando el futuro de la gestión de ventas e inventario 🚀
