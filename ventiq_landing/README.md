# ventiq_landing · sitio de Inventtia

Sitio estático (HTML + CSS + JS, sin build step ni framework) que presenta la empresa,
sus siete aplicaciones y todas las descargas.

## Estructura

```
ventiq_landing/
├── index.html               Home editorial (a mano)
├── descargas.html           Todos los APK en un solo lugar        ← generado
├── apps/
│   ├── index.html           Índice de todas las apps              ← generado
│   ├── caja.html            Inventtia Caja (TPV)                  ← generado
│   ├── admin.html           Inventtia Gestión                     ← generado
│   ├── catalogo.html        Inventtia Catálogo                    ← generado
│   ├── flow.html            Inventtia GoReserva                   ← generado
│   ├── muevete.html         Muevete (transporte)                  ← generado
│   ├── carnaval.html        Carnaval (cliente · delivery · proveedor) ← generado
│   └── superadmin.html      Super Admin (interno)                 ← generado
├── tutorials.html · sales.html · contact.html · privacy.html
├── data-safety.html · delete-account.html · r.html
├── assets/
│   ├── css/
│   │   ├── premium-v3.css   Base de diseño (tokens, nav, botones, mockups)
│   │   ├── responsive.css   Correcciones responsive (móvil real)
│   │   ├── apps.css         Componentes de fichas de app y descargas
│   │   └── fixes.css        Legibilidad de titulares (énfasis sin recortes)
│   ├── js/
│   │   ├── premium-v3.js    Nav, drawer, reveals, stack, tilt
│   │   ├── app-page.js      Barra de descarga fija + acordeón FAQ
│   │   ├── aurora-bg.js     Fondo animado del home
│   │   ├── tracking.js      Métricas (Supabase) + gtag
│   │   └── supabase.min.js
│   └── images/              Logos, capturas y tutoriales
└── scripts/
    ├── apps.data.mjs        ← FUENTE ÚNICA: apps, precios, APK, textos
    ├── build-pages.mjs      Genera apps/*.html, descargas.html y sitemap.xml
    └── verify.mjs           Valida enlaces, HTML, CSS y APK
```

## Flujo de trabajo

```bash
# 1. Editar contenido (una sola vez, en un solo sitio)
#    scripts/apps.data.mjs  → nombre, resumen, features, precios, APK, FAQ…

# 2. Regenerar las páginas derivadas
node scripts/build-pages.mjs

# 3. Verificar antes de publicar (0 errores = listo)
node scripts/verify.mjs
```

`index.html` se edita a mano: es la home editorial. Todo lo demás sale del catálogo.
No hay dependencias: solo Node 18+ (`node:fs`, `node:path`).

## Descargas

Los APK se sirven desde el bucket público `apk` del Supabase de producción:

```
https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/<archivo>.apk
```

`apps.data.mjs` es la lista canónica. Estado verificado de los archivos:

| App | Archivo | Tamaño | Subido |
|---|---|---|---|
| Inventtia Caja | `inventtia caja.apk` | 95,9 MB | 2026-10-27 |
| Inventtia Gestión | `vendedor admin.apk` | 114,4 MB | 2026-10-29 |
| Inventtia Catálogo | `inventtia marketplace.apk` | 23,6 MB | 2025-12-17 |
| GoReserva | `goreservas.apk` | 79,5 MB | 2026-10-30 |
| Muevete | `muevete.apk` | 187,3 MB | 2026-11-14 |
| Carnaval | `carnaval_new.apk` | 93,0 MB | 2026-10-14 |
| Carnaval Delivery | `carnaval-delivery.apk` | 58,5 MB | 2026-10-26 |
| Carnaval Proveedores | `carnaval proveedores.apk` | 85,4 MB | 2026-02-16 |
| Super Admin | `superadmin.apk` | 69,1 MB | 2026-09-23 |

> El enlace histórico `vendedor.apk` **no existe** en el bucket (devuelve 400).
> Se sustituyó por `inventtia caja.apk`. `scripts/verify.mjs` falla si vuelve a aparecer.

Builds alternativas (`flow.apk`, `vendedor cuba.apk`, `inventtia catalogo.apk`,
`carnaval.apk`) se listan al final de `descargas.html` por si soporte las pide.

## Por qué existe `responsive.css`

`premium-v3.css` está escrito desktop-first y tenía cuatro fallos que rompían el
móvil de verdad, no solo "se veía raro":

1. **`.v2-eyebrow` con `width: max-content`** — el texto del hero no podía
   envolver y desbordaba el viewport a 360–390 px, arrastrando scroll horizontal.
2. **`.v2-nav-inner` sin regla móvil** — marca (132 px) + CTA "Pedir presupuesto"
   (≈170 px) + burger (40 px) + gaps no caben bajo ~700 px. Ahora el CTA vive
   solo en el drawer y la marca se reduce.
3. **`.v2-hero h1 em` con `margin-top: -25px` y `line-height: 1.45`** — pensado
   para 86 px de escritorio; a 33–42 px las líneas del titular se solapaban.
   Ahora el desplazamiento negativo se anula bajo 980 px y el titular baja de
   escala con `clamp()`.
4. **`.v2-stack-visual-phone` con `min-height: 540px`** — dejaba medio metro de
   aire en tablet y móvil; y las listas de dos columnas se apretaban bajo 560 px.

Además se añadieron: `overflow-x: clip` global (sin romper `position: sticky`),
`scroll-margin-top` para que los anchors no queden bajo el nav fijo, áreas
táctiles de 44–50 px y `text-wrap: balance` en titulares.

## Convenciones

- **Idioma**: todo el contenido en español.
- **Precios**: salen de la base de datos de Inventtia (`app_suscripciones_plan`,
  `muevete.configuracion_tarifas`). Si cambian allí, se actualizan en
  `apps.data.mjs` y se regenera.
- **APK**: siempre con `download` y `data-track-event="apk_download"`.
- **Accesibilidad**: `alt` en todas las imágenes, skip-link, foco visible,
  `aria-current` en la navegación, FAQ con `<details>`.

## Publicación

Sitio estático: basta con subir la carpeta tal cual (Vercel, Netlify, Nginx,
S3…). Las rutas son relativas, así que funciona en la raíz del dominio o en
cualquier subcarpeta. `sitemap.xml` y `robots.txt` apuntan a `https://inventtia.com`.