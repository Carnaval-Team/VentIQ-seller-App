# Planes con límites, planes privados y "Contactar con ventas"

**Fecha:** 29-10-2026 · **Ámbito:** schema `flow` (Supabase), panel `ventiq_superadmin` y app `inventtia_flow` (GoReserva).

Esta entrega convierte los planes de suscripción en **productos con límites reales**, añade **planes privados por cliente** y la modalidad **"Contactar con ventas"** para los acuerdos a medida. Todo se configura desde el panel del superadmin.

---

## 1. Qué hace ahora el sistema

| Antes | Ahora |
|---|---|
| Plan = duración + precio. Sin límites. | Plan = duración + precio + **límites** (entidades, locales, servicios por local, servicios de catálogo, usuarios) + **etiqueta** de tarjeta. |
| Todos los planes eran públicos. | Plan **público** (todos) o **privado de una entidad** (solo su dueño/admin lo ve y lo puede pagar). |
| Todos los planes se compraban por Transfermóvil. | Modalidad **pago** (Transfermóvil, como antes) o **contacto** (botón "Contactar con ventas" que abre WhatsApp, sin intent de pago). |
| Nada impedía crear 10 locales con un plan de 2. | Al crear una **entidad, local, servicio, asignación local-servicio, admin o vendedor**, un trigger de Postgres aplica el límite del plan vivo y bloquea con un mensaje claro. |
| Tarjeta de plan = fila de datos. | Tarjeta tipo ficha de producto: precio grande, cinta "Más popular", lista de lo que incluye, chip de plan privado y botón de ventas. |

---

## 2. Cómo activarlo

En el editor SQL de Supabase, en este orden:

1. `inventtia_flow/docs/flow_schema/migraciones/72_planes_limites_privados.sql`
2. `inventtia_flow/docs/flow_schema/migraciones/73_seed_planes_2026.sql`
3. `inventtia_flow/docs/flow_schema/migraciones/74_suscripcion_cobro_en_cup.sql`

Las tres son **idempotentes** (se pueden reejecutar sin efecto), terminan con `notify pgrst, 'reload schema';` y traen al final bloques comentados de **verificación** y de **reversión**. La 74 depende de la 72 y de la 60 y lo comprueba sola antes de tocar nada.

> **Estado verificado el 30-10-2026 en la base de release:** la **72 y la 73 ya están aplicadas** (existen `id_entidad`, `modalidad` y `etiqueta`, y los cuatro planes están creados). Lo único pendiente es la **74**, que es la que hace que el cobro salga en CUP. Mientras no se aplique, la app sigue funcionando y el intent se crea en la moneda del plan.

Después, en el panel: **Superadmin → Planes de suscripción**. Ahí están los cuatro planes y se puede editar cualquier límite, crear planes privados o desactivar lo que no se venda.

---

## 3. Los planes que se siembran

| Código | Nombre | Días | Precio | Límites | Etiqueta |
|---|---|---|---|---|---|
| `starter` | Inicio | 30 | 20 USD | 1 entidad · **2 locales** · 5 servicios por local · 3 usuarios | — |
| `plus` | Plus | 30 | 30 USD | 1 entidad · **3 locales** · 10 servicios por local · 8 usuarios | Más popular |
| `professional` | Profesional | 30 | 50 USD | 2 entidades · **5 locales** · 10 servicios por local · 15 usuarios | — |
| `enterprise` | Empresarial | 30 | — (contacto) | Sin límites: se negocia con ventas | — |

Además, la semilla **desactiva** los planes de prueba `flow_mensual`, `flow_trimestral` y `flow_anual` (1/2/3 CUP). No se borran y **no se toca ninguna suscripción ya acreditada**: las entidades que los tengan conservan sus días y su historial.

`servicios_catalogo` no se siembra a propósito (ausente = sin límite), para no sorprender a los negocios que ya tienen catálogo montado.

### El cobro se hace siempre en CUP

`flow.suscripcion_plan.precio` + `moneda` son el **precio comercial** (puede estar en USD, EUR o MLC), pero **Transfermóvil solo cobra en CUP**. Al crear el intent, el servidor convierte el precio con la **tasa del día** (`flow.tasa_factor`, caché de `flow.tasa_cambio`) y redondea a **pesos enteros**, igual que ya hacía el prepago del servicio. Si no hay tasa para esa moneda, **no se crea el intent** y la app muestra «No hay tasa de cambio para cobrar en CUP. Inténtalo más tarde.»

- El intent se guarda y se paga **siempre en CUP** (`monto` + `moneda = 'CUP'`); la app y el panel muestran además el precio del plan y la equivalencia (`monto_plan`, `moneda_plan`, `tasa_cup`) para que nadie se lleve la sorpresa al abrir Transfermóvil.
- Con la caché del **28-10-2026** (USD → CUP = 845), un plan de 20 USD se cobra **16.900 CUP**.
- Consecuencia práctica: cambiar la moneda del plan **no cambia el importe cobrado** salvo por el redondeo; lo que manda es la tasa del día. El superadmin ve el aviso en el editor y la nota «Se cobra en CUP al cambio del día» en las tarjetas que no están en CUP.
- Los planes en **modalidad contacto** no generan intent (botón de WhatsApp), así que la conversión no les aplica.

> **Estado de los planes vivos al 30-10-2026** (editados a mano después de la semilla): `starter` 1 CUP/30 días · `plus` 2 CUP/30 días · `professional` **3 USD con `duracion_dias = 3`** · `enterprise` contacto. Los precios parecen valores de prueba y los 3 días de `professional` tienen pinta de error de edición: con la 74 aplicada, ese plan cobraría 2.535 CUP por 3 días.

---

## 4. Cómo funcionan los límites

**Claves de `limites` (jsonb):** `entidades`, `locales`, `servicios_por_local`, `servicios_catalogo`, `usuarios`.

**Regla:** número **> 0** = límite. Ausente, `null`, `0` o negativo = **sin límite**.

| Recurso | Se cuenta sobre | Cuándo se aplica |
|---|---|---|
| `entidades` | `flow.entidad.owner_uuid` (cuenta del dueño) | Al crear una entidad |
| `locales` | `flow.app_dat_locales.id_entidad` | Al crear un local |
| `servicios_por_local` | `flow.local_servicio.id_local` | Al asignar un servicio a un local |
| `servicios_catalogo` | `flow.app_dat_servicios.id_entidad` | Al crear un servicio |
| `usuarios` | `entidad_admin` + `entidad_vendedor` (un solo cupo) | Al añadir admin o vendedor |

**Reglas de convivencia (importantes para soporte):**

- **Sin plan no hay límites.** Es el mismo *grandfathering* que `flow.entidad_activa`: una entidad sin fila de suscripción, o en trial sin plan acreditado, **no** se bloquea. Los límites empiezan a aplicar cuando se le acredita un plan.
- Las entidades que **ya superan** los límites nuevos no se tocan: el trigger es `BEFORE INSERT`, solo bloquea altas nuevas. Para hacer soporte con una entidad al tope hay que **subirle el plan**.
- Despublicar (poner `activo = false`) un local o un servicio **no libera cupo**; borrarlo sí.
- El enforcement está en **Postgres**, no en la app: da igual si el alta se hace desde la app, desde el panel o por API.

**Qué ve el usuario cuando toca el techo:**

> Tu plan actual no permite crear más locales. Tu plan Inicio permite 2 locales y ya usas 2. Mejora tu plan en Mi suscripción.

El token técnico (`ERR_LIMITE_PLAN:`) nunca llega a la interfaz.

---

## 5. Crear un plan privado para un cliente (caso "negociable")

1. En **Superadmin → Planes de suscripción → Nuevo plan**.
2. Rellena nombre, días, precio y moneda (USD/CUP/EUR/MLC).
3. En **Límites**, deja vacíos los que no quieras restringir; pon números en los que sí.
4. En **Modalidad**, elige:
   - **Pago** → el cliente lo compra con Transfermóvil como cualquier plan.
   - **Contactar con ventas** → se muestra "A convenir" con botón de WhatsApp y **no** genera intent de pago.
5. Activa **Plan privado** y busca la entidad (por nombre). El plan queda **invisible** para el resto: solo lo ven el dueño/admin de esa entidad y el superadmin.
6. Guarda. Si dejas el código vacío, el servidor genera `privado_<idEntidad>_<n>`.

El cliente lo verá en **Mi suscripción → Planes**, con el chip "Plan privado / Exclusivo para <su entidad>", y podrá pagarlo con el flujo de siempre (intent → Transfermóvil → "Ya he pagado" → el superadmin lo aprueba). Al aprobarse, se le acreditan los días y **los límites del plan pasan a aplicar** automáticamente.

---

## 6. Contrato del servidor (para futuros desarrollos)

```sql
-- Columna nueva
flow.suscripcion_plan.id_entidad  integer null   -- NULL = público; NOT NULL = privado de esa entidad
flow.suscripcion_plan.modalidad   text not null  -- 'pago' | 'contacto'
flow.suscripcion_plan.etiqueta    text null      -- cinta de la tarjeta

-- Consultas
flow.entidad_limites(p_id_entidad integer)
  -> {ok, data:{plan_id, plan_codigo, plan_nombre, limites, vigente}}
flow.entidad_limite_alcanzado(p_id_entidad integer, p_recurso text, p_extra integer default 1)
  -> {ok, data:{bloqueado, recurso, usado, maximo, plan_nombre, mensaje}}

-- RPC redefinidos
flow.admin_planes_listar()                  -- + id_entidad, entidad_denominacion, modalidad, etiqueta
flow.admin_plan_guardar(..., p_modalidad, p_id_entidad, p_etiqueta)   -- 13 args
flow.cliente_planes_suscripcion()           -- públicos + privados del llamante; + modalidad, etiqueta,
                                            --   es_privado, id_entidad, entidad_denominacion, contacto_whatsapp
flow.cliente_crear_intent_suscripcion(...)  -- valida que el plan sea público o privado de ESA entidad
```

**Semántica de nulos en `admin_plan_guardar`** (importante al integrar):

| Campo | `null` | valor | `0` / `''` |
|---|---|---|---|
| `p_id_entidad` | conserva | asigna entidad privada | **0 = publicar** (id_entidad NULL) |
| `p_modalidad` | conserva | `pago` / `contacto` | — |
| `p_etiqueta` | conserva | pone la cinta | `''` = quitar la cinta |
| `p_limites` | conserva | objeto jsonb | `{}` = borrar límites |

---

## 7. Archivos de esta entrega

**SQL (nuevos, sin aplicar):**
- [72_planes_limites_privados.sql](flow_schema/migraciones/72_planes_limites_privados.sql) — columnas, RLS de privacidad de planes, `entidad_limites`, `entidad_limite_alcanzado`, 6 triggers, RPC redefinidos.
- [73_seed_planes_2026.sql](flow_schema/migraciones/73_seed_planes_2026.sql) — los 4 planes y la retirada de los de prueba.

**Superadmin (`ventiq_superadmin/`):**
- `lib/screens/flow_planes_screen.dart` — rejilla responsive de tarjetas + editor en secciones.
- `lib/widgets/planes_ui.dart` (nuevo) — tarjeta, cinta, chips, bloque de precio/contacto, helpers de límites y WhatsApp.
- `lib/services/suscripcion_admin_service.dart` — `guardarPlanDetallado()` y tolerancia pre-migración.

**App Flow (`inventtia_flow/`):**
- `lib/models/suscripcion.dart` — `PlanSuscripcion` con `modalidad`, `etiqueta`, `esPrivado`, `entidadDenominacion`, `contactoWhatsapp` y `caracteristicas`.
- `lib/screens/admin/mi_suscripcion_screen.dart` — tarjetas con lo que incluye, chip de privado y "Contactar con ventas".
- `lib/services/suscripcion_service.dart` — `LimitePlanException` y traducción del error de límite.
- `lib/services/catalogo_service.dart` y `lib/services/entidad_service.dart` — mensajes de límite en locales, servicios, asignaciones, entidades y usuarios.

---

## 8. Verificación hecha y pendientes

**Hecho:** análisis estático con el analizador de Dart sobre las dos apps → **0 diagnósticos en los archivos tocados** (los 2 errores de `ventiq_superadmin` están en `test/supplier_payment_service_test.dart`, preexistentes). SQL validado sintácticamente con `pglast` y contrastado contra el esquema real (columnas, FKs, ACL y `pg_policies`) **en solo lectura**: no se aplicó ni se escribió nada en la base de datos.

**Pendiente (mejoras posibles, ninguna bloqueante):**
1. El aviso de límite no tiene todavía un botón "Ver planes": la excepción ya lleva el recurso y la sugerencia; falta cablear un `SnackBar` con acción a la ruta `/mi-suscripcion` en las pantallas de gestión (fuera del alcance de esta entrega).
2. El RPC `entidad_limites` está listo pero la app aún no pinta "tu plan actual: 2/2 locales" en la pantalla de gestión.
3. No hay tests de widget de la pantalla de planes (no había ninguno antes).

---

## 9. Reversión

Cada archivo trae su bloque comentado. En resumen: soltar los 6 triggers, borrar las funciones nuevas y volver a pegar `admin_plan_guardar` de 10 argumentos y la política de lectura anterior (está referenciado archivo:línea en el bloque 9 del 72). Las columnas nuevas son destructivas de revertir porque pierden `id_entidad`, `modalidad` y `etiqueta` de los planes guardados.
