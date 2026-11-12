# 10 · Incidente P0: clave `service_role` de producción expuesta

> **Severidad: CRÍTICA.** No es un riesgo del plan de taxi: es una exposición **activa y ya materializada** de toda la base de datos de producción.
> **Fecha de detección**: 2026-11-12. **Detectado por**: especialista legal (08) y verificado por el Lead decodificando los JWT embebidos.
> **Estado**: confirmado con evidencia. Requiere decisión del responsable del proyecto.

---

## 1. Qué pasa

La app compila contra producción con una clave que tiene `role = service_role`. Esa clave **salta todas las políticas RLS** y da lectura/escritura total sobre el esquema `public` y `muevete`.

Verificado decodificando el payload del JWT embebido en `inventtia_muevete/lib/config/supabase_config.dart:11-12`:

```
release (kReleaseMode) → project_ref = vsieeihstajlrdvpuooh (PRODUCCIÓN)
                         role        = service_role        ← bypass total de RLS
```

## 2. Evidencia (los tres vectores)

| # | Vector | Evidencia |
|---|---|---|
| 1 | **6 apps llevan la clave de producción en el build de release** | `inventtia_muevete`, `ventiq_app`, `ventiq_admin_app`, `ventiq_licencer_express`, `ventiq_marketplace`, `ventiq_superadmin` — todas con `role=service_role` y `ref=vsieeihstajlrdvpuooh`. La de debug es `anon` (correcta) |
| 2 | **El repositorio es público** | `https://github.com/Carnaval-Team/VentIQ-seller-App` responde 200 sin autenticación |
| 3 | **Está en el historial de git** | `git log -S` encuentra la clave en **7 commits**; además aparece literal en `ventiq_admin_app/supabase/migrations/20260527_wapi_dispatch_vault.sql` y `20260602_wapi_update_service_key.sql` |
| 4 | **Los triggers de push también la embeben** | los 3 triggers `pg_net` de producción llevan el JWT de `service_role` dentro de la definición (`pg_trigger`), legible por cualquiera con acceso al catálogo |

## 3. Alcance del daño

Con esa clave, un tercero puede, **sin autenticarse como usuario**:

- Leer y modificar **CI, fotos del carnet frente y dorso** de clientes y choferes.
- Leer **387 351 posiciones históricas** y la ubicación en vivo de todos los choferes.
- Leer y alterar **wallets y transacciones** (`wallet_drivers`, `suscription_user`, `transacciones_wallet`).
- Crear, modificar o borrar **viajes, solicitudes, tarifas y configuraciones**.
- Insertar usuarios, choferes o viajes falsos.
- **Saltarse cualquier medida de este plan**: KYC, consentimiento, gate de identidad, comisión, botón de pánico. No sirve de nada implementar H1/H2 mientras la clave esté viva.

> Peor aún: es más grave que cualquier hallazgo de RLS anterior, porque el RLS deja de importar.

## 4. Por qué no basta con "borrar el commit"

El historial de git ya contiene la clave en 7 commits; el repo es público; los APK ya distribuidos la llevan compilada. **La clave debe considerarse comprometida de forma permanente.** La única remediación real es **rotarla y dejar de usarla**.

## 5. Acciones inmediatas (hoy, sin tocar código)

| # | Acción | Efecto | Riesgo |
|---|---|---|---|
| A1 | **Hacer privado el repositorio** en GitHub | corta la exposición pública del código y del historial | ninguno para la app |
| A2 | Revisar en el historial de `pg_stat_statements` / logs de la API si hubo actividad anómala con esa clave | detectar abuso previo | ninguno |
| A3 | **Desactivar/rotar la clave legacy** (`service_role`) en Supabase | invalida la clave filtrada | **rompe todas las apps hasta que se actualicen** |
| A4 | Rotar el secreto de push de los triggers a Vault (ya está escrito en `030_baseline_sync_produccion.sql`) | quita el token del catálogo | requiere recrear triggers |

## 6. Remediación estructural (lo que de verdad lo cierra)

El problema de fondo: **la app cliente/admin no puede tener una credencial privilegiada**. Todo lo que hoy hace con `service_role` (saltarse RLS) debe pasar a RPCs `SECURITY DEFINER` con validación de rol, y la app debe usar la clave **publishable/anon**.

El proyecto ya tiene una clave moderna disponible: `sb_publishable_...` (`type: publishable`, `disabled: false`). Es la que debe ir en el release.

```
1. Preparar RPCs servidor-side para todo lo privilegiado (ya es H3/H7 del plan de taxi; en las otras 5 apps es trabajo aparte).
2. Cambiar las 6 apps a sb_publishable_* y endurecer RLS (041).
3. Rotar/deshabilitar la clave legacy service_role.
4. Publicar actualización forzada (versión mínima obligatoria).
5. Recrear los 3 triggers de push leyendo de Vault.
6. Auditar 30 días atrás.
```

## 7. Decisión tomada por el usuario (2026-11-12)

> **NO se rota la `service_role`.** Hay app en producción y se decide no interrumpirla. Se cambia únicamente la clave en los proyectos (la app pasa a usar `anon`) y se asume el riesgo de que la clave filtrada siga viva.

| Decisión | Estado |
|---|---|
| Rotar / desactivar `service_role` | ❌ **descartado** por decisión del usuario. No se intenta ni se ejecuta |
| Cambiar la clave de release a `anon` en `inventtia_muevete` | ✅ **hecho y verificado** (ambas claves del archivo decodifican `role=anon`) |
| Cambiar las otras 5 apps | ⏳ pendiente, fuera del alcance de este plan |
| Repositorio a privado | ⏳ recomendado, no bloqueante |
| Triggers de push con token en Vault | ⏳ el baseline `030` ya los deja listos para entornos nuevos; no se recrean en producción |

### Consecuencia aceptada (registro honesto del riesgo)

Mientras la clave `service_role` siga viva, cualquiera que haya descargado el APK o leído el repo público **mantiene acceso total** a la base de datos: CI, fotos de carnet, wallets y ubicaciones. El cambio a `anon` **no cierra** esa puerta; solo evita que las **versiones nuevas** distribuyan una credencial privilegiada. La reducción real del riesgo llega cuando (a) el repo esté privado, (b) las apps distribuidas se actualicen y (c) se rote la clave en una ventana futura.

**Recomendación para el futuro, sin bloquear nada ahora**: cuando exista una ventana de mantenimiento, rotar la clave y publicar las versiones que ya usan `anon` (a partir de este cambio, todas las nuevas).

## 8. Lo que este incidente cambia en el plan

- Se añade **H0-A** como hito bloqueante previo a H0 (ver `PLAN-IMPLEMENTACION.md` §6).
- El hardening de RLS (`041`) deja de ser "cutover" y pasa a ser **requisito para poder rotar**.
- Los especialistas de seguridad y legal tienen razón en sus riesgos #1 y #2: sin esto, sus medidas son cosméticas.