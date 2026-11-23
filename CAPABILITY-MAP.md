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

# Capability Map: Fondo de Inversión → Compras → Recepción → Consumo

Plan y estado: [`docs/planes/fondo-inversion/`](docs/planes/fondo-inversion/README.md). SQL:
`ventiq_admin_app/lib/sql/compra/`.

| Module id | Responsabilidad | Depende de |
|---|---|---|
| `fondo-ledger` | Llevar el saldo por (cuenta, medio, moneda) con partida doble, idempotencia y conciliación R1; nada más escribe saldos. | — |
| `compra-documento` | La compra como documento: líneas, ajustes, estados y su historial. Es la única puerta de los montos comprometidos. | `fondo-ledger` |
| `compra-reserva-pago` | Reservar del fondo, pagar consumiendo lo reservado y anular devolviendo. | `compra-documento`, `fondo-ledger` |
| `recepcion-compra` | Vincular recepciones a la compra sin mover dinero y sin sobre-recibir; carril B independiente. | `compra-documento` |
| `costo-aterrizado` | Repartir flete, aduana, seguro e importadora al costo del producto, con reversa marcada al cancelar la recepción. | `recepcion-compra` |
| `aportes-inversores` | Que los inversores cubran una compra al 100 % sin que ese dinero entre al fondo ni se mezcle con su porcentaje de utilidad. | `compra-documento` |
| `reportes-conciliacion` | R1-R7 y la conciliación programada: probar que el saldo es real y que el dinero cuadra. | todos los anteriores |

Orden de construcción: `fondo-ledger` → `compra-documento` → `compra-reserva-pago` y `recepcion-compra` →
`costo-aterrizado` → `aportes-inversores` → `reportes-conciliacion`.

## Contratos entre módulos

- `fondo-ledger` entrega a todos un único aplicador de movimientos (`_fdi_aplicar_movimiento`); ningún
  módulo escribe `fdi_dat_saldo` por su cuenta.
- `compra-reserva-pago` y `aportes-inversores` son **excluyentes por compra** (`modo_liquidacion`): en
  modo `fondo` no existe ningún aporte y en modo `inversores` no existe reserva ni pago del fondo. Se
  impone con triggers, no solo en las RPC.
- `aportes-inversores` no toca `fdi_dat_saldo` ni `fdi_dat_movimiento`: el pago de una compra de
  inversores deja filas en `fdi_dat_compra_pago` con `origen='aporte'`, sin cuenta, sin medio y sin
  movimiento.
- `costo-aterrizado` entrega el costo real al inventario; **no** recalcula ventas, pagos ni liquidaciones
  históricas, y el `precio_promedio` ya ponderado no se reconstruye al cancelar (límite declarado).
- `reportes-conciliacion` solo lee. R1 es la única verdad de la conciliación y corre sola por `pg_cron`;
  si alguna vez no cuadra, el reporte de caja y el de compras no deben «arreglarlo».
