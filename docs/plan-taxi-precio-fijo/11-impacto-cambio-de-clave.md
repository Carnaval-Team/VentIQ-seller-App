# 11 · Impacto de cambiar `service_role` por la clave publishable

> **Pregunta que responde**: si rotamos la clave y las apps pasan a `sb_publishable_…`, ¿qué deja de funcionar?
> **Método**: (a) políticas RLS reales por tabla y operación (`pg_policies` en producción), (b) escrituras directas a BD en el código de `inventtia_muevete` (grep de `.from('tabla')…insert/update/delete/upsert`).
> **Conclusión corta**: **el cambio es viable**. La app no se cae entera; fallan unas pocas operaciones concretas que, además, son las que el flujo nuevo reemplaza por RPCs.

---

## 1. Por qué puede funcionar

Hoy la app usa `service_role`, que **salta el RLS**. Al cambiar a la clave publishable, las peticiones pasan a ejecutarse como `authenticated` y **el RLS sí aplica**.

La buena noticia: **todas las tablas que la app escribe tienen políticas para `authenticated`**. No hay ninguna tabla "sin política" que provoque un fallo universal.

| Tabla | Escrituras directas en el código | Políticas `authenticated` | ¿Sobrevive? |
|---|---|---|---|
| `users` | 4 | ALL / INSERT / UPDATE | ✅ |
| `drivers` | 12 | ALL / DELETE / INSERT / SELECT / UPDATE | ✅ |
| `vehiculos` | 3 | ALL / INSERT / UPDATE | ✅ |
| `place` | 4 | ALL / INSERT / SELECT / UPDATE | ✅ |
| `solicitudes_transporte` | 8 | INSERT / SELECT / UPDATE | ⚠️ parcial |
| `viajes` | 8 | INSERT / SELECT / UPDATE | ✅ |
| `suscription_user` (wallet cliente) | 3 | ALL / INSERT / UPDATE | ✅ |
| `wallet_drivers` | 4 | INSERT / SELECT / UPDATE | ✅ |
| `transacciones_wallet` | 6 | INSERT / SELECT | ✅ |
| `notificaciones`, `push_tokens`, `direcciones_rapidas`, `paradas_viaje`, `valoraciones_viaje` | 2 c/u | ALL / INSERT / UPDATE | ✅ |

## 2. Lo que sí se rompe

| # | Operación | Por qué falla | Dónde |
|---|---|---|---|
| R1 | El **chofer** actualiza el estado de una `solicitud` del cliente (`completada`, `aceptada`) | la única política de UPDATE es `solicitudes_update_own_client` con `user_id = auth.uid()`; el chofer no es el dueño de la fila | `incoming_requests_screen.dart:629`, `completion_sync_service.dart:136-140` |
| R2 | Cualquier lectura de una solicitud **ajena** por parte del chofer para ver los viajes disponibles | `drivers_see_solicitudes USING(true)` sí lo permite (sigue abierta), así que **hoy no falla**, pero es justo la que hay que cerrar | `driver_service.dart:297-306` |
| R3 | Operaciones de wallet sobre filas de **otro** usuario | `suscription_user_update_own` y `wallet_drivers_update_own` son por `auth.uid()`; el cierre de viaje ya va por RPC | `wallet_service.dart` (hold/refund directos) |

R1 y R3 son exactamente las que el plan reemplaza por `fn_completar_viaje` (H7) y `fn_tomar_viaje` (H3).

## 3. El detalle incómodo: por qué "funciona"

Sobrevive en buena parte por dos políticas **abiertas de par en par**:

```sql
-- muevete.users
users_        ALL  USING (true) WITH CHECK (true)
-- muevete.place
places_       ALL  USING (true) WITH CHECK (true)
```

Es decir: cualquier usuario autenticado puede leer y **modificar todos los `users` y todas las `place`** (nombre, teléfono, CI, fotos, posición). Son el puente que mantiene la app viva, y son un agujero grave por sí mismas.

**Consecuencia honesta**: rotar la clave **reduce** la exposición de *"cualquiera en internet, sin cuenta"* a *"cualquier usuario registrado"*. Es una mejora enorme, pero **no cierra el problema**: el cierre real es rotar + RPCs + endurecer RLS (`041`).

## 4. Secuencia recomendada (una sola release)

```
1. Rotar/deshabilitar la clave legacy service_role en el dashboard de Supabase.
2. Publicar las apps con sb_publishable_… (ya disponible, activa).
3. En la misma release, parchear R1 y R3:
     · cierre de viaje por RPC (aunque sea mínima: fn_completar_viaje de H7)
     · hold/refund de wallet por RPC
   Sin estos dos parches, completar un viaje dejaría de funcionar.
4. Recrear los 3 triggers de push con el token desde Vault (ya escrito en 030).
5. Endurecer RLS (041) y pasar todo lo privilegiado a RPC en la release siguiente.
6. Forzar versión mínima para que no queden apps con la clave vieja.
```

## 5. ¿Y si no se puede parchear R1 y R3 a tiempo?

Alternativa de emergencia que **no requiere tocar código**: dejar una política temporal más permisiva que cubra las dos operaciones rotas:

```sql
-- TEMPORAL, se elimina con 041. Nunca dejar esto puesto.
create policy solicitudes_update_driver_temporal on muevete.solicitudes_transporte
  for update to authenticated
  using (exists (select 1 from muevete.drivers d where d.uuid = auth.uid()))
  with check (true);
```

Con esto el flujo viejo sigue funcionando con la clave publishable y se puede rotar **hoy mismo**. El coste es que cualquier chofer puede actualizar cualquier solicitud durante el tiempo que dure la transición.

## 6. Recomendación

| Escenario | Recomendación |
|---|---|
| Se puede publicar una release en 24-48 h | **Rotar ya** + release con publishable + parches R1/R3 + política temporal si hace falta |
| No se puede publicar en una semana | Rotar igualmente + política temporal de §5, y aceptar que cualquier chofer puede tocar solicitudes temporalmente. Sigue siendo infinitamente mejor que la situación actual |

En ambos casos: **hacer privado el repositorio hoy**, que eso no rompe nada.