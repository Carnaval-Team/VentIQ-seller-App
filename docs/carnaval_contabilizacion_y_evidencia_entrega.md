# Carnaval: Contabilización (Admin) + Evidencia de entrega (App Delivery)

Documento de contrato de modelo de negocio y plan de implementación.
La **app de delivery** solo entrega y adjunta evidencia.
La **contabilización** la hace gerente/supervisor en Inventtia Admin, de forma independiente.

---

## 1. Responsabilidades por app

| Actor | App | Qué hace | Qué NO hace |
|-------|-----|----------|-------------|
| Chofer / repartidor | App Delivery (carnaval-delivery) | Iniciar entrega, completar con foto + observaciones, sync offline | Contabilizar, recibir dinero en negocio, aceptar/cancelar órdenes |
| Gerente / supervisor | Inventtia Admin (`ventiq_admin_app`) | Revisar pago, marcar efectivo recibido en negocio, contabilizar | Completar entrega del chofer (salvo recogida en tienda) |
| Seller / caja | Inventtia Caja (`ventiq_app`) | Ver estado Carnaval (solo lectura) | Gestionar entrega ni contabilizar Carnaval |

---

## 2. Flujos de negocio

### 2.1 Pago online / Stripe / TropiPay / transferencia ya revisada

```text
Revisar pago (admin)
  → Contabilizar (admin)     ← puede ser ANTES de entregar
  → Asignar repartidor
  → Entregar + evidencia (delivery)
```

La entrega **no bloquea** la contabilización.

### 2.2 Pago en efectivo

```text
Procesar / Asignar
  → Entregar + evidencia (delivery)     ← el chofer NO contabiliza
  → Chofer lleva el efectivo al negocio
  → Admin marca "efectivo recibido en negocio"
  → Contabilizar (admin)                ← independiente y DESPUÉS
```

Regla clave: en efectivo, **cobrar al cliente / entregar** ≠ **contabilizado**.
Contabilizado = dinero ya recibido y revisado en el negocio.

---

## 3. Estados de orden (delivery)

Estados que mueve la app de delivery:

```text
Asignado  →  Entregando  →  Completado (+ evidencia)
```

Reglas:

- Solo el repartidor asignado (`Orders.repartidor`) puede iniciar/completar.
- Completar requiere foto de evidencia (obligatoria recomendada).
- Observaciones: opcionales o mínimas (definir en UX).
- `metodo_pago` **no cambia** el flujo del chofer: siempre entrega + evidencia.
- Idempotencia offline con `entrega_client_uuid`: mismo uuid → success sin duplicar.

Estados previos (Nuevo, En Revision, Pendiente de Pago, Procesando, Cancelado) los gestiona admin/cliente, no delivery.

---

## 4. Cambios de modelo de datos

### 4.1 Columnas nuevas en `carnavalapp."Orders"`

```sql
ALTER TABLE carnavalapp."Orders"
  -- Evidencia de entrega (escribe APP DELIVERY)
  ADD COLUMN IF NOT EXISTS foto_entrega_url TEXT,
  ADD COLUMN IF NOT EXISTS observaciones_entrega TEXT,
  ADD COLUMN IF NOT EXISTS entrega_completada_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS entrega_client_uuid UUID,

  -- Contabilización (escribe SOLO ADMIN Inventtia)
  ADD COLUMN IF NOT EXISTS contabilizado_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS contabilizado_por TEXT,

  -- Efectivo recibido en el negocio (escribe SOLO ADMIN Inventtia)
  ADD COLUMN IF NOT EXISTS efectivo_recibido_en_negocio_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS efectivo_recibido_por TEXT;
```

Campos ya existentes a reutilizar al completar:

- `status` → `'Completado'`
- `completado_por` (TEXT)
- `completado_en` (TIMESTAMPTZ)

### 4.2 Quién escribe cada campo

| Campo | Quién escribe | Uso |
|-------|---------------|-----|
| `foto_entrega_url` | Delivery | URL de la foto de evidencia |
| `observaciones_entrega` | Delivery | Texto del chofer |
| `entrega_completada_at` | Delivery | Timestamp de entrega |
| `entrega_client_uuid` | Delivery | Idempotencia offline |
| `completado_por` / `completado_en` | Delivery | Quién/cuándo completó la entrega |
| `status = 'Completado'` | Delivery | Cierre operativo de entrega |
| `contabilizado_at` / `contabilizado_por` | **Admin** | Delivery NO escribe |
| `efectivo_recibido_en_negocio_at` / `efectivo_recibido_por` | **Admin** | Delivery NO escribe |

### 4.3 Tabla opcional de evidencias (si quieren historial)

```sql
CREATE TABLE IF NOT EXISTS carnavalapp.order_delivery_evidence (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES carnavalapp."Orders"(id) ON DELETE CASCADE,
  foto_url TEXT NOT NULL,
  observaciones TEXT,
  repartidor_id BIGINT REFERENCES carnavalapp.repartidores(id),
  client_uuid UUID NOT NULL,
  captured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  synced_at TIMESTAMPTZ,
  UNIQUE (order_id, client_uuid)
);
```

Para MVP alcanzan las columnas en `Orders`.

---

## 5. Contrato RPC para la app de delivery

### 5.1 `fn_carnaval_iniciar_entrega(p_order_id bigint)`

- Auth: repartidor asignado a la orden.
- Efecto: `status` `Asignado` → `Entregando`.
- Historial: el trigger existente de `order_status_history` debe registrar `Entregando`.

### 5.2 `fn_carnaval_completar_entrega(...)`

Parámetros:

```text
p_order_id           bigint
p_foto_url           text      -- requerido
p_observaciones      text      -- nullable
p_client_uuid        uuid      -- requerido (offline)
p_completado_por     text      -- nombre del repartidor
```

Efectos:

1. Validar repartidor asignado y status `Entregando` (o `Asignado` si se permite completar directo).
2. Si ya existe el mismo `entrega_client_uuid` → return success idempotente.
3. Setear:
   - `status = 'Completado'`
   - `foto_entrega_url`
   - `observaciones_entrega`
   - `entrega_completada_at = now()`
   - `entrega_client_uuid`
   - `completado_por`, `completado_en`
4. **No** tocar `contabilizado_*` ni `efectivo_recibido_*`.

Respuesta sugerida:

```json
{
  "success": true,
  "order_id": 123,
  "status": "Completado",
  "idempotent": false
}
```

---

## 6. Storage de la foto (delivery)

- Bucket: existente (`productos`) o nuevo `carnaval-entregas`.
- Path sugerido: `entregas/{order_id}/{client_uuid}.jpg`
- Online: subir foto → obtener URL → llamar RPC completar.
- Offline: guardar foto local + payload; al reconectar: upload → RPC con el **mismo** `client_uuid`.

---

## 7. Cola offline (app delivery)

Payload mínimo por operación pendiente:

```json
{
  "op_type": "completar_entrega",
  "client_uuid": "uuid-v4",
  "order_id": 123,
  "foto_local_path": "...",
  "observaciones": "...",
  "completado_por": "Nombre Chofer",
  "created_at": "ISO-8601",
  "status": "pending"
}
```

Estados locales: `pending` → `uploading` → `synced` | `failed`.

Orden de sync: **subir foto → RPC**. Reintentos seguros gracias a `client_uuid`.

También encolar `iniciar_entrega` si se pierde red al pasar a `Entregando`.

---

## 8. Qué implementa Inventtia Admin (después / en paralelo)

No lo hace la app de delivery; se lista para no mezclar responsabilidades.

1. Botón **Contabilizar** (gerente/supervisor).
2. Reglas:
   - Online/Stripe/TropiPay/transferencia revisada: puede contabilizar antes o después de `Completado`.
   - Efectivo: solo si `efectivo_recibido_en_negocio_at` está set (dinero en el negocio).
3. Acción **Registrar efectivo recibido en negocio** (admin).
4. Resolver operación VentIQ (`observaciones` tipo `Venta desde orden {id}`) y marcarla contabilizada / estado completada.
5. Filtros: pendientes de contabilizar, efectivo por recibir en negocio, entregadas con evidencia.
6. Mostrar en detalle: foto + observaciones de entrega (solo lectura).

---

## 9. Checklist para el equipo de la app Delivery

- [ ] Aplicar migración de columnas de evidencia (y opcional tabla evidence).
- [ ] Implementar / consumir RPC `fn_carnaval_iniciar_entrega`.
- [ ] Implementar / consumir RPC `fn_carnaval_completar_entrega` con `client_uuid`.
- [ ] UI: iniciar entrega → completar con cámara + observaciones.
- [ ] Cola offline + sync al recuperar conexión.
- [ ] **No escribir** `contabilizado_*` ni `efectivo_recibido_*`.
- [ ] Probar: doble sync no duplica; otro repartidor no puede completar; foto obligatoria.

---

## 10. Checklist para Inventtia Admin (referencia)

- [ ] Migración campos `contabilizado_*` y `efectivo_recibido_*`.
- [ ] RPC `fn_carnaval_contabilizar_orden` con reglas por `metodo_pago`.
- [ ] RPC / acción marcar efectivo recibido en negocio.
- [ ] UI detalle: Contabilizar + ver evidencia.
- [ ] Filtros / dashboard de cartera Carnaval pendiente de contabilizar.

---

## 11. Orden sugerido de trabajo

1. SQL: columnas + RPCs de entrega (compartido).
2. App Delivery: completar con evidencia + offline.
3. Admin: efectivo recibido en negocio + Contabilizar.
4. Filtros, bitácora y endurecimiento de roles.

---

## 12. Criterios de aceptación

- Chofer completa con foto + obs; orden queda `Completado` con evidencia.
- Chofer sin red puede completar; al reconectar sube sin duplicar.
- Chofer **nunca** contabiliza.
- Online: admin puede contabilizar sin esperar entrega.
- Efectivo: admin solo contabiliza después de registrar recepción del dinero en el negocio.
- Contabilizar es idempotente sobre la operación VentIQ vinculada.
