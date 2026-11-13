# 14 · Despliegue y cutover del taxi de precio fijo

> **Estado**: runbook listo para ejecutar. Hito **H8**.
> **Alcance**: pasar del flujo viejo (negociación + precio libre) al flujo nuevo
> (precio fijo congelado en servidor) sin dejar viajes huérfanos y sin que las
> apps viejas rompan el dinero.
> **Proyecto de producción**: `vsieeihstajlrdvpuooh`. **Pruebas**: `qhprswhhfasrikhawjoz`.
> **Documentos hermanos**: [`06-aplicar-migraciones.md`](06-aplicar-migraciones.md)
> (cómo aplicar SQL), [`13-contrato-app-rpc.md`](13-contrato-app-rpc.md)
> (qué llama la app), [`PLAN-IMPLEMENTACION.md`](PLAN-IMPLEMENTACION.md) §7–§10.

**Regla de oro**: cada paso se verifica antes de pasar al siguiente. El orden no
es negociable; los tres pasos irreversibles (`041`, versión mínima y flag) van al
final y en ese orden exacto.

---

## Índice

1. [Prerrequisitos](#1-prerrequisitos)
2. [Orden exacto del cutover](#2-orden-exacto-del-cutover)
3. [`MUEVETE_QR_SECRET` en los builds](#3-muevete_qr_secret-en-los-builds)
4. [Versión mínima forzada](#4-versión-mínima-forzada)
5. [Verificación post-despliegue](#5-verificación-post-despliegue)
6. [Rollback](#6-rollback)
7. [Riesgos conocidos y mitigación](#7-riesgos-conocidos-y-mitigación)
8. [Anexo · Matriz E2E manual (dos dispositivos)](#8-anexo--matriz-e2e-manual-dos-dispositivos)

---

## 1. Prerrequisitos

### 1.1 Personas y permisos

| Rol | Quién | Qué firma |
|---|---|---|
| **Aprueba el corte** | Lead del plan de taxi | go/no-go de la ventana y del rollback |
| **Ejecuta SQL** | DBA / responsable de infra | cada `Success` de migración |
| **Ejecuta builds** | responsable de release | APK + web con `--dart-define` |
| **Verifica en dispositivo** | QA (H8) | matriz E2E del §8 |
| **Opera el panel** | superadmin | versión mínima y tarifas |

Accesos que hay que tener **antes** de abrir la ventana:

- [ ] SQL Editor del proyecto de producción `vsieeihstajlrdvpuooh` (rol `postgres`).
- [ ] Dashboard de Supabase → *Database → Backups* (y PITR si el plan lo tiene).
- [ ] Panel superadmin (`ventiq_superadmin`) con una cuenta de rol superadmin.
- [ ] Consola de las tiendas / hosting web donde se publica el APK y la web.
- [ ] Dos dispositivos con la **build vieja** instalada (para probar que se
      bloquea) y dos con la **build nueva** (cliente y chofer).
- [ ] Gestor de contraseñas del equipo (para `MUEVETE_QR_SECRET`).

### 1.2 Respaldo

Antes de tocar nada:

```sql
-- 1) Foto de los números que no deben cambiar de significado
select count(*) as solicitudes from muevete.solicitudes_transporte;   -- ~55
select count(*) as viajes      from muevete.viajes;                  -- ~44
select count(*) as usuarios    from muevete.users;
select count(*) as choferes    from muevete.drivers;
select count(*) as wallets     from muevete.wallet_drivers;
select count(*) as wallets_cli from muevete.suscription_user;
```

- [ ] Anotar esos seis números en el ticket de la ventana.
- [ ] Tomar un backup lógico de los esquemas que se tocan (además del backup
      automático del dashboard):

```bash
pg_dump --schema=muevete --schema=public \
        --no-owner --no-privileges \
        --file=cutover_muevete_$(date +%F_%H%M).sql \
        "$PROD_DATABASE_URL"
```

- [ ] Guardar también el volcado de políticas **antes** de `041` (es el único
      sitio del que se podría reconstruir el estado previo):

```sql
select schemaname, tablename, policyname, cmd, roles::text, qual, with_check
  from pg_policies
 where schemaname = 'muevete'
 order by tablename, policyname;
```

### 1.3 Estado de partida (todo debe cumplirse)

```sql
-- a) 030–040 aplicadas en producción
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'muevete'
   and proname in ('fn_cotizar_viaje','fn_crear_solicitud','fn_viajes_disponibles',
                   'fn_tomar_viaje','fn_completar_viaje','fn_cancelar_solicitud',
                   'fn_recargar_wallet')
 order by 1;                          -- esperado: 7 filas

-- b) el flag sigue APAGADO (si ya está en true, alguien se adelantó: PARAR)
select taxi_precio_fijo_activo from muevete.configuracion_tarifas where id = 1;
-- esperado: false

-- c) no hay viajes abiertos viejos que se queden huérfanos
select estado, count(*) from muevete.solicitudes_transporte
 where estado in ('pendiente','aceptada') group by 1;
-- esperado: 0 filas, o un puñado que se cierra en el paso 1

-- d) la tabla de versiones existe y tiene filas (mecanismo del §4)
select app_name, version_actual, build_number, actualizacion_obligatoria, activa
  from public.app_versiones order by app_name, build_number desc;
```

- [ ] (a) 7 funciones.
- [ ] (b) `false`.
- [ ] (c) sin `pendiente`/`aceptada` colgadas.
- [ ] (d) existe al menos una fila por app; si la tabla está vacía, el
      mecanismo del §4 **no bloquea nada** hasta que se inserte la primera.

> **Dependencia del panel**: el service del superadmin
> (`ventiq_superadmin/lib/services/versiones_service.dart`) escribe por
> `fn_app_version_guardar` / `fn_app_version_eliminar` y usa las columnas
> `titulo`, `novedades` y `url_descarga`, que añade la migración
> `75_app_versiones_novedades.sql` (`inventtia_flow/docs/flow_schema/migraciones/`).
> Verificar:
>
> ```sql
> select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
>  where n.nspname = 'public'
>    and proname in ('fn_app_version_guardar','fn_app_version_eliminar');
> select column_name from information_schema.columns
>  where table_schema='public' and table_name='app_versiones'
>    and column_name in ('titulo','novedades','url_descarga');
> ```
>
> Si faltan, el panel **no puede guardar** y hay que usar el camino SQL del §4.4
> (o aplicar la 75 primero, fuera de esta ventana).

### 1.4 Ventana

- [ ] Horario de menor demanda (mañana temprano en La Habana; evitar 07:00–09:00
      y 17:00–20:00).
- [ ] Duración reservada: **90 minutos** (SQL ~15 min, builds y publicación ~40,
      verificación ~30).
- [ ] Aviso a los choferes con 24 h de antelación (grupo de WhatsApp/soporte):
      "mañana hay que actualizar la app; sin actualizar no se pueden tomar
      viajes".
- [ ] Canal de soporte con una persona asignada durante la ventana.

---

## 2. Orden exacto del cutover

Cada casilla se marca **sólo** cuando su verificación da lo esperado. Si algo
falla: parar, mirar §6 y decidir con el Lead. No se salta al siguiente paso
"para ver si funciona".

### Paso 0 · Congelar (5 min)

- [ ] Avisar por el canal de soporte: "no publicar viajes nuevos durante 15 min".
- [ ] Confirmar que no hay `solicitudes` en `pendiente`/`aceptada` (§1.3 c).
      Si hay, esperar a que se cierren o cancelarlas con la app (con reembolso).

### Paso 1 · Aplicar 030–040 (10–15 min)

- [ ] Aplicar **en orden**, archivo por archivo, en el SQL Editor de producción:
      `030` → `031` → `032` → `033` → `034` → `035` → `036` → `037` → `038` →
      `039` → `040`.
      (Si 030–040 ya están aplicadas de una ventana anterior, este paso es
      idempotente en su mayor parte; aun así ejecutar y comprobar.)
- [ ] Verificar tras cada bloque con lo que indica
      [`06-aplicar-migraciones.md`](06-aplicar-migraciones.md) §3.
- [ ] Verificación final del paso:

```sql
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='muevete' and proname like 'fn_%' order by 1;

select count(*) as tablas_en_realtime
  from pg_publication_tables
 where pubname='supabase_realtime' and schemaname='muevete'
   and tablename in ('solicitudes_transporte','viajes','place',
                     'notificaciones','vehicle_type','ofertas_chofer');
-- esperado en producción: 6 (las 6 ya están publicadas desde antes del plan).
-- El proyecto de pruebas sólo tiene 2 (las que añade 041), y está bien.
```

**Por qué primero**: `030`–`040` son **aditivas** (columnas con default, tablas
nuevas, RPC nuevas). No rompen las apps viejas, que siguen escribiendo por las
políticas antiguas. Es lo único que se puede aplicar sin ventana de riesgo.

- [ ] 7+ funciones, realtime con las tablas esperadas, flag todavía en `false`.

### Paso 2 · Publicar las apps nuevas (30–40 min)

Orden: **superadmin → chofer → cliente**. El superadmin primero porque es quien
configura tarifas y versiones; el chofer antes que el cliente porque sin oferta
no sirve que el cliente ya pueda pedir.

- [ ] Build del superadmin (sin `--dart-define`; no usa QR).
- [ ] Build del **chofer** y del **cliente** con el secreto (§3):

```bash
# El ÚNICO define propio del taxi es el secreto del QR.
# La URL y la anon key NO son dart-define: salen de
# lib/config/supabase_config.dart, que elige producción sólo en modo release.
flutter build apk --release \
  --dart-define=MUEVETE_QR_SECRET="$MUEVETE_QR_SECRET"
```

> **Trampa de build**: `supabase_config.dart` decide por `kReleaseMode`.
> `flutter build apk --release` y `flutter build web --release` apuntan a
> **producción** (`vsieeihstajlrdvpuooh`); `flutter run` y cualquier build debug
> apuntan a **pruebas** (`qhprswhhfasrikhawjoz`). Un APK publicado desde un build
> debug manda a los usuarios al proyecto de pruebas, donde `taxi_precio_fijo_activo`
> puede estar en otro estado. Comprobar en el dispositivo que un viaje de prueba
> aparece en producción:

```sql
select id, created_at from muevete.solicitudes_transporte order by id desc limit 1;
```

- [ ] Publicar APK/web en el canal de siempre.
- [ ] Comprobar en un dispositivo con la build nueva que abre y llega al login.
- [ ] **No** subir todavía la versión mínima.

**Por qué ahora y no antes**: hasta este momento el flag está en `false`, así
que las RPC nuevas responden `P0003 servicio_en_mantenimiento`. Eso es
intencionado: si alguien con la build nueva publica un viaje antes de tiempo, ve
"servicio en mantenimiento" en vez de un viaje a medias.

### Paso 3 · Subir la versión mínima (5 min)

Detalle completo en §4. En la ventana basta:

- [ ] Insertar/actualizar la fila de `public.app_versiones` de
      `inventtia_muevete` con `build_number` **mayor** que el de toda build en
      circulación y `actualizacion_obligatoria = true` (§4.3).
- [ ] Verificar desde un dispositivo con la build vieja: al abrir, a los ~4 s
      aparece "Actualización Obligatoria" y **no** se puede cerrar (§4.5).
- [ ] Esperar 10–15 min y comprobar que baja el tráfico de la build vieja
      (§5.2, consulta de versiones).

**Por qué antes de `041`**: `041` revoca las escrituras que usan las apps
viejas. Si se aplicara con el parque viejo activo, esos usuarios no podrían ni
publicar ni tomar viajes y el negocio se detiene en seco. La versión mínima es
el mecanismo que convierte "no pueden operar" en "se les pide actualizar".

### Paso 4 · Aplicar `041` (5 min)

- [ ] Pegar `inventtia_muevete/docs/migrations/041_taxi_rls_hardening.sql`
      completo en el SQL Editor.
- [ ] Esperar `Success`. **Leer los `NOTICE`/`WARNING` de la salida** (ver §7.3:
      un `WARNING` de wallets duplicados es informativo y no aborta).
- [ ] Verificar que las políticas peligrosas ya no existen:

```sql
select tablename, policyname from pg_policies
 where schemaname='muevete'
   and policyname in ('users_','solicitudes_select_own_client',
                      'drivers_see_solicitudes','solicitudes_insert_client',
                      'solicitudes_update_own_client','viajes_insert_authenticated',
                      'wallet_drivers_insert_own','wallet_drivers_update_own',
                      'transacciones_insert_client','suscription_user_insert_own',
                      'suscription_user_update_own','places_');
-- esperado: 0 filas
```

- [ ] Verificar que las políticas nuevas están:

```sql
select policyname from pg_policies
 where schemaname='muevete' and tablename='solicitudes_transporte' order by 1;
-- esperado, entre otras: solicitudes_select_driver_asignado,
--                        solicitudes_select_own_client, superadmin_all_...
```

**Por qué `041` va después de la versión mínima**: es la migración que **rompe a
propósito** a las apps viejas (revoca `INSERT`/`UPDATE` directos sobre
`solicitudes_transporte`, `viajes`, `wallet_drivers`, `transacciones_wallet`,
`suscription_user` y deja `ofertas_chofer` en solo lectura). Aplicarla antes de
que el parque esté actualizado deja a los usuarios viejos sin poder operar y sin
mensaje que les explique qué hacer.

- [ ] Flag sigue en `false` (aún no se enciende).

### Paso 5 · Encender `taxi_precio_fijo_activo` (2 min)

```sql
update muevete.configuracion_tarifas
   set taxi_precio_fijo_activo = true
 where id = 1;

select taxi_precio_fijo_activo from muevete.configuracion_tarifas where id = 1;
-- esperado: true
```

- [ ] Flag en `true`.
- [ ] Prueba inmediata en dos dispositivos nuevos: cliente publica → chofer ve →
      chofer toma (§8, casos 2–5).
- [ ] Si esa prueba falla, ver §6 (revertir el flag es el rollback barato).

**Por qué el flag va al final**: es el interruptor de negocio, no de esquema.
Mientras esté en `false`, las RPC nuevas rechazan crear y tomar viajes
(`P0003`), y la app nueva muestra "Servicio en mantenimiento" (contrato §1). Se
enciende **sólo** cuando el esquema está endurecido (`041`) y el parque está
actualizado; en ese momento el flujo nuevo es el único camino posible y no hay
vuelta atrás a medias: apagarlo devuelve "mantenimiento", no el flujo viejo.

### Paso 6 · Verificar (20–30 min)

- [ ] Ejecutar el bloque SQL de §5.1 y anotar los resultados.
- [ ] Recorrer los casos 1–14 de la matriz del §8 en dos dispositivos.
- [ ] Vigilar durante 24 h: viajes/hora, `p50` de asignación, errores `P0020`/
      `P0033` en logs de la app.

### Paso 7 · Cerrar la ventana

- [ ] Anunciar "actualización completada" a los choferes.
- [ ] Guardar en el ticket: hora de cada paso, salida de las verificaciones,
      versión publicada (`version_actual` + `build_number`).
- [ ] Programar revisión a 24 h y a 7 días (KPIs de `15-kpis.sql`).
- [ ] Dejar `ofertas_chofer` en solo lectura durante **una release más**; no
      borrarla en esta ventana.

---

## 3. `MUEVETE_QR_SECRET` en los builds

### 3.1 Qué es y por qué es obligatorio

El cierre de viaje por QR (offline) firma un payload con **HMAC-SHA256**. El
secreto se inyecta en tiempo de compilación y **no vive en el repo** (el repo es
público):

`inventtia_muevete/lib/services/trip_completion_qr_service.dart`

```dart
static const String _hmacSecret = String.fromEnvironment('MUEVETE_QR_SECRET');
```

El servicio **falla cerrado** si el define falta o está vacío:

- `generatePayload()` lanza `StateError` → la UI muestra
  `noConfiguradoMensaje` ("El cierre por QR no está configurado; usa el cierre
  en la app") en vez de pintar un QR inválido.
- `validateAndDecode()` devuelve `null` → el escáner rechaza todo QR.

Es decir: **sin `--dart-define` el cierre por QR queda deshabilitado a
propósito**. Las otras dos vías (online y offline en la app) siguen funcionando,
así que el viaje no se pierde; lo que se pierde es el cierre entre dos teléfonos
sin red.

### 3.2 Generarlo

Una sola vez, y el **mismo valor** en la build del cliente y en la del chofer
(uno firma, el otro valida; si no coinciden, todo QR se rechaza):

```bash
# Linux / macOS / Git Bash
openssl rand -base64 48 | tr -d '\n'

# Windows PowerShell (equivalente)
[Convert]::ToBase64String((1..48 | ForEach-Object { Get-Random -Max 256 }))
```

Requisitos prácticos: ≥ 32 bytes de entropía, sin espacios ni saltos de línea
(se pasa como argumento de línea de comandos), sin comillas dentro del valor.

### 3.3 Dónde guardarlo (no en el repo)

- [ ] Gestor de contraseñas del equipo, entrada
      `muevete/qr_hmac_secret` con fecha de creación y quién lo generó.
- [ ] Variable de entorno del runner de CI (`MUEVETE_QR_SECRET`), marcada como
      secreta y enmascarada en logs.
- [ ] **Nunca** en: `lib/`, `assets/`, `--dart-define` escrito en un README,
      `.vscode/launch.json` versionado, ni en un mensaje de chat.

### 3.4 Usarlo en cada build

```bash
export MUEVETE_QR_SECRET='<valor del gestor>'

flutter build apk --release \
  --dart-define=MUEVETE_QR_SECRET="$MUEVETE_QR_SECRET"

flutter build web --release \
  --dart-define=MUEVETE_QR_SECRET="$MUEVETE_QR_SECRET"
```

Es el **único** `--dart-define` del módulo taxi. La URL y la anon key de Supabase
no se pasan por línea de comandos: `lib/config/supabase_config.dart` las elige
según `kReleaseMode` (ver la trampa de build en §2, paso 2).

- [ ] Build del **cliente** con el define.
- [ ] Build del **chofer** con el define.
- [ ] Verificar en el dispositivo que el botón "Cerrar con QR" genera un QR (si
      falta el secreto, muestra el aviso de no configurado).

### 3.5 Rotación

Rotar el secreto **invalida los QR ya mostrados** (ventana anti-replay de 10
minutos, así que el impacto es corto). Procedimiento: generar nuevo → recompilar
y publicar ambas apps → subir `build_number` y mantener
`actualizacion_obligatoria = true` → el parque se actualiza y los QR viejos
dejan de validarse solos.

> Si se rota el secreto sin subir la versión mínima, quedan teléfonos con
> secretos distintos: el cliente nuevo escanea el QR del chofer viejo y no
> valida. El síntoma es "el QR no sirve" y no hay log que lo explique: por eso
> rotación y versión mínima van juntas.

---

## 4. Versión mínima forzada

### 4.1 El mecanismo real (leído del código, no del diseño)

Cadena completa, en orden:

1. **La app lee su propia versión de un asset**, no del servidor:
   `inventtia_muevete/assets/changelog.json`

   ```json
   { "current_version": "1.0.0", "build": 1,
     "app_name": "inventtia_muevete",
     "download_url_apk": "", "download_url_web": "" }
   ```

   > `pubspec.yaml` dice `version: 1.0.0+1`. **El número que compara el
   > mecanismo es `build` de este JSON**, no el de `pubspec.yaml`: hay que
   > mantenerlos sincronizados a mano en cada release.

2. **`UpdateService.checkForUpdates()`** (`lib/services/update_service.dart`)
   llama a la RPC:

   ```dart
   _supabase.rpc('fn_check_update', params: {
     'p_app_name': appName,          // 'inventtia_muevete'
     'p_version_actual': currentVersion, // '1.0.0'
     'p_build_actual': currentBuild,     // 1
   });
   ```

3. **`public.fn_check_update`** lee de la tabla **`public.app_versiones`**:

   ```sql
   SELECT * INTO v_latest FROM app_versiones
    WHERE app_name = p_app_name AND activa = TRUE
    ORDER BY build_number DESC LIMIT 1;

   IF FOUND AND v_latest.build_number > p_build_actual THEN
       v_hay_update := TRUE;
   END IF;
   ```

   Devuelve `hay_actualizacion`, `version_disponible`, `obligatoria`,
   `version_minima`, `fecha_lanzamiento`.

   Columnas reales de `public.app_versiones`: `id`, `app_name`,
   `version_actual`, `version_minima`, `version_maxima`, `build_number`,
   `actualizacion_obligatoria`, `fecha_lanzamiento`, `activa` (+ `titulo`,
   `novedades`, `url_descarga` si está aplicada la migración 75).

4. **La decisión de bloquear la toma `actualizacion_obligatoria` de la última
   fila activa**, no `version_minima`:
   `update_dialog_helper.dart` hace
   `barrierDismissible: !isObligatory` y `onWillPop: () async => !isObligatory`,
   y **oculta el botón "Más tarde"**. El diálogo se llama "Actualización
   Obligatoria" y sólo se puede salir descargando.

5. **Cuándo se dispara**: `UpdateChecker` (widget envolvente de la app) espera
   4 segundos tras el primer frame y llama a `checkForUpdates()` una sola vez
   por sesión (`_checkedThisSession`). Además hay comprobaciones forzadas en
   `landing_screen.dart` (botón "Buscar actualizaciones") y en `client_drawer.dart`.

### 4.2 Consecuencia práctica (importante)

- **`version_minima` se devuelve pero la app no lo usa.** Hoy el bloqueo real es
  "*build_number* de la última fila activa es mayor que el mío **y** esa fila
  tiene `actualizacion_obligatoria = true`".
- Por eso la fila que se inserta en el cutover debe tener un `build_number`
  **mayor que el de cualquier build instalada**; si no, nadie ve el diálogo
  aunque `version_minima` diga otra cosa.
- Y por eso, después del cutover, **no se debe publicar una fila nueva con
  `actualizacion_obligatoria = false`** mientras queden builds viejas: la
  última fila activa sería esa, y las apps viejas dejarían de estar bloqueadas
  (el diálogo pasaría a ser opcional). Mientras el parque no esté limpio, toda
  fila nueva va con `obligatoria = true`.

### 4.3 Dónde se configura (pantalla del superadmin)

- **Pantalla**: `ventiq_superadmin` → menú **"Versiones de las apps"**,
  ruta `/versiones` (`lib/screens/versiones_screen.dart` +
  `lib/widgets/versiones_ui.dart`).
- Botón **"Nueva versión"**. Campos del formulario:

  | Campo | Qué poner en el cutover |
  |---|---|
  | **App \*** | `inventtia_muevete` (el selector lista las 5 apps del ecosistema) |
  | **Versión \*** | `1.1.0` (la que se publica) |
  | **Build \*** | `2` (mayor que el de toda build instalada) |
  | **Versión mínima \*** | `1.1.0` (el editor la sugiere igual a la versión nueva) |
  | **Obligatoria** (switch) | **ON** — "El usuario no puede omitirla" |
  | **Activa** (switch) | ON |
  | Título del changelog / Añadir cambio | opcional (lo pinta la app como "Novedades") |
  | URL de descarga | opcional; **la app no la usa para el diálogo** (ver aviso) |

  > **La URL de descarga que abre el botón "Descargar" sale del
  > `assets/changelog.json` de la build** (`download_url_apk` /
  > `download_url_web`), no de la fila de `app_versiones`. Si el JSON se compiló
  > con las URLs vacías (como está hoy en el repo), el botón cae en el diálogo
  > de descarga manual con el texto "No hay una URL de descarga configurada".
  > **Antes de los builds del cutover hay que rellenar esas dos URLs en el
  > JSON.**

### 4.4 Camino SQL (si el panel no puede guardar)

Cuando la migración 75 no está aplicada, `fn_app_version_guardar` no existe y el
panel falla al guardar. Alternativa equivalente, con las columnas que sí existen:

```sql
-- Desactivar la última fila activa de la app (para que la nueva sea "la última")
update public.app_versiones
   set activa = false
 where app_name = 'inventtia_muevete' and activa = true;

insert into public.app_versiones
  (app_name, version_actual, version_minima, build_number,
   actualizacion_obligatoria, fecha_lanzamiento, activa)
values
  ('inventtia_muevete', '1.1.0', '1.1.0', 2,
   true, now(), true);

select id, app_name, version_actual, version_minima, build_number,
       actualizacion_obligatoria, activa
  from public.app_versiones
 where app_name = 'inventtia_muevete'
 order by build_number desc;
```

- [ ] La fila nueva es la de `build_number` más alto y la única con `activa = true`.

### 4.5 Verificarlo desde un dispositivo

1. Instalar la **build vieja** (la que está en la calle) en un teléfono.
2. Abrir la app y esperar **~4–5 segundos** en la primera pantalla.
3. Debe aparecer el diálogo **"Actualización Obligatoria"** (icono de aviso
   naranja) con "Nueva versión disponible: 1.1.0".
4. Intentar cerrarlo: tocar fuera del diálogo y el botón atrás **no** lo cierran;
   no existe el botón "Más tarde".
5. Tocar "Descargar"/"Actualizar ahora" → debe abrir el APK o recargar la web.
6. Instalar la build nueva → abrir la app → **no** debe aparecer el diálogo.

Comprobación desde SQL (sirve para ver si el parque está migrando). No hay tabla
de "versiones instaladas"; el proxy es el tráfico de la app y, si se instrumenta,
un `insert` en una tabla de telemetría. Mientras no exista, el indicador es 4–5
de la matriz manual más los reportes de soporte.

### 4.6 Valor sugerido

| Campo | Valor | Motivo |
|---|---|---|
| `version_actual` | **`1.1.0`** | primer release del flujo sin negociación (hoy `1.0.0`) |
| `build_number` | **`2`** | hoy las builds en calle son `build = 1`; `2 > 1` dispara el diálogo |
| `version_minima` | **`1.1.0`** | queda registrado para cuando la app lo use |
| `actualizacion_obligatoria` | **`true`** | es lo que hace el diálogo no cancelable |
| `activa` | **`true`** | `fn_check_update` sólo mira filas activas |

Y en la app, antes de compilar: `pubspec.yaml` → `version: 1.1.0+2` y
`assets/changelog.json` → `"current_version": "1.1.0"`, `"build": 2`, más
`download_url_apk` / `download_url_web` con las URLs reales.

### 4.7 Estado real en producción (verificado el 2026-11-12)

Consultado en **sólo lectura** contra `vsieeihstajlrdvpuooh`:

- `public.app_versiones` **existe con todas las columnas** (incluidas `titulo`,
  `novedades` y `url_descarga`), así que el camino SQL de §4.4 es válido.
- **No existe ninguna fila con `app_name = 'inventtia_muevete'`.** Las apps
  registradas hoy son `inventtia_flow` (build 16), `ventiq_admin` (294),
  `ventiq_app` (852) y `ventiq_marketplace` (14).
- Por tanto el Paso 3 **no es un `UPDATE`: es el primer `INSERT`** de la fila de
  muevete. Hasta que esa fila exista, `fn_check_update` no devuelve nada y
  **ninguna build queda bloqueada**; ese paso es lo único que impide que un
  chofer con la app vieja siga operando contra el flujo nuevo.
- En el proyecto de **pruebas** `app_versiones` está vacía y le faltan las RPC
  `fn_app_version_guardar` / `fn_app_version_eliminar`: allí el panel de
  versiones no puede guardar y hay que usar SQL directo.

---

## 5. Verificación post-despliegue

### 5.1 SQL de comprobación

Ejecutar en producción y anotar en el ticket.

```sql
-- V1 · el flag está encendido y la config es la esperada
select taxi_precio_fijo_activo, comision_pct, recarga_pct,
       limite_deuda_efectivo, precio_minimo_auto, redondeo_cup
  from muevete.configuracion_tarifas where id = 1;
-- esperado: true | 15.00 | 11.00 | 1000 | 1500 | 50

-- V2 · no queda ninguna solicitud abierta colgada del flujo viejo
select estado, count(*) from muevete.solicitudes_transporte
 where estado in ('pendiente','aceptada')
   and created_at < now() - interval '2 hours'
 group by 1;
-- esperado: 0 filas (si hay, ver V7 y el script de expiración)

-- V3 · las RPC responden. OJO con la elección del trayecto:
--       · destino a ~2 km con p_km de ruta 3,3 → km_total 2,037 → 1500 (tarifa fija)
--       · destino a ~170 m → km_total 0,168 → 1000 (válvula `precio_corto`, < 1,5 km)
select muevete.fn_cotizar_viaje(22.40689, -79.96450, 22.40900, -79.96000, 5,
                                now(), 3.3) ->> 'precio_plataforma' as precio_auto;
-- esperado: 1500

-- V4 · los viajes nuevos tienen precio y comisión congelados (no nulos)
select count(*) filter (where precio_plataforma is null) as sin_precio,
       count(*) filter (where comision_pct is null)      as sin_comision,
       count(*) filter (where driver_id is not null
                          and aceptada_at is null)       as aceptada_sin_timestamp,
       count(*)                                          as total
  from muevete.solicitudes_transporte
 where created_at >= now() - interval '2 hours';
-- esperado: 0 en las tres primeras columnas

-- V5 · cada solicitud aceptada tiene exactamente un viaje
select count(*) as solicitudes_con_viaje_duplicado
  from (select solicitud_id from muevete.viajes
         where solicitud_id is not null
         group by 1 having count(*) > 1) d;
-- esperado: 0

-- V6 · wallets del cliente sin duplicados (los rompe el índice de 041)
select count(*) as usuarios_con_wallet_duplicado
  from (select user_id from muevete.suscription_user
         where user_id is not null group by 1 having count(*) > 1) d;
-- esperado: 0

-- V7 · script de expiración de las solicitudes abiertas del cutover
--      (sólo si V2 devolvió filas; deja rastro en motivo_cancelacion)
update muevete.solicitudes_transporte
   set estado = 'expirada',
       cancelada_at = now(),
       motivo_cancelacion = coalesce(motivo_cancelacion, 'expirada_cutover')
 where estado = 'pendiente'
   and created_at < now() - interval '1 hour';

-- V8 · las políticas peligrosas siguen fuera (repetición del paso 4)
select count(*) as politicas_peligrosas
  from pg_policies
 where schemaname='muevete'
   and policyname in ('users_','drivers_see_solicitudes',
                      'solicitudes_insert_client','solicitudes_update_own_client',
                      'viajes_insert_authenticated','wallet_drivers_insert_own',
                      'wallet_drivers_update_own','transacciones_insert_client',
                      'suscription_user_insert_own','suscription_user_update_own',
                      'places_');
-- esperado: 0

-- V9 · realtime con fila completa (para que el cliente vea la asignación)
select relname, relreplident from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname='muevete' and relname in ('solicitudes_transporte','viajes');
-- esperado: 'f' (FULL) en las dos
```

- [ ] V1–V9 con lo esperado, o con una explicación escrita de cada desviación.

### 5.2 Qué mirar en la app (orden de la prueba de humo)

Con **dos dispositivos nuevos** (un cliente, un chofer):

1. **Publicar**: el cliente cotiza origen→destino, ve el desglose
   (`precio_plataforma` grande, comisión, neto del chofer), elige tipo y pago,
   y toca "Solicitar viaje · X CUP". Debe aparecer "Buscando conductor…",
   **no** una pantalla de ofertas ni ningún campo de precio editable.
2. **Ver la lista**: el chofer de la zona ve la tarjeta con "El cliente paga",
   "Comisión plataforma" y "A ti te tocan" (1 500 / 225 / 1 275), la distancia y
   la cuenta atrás del TTL. Si está fuera de zona o con deuda en el tope, la
   tarjeta se ve **atenuada con el motivo**, no desaparece.
3. **Tomar**: el chofer toca "Tomar viaje" → el cliente recibe la asignación en
   ≤ 3 s (realtime) y el chofer entra a la pantalla del viaje activo.
4. **Cerrar**: probar las tres vías.
   - **online**: "Completar viaje" → recibo con el desglose congelado.
   - **offline**: modo avión → completar → sale de la cola al volver la red
     (idempotente).
   - **QR**: el chofer muestra el QR, el cliente escanea → cierre sin red.
5. **Cancelar con reembolso**: cliente paga con wallet → cancela antes de que el
   chofer llegue → el saldo vuelve exacto al valor previo y el historial muestra
   un movimiento `reembolso` positivo.
6. **Chofer con deuda**: completar un viaje en efectivo deja
   `wallet_drivers.balance` en `-225`. Pedir una recarga de 1 000 **crea la
   transacción `pendiente`** con `total_a_pagar = 1110` (1 000 + 11 %) y **no
   mueve el saldo todavía**; el superadmin la aprueba y entonces el balance pasa
   a `775` (−225 + 1 000). Es el flujo correcto: el saldo sólo lo acredita la
   aprobación, nunca la app.

En el `logcat` del dispositivo nuevo, durante la prueba, no debe aparecer
`P0003 servicio_en_mantenimiento`, ni `P0012`/`P0020` fuera de los casos
provocados a propósito.

---

## 6. Rollback

### 6.1 Qué se revierte y qué no

| Acción | ¿Se revierte? | Cómo | Efecto real |
|---|---|---|---|
| `taxi_precio_fijo_activo` a `false` | **Sí, es el rollback barato** | `update ... set taxi_precio_fijo_activo = false where id = 1;` | Las RPC nuevas responden `P0003 servicio_en_mantenimiento`. La app nueva muestra "Servicio en mantenimiento". **El flujo viejo NO vuelve** si `041` ya se aplicó: las escrituras directas siguen revocadas. |
| `041` (RLS) | **No** | — | Revertirla **reabre los agujeros de dinero** (`wallet_drivers_update_own` dejaba al chofer subirse el saldo; `suscription_user_update_own` al cliente acreditarse saldo). Se corrige hacia adelante. |
| `030`–`040` | No hace falta | — | Son aditivas; las apps nuevas dependen de ellas. Dejarlas no rompe nada. |
| Apps publicadas | Sí | volver a publicar la build anterior en el canal | Pero si `041` está aplicada, la build anterior **no puede escribir** en las tablas de dinero/viajes. |
| Versión mínima | Sí | `update public.app_versiones set actualizacion_obligatoria = false, activa = false where ...` | Baja el bloqueo, pero deja al parque en builds que ya no pueden operar si `041` está aplicada. |
| Datos de viajes en curso | — | — | No se tocan: el rollback no borra solicitudes ni viajes. |

**Regla**: `041` es el punto de no retorno del dinero. **Antes** de `041` el
rollback es completo (flag + volver a publicar la build vieja). **Después** de
`041` sólo existe *forward-fix*.

### 6.2 Procedimiento de forward-fix

Si tras `041` algo se rompe:

1. **Contener** (2 min): `update muevete.configuracion_tarifas set
   taxi_precio_fijo_activo = false where id = 1;` → la app nueva muestra
   mantenimiento y nadie crea viajes a medias. No se pierde dinero.
2. **Diagnosticar** (10 min): ¿es una RPC, una política o la app? Consultas útiles:

```sql
-- errores recientes de las RPC (si hay logging de Postgres activo)
select * from postgres_logs order by timestamp desc limit 50;   -- vía dashboard

-- ¿alguna operación choca con RLS?
select tablename, policyname, cmd from pg_policies
 where schemaname='muevete' order by tablename, policyname;
```

3. **Corregir con una migración nueva** (`042_...`), nunca editando `041` ya
   aplicada.
4. **Reencender** el flag y volver a §5.

### 6.3 Checklist de rollback

- [ ] ¿Ya se aplicó `041`? → si **no**, rollback completo: flag a `false` +
      republicar la build anterior + bajar la versión mínima. Fin.
- [ ] ¿Ya se aplicó `041`? → `flag = false` (contención) + forward-fix.
- [ ] Confirmar que ningún viaje quedó en `aceptada` sin salida:

```sql
select id, estado, driver_id, created_at from muevete.solicitudes_transporte
 where estado in ('pendiente','aceptada') and created_at < now() - interval '2 hours';
```

- [ ] Avisar a los choferes por el canal de soporte (qué pasa y qué hacer).
- [ ] Escribir en el ticket: hora, acción, motivo, quién aprobó.
- [ ] No dejar el flag apagado más de lo necesario: cada minuto en
      mantenimiento es demanda perdida.

---

## 7. Riesgos conocidos y mitigación

### 7.1 `solicitudes_push` del proyecto de pruebas apunta a PRODUCCIÓN 🔴

> **Actualización 2026-11-12:** los tres triggers (`solicitudes_push`,
> `ofertas_push`, `notificaciones_push`) quedaron **deshabilitados** en el proyecto
> de pruebas (`ALTER TABLE ... DISABLE TRIGGER`), así que ya no se envían push
> reales al probar. Queda pendiente, para producción, rotar el JWT `service_role`
> que está embebido en sus definiciones (decisión del equipo; ver
> `10-incidente-credenciales.md`).

Verificado en `qhprswhhfasrikhawjoz`:

```sql
select tgname, pg_get_triggerdef(t.oid)
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname='muevete' and t.tgname in
       ('solicitudes_push','ofertas_push','notificaciones_push');
```

Los tres triggers (`solicitudes_push` sobre `muevete.solicitudes_transporte`,
`ofertas_push` sobre `ofertas_chofer`, `notificaciones_push` sobre
`notificaciones`) llaman a
`supabase_functions.http_request('https://vsieeihstajlrdvpuooh.supabase.co/functions/v1/send-push-notification', ...)`
con un **JWT de `service_role` de producción** en la cabecera
`Authorization`.

**Impacto**

- Cualquier `INSERT` en esas tablas **en pruebas** dispara una notificación push
  **real** a usuarios **reales** por la Edge Function de producción. Durante los
  tests de H8 eso significa pushes espurios a clientes/choferes de verdad.
- El token de `service_role` de producción está guardado en la base de pruebas
  (y por tanto en cualquier `pg_dump` de pruebas). Es el mismo token del
  incidente **P0** de [`10-incidente-credenciales.md`](10-incidente-credenciales.md).

**Mitigación**

- [ ] Mientras se hacen pruebas: desactivar los tres triggers en pruebas
      (reversible, no borra nada y no afecta a producción):

```sql
alter table muevete.solicitudes_transporte disable trigger solicitudes_push;
alter table muevete.ofertas_chofer        disable trigger ofertas_push;
alter table muevete.notificaciones        disable trigger notificaciones_push;
```

- [ ] Volver a habilitarlos **sólo** si se está probando el envío de pushes, y
      con un usuario de pruebas como destinatario.
- [ ] Rotar el `service_role` de producción (H0-A) y, al recrear los triggers,
      apuntarlos a la Edge Function del proyecto correcto.
- [ ] Nunca ejecutar los tests de H8 contra producción: insertan filas.

### 7.2 Apps viejas escaneando un QR v2: pierden `precio` del payload 🟠

La build nueva escribe **v2**, que **no lleva precios**:

```json
{"v":2,"solicitud_id":123,"viaje_id":456,"ts":"...Z","hmac":"..."}
```

La build vieja espera **v1** (`sol_id`, `driver_id`, `user_id`, `metodo`,
`precio`, `precio_base`) y **valida el importe contra el `precio` del QR**. Con
un v2:

- la app vieja no encuentra `precio` → rechaza el QR o cierra con importe 0;
- el chofer y el cliente ven "el QR no sirve" y no entienden por qué.

**Impacto**: sólo afecta a combinaciones cruzadas (una build vieja con una
nueva). No hay pérdida de dinero: el cierre siempre lo decide el servidor
(`fn_completar_viaje` no recibe precio), y las vías online/offline siguen
funcionando.

**Mitigación**

- [ ] La versión mínima (§4) es la mitigación real: hay que subirla **antes** de
      `041` y mantener `actualizacion_obligatoria = true` hasta que no queden
      builds viejas.
- [ ] En soporte, guion conocido: "pide al otro que actualice; mientras tanto
      cierra desde la app".
- [ ] El servicio acepta v1 **al leer** (y descarta sus precios), así que los QR
      v1 ya pintados en un teléfono no se invalidan de golpe.

### 7.3 Wallets duplicados: sólo `WARNING`, la migración **no** aborta 🟡

`041` §8 intenta crear `suscription_user_user_id_uidx` (un wallet por usuario).
Si hay duplicados:

```sql
select user_id, count(*) from muevete.suscription_user
 where user_id is not null group by 1 having count(*) > 1;
```

la migración emite
`RAISE WARNING 'suscription_user tiene N usuarios con más de un wallet: NO se crea el índice único...'`
y **termina con `Success`** sin crear el índice. Ese comportamiento es
deliberado: el `COMMENT ON INDEX` está **dentro del `ELSE`**, porque comentar un
índice inexistente lanzaría error y abortaría la migración entera (era el bug
original, ya corregido).

**Impacto**: el endurecimiento de RLS se aplica igual, pero se queda sin la
garantía de unicidad. Con duplicados, `fn_tomar_viaje` apunta a la fila de menor
`id` (determinista), pero el saldo del cliente puede quedar repartido y el
reembolso ir a la fila equivocada.

**Mitigación**

- [ ] Antes de la ventana, consolidar duplicados (a mano, con visto bueno):

```sql
-- 1) ver el desglose
select user_id, array_agg(id order by id) as wallets,
       array_agg(balance order by id) as saldos, sum(balance) as total
  from muevete.suscription_user where user_id is not null
 group by 1 having count(*) > 1;

-- 2) consolidar: sumar en la fila menor y borrar el resto (por id, nunca por user_id)
--    update muevete.suscription_user s set balance = t.total
--      from (select user_id, sum(balance) total from muevete.suscription_user
--             where user_id is not null group by 1) t
--     where s.user_id = t.user_id
--       and s.id = (select min(x.id) from muevete.suscription_user x where x.user_id = t.user_id);
--    delete from muevete.suscription_user s
--     where s.user_id is not null
--       and s.id <> (select min(x.id) from muevete.suscription_user x where x.user_id = s.user_id);
```

- [ ] Reejecutar sólo el bloque 8 (es idempotente) o comprobar al final:

```sql
select indexname from pg_indexes
 where schemaname='muevete' and indexname='suscription_user_user_id_uidx';
-- esperado: 1 fila. Si no está, había duplicados: consolidar y reintentar.
```

- [ ] Leer siempre los `WARNING` de la salida de `041` y anotarlos en el ticket.

### 7.4 Otros riesgos de la ventana

| Riesgo | Señal | Mitigación |
|---|---|---|
| Realtime no llega al cliente y "no aparece el chofer" | el chofer toma y el cliente sigue en "Buscando…" | `041` §9 ya pone `REPLICA IDENTITY FULL` y publica las tablas. Verificar V9 (§5.1). Plan B: la app refresca cada 20 s (contrato §6). |
| `ofertas_chofer` en solo lectura rompe una pantalla vieja | chofer con build vieja ve "Error al ofertar" | Versión mínima antes de `041`. La tabla **no** se borra. |
| Solicitudes abiertas el día del corte quedan huérfanas | V2 con filas | V7 (script de expiración) + verificar retenciones de wallet devueltas. |
| Flag encendido antes de tiempo | `P0003` masivo en logs de la app nueva | El orden del §2 lo evita; si pasa, apagar el flag y revisar el paso. |
| Secreto QR distinto entre cliente y chofer | "el QR no sirve" en todos los casos | §3.5: rotar siempre con versión mínima. |
| `build` del `changelog.json` desincronizado del `pubspec` | el diálogo aparece con la app ya actualizada, o no aparece nunca | Checklist de release: subir los dos números juntos. |
| El panel de versiones no guarda (falta migración 75) | error al pulsar Guardar | Usar el camino SQL del §4.4. |
| Cambio de `comision_pct` a mitad de día | `desvio_pct` ≠ 0 en K06 | Los viajes ya creados tienen su `comision_pct` congelado: el cambio sólo afecta a los nuevos. |

---

## 8. Anexo · Matriz E2E manual (dos dispositivos)

> **Montaje**: dispositivo **C** = app del cliente (build nueva), dispositivo
> **D** = app del chofer (build nueva). Ambos con el **mismo**
> `MUEVETE_QR_SECRET`. Un tercer teléfono **V** opcional con la build vieja.
> Zona de prueba: centro de Santa Clara (Parque Vidal, 22.40689, -79.96450).
> Flag encendido. Salvo que el caso diga lo contrario, el pago es **efectivo**.

| # | Caso | Pasos | Resultado esperado | Cómo se comprueba |
|---|---|---|---|---|
| 1 | **Cotizar** | C: origen en el centro, destino a ~2 km (22.40689,-79.96450 → 22.40900,-79.96000, ruta 3,3 km), tipo Auto | Precio grande = **1 500 CUP**; desglose con comisión 225 y neto chofer 1 275; sin campo de precio editable; sin botón "Ofertar" | En pantalla. SQL: `select muevete.fn_cotizar_viaje(22.40689,-79.96450,22.40900,-79.96000,5,now(),3.3)->>'precio_plataforma';` → `1500`. **Ojo**: un destino a < 1,5 km (p. ej. 22.40750,-79.96300) da **1 000** por la válvula `precio_corto` — es correcto, no es un bug |
| 2 | **Publicar** | C: "Solicitar viaje · 1 500 CUP", pago efectivo | Se crea la solicitud `pendiente`, aparece "Buscando conductor…" | SQL: `select id,estado,driver_id,precio_plataforma,precio_chofer,comision_pct,expires_at from muevete.solicitudes_transporte order by id desc limit 1;` → `pendiente`, `driver_id` null, `1500`, `1275`, `15.00`, `expires_at ≈ now()+15 min` |
| 3 | **Ver en la lista del chofer de la zona** | D (online, en el centro): abrir "Viajes disponibles" | Aparece la tarjeta con "El cliente paga 1 500", "Comisión 225", "A ti te tocan 1 275", distancia y cuenta atrás; botón habilitado | En pantalla. SQL: `select (x->>'puede_tomar')::bool, x->>'motivo_bloqueo' from muevete.fn_viajes_disponibles(22.40689,-79.96450,10) x;` → `true`, null |
| 4 | **Tomar** | D: "Tomar viaje" | D entra al viaje activo; C recibe la asignación en ≤ 3 s con nombre y chapa del chofer | SQL: `select estado,driver_id,aceptada_at from muevete.solicitudes_transporte where id=<id>;` → `aceptada`, driver de D, `aceptada_at` no nulo. `select count(*) from muevete.viajes where solicitud_id=<id>;` → `1` |
| 5 | **Primero gana (dos choferes)** | Con otro chofer **E** en la misma zona: D y E tocan "Tomar" casi a la vez sobre el mismo viaje | Sólo uno entra. El otro ve **"Otro conductor lo tomó primero"** y la lista se refresca | SQL: un solo `viaje` para esa solicitud (§5.1 V5). Cubierto también por `tests/test_concurrencia.sql` (10/10) |
| 6 | **Cerrar online** | D: "Completar viaje" (con red) | Recibo con total 1 500, comisión 225, neto 1 275; el viaje desaparece de activos | SQL: `select estado,completada_at,precio_plataforma from muevete.solicitudes_transporte where id=<id>;` → `completada`. `select balance from muevete.wallet_drivers where driver_id=<D>;` → `-225` (efectivo) |
| 7 | **Cerrar offline** | D: modo avión → "Completar viaje" → volver la red | Cierre aceptado sin red; al reconectar se sincroniza una sola vez (idempotente, sin doble cobro) | SQL: mismo `select` que #6, y `select count(*) from muevete.transacciones_wallet where viaje_id=<id>;` no crece al reintentar |
| 8 | **Cerrar por QR** | D: mostrar QR (pantalla de cierre). C: escanear. **Ambos con el secreto compilado** | Cierre inmediato en los dos teléfonos; total 1 500; sin campo de precio en el QR | SQL: `viaje.completado = true` y solicitud `completada`. Si falta el secreto en el build: D muestra "El cierre por QR no está configurado…" (fail closed) |
| 9 | **Cancelar con reembolso wallet** | C con saldo 2 000: publica pagando con **wallet** → D toma (se retienen 1 500) → C cancela antes del abordaje | Saldo de C vuelve a **2 000**; historial con movimiento `reembolso` +1 500 | SQL: `select balance from muevete.suscription_user where user_id=<C>;` → `2000`. `select tipo,monto from muevete.transacciones_wallet where viaje_id=<id> order by id;` → `cobro_viaje -1500`, `reembolso +1500` |
| 10 | **Fuera de zona** | D con el pin movido a otro municipio (o zona distinta): intenta tomar un viaje del centro | Rechazo **"El viaje está fuera de tu zona"** (`P0022`); la solicitud sigue `pendiente` para otro | SQL: `select estado,driver_id from muevete.solicitudes_transporte where id=<id>;` → sigue `pendiente` / null. En la lista, `puede_tomar=false` con `motivo_bloqueo` |
| 11 | **Sin choferes** | C publica cuando **no hay ningún chofer online** en la zona | "Buscando conductor…" con cuenta atrás; al vencer el TTL (15 min) pasa a `expirada` y no queda huérfana | En pantalla. SQL: `select estado,motivo_cancelacion from muevete.solicitudes_transporte where id=<id>;` → `expirada` / `expirada_ttl`. KPI K05 lo cuenta |
| 12 | **Deuda en el tope** | Llevar el wallet de D a `-1000` (tope). Abrir la lista y tocar "Tomar" | La tarjeta se ve **atenuada** con "Alcanzaste tu límite de deuda. Recarga para seguir" (`P0023`); no puede tomar | SQL: `select balance from muevete.wallet_drivers where driver_id=<D>;` → `-1000`. `fn_viajes_disponibles` → `puede_tomar=false`, `motivo_bloqueo` con el tope. Tras recargar 1 000 (`fn_recargar_wallet`), vuelve a poder |
| 13 | **KYC incompleto** | D sin `kyc_estado='aprobado'` (o sin docs): abrir la lista y tocar "Tomar" | "Tu cuenta aún no está aprobada" (`P0011`) o `P0050 perfil_incompleto_chofer` con los `motivos` marcados en el onboarding. La app **abre el onboarding**, no un error genérico | SQL: `select kyc,kyc_estado from muevete.drivers where id=<D>;`. `select muevete.fn_usuario_habilitado('<uuid D>','chofer');` → `habilitado=false` + `motivos` |
| 14 | **Contacto de emergencia faltante** | Borrar/poner en `revocado` el contacto prioridad 1 de C y de D, y operar | Gate de seguridad: `P0110 sin_contacto_emergencia`; la app abre "Mi seguridad → Contacto de emergencia". **No** se puede publicar ni tomar | SQL: `select count(*) from muevete.contactos_emergencia where user_uuid=<uuid> and prioridad=1 and estado<>'revocado';` → `0`. `select muevete.fn_gate_seguridad('<uuid>', <driver_id>);` → `ok=false` |
| 15 | **App vieja bloqueada** | V (build vieja): abrir la app | A los ~4 s, "Actualización Obligatoria", no cancelable, sin botón "Más tarde" (§4.5) | En pantalla. SQL: la fila de `app_versiones` con `actualizacion_obligatoria=true` y `build_number` > build de V |
| 16 | **Servicio en mantenimiento** | Con el flag en `false`, C intenta publicar | "El servicio está en mantenimiento. Intenta más tarde." (`P0003`), no un error genérico | SQL: `select taxi_precio_fijo_activo from muevete.configuracion_tarifas where id=1;` → `false`. (Sólo antes del paso 5) |

**Criterio de aceptación de la matriz**: los 16 casos con su resultado esperado.
Los casos 1–9 y 11 son bloqueantes del go-live; 10 y 12–14 son bloqueantes de la
semana 1; 15 y 16 son de la ventana de cutover.

---

### Registro de la ventana (rellenar a mano)

| Paso | Hora inicio | Hora fin | Resultado | Quién |
|---|---|---|---|---|
| 0 · congelar | | | | |
| 1 · 030–040 | | | | |
| 2 · publicar apps | | | | |
| 3 · versión mínima | | | | |
| 4 · `041` | | | | |
| 5 · flag `true` | | | | |
| 6 · verificación | | | | |
| 7 · cierre | | | | |