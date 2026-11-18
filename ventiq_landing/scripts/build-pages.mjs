/**
 * ============================================================================
 * GENERADOR DE PÁGINAS ESTÁTICAS · ventiq_landing
 * ----------------------------------------------------------------------------
 * Uso:  node scripts/build-pages.mjs
 *
 * Escribe, a partir de scripts/apps.data.mjs:
 *   · apps/<slug>.html   → una página de presentación por app
 *   · apps/index.html    → índice de todas las apps
 *   · descargas.html     → todos los APK en un solo lugar
 *   · sitemap.xml
 *
 * No tiene dependencias: solo Node 18+.
 * index.html se mantiene a mano (es la home editorial).
 * ============================================================================
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SITE, APPS, EXTRA_APKS, apk } from './apps.data.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const HOY = '2026-11-16';

/** Fecha real de subida de cada APK al bucket (consultada en storage.objects). */
const APK_UPDATED = {
  'inventtia caja.apk': '2026-10-27',
  'vendedor admin.apk': '2026-10-29',
  'inventtia marketplace.apk': '2025-12-17',
  'inventtia catalogo.apk': '2026-03-26',
  'goreservas.apk': '2026-10-30',
  'flow.apk': '2026-10-30',
  'muevete.apk': '2026-11-14',
  'carnaval_new.apk': '2026-10-14',
  'carnaval.apk': '2026-10-13',
  'carnaval-delivery.apk': '2026-10-26',
  'carnaval proveedores.apk': '2026-02-16',
  'superadmin.apk': '2026-09-23',
  'vendedor cuba.apk': '2026-10-27',
};

/* ------------------------------------------------------------------ utils */

const esc = (s = '') =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

/** Links internos relativos → prefijados con la base de la página. */
const resolve = (href, base) =>
  /^(https?:|mailto:|tel:|#)/.test(href) ? href : base + href;

const fechaCorta = (iso) => {
  if (!iso) return '';
  const [y, m, d] = iso.split('-');
  return `${d}/${m}/${y}`;
};

const fileForApk = (url) => {
  const tail = url.split('/').pop() || '';
  try {
    return decodeURIComponent(tail);
  } catch {
    return tail;
  }
};

const btnIcon = (kind) =>
  kind === 'apk' ? 'fa-download' : kind === 'web' ? 'fa-arrow-up-right-from-square' : 'fa-google-play';

/* --------------------------------------------------------------- parciales */

function head({ title, desc, canonical, base, jsonLd, ogImage }) {
  const img = ogImage || `${SITE.url}/assets/images/inventtia_logo.jpg`;
  return `<!DOCTYPE html>
<html lang="es">
<head>
    <!-- Google tag (gtag.js) -->
    <script async src="https://www.googletagmanager.com/gtag/js?id=G-HVE9907KZB"></script>
    <script>
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', 'G-HVE9907KZB');
    </script>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <meta name="color-scheme" content="light dark">
    <meta name="theme-color" media="(prefers-color-scheme: light)" content="#F7FAFB">
    <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#0C1A2A">
    <title>${esc(title)}</title>
    <meta name="description" content="${esc(desc)}">
    <meta name="robots" content="index, follow">
    <link rel="canonical" href="${esc(canonical)}">

    <meta property="og:type" content="website">
    <meta property="og:url" content="${esc(canonical)}">
    <meta property="og:title" content="${esc(title)}">
    <meta property="og:description" content="${esc(desc)}">
    <meta property="og:image" content="${esc(img)}">
    <meta property="og:locale" content="es_ES">
    <meta property="og:site_name" content="Inventtia">

    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${esc(title)}">
    <meta name="twitter:description" content="${esc(desc)}">
    <meta name="twitter:image" content="${esc(img)}">

    <link rel="icon" type="image/jpeg" href="${base}assets/images/inventtia_logo.jpg">
    <link rel="apple-touch-icon" href="${base}assets/images/inventtia_logo.jpg">
${jsonLd ? `\n    <script type="application/ld+json">\n${JSON.stringify(jsonLd, null, 2)}\n    </script>\n` : ''}
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/geist@1.3.1/dist/fonts/geist-sans/style.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/geist@1.3.1/dist/fonts/geist-mono/style.css">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link rel="stylesheet" href="${base}assets/css/premium-v3.css">
    <link rel="stylesheet" href="${base}assets/css/responsive.css">
    <link rel="stylesheet" href="${base}assets/css/apps.css">
    <link rel="stylesheet" href="${base}assets/css/fixes.css">
</head>`;
}

const NAV_ITEMS = [
  { href: 'index.html#empresa', label: 'Nosotros' },
  { href: 'index.html#servicios', label: 'Servicios' },
  { href: 'apps/index.html', label: 'Apps' },
  { href: 'descargas.html', label: 'Descargas' },
  { href: 'tutorials.html', label: 'Tutoriales' },
  { href: 'contact.html', label: 'Contacto' },
];

const WA = `${SITE.whatsapp}?text=${encodeURIComponent(
  'Hola Inventtia, quiero información sobre sus aplicaciones y precios.',
)}`;

function nav(base, active) {
  const links = NAV_ITEMS.map(
    (i) =>
      `                <a href="${resolve(i.href, base)}"${i.href === active ? ' aria-current="page"' : ''}>${i.label}</a>`,
  ).join('\n');
  const drawerLinks = NAV_ITEMS.map(
    (i) => `            <a href="${resolve(i.href, base)}">${i.label}</a>`,
  ).join('\n');

  return `    <nav class="v2-nav" aria-label="Principal">
        <div class="v2-nav-inner">
            <a href="${base}index.html" class="v2-brand" aria-label="Inventtia">
                <img src="${base}assets/images/inventtia_wordmark.jpg" alt="Inventtia" class="v2-brand-logo" width="130" height="34">
            </a>

            <div class="v2-nav-links">
${links}
            </div>

            <a href="${WA}" target="_blank" rel="noopener" class="v2-nav-cta">
                <i class="fab fa-whatsapp" aria-hidden="true" style="font-size:14px"></i>
                Pedir presupuesto
            </a>

            <button class="v2-burger" aria-label="Abrir menú" aria-expanded="false">
                <i class="fas fa-bars" aria-hidden="true"></i>
            </button>
        </div>
    </nav>

    <div class="v2-drawer" data-drawer aria-hidden="true">
        <div class="v2-drawer-scrim"></div>
        <div class="v2-drawer-panel" role="dialog" aria-label="Menú de navegación" aria-modal="true">
            <div class="v2-drawer-top">
                <span class="v2-brand">
                    <img src="${base}assets/images/inventtia_wordmark.jpg" alt="Inventtia" class="v2-brand-logo" width="130" height="34">
                </span>
                <button class="v2-drawer-close" data-drawer-close aria-label="Cerrar menú">
                    <i class="fas fa-xmark" aria-hidden="true"></i>
                </button>
            </div>
${drawerLinks}
            <a href="${WA}" target="_blank" rel="noopener" class="v2-btn v2-btn-primary">
                <i class="fab fa-whatsapp" aria-hidden="true"></i>
                Pedir presupuesto
            </a>
        </div>
    </div>`;
}

function footer(base) {
  const appLinks = APPS.map(
    (a) => `                        <li><a href="${base}apps/${a.slug}.html">${esc(a.name)}</a></li>`,
  ).join('\n');

  return `    <footer class="v2-footer" aria-labelledby="footer-h">
        <h2 id="footer-h" class="sr-only" style="position:absolute;left:-9999px;">Pie de página</h2>
        <div class="v2-shell">
            <div class="v2-footer-grid">
                <div>
                    <a href="${base}index.html" class="v2-brand">
                        <img src="${base}assets/images/inventtia_wordmark.jpg" alt="Inventtia" class="v2-brand-logo" width="220" height="58">
                    </a>
                    <p class="v2-footer-tag">
                        Software que opera en el mundo real: punto de venta, gestión, catálogo, turnos, transporte y comercio.
                    </p>
                </div>

                <div>
                    <h5>Aplicaciones</h5>
                    <ul>
${appLinks}
                    </ul>
                </div>

                <div>
                    <h5>Recursos</h5>
                    <ul>
                        <li><a href="${base}descargas.html">Descargar apps</a></li>
                        <li><a href="${base}sales.html">Servicios IT</a></li>
                        <li><a href="${base}tutorials.html">Tutoriales</a></li>
                        <li><a href="${base}contact.html">Contacto</a></li>
                        <li><a href="${base}privacy.html">Privacidad</a></li>
                        <li><a href="${base}data-safety.html">Seguridad de datos</a></li>
                    </ul>
                </div>

                <div>
                    <h5>Contacto</h5>
                    <ul>
                        <li><a href="${SITE.whatsapp}" target="_blank" rel="noopener">WhatsApp</a></li>
                        <li><a href="mailto:${SITE.email}">${SITE.email}</a></li>
                        <li><a href="tel:+5353765120">${SITE.phone}</a></li>
                    </ul>
                </div>
            </div>

            <div class="v2-footer-bottom">
                <span>© 2026 Inventtia. Todos los derechos reservados.</span>
                <span class="v2-mono">
                    <a href="${SITE.whatsapp}" target="_blank" rel="noopener">+53 53765120</a>
                    &nbsp;·&nbsp;
                    <a href="mailto:${SITE.email}">${SITE.email}</a>
                </span>
            </div>
        </div>
    </footer>`;
}

function scripts(base) {
  return `    <script src="${base}assets/js/supabase.min.js" defer></script>
    <script src="${base}assets/js/tracking.js" defer></script>
    <script src="${base}assets/js/premium-v3.js" defer></script>
    <script src="${base}assets/js/app-page.js" defer></script>`;
}

const scrollProgress = `    <div class="v2-scroll-progress" aria-hidden="true"></div>`;

/* --------------------------------------------------------------- botones */

function actionBtn(dl, base, { ghost = false } = {}) {
  const cls = ghost ? 'v2-btn v2-btn-ghost' : 'v2-btn v2-btn-primary';
  const ext = /^https?:/.test(dl.href);
  const attrs = [];
  if (dl.kind === 'apk') attrs.push('download');
  if (ext) attrs.push('target="_blank"', 'rel="noopener"');
  const track = dl.kind === 'apk' ? 'apk_download' : dl.kind === 'store' ? 'store_click' : 'web_app_click';
  return `<a class="${cls}" href="${esc(resolve(dl.href, base))}" ${attrs.join(' ')} data-track-event="${track}">
                    <i class="fas ${btnIcon(dl.kind)}" aria-hidden="true"></i>
                    ${esc(dl.label)}
                </a>`;
}

/* ------------------------------------------------------------- bloques HTML */

function appCard(app, base) {
  return `                <article class="app-card">
                    <a class="app-card__cover" href="${base}apps/${app.slug}.html" aria-label="${esc(app.name)}: ${esc(app.summary)}"></a>
                    <div class="app-card-top">
                        <div class="app-icon" data-tone="${app.tone}" aria-hidden="true"><i class="fas ${app.icon}"></i></div>
                        <div>
                            <h3>${esc(app.name)}</h3>
                            <span class="app-card-cat">${esc(app.category)}</span>
                        </div>
                    </div>
                    <p>${esc(app.summary)}</p>
                    <ul class="app-card-tags">${app.badges
                      .slice(0, 3)
                      .map((b) => `<li>${esc(b)}</li>`)
                      .join('')}</ul>
                    <div class="app-card-actions">
                        <a class="v2-btn v2-btn-ghost" href="${base}apps/${app.slug}.html">Ver ficha</a>
                        ${
                          (app.downloads.find((d) => d.primary) || app.downloads[0])
                            ? `<a class="v2-btn v2-btn-primary" href="${esc(
                                resolve((app.downloads.find((d) => d.primary) || app.downloads[0]).href, base),
                              )}" ${/^https?:/.test((app.downloads.find((d) => d.primary) || app.downloads[0]).href) ? 'target="_blank" rel="noopener"' : ''} ${(app.downloads.find((d) => d.primary) || app.downloads[0]).kind === 'apk' ? 'download' : ''} data-track-event="apk_download">
                                    <i class="fas ${btnIcon((app.downloads.find((d) => d.primary) || app.downloads[0]).kind)}" aria-hidden="true"></i>
                                    Descargar
                                </a>`
                            : ''
                        }
                    </div>
                </article>`;
}

function phoneMock(app, base = '') {
  const p = app.heroPhone || {};
  const toneClass = p.tone === 'teal' ? 'v2-phone-screen-teal' : p.tone === 'red' ? 'v2-phone-screen-red' : 'v2-phone-screen-navy';
  const media = p.logo
    ? `<img src="${base}${p.logo}" alt="${esc(app.name)}" class="v2-phone-logo">`
    : `<div class="app-icon" data-tone="${app.tone}" aria-hidden="true"><i class="fas ${p.icon || app.icon}"></i></div>`;
  return `                <div class="v2-phone" data-tone="${app.tone}">
                    <div class="v2-phone-screen ${toneClass}">
                        <div class="v2-phone-island" aria-hidden="true"></div>
                        <div class="v2-phone-status" aria-hidden="true">
                            <span>9:41</span>
                            <span class="v2-status-right">
                                <i class="fas fa-signal" aria-hidden="true"></i>
                                <i class="fas fa-wifi" aria-hidden="true"></i>
                                <i class="fas fa-battery-three-quarters" aria-hidden="true"></i>
                            </span>
                        </div>
                        <div class="v2-phone-content-center">
                            ${media}
                            <h3 class="v2-phone-title">${esc(p.title || app.shortName)}</h3>
                            <p class="v2-phone-tag">${esc(p.tag || app.category)}</p>
                        </div>
                    </div>
                </div>`;
}

function pricingBlock(app, base) {
  const p = app.pricing;
  const parts = [];

  if (p.fare) {
    parts.push(`                <div class="fare-card">
                    <h3 style="font-family:var(--v2-font-display);font-size:18px;margin:0 0 14px;letter-spacing:-0.02em;color:var(--v2-text)">${esc(
                      p.fare.title,
                    )}</h3>
                    <div class="fare-rows">
${p.fare.rows
  .map(
    (r) => `                        <div class="fare-row${/comisi/i.test(r.label) ? '' : ''}"><span>${esc(r.label)}</span><b>${esc(
      r.value,
    )}</b></div>`,
  )
  .join('\n')}
                    </div>
                    <div class="fare-formula">${esc(p.fare.formula).replace(/\n/g, '<br>')}</div>
                    <p class="price-note">${esc(p.fare.note)}</p>
                </div>`);
  }

  if (p.plans && p.plans.length) {
    const cls = p.plans.length === 4 ? 'price-grid price-grid--four' : 'price-grid';
    parts.push(`                <div class="${cls} mt-lg">
${p.plans
  .map(
    (pl) => `                    <article class="price-card${pl.featured ? ' price-card--featured' : ''}">
                        ${pl.featured ? '<span class="price-flag">Recomendado</span>' : ''}
                        <p class="price-name">${esc(pl.name)}</p>
                        <p class="price-amount">${esc(pl.price)}${pl.period ? `<small>${esc(pl.period)}</small>` : ''}</p>
                        <p class="price-desc">${esc(pl.desc)}</p>
                        <ul class="price-list">
${pl.items.map((i) => `                            <li><i class="fas fa-check" aria-hidden="true"></i> ${esc(i)}</li>`).join('\n')}
                        </ul>
                        <a class="v2-btn ${pl.featured ? 'v2-btn-primary' : 'v2-btn-ghost'}" href="${esc(resolve(pl.cta.href, base))}"${
                          /^https?:/.test(pl.cta.href) ? ' target="_blank" rel="noopener"' : ''
                        }>${esc(pl.cta.label)}</a>
                    </article>`,
  )
  .join('\n')}
                </div>`);
  }

  return parts.join('\n');
}

/* ------------------------------------------------------------ página de app */

function appPage(app, index) {
  const base = '../';
  const canonical = `${SITE.url}/apps/${app.slug}.html`;
  const primary = app.downloads.find((d) => d.primary) || app.downloads[0];
  const secondary = app.downloads.find((d) => d !== primary);

  const ld = {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: app.name,
    applicationCategory: 'BusinessApplication',
    operatingSystem: 'Android, Web',
    description: app.summary,
    url: canonical,
    publisher: { '@type': 'Organization', name: 'Inventtia', url: SITE.url },
  };
  if (app.pricing.plans && app.pricing.plans.length) {
    const nums = app.pricing.plans
      .map((p) => parseFloat(String(p.price).replace(/[^\d.,]/g, '').replace(',', '.')))
      .filter((n) => Number.isFinite(n));
    if (nums.length) {
      ld.offers = {
        '@type': 'AggregateOffer',
        priceCurrency: /CUP/.test(app.pricing.plans[0].period) ? 'CUP' : 'USD',
        lowPrice: Math.min(...nums),
        highPrice: Math.max(...nums),
        offerCount: app.pricing.plans.length,
      };
    }
  }

  const facts = app.facts
    .map((f) => `                        <div class="app-fact"><b>${esc(f.value)}</b><span>${esc(f.label)}</span></div>`)
    .join('\n');

  const capabilities = app.what
    .map(
      (w) =>
        `                        <li><i class="fas fa-check" aria-hidden="true"></i> <span>${esc(w)}</span></li>`,
    )
    .join('\n');

  const features = app.features
    .map(
      (f) => `                    <article class="feature-card">
                        <i class="fas ${f.icon}" aria-hidden="true"></i>
                        <h3>${esc(f.title)}</h3>
                        <p>${esc(f.text)}</p>
                    </article>`,
    )
    .join('\n');

  const steps = app.steps
    .map(
      (s) => `                    <article class="step">
                        <h3>${esc(s.title)}</h3>
                        <p>${esc(s.text)}</p>
                    </article>`,
    )
    .join('\n');

  const gallery =
    app.shots && app.shots.length >= 2
      ? `    <section class="app-section app-section--tint" aria-labelledby="shots-h">
        <div class="v2-shell">
            <div class="app-head">
                <span class="app-kicker">Capturas reales</span>
                <h2 id="shots-h">Así se ve <em>${esc(app.shortName)}</em> por dentro</h2>
                <p>Pantallas de la app publicada, no un mockup de diseño.</p>
            </div>
            <div class="shot-strip" role="list">
${app.shots
  .map(
    (s) => `                <figure class="shot" role="listitem">
                    <img src="${base}${esc(s.src)}" alt="${esc(s.alt)}" loading="lazy" width="720" height="1280">
                    <figcaption>${esc(s.alt)}</figcaption>
                </figure>`,
  )
  .join('\n')}
            </div>
        </div>
    </section>`
      : '';

  const faq = app.faq
    .map(
      (f) => `                <details>
                    <summary>${esc(f.q)}</summary>
                    <p>${esc(f.a)}</p>
                </details>`,
    )
    .join('\n');

  const prev = APPS[(index - 1 + APPS.length) % APPS.length];
  const next = APPS[(index + 1) % APPS.length];

  const dlActions =
    primary || secondary
      ? [
          primary ? actionBtn(primary, base) : '',
          secondary ? actionBtn(secondary, base, { ghost: true }) : '',
          app.downloads.length > 2
            ? `<a class="v2-btn v2-btn-ghost" href="${base}descargas.html"><i class="fas fa-list" aria-hidden="true"></i> Todas las descargas</a>`
            : '',
        ]
          .filter(Boolean)
          .join('\n                ')
      : '';

  const dlMeta = app.downloads
    .filter((d) => d.kind === 'apk')
    .map((d) => {
      const file = fileForApk(d.href);
      return `                    <li><b>${esc(d.meta.replace('Android 8+ · ', ''))}</b><span>Android 8+</span></li>
                    <li><b>${esc(fechaCorta(APK_UPDATED[file]))}</b><span>Última actualización</span></li>`;
    })
    .slice(0, 2)
    .join('\n');

  return `${head({
    title: `${app.name} · ${app.category}`,
    desc: app.summary.slice(0, 300),
    canonical,
    base,
    jsonLd: ld,
    ogImage: app.heroShot ? `${SITE.url}/${app.heroShot}` : undefined,
  })}
<body class="v2 app-page has-dl-sticky">

    <a class="skip-link" href="#contenido">Saltar al contenido</a>
${scrollProgress}

${nav(base, 'apps/index.html')}

    <header class="app-hero">
        <div class="v2-shell">
            <nav class="crumbs" aria-label="Ruta de navegación">
                <a href="${base}index.html">Inventtia</a>
                <span class="sep" aria-hidden="true">/</span>
                <a href="${base}apps/index.html">Apps</a>
                <span class="sep" aria-hidden="true">/</span>
                <span aria-current="page">${esc(app.shortName)}</span>
            </nav>

            <div class="app-hero-grid">
                <div>
                    <div class="app-hero-head">
                        <div class="app-icon" data-tone="${app.tone}" aria-hidden="true"><i class="fas ${app.icon}"></i></div>
                        <span class="app-kicker">${esc(app.category)}</span>
                    </div>

                    <h1>${esc(app.name)}</h1>
                    <p class="app-hero-claim">${esc(app.tagline)}</p>
                    <p class="app-hero-sub">${esc(app.summary)}</p>

                    <ul class="app-badges">
${app.badges.map((b) => `                        <li class="app-badge"><i class="fas fa-check" aria-hidden="true"></i> ${esc(b)}</li>`).join('\n')}
                    </ul>

                    <div class="app-hero-actions">
                        ${primary ? actionBtn(primary, base) : ''}
                        ${secondary ? actionBtn(secondary, base, { ghost: true }) : ''}
                    </div>
                    <p class="app-hero-note">${
                      primary && primary.meta ? esc(primary.meta) : 'Descarga directa, sin intermediarios.'
                    } · <a href="${base}descargas.html" style="color:inherit;text-decoration:underline">ver todas las descargas</a></p>

                    <div class="app-facts">
${facts}
                    </div>
                </div>

                <div class="app-hero-visual">
${app.heroShot ? `                    <div class="app-hero-shot">
                        <img src="${base}${esc(app.heroShot)}" alt="${esc(app.name)} en uso" width="720" height="1280">
                    </div>` : phoneMock(app, base)}
                </div>
            </div>
        </div>
    </header>

    <main id="contenido">

        <section class="app-section" aria-labelledby="what-h">
            <div class="v2-shell">
                <div class="app-head">
                    <span class="app-kicker">Qué hace</span>
                    <h2 id="what-h">Lo que <em>${esc(app.shortName)}</em> resuelve</h2>
                    <p>${esc(app.summary)}</p>
                </div>
                <ul class="capability-list">
${capabilities}
                </ul>
            </div>
        </section>

        <section class="app-section app-section--tint" aria-labelledby="feat-h">
            <div class="v2-shell">
                <div class="app-head">
                    <span class="app-kicker">Características</span>
                    <h2 id="feat-h">Para qué sirve, en detalle</h2>
                </div>
                <div class="feature-cards">
${features}
                </div>
            </div>
        </section>

        <section class="app-section" aria-labelledby="steps-h">
            <div class="v2-shell">
                <div class="app-head">
                    <span class="app-kicker">Cómo funciona</span>
                    <h2 id="steps-h">Tres pasos y estás operando</h2>
                </div>
                <div class="steps">
${steps}
                </div>
            </div>
        </section>

        <section class="app-section app-section--tint" id="precios" aria-labelledby="price-h">
            <div class="v2-shell">
                <div class="app-head">
                    <span class="app-kicker">Precios</span>
                    <h2 id="price-h">${esc(app.pricing.model)}</h2>
                    ${app.pricing.intro ? `<p>${esc(app.pricing.intro)}</p>` : ''}
                </div>
${pricingBlock(app, base)}
                ${app.pricing.note ? `<p class="price-note">${esc(app.pricing.note)}</p>` : ''}
            </div>
        </section>

${gallery}

        <section class="app-section" id="descargas" aria-labelledby="dl-h">
            <div class="v2-shell">
                <div class="dl-panel">
                    <h2 id="dl-h">Descarga ${esc(app.name)}</h2>
                    <p>Instala el APK en Android o abre la versión web sin instalar nada. Los archivos salen del almacenamiento de Inventtia, sin intermediarios ni tiendas de terceros.</p>
                    <div class="dl-actions">
                ${dlActions}
                    </div>
                    <ul class="dl-meta">
${dlMeta}
                        <li><b>Inventtia</b><span>Desarrollador</span></li>
                        <li><b>Español</b><span>Idioma</span></li>
                    </ul>
                </div>
            </div>
        </section>

        <section class="app-section app-section--tint" aria-labelledby="faq-h">
            <div class="v2-shell">
                <div class="app-head">
                    <span class="app-kicker">Preguntas frecuentes</span>
                    <h2 id="faq-h">Lo que suelen preguntar</h2>
                </div>
                <div class="faq">
${faq}
                </div>
            </div>
        </section>

        <div class="v2-shell">
            <nav class="app-pager" aria-label="Otras apps">
                <a href="${prev.slug}.html" class="is-prev">
                    <span>App anterior</span>
                    <b>${esc(prev.name)}</b>
                </a>
                <a href="${next.slug}.html" class="is-next">
                    <span>App siguiente</span>
                    <b>${esc(next.name)}</b>
                </a>
            </nav>
        </div>

        <section class="app-cta" aria-labelledby="cta-h">
            <div class="v2-shell">
                <h2 id="cta-h">¿Lo vemos con tu negocio?</h2>
                <p>Te mostramos ${esc(app.shortName)} funcionando con tus datos y te decimos cuánto cuesta sin compromiso.</p>
                <div class="app-cta-actions">
                    <a class="v2-btn v2-btn-primary" href="${WA}" target="_blank" rel="noopener">
                        <i class="fab fa-whatsapp" aria-hidden="true"></i> Escribir por WhatsApp
                    </a>
                    <a class="v2-btn v2-btn-ghost" href="${base}contact.html">Página de contacto</a>
                </div>
            </div>
        </section>
    </main>

${footer(base)}

    <div class="dl-sticky" data-dl-sticky aria-hidden="true">
        <span class="dl-sticky-label">
            <b>${esc(app.shortName)}</b>
            ${primary && primary.kind === 'apk' ? esc(primary.meta) : 'Disponible en la web'}
        </span>
        <a class="v2-btn v2-btn-primary" href="${esc(resolve((primary || app.downloads[0]).href, base))}" ${
          /^https?:/.test((primary || app.downloads[0]).href) ? 'target="_blank" rel="noopener"' : ''
        } ${(primary || app.downloads[0]).kind === 'apk' ? 'download' : ''} data-track-event="apk_download">
            <i class="fas ${btnIcon((primary || app.downloads[0]).kind)}" aria-hidden="true"></i>
            Descargar
        </a>
    </div>

${scripts(base)}
</body>
</html>
`;
}

/* ---------------------------------------------------------------- apps index */

function appsIndexPage() {
  const base = '../';
  const canonical = `${SITE.url}/apps/`;

  return `${head({
    title: 'Apps de Inventtia · punto de venta, gestión, catálogo, turnos y transporte',
    desc: 'Todas las aplicaciones de Inventtia en un solo lugar: Caja (TPV), Gestión, Catálogo, GoReserva, Muevete, Carnaval y Super Admin. Qué hace cada una, qué cuesta y cómo descargarla.',
    canonical,
    base,
  })}
<body class="v2 app-page">

    <a class="skip-link" href="#contenido">Saltar al contenido</a>
${scrollProgress}

${nav(base, 'apps/index.html')}

    <header class="app-hero">
        <div class="v2-shell">
            <nav class="crumbs" aria-label="Ruta de navegación">
                <a href="${base}index.html">Inventtia</a>
                <span class="sep" aria-hidden="true">/</span>
                <span aria-current="page">Apps</span>
            </nav>

            <div class="app-hero-grid">
                <div style="grid-column:1/-1;max-width:64ch">
                    <span class="app-kicker">Catálogo de productos</span>
                    <h1>Siete apps. <em>Una</em> sola forma de trabajar.</h1>
                    <p class="app-hero-sub">
                        Cada aplicación resuelve una parte del negocio y todas comparten la misma cuenta y la misma base de datos.
                        Elige la que necesitas: cada ficha explica qué hace, qué incluye, cuánto cuesta y cómo descargarla.
                    </p>
                    <div class="app-hero-actions" style="flex-direction:row;flex-wrap:wrap">
                        <a class="v2-btn v2-btn-primary" href="${base}descargas.html">
                            <i class="fas fa-download" aria-hidden="true"></i> Ir a descargas
                        </a>
                        <a class="v2-btn v2-btn-ghost" href="${base}index.html">Volver al inicio</a>
                    </div>
                </div>
            </div>
        </div>
    </header>

    <main id="contenido">
        <section class="app-section" aria-labelledby="all-h">
            <div class="v2-shell">
                <div class="app-head">
                    <span class="app-kicker">Todas las apps</span>
                    <h2 id="all-h">Elige por dónde <em>empezar</em></h2>
                    <p>Si vendes en mostrador, empieza por Caja. Si administras, por Gestión. Si quieres vender en línea, por Catálogo.</p>
                </div>
                <div class="apps-grid">
${APPS.map((a) => appCard(a, base)).join('\n')}
                </div>
            </div>
        </section>

        <section class="app-cta" aria-labelledby="cta-h">
            <div class="v2-shell">
                <h2 id="cta-h">¿No sabes cuál te toca?</h2>
                <p>Cuéntanos cómo trabajas hoy y te decimos qué combinación de apps te resuelve el día sin pagar de más.</p>
                <div class="app-cta-actions">
                    <a class="v2-btn v2-btn-primary" href="${WA}" target="_blank" rel="noopener">
                        <i class="fab fa-whatsapp" aria-hidden="true"></i> Escribir por WhatsApp
                    </a>
                    <a class="v2-btn v2-btn-ghost" href="${base}contact.html">Contacto</a>
                </div>
            </div>
        </section>
    </main>

${footer(base)}

${scripts(base)}
</body>
</html>
`;
}

/* ----------------------------------------------------------------- descargas */

function downloadsPage() {
  const base = '';
  const canonical = `${SITE.url}/descargas.html`;

  const business = APPS.filter((a) => ['caja', 'admin', 'catalogo', 'flow', 'muevete'].includes(a.slug));
  const carnaval = APPS.filter((a) => a.slug === 'carnaval');
  const internal = APPS.filter((a) => a.slug === 'superadmin');

  const row = (app) => {
    const apkDl = app.downloads.find((d) => d.kind === 'apk');
    const webDl = app.downloads.find((d) => d.kind === 'web');
    const stores = app.downloads.filter((d) => d.kind === 'store');
    const extraApks = app.downloads.filter((d) => d.kind === 'apk').slice(1);

    const actions = [
      apkDl
        ? `<a class="v2-btn v2-btn-primary" href="${esc(apkDl.href)}" download data-track-event="apk_download"><i class="fas fa-download" aria-hidden="true"></i> APK</a>`
        : '',
      webDl
        ? `<a class="v2-btn v2-btn-ghost" href="${esc(webDl.href)}" target="_blank" rel="noopener" data-track-event="web_app_click"><i class="fas fa-arrow-up-right-from-square" aria-hidden="true"></i> Web</a>`
        : '',
      ...stores.map(
        (s) =>
          `<a class="v2-btn v2-btn-primary" href="${esc(s.href)}" target="_blank" rel="noopener" data-track-event="store_click"><i class="fab ${
            /apple/.test(s.href) ? 'fa-apple' : 'fa-google-play'
          }" aria-hidden="true"></i> ${esc(s.label)}</a>`,
      ),
      `<a class="v2-btn v2-btn-ghost" href="apps/${app.slug}.html">Ficha</a>`,
    ]
      .filter(Boolean)
      .join('\n                        ');

    const metaParts = [];
    if (apkDl) {
      const file = fileForApk(apkDl.href);
      metaParts.push(apkDl.meta);
      if (APK_UPDATED[file]) metaParts.push(`subido ${fechaCorta(APK_UPDATED[file])}`);
      if (extraApks.length) metaParts.push(`+${extraApks.length} build${extraApks.length > 1 ? 's' : ''} alterna${extraApks.length > 1 ? 's' : ''}`);
    } else {
      metaParts.push(app.downloads[0].meta);
    }

    return `                    <div class="dl-row">
                        <div class="app-icon" data-tone="${app.tone}" aria-hidden="true"><i class="fas ${app.icon}"></i></div>
                        <div class="dl-row-main">
                            <h3>${esc(app.name)}${app.slug === 'carnaval' ? ' <span class="tag tag--new">Play Store</span>' : ''}${
                              app.slug === 'superadmin' ? ' <span class="tag tag--warn">Interno</span>' : ''
                            }</h3>
                            <p>${esc(metaParts.filter(Boolean).join(' · '))}</p>
                        </div>
                        <div class="dl-row-actions">
                        ${actions}
                        </div>
                    </div>`;
  };

  const extras = EXTRA_APKS.map(
    (x) => `                    <div class="dl-row">
                        <div class="app-icon" data-tone="admin" aria-hidden="true"><i class="fas fa-box-archive"></i></div>
                        <div class="dl-row-main">
                            <h3>${esc(x.name)}</h3>
                            <p>${esc(x.note)} · ${esc(x.size)}</p>
                        </div>
                        <div class="dl-row-actions">
                            <a class="v2-btn v2-btn-ghost" href="${esc(apk(x.file))}" download data-track-event="apk_download"><i class="fas fa-download" aria-hidden="true"></i> APK</a>
                        </div>
                    </div>`,
  ).join('\n');

  return `${head({
    title: 'Descargar las apps de Inventtia · APK directos y versiones web',
    desc: 'Descarga los APK de Inventtia Caja, Gestión, Catálogo, GoReserva, Muevete y Carnaval. Enlaces directos, sin intermediarios, con tamaño y fecha de cada build.',
    canonical,
    base,
  })}
<body class="v2 app-page">

    <a class="skip-link" href="#contenido">Saltar al contenido</a>
${scrollProgress}

${nav(base, 'descargas.html')}

    <header class="app-hero">
        <div class="v2-shell">
            <nav class="crumbs" aria-label="Ruta de navegación">
                <a href="index.html">Inventtia</a>
                <span class="sep" aria-hidden="true">/</span>
                <span aria-current="page">Descargas</span>
            </nav>

            <div class="app-hero-grid">
                <div style="grid-column:1/-1;max-width:66ch">
                    <span class="app-kicker">Descargas</span>
                    <h1>Descarga directa, <em>sin</em> vueltas.</h1>
                    <p class="app-hero-sub">
                        Todos los APK de Inventtia en una sola página, con su tamaño y la fecha de la última build.
                        Si prefieres no instalar nada, cada app tiene su versión web o su tienda oficial.
                    </p>
                    <div class="app-hero-actions" style="flex-direction:row;flex-wrap:wrap">
                        <a class="v2-btn v2-btn-primary" href="#negocio">
                            <i class="fas fa-briefcase" aria-hidden="true"></i> Apps de negocio
                        </a>
                        <a class="v2-btn v2-btn-ghost" href="#carnaval">
                            <i class="fas fa-bag-shopping" aria-hidden="true"></i> Carnaval
                        </a>
                    </div>
                </div>
            </div>
        </div>
    </header>

    <main id="contenido">
        <section class="app-section" aria-labelledby="negocio">
            <div class="v2-shell">
                <div class="dl-group">
                    <div class="dl-group-head">
                        <h2 id="negocio">Apps de negocio</h2>
                        <span>Punto de venta · gestión · catálogo · turnos · transporte</span>
                    </div>
                    <div class="dl-rows">
${business.map(row).join('\n')}
                    </div>
                </div>

                <div class="dl-group" id="carnaval">
                    <div class="dl-group-head">
                        <h2>Carnaval</h2>
                        <span>Cliente · delivery · proveedores</span>
                    </div>
                    <div class="dl-rows">
${carnaval.map(row).join('\n')}
                        <div class="dl-row">
                            <div class="app-icon" data-tone="carnaval" aria-hidden="true"><i class="fas fa-motorcycle"></i></div>
                            <div class="dl-row-main">
                                <h3>Carnaval Delivery</h3>
                                <p>App del repartidor · Android 8+ · 58,5 MB · subido 26/10/2026</p>
                            </div>
                            <div class="dl-row-actions">
                                <a class="v2-btn v2-btn-primary" href="${esc(apk('carnaval-delivery.apk'))}" download data-track-event="apk_download"><i class="fas fa-download" aria-hidden="true"></i> APK</a>
                            </div>
                        </div>
                        <div class="dl-row">
                            <div class="app-icon" data-tone="carnaval" aria-hidden="true"><i class="fas fa-store"></i></div>
                            <div class="dl-row-main">
                                <h3>Carnaval Proveedores</h3>
                                <p>App del comercio · Android 8+ · 85,4 MB · subido 16/02/2026</p>
                            </div>
                            <div class="dl-row-actions">
                                <a class="v2-btn v2-btn-primary" href="${esc(apk('carnaval proveedores.apk'))}" download data-track-event="apk_download"><i class="fas fa-download" aria-hidden="true"></i> APK</a>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="dl-group">
                    <div class="dl-group-head">
                        <h2>Uso interno</h2>
                        <span>Solo equipo Inventtia</span>
                    </div>
                    <div class="dl-rows">
${internal.map(row).join('\n')}
                    </div>
                </div>
            </div>
        </section>

        <section class="app-section app-section--tint" aria-labelledby="how-h">
            <div class="v2-shell">
                <div class="app-head">
                    <span class="app-kicker">Instalación</span>
                    <h2 id="how-h">Cómo instalar un APK en Android</h2>
                    <p>Android pide permiso la primera vez porque el archivo no viene de Play Store. Es normal y no es un virus: el archivo está alojado en el almacenamiento de Inventtia.</p>
                </div>
                <ol class="steps-inline">
                    <li><span><b>Descarga el APK</b> desde esta página. Se guarda en la carpeta <i>Descargas</i> del teléfono.</span></li>
                    <li><span><b>Ábrelo</b> desde la notificación o desde Archivos. Si Android pregunta, permite "instalar apps desconocidas" solo para esa app (Archivos o Chrome).</span></li>
                    <li><span><b>Confirma la instalación</b>. Si ya tenías la app, se actualiza encima y conserva tus datos.</span></li>
                    <li><span><b>Abre la app e inicia sesión</b> con el usuario que te entregó Inventtia. Si no tienes, escríbenos por WhatsApp.</span></li>
                </ol>

                <div class="fare-formula" style="margin-top:22px">
                    Si Play Protect muestra un aviso al instalar, es porque el APK no pasó por Play Store.
                    Elige "Instalar de todos modos": puedes verificar el archivo comparando el tamaño que
                    aparece en esta página con el que muestra tu gestor de archivos.
                </div>
            </div>
        </section>

        <section class="app-section" aria-labelledby="alt-h">
            <div class="v2-shell">
                <div class="app-head">
                    <span class="app-kicker">Builds alternativas</span>
                    <h2 id="alt-h">Otras builds en el almacenamiento</h2>
                    <p>Estas versiones existen porque se publicaron con otro nombre o son builds anteriores. Solo úsalas si soporte te lo pide expresamente.</p>
                </div>
                <div class="dl-rows">
${extras}
                </div>
            </div>
        </section>

        <section class="app-cta" aria-labelledby="cta-h">
            <div class="v2-shell">
                <h2 id="cta-h">¿No encuentras tu app?</h2>
                <p>Escríbenos y te pasamos el enlace exacto de la build que necesitas, con el usuario de tu tienda.</p>
                <div class="app-cta-actions">
                    <a class="v2-btn v2-btn-primary" href="${WA}" target="_blank" rel="noopener">
                        <i class="fab fa-whatsapp" aria-hidden="true"></i> Escribir por WhatsApp
                    </a>
                    <a class="v2-btn v2-btn-ghost" href="apps/index.html">Ver todas las apps</a>
                </div>
            </div>
        </section>
    </main>

${footer(base)}

${scripts(base)}
</body>
</html>
`;
}

/* ------------------------------------------------------------------ sitemap */

function sitemap() {
  const urls = [
    { loc: `${SITE.url}/`, pr: '1.0', cf: 'weekly', lm: HOY },
    { loc: `${SITE.url}/apps/`, pr: '0.9', cf: 'weekly', lm: HOY },
    { loc: `${SITE.url}/descargas.html`, pr: '0.9', cf: 'weekly', lm: HOY },
    ...APPS.map((a) => ({ loc: `${SITE.url}/apps/${a.slug}.html`, pr: '0.8', cf: 'monthly', lm: HOY })),
    { loc: `${SITE.url}/sales.html`, pr: '0.8', cf: 'monthly', lm: HOY },
    { loc: `${SITE.url}/tutorials.html`, pr: '0.7', cf: 'monthly', lm: HOY },
    { loc: `${SITE.url}/contact.html`, pr: '0.7', cf: 'monthly', lm: HOY },
    { loc: `${SITE.url}/privacy.html`, pr: '0.3', cf: 'yearly', lm: HOY },
    { loc: `${SITE.url}/data-safety.html`, pr: '0.3', cf: 'yearly', lm: HOY },
    { loc: `${SITE.url}/delete-account.html`, pr: '0.3', cf: 'yearly', lm: HOY },
  ];

  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls
  .map(
    (u) => `    <url>
        <loc>${u.loc}</loc>
        <lastmod>${u.lm}</lastmod>
        <changefreq>${u.cf}</changefreq>
        <priority>${u.pr}</priority>
    </url>`,
  )
  .join('\n')}
</urlset>
`;
}

/* --------------------------------------------------------------------- run */

const write = (rel, content) => {
  const target = path.join(ROOT, rel);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, content, 'utf8');
  return `${rel} (${(Buffer.byteLength(content) / 1024).toFixed(1)} KB)`;
};

const written = [];

APPS.forEach((app, i) => written.push(write(`apps/${app.slug}.html`, appPage(app, i))));
written.push(write('apps/index.html', appsIndexPage()));
written.push(write('descargas.html', downloadsPage()));
written.push(write('sitemap.xml', sitemap()));

console.log('Generado:');
written.forEach((w) => console.log('  · ' + w));
console.log(`\nApps: ${APPS.length} · APK referenciados: ${new Set(
  APPS.flatMap((a) => a.downloads.filter((d) => d.kind === 'apk').map((d) => d.href)).concat(
    EXTRA_APKS.map((x) => apk(x.file)),
  ),
).size}`);