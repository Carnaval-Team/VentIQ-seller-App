# Plan de evolución del Home cliente

## Estado actual

La pantalla Home del cliente quedó integrada como primera pestaña de usuarios sin rol administrativo. Está preparada para seguir funcionando aunque el esquema remoto todavía no tenga las tablas de marketplace.

### Ya implementado

- Top bar índigo con saludo, avatar con estado, campana, ubicación activa y subtítulo.
- Buscador local con micrófono como acción preparada, filtros avanzados y chips contextuales.
- Riel horizontal de categorías con estado activo.
- Cuadrícula de colecciones temáticas.
- Carrusel patrocinado con snap, badge de verificación, CTA y puntos.
- Ofertas relámpago con contador regresivo, descuento, precio anterior y cupos.
- Recomendados con favorito persistido durante la sesión.
- Establecimientos populares con portada, logo, verificación, tags y CTA.
- Ranking semanal, reseña verificada, beneficio de bienvenida, pasos de uso y footer.
- Badge coral de reservas en la navegación inferior.
- Navegación a `LocalServicioDetailScreen` cuando existe un `LocalServicio` real.
- Estado vacío, pull-to-refresh, feedback con toast flotante y fallback visual.
- Paginación infinita en el feed: las páginas del Home se cargan desde un repositorio con caché en memoria; el desplazamiento no hace una petición por tarjeta.

## Datos y viabilidad

| Bloque | Fuente actual | Estado | Próximo paso |
|---|---|---|---|
| Nombre, local, foto, categoría, precio base | `cliente_obtener_servicios` + `LocalServicio` | Real | Mantener compatibilidad con el RPC actual |
| Reserva directa, detalle y disponibilidad | Flujos existentes de `flow` | Real | Conectar CTA de las tarjetas con disponibilidad cuando corresponda |
| Categorías | Inferencia por nombre/tipo de actividad | Viable provisional | Crear catálogo de categorías configurable |
| Horario abierto | Texto de horario del local | Aproximación | Normalizar horarios y calcular zona horaria/feriados en servidor |
| Ratings y reseñas | No hay modelo específico | Mock visual | Crear tablas, RLS y RPC de lectura/escritura |
| Favoritos | No hay tabla específica | Local durante la sesión | Crear favoritos por usuario y sincronizar con RPC |
| Descuentos, cupos y flash deals | No hay modelo específico | Mock visual | Crear promociones, reglas de vigencia y reservas de cupos |
| Patrocinados | No hay modelo específico | Mock visual | Crear campañas y prioridad de publicación |
| Distancia | No existe cálculo de ubicación del usuario | Etiqueta aproximada | Añadir coordenadas/consentimiento y cálculo server-side |
| Recomendaciones | No hay historial de preferencias | Derivadas del catálogo | Añadir RPC de ranking y señales de interacción |
| Fidelidad | No existe programa de puntos | Mock visual | Definir reglas, saldo, vencimiento y auditoría |
| Colecciones | No hay entidad persistida | Contenido estático | Crear colecciones y relación con servicios |

## Siguiente fase: RPC único para el Home

Crear una función estable en el esquema `flow`, por ejemplo `cliente_home_feed`, que reciba:

- `p_cursor` o `p_offset` y `p_limit`.
- `p_query`.
- `p_categoria`.
- `p_provincia` o ubicación normalizada.
- `p_abierto_ahora` y `p_mejor_valorados`.
- `p_uuid_usuario` opcional para personalización.

La respuesta debería ser un objeto JSON con:

- `items` paginados de servicios.
- `has_more` y `next_cursor`.
- `recommended`.
- `popular_places`.
- `flash_offers` vigentes.
- `sponsored` activo.
- `collections` publicadas.
- `metadata` de categorías y contador de notificaciones.

La app ya concentra el punto de integración en `lib/services/home_catalog_service.dart`. Cuando exista el RPC, sustituir la lectura única de `CatalogoService.getLocalServicios()` por esa función, conservar el caché de una página y evitar llamadas duplicadas con un `Future` compartido.

## Orden recomendado de implementación backend

1. Catálogo de categorías y relación servicio-categoría.
2. Favoritos con índice por usuario y servicio.
3. Reseñas con verificación de reserva completada.
4. Promociones con vigencia, descuento y cupos atómicos.
5. Campañas patrocinadas y colecciones.
6. RPC `cliente_home_feed` con cursor estable e índices.
7. Recomendaciones y ranking semanal.
8. Beneficios de bienvenida y fidelidad.
9. Realtime únicamente para contador de reservas/notificaciones, no para cada tarjeta del feed.

## Checks de producto pendientes

- Confirmar el nombre final de marca y el texto de ubicación predeterminado.
- Reemplazar fotos/gradientes de vista previa por `foto` de Storage cuando el catálogo las tenga.
- Validar en viewport móvil de 390 x 844 y en Android con texto grande.
- Añadir tests de interacción para búsqueda, categorías, favoritos, carga infinita y navegación al detalle.
- Añadir tests del RPC paginado antes de habilitar datos comerciales.
