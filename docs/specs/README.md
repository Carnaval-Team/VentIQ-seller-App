# Specs por app

Mapa de la pasada as-built. Cada app tiene su propio documento. El backend compartido (Postgres, RLS, RPC) se cita como dependencia dentro de la app que lo usa.

| Id | App | Documento | Estado |
|---|---|---|---|
| ventiq-app | `ventiq_app` — Inventtia Caja (TPV) | [SPEC-ventiq-app.md](SPEC-ventiq-app.md) | Borrador para revisión |
| ventiq-admin | `ventiq_admin_app` — Inventtia Gestión | [SPEC-ventiq-admin.md](SPEC-ventiq-admin.md) | Borrador para revisión |
| inventtia-muevete | `inventtia_muevete` — Muevete | [SPEC-inventtia-muevete.md](SPEC-inventtia-muevete.md) | Borrador para revisión |
| inventtia-flow | `inventtia_flow` — GoReserva | [SPEC-inventtia-flow.md](SPEC-inventtia-flow.md) | Borrador para revisión |
| ventiq-superadmin | `ventiq_superadmin` — Inventtia Super Admin | [SPEC-ventiq-superadmin.md](SPEC-ventiq-superadmin.md) | Borrador para revisión |
| ventiq-marketplace | `ventiq_marketplace` — Inventtia Catálogo | [SPEC-ventiq-marketplace.md](SPEC-ventiq-marketplace.md) | Borrador para revisión |
| ventiq-landing | `ventiq_landing` — sitio Inventtia | [SPEC-ventiq-landing.md](SPEC-ventiq-landing.md) | Borrador para revisión |

Orden: ventiq-app → ventiq-admin → inventtia-muevete → inventtia-flow → ventiq-superadmin → ventiq-marketplace → ventiq-landing.

Fuera de esta línea base: `tasks/SPEC-product-currency-*.md` y el contrato de precios vigentes en `AGENTS.md`. Están en implementación y cruzan TPV y admin.

El pase entre newa y main, para cuando ese trabajo cierre, está en `tasks/plan_sync_newa_main.md`. No se aplica todavía.
