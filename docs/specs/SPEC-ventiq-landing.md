# Spec: ventiq-landing (sitio Inventtia)

Línea base as-built de `ventiq_landing`. Es un sitio estático. No es una app Flutter. Cada afirmación lleva una marca:

- **Observado** — está en el HTML o en el JavaScript, o en una RPC leída en main el 2026-11-14.
- **Inferido** — se sigue del comportamiento, sin un test que lo fije.
- **Abierto** — el código no decide si ese comportamiento es el deseado.

El sitio presenta la suite y enlaza las descargas. No administra tiendas ni cobra.

## Objective

**Observado.** `ventiq_landing` es la página pública de Inventtia. Habla con main (`https://vsieeihstajlrdvpuooh.supabase.co`) desde el navegador, con la clave anónima. Esa clave no se copia aquí.

Páginas:

| Archivo | Qué es |
|---|---|
| `index.html` | Inicio, cifras y descargas de Caja, Gestión, Catálogo y GoReserva |
| `tutorials.html` | Guías de Caja y de Gestión |
| `contact.html` | Formulario de contacto |
| `sales.html` | Oferta de servicios |
| `privacy.html` | Privacidad |
| `data-safety.html` | Seguridad de datos |
| `delete-account.html` | Borrado de cuenta |
| `r.html` | Llegada de referido o carnaval, con el APK de carnaval |

Éxito para esta página: el inicio pinta las cifras que devuelve `fn_estadisticas_globales_ventiq` y, si esa llamada falla, deja las cifras que ya trae el HTML. Un clic marcado se intenta registrar. La descarga abre el APK público del storage.

## Tech Stack

**Observado.**

- HTML, CSS en `assets/css/` y JavaScript en `assets/js/`. Sin framework.
- Cliente de Supabase en el navegador (`assets/js/supabase.min.js`), solo en el inicio y en `r.html`.
- `sitemap.xml` y `robots.txt` en la raíz del sitio.

## Commands

Se abre el HTML en un navegador. No hay `flutter test` ni un empaquetado de app. Un cambio de cifra o de formulario se comprueba recargando `index.html` y `contact.html`.

## Qué hace el sitio

### Inicio y descargas

**Observado.** `loadGlobalStats` en `assets/js/main.js` llama `fn_estadisticas_globales_ventiq`. Si la respuesta trae `success` y `data`, sustituye las cifras de la página. Si hay error, deja los valores que ya están en el HTML.

Los APK salen del bucket público `apk`: vendedor, admin, catálogo y GoReserva. El script también abre «vendedor cuba» desde un botón. `r.html` apunta al APK de carnaval del mismo bucket.

### Medición

**Observado.** `assets/js/tracking.js` expone `window.VentiqTracking.track`. Cada elemento con `data-track-event` llama `fn_track_landing_event` con el tipo de evento, un código, la plataforma (Android, iOS o Desktop), el user agent, la URL, el referrer y un id de sesión guardado en `sessionStorage`. Si el cliente de Supabase no cargó, el clic no se registra y la página sigue.

Esa función no está en main el 2026-11-14. El script escribe el error en la consola y no bloquea la página.

### Contacto y tutoriales

**Observado.** `contact.js` valida los campos requeridos en el navegador, guarda el borrador en `localStorage` bajo `inventtia_contact_form` y puede abrir `mailto:soporteinventtia@gmail.com`. No inserta una fila en Postgres.

`tutorials.html` cambia entre guías de Caja y de Gestión y recorre los pasos en un modal. No llama al servidor.

## Reglas que impone el servidor

**Verificado el 2026-11-14 en main.**

`fn_estadisticas_globales_ventiq` es `SECURITY DEFINER`. Responde éxito con los datos, o el mensaje «Error al obtener estadísticas globales». No exige superadmin. La lee la clave anónima del sitio.

`fn_track_landing_event` no está desplegada. El sitio la llama igual.

Los APK son objetos públicos del storage. Bajarlos no pasa por una RPC.

## Code Style

**Observado.** Un script por página. Las llamadas a Supabase viven en `main.js` y `tracking.js`. El texto visible está en español. Los enlaces de descarga son absolutos al storage de main.

## Testing Strategy

**Observado.** No hay suite automatizada. La comprobación es abrir el HTML: las cifras, un clic con `data-track-event` y el formulario de contacto.

## Boundaries

- **Always:** Leer las cifras con `fn_estadisticas_globales_ventiq` y conservar las del HTML si falla. Registrar el clic solo como medición, sin frenar la descarga. Dejar el contacto en el navegador y en el correo.
- **Ask first:** Crear `fn_track_landing_event` en main. Apuntar una descarga a otro bucket.
- **Never:** Copiar la clave anónima a otro documento. Hacer que el formulario escriba en las tablas de tiendas o de usuarios. Tratar este sitio como Caja, Gestión o Catálogo.

## Success Criteria

1. El inicio llama `fn_estadisticas_globales_ventiq` y, si responde `success`, muestra `data`.
2. Si esa llamada falla, las cifras que ya trae el HTML siguen visibles.
3. Un clic con `data-track-event` intenta `fn_track_landing_event` y, si la función no existe, la página sigue.
4. El formulario de contacto no inserta en Postgres. Puede abrir el correo de soporte.
5. Las descargas apuntan al bucket público `apk` de main.

## Open Questions

1. **Abierto.** `fn_track_landing_event` no está en main. Falta decidir si se despliega o si el sitio deja de llamarla.
