# Diseño de vistas (Stitch) — Muevete Taxi

Proyecto de Stitch: **`15260051533526132726`** — "Muevete Taxi · Precio fijo por zonas".
Design system: **`assets/2790902494724217266`** (nombre "Muevete Taxi").
Tokens (deben coincidir con `lib/config/app_theme.dart`):

- Primario `#195DE6`, secundario `#4B7FFF`, terciario/éxito `#22C55E`, neutro `#F5F7FA`.
- Tipografía única **Plus Jakarta Sans** (headline, body y label).
- Radios 8 / 14 / 16, sombras suaves, densidad cómoda (16 px lateral, 12 px entre bloques).
- Modo claro por defecto. Montos en CUP grandes y con separador de miles (`1 500 CUP`).
- El % y el neto del chofer son información de primer nivel, no letra pequeña.

> **Regla de producto en todas las vistas de precio:** no existe campo de oferta, slider
> ni puja. El precio se muestra de sólo lectura y con su desglose.

## Pantallas generadas

| # | Pantalla | Para quién | Estado | ID |
|---|---|---|---|---|
| 1 | **Viajes Disponibles – Chofer** | chofer | ✅ generada | `534cf97ac0cd4b0d88b211c89c0ec9d8` |
| 2 | **Confirma tu viaje** (desglose de precio + tipo + pasajeros + pago + CTA "Solicitar viaje · 1 500 CUP") | cliente | ✅ generada | `4f35f6a9ec1c4dcabdc16d2537644a16` |
| 3 | **Buscando conductor…** (mapa + radar + precio congelado + cancelar sin costo) | cliente | ✅ generada | `5b5cc3833b07416a8755930fd43dd6f1` |

Abrir: <https://stitch.withgoogle.com/projects/15260051533526132726>

## Pantallas pendientes (H4/H5/H6)

4. **Viaje en curso (cliente)** — conductor asignado, chapa, verificación mutua (CI parcial), compartir viaje, botón de pánico discreto, contacto de emergencia.
5. **Viaje activo (chofer)** — ruta hacia el cliente, "Tu ganancia 1 275 CUP", confirmar abordaje, completar viaje, desglose final.
6. **Editor de zonas (superadmin)** — mapa con dibujo de polígonos, lista de zonas, vigencia (`vigente_desde`/`vigente_hasta`), modo de tarifa (`fijo` / `fijo_mas_km` / `por_km`), simulador "origen→destino me debería dar X".
7. **Onboarding KYC** — CI + carnet frente/dorso + provincia/municipio/**poblado** + dirección, con los campos que faltan resaltados desde `fn_usuario_habilitado` (`perfil.faltantes`).
8. **Mi seguridad** — contacto de emergencia obligatorio (con verificación), compartir ubicación, historial de incidentes, 106.

## Cómo pedirlas a Stitch

Usar `generate_screen_from_text` con `projectId` y `designSystem` de arriba y
`deviceType = MOBILE` (780×1688). Cada prompt debe:

1. Nombrar el rol (cliente / chofer / superadmin) en la primera frase.
2. Listar el contenido de arriba a abajo, con los textos reales en español de Cuba.
3. Cerrar con la restricción explícita: *"sin campos de negociación, sin slider de
   oferta, sin pujas: el precio lo calcula el sistema"*.
4. Pedir estados vacío / carga / error cuando la pantalla muestra datos.

Después de generarlas, implementar en Flutter respetando `AppTheme` y el contrato de
RPC de [`../13-contrato-app-rpc.md`](../13-contrato-app-rpc.md).