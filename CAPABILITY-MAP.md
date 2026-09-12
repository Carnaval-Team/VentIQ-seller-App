# Capability Map: Fondo de Caja y preparación offline

| Module id | Responsabilidad | Depende de |
|---|---|---|
| `offline-readiness` | Registrar y validar que cada módulo obligatorio terminó su sincronización, aunque su resultado sea vacío; bloquear la activación manual de modo offline si falta alguno. | — |
| `default-cash-fund` | Configurar una única cuenta predeterminada de Fondo de Caja por tienda y exponerla al cliente para uso online/offline. | — |
| `expense-cash-fund` | Permitir marcar un egreso para generar una recarga idempotente en la cuenta predeterminada, tanto online como mediante sincronización posterior. | `default-cash-fund`, `offline-readiness` |

Orden de construcción: `offline-readiness` y `default-cash-fund` → `expense-cash-fund`.

## Contratos entre módulos

- `default-cash-fund` entrega a `offline-readiness` el estado confirmado de sincronización de la cuenta predeterminada, incluso cuando no existe una cuenta configurada.
- Para permitir modo offline, `offline-readiness` exige que exista una cuenta predeterminada válida; no basta con haber confirmado que no existe.
- `default-cash-fund` entrega a `expense-cash-fund` el identificador de la cuenta receptora correspondiente a la tienda autenticada.
- `expense-cash-fund` identifica cada recarga por el egreso de origen para que los reintentos no dupliquen saldo.
