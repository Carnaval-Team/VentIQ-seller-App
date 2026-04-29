# Inventtia Marketplace

**Catálogo multitienda para descubrir productos, planificar compras y trazar rutas.**

---

## Descripción

Inventtia Marketplace es una aplicación de catálogo y planificación de compras presenciales, diseñada para el mercado cubano dentro del ecosistema VentIQ/Inventtia. Conecta a compradores con tiendas locales, permitiéndoles explorar productos de múltiples vendedores sin necesidad de registro.

## Para compradores

- Exploración de un catálogo completo de productos y tiendas con búsqueda avanzada y filtros por categoría.
- Sistema de valoración con estrellas y comentarios para productos y tiendas.
- Carrito de compras inteligente que funciona como un planificador de visitas: agrupa los productos por tienda para facilitar las compras presenciales.
- Generación de rutas optimizadas mediante OSRM para visitar las tiendas del plan de compras en el orden más eficiente, con navegación GPS en tiempo real, detección de llegada y seguimiento del recorrido.
- Contacto directo con tiendas vía WhatsApp para realizar pedidos.
- Sistema de notificaciones en tiempo real con suscripciones a tiendas y productos de interés.
- Acceso como invitado (sin cuenta) para navegar el catálogo completo; el registro habilita funciones adicionales como valoraciones y notificaciones.
- Acceso por enlaces profundos y códigos QR para abrir tiendas directamente.

## Para vendedores (suscripción anual de 6,000 CUP)

- Creación y gestión completa del perfil de tienda: nombre, dirección, ubicación en mapa, imagen, teléfono, horarios de apertura y cierre.
- Gestión de productos con nombre, imagen, precio, stock, categorías y variantes/presentaciones.
- Control de visibilidad en el catálogo público.
- Generación de códigos QR imprimibles que enlazan directamente a la tienda en el catálogo.
- Difusión de productos a grupos de WhatsApp mediante la API de Whapi Cloud.

## Características técnicas

- Desarrollada en Flutter con soporte para Android y Web (desplegada en Netlify).
- Backend en Supabase (autenticación, base de datos PostgreSQL, almacenamiento de imágenes, suscripciones en tiempo real).
- Mapas interactivos con flutter_map y OpenStreetMap.
- Tema claro y oscuro con paleta azul/naranja.
- Servicio en segundo plano para recepción de notificaciones en tiempo real vía WebSocket.
- Forma parte del ecosistema Inventtia junto a apps de administración de flotas, gestión de negocios y licenciamiento.
