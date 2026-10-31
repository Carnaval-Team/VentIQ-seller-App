-- ════════════════════════════════════════════════════════════════════════════
-- PUBLICAR LA VERSION 1.5.0 DE GORESERVA (inventtia_flow)
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE ES ESTO
--   No es una migración: es la PUBLICACIÓN de una versión en la tabla
--   `public.app_versiones`. A partir de aquí la app avisa a los usuarios de que
--   hay versión nueva, les enseña estas novedades y les da el enlace de descarga.
--
-- ⚠ ANTES DE PEGAR ESTO: EL BUILD TIENE QUE SER MAYOR QUE 15 ⚠
--   La app compara el build que trae instalado con el build de la última versión
--   activa de la tabla. Hoy:
--       · `pubspec.yaml` dice `version: 1.4.0+8`  ->  la app se presenta como build 8
--       · la última fila de la tabla es 1.4.7 build 15
--   Si subes el APK con build 8, la app verá "hay una versión mejor (15)" y te
--   pedirá actualizar... pero el APK del enlace ya es el nuevo: se instalaría el
--   mismo y volvería a avisar. Bucle.
--
--   PASOS CORRECTOS (en este orden):
--     1. En `inventtia_flow/pubspec.yaml`:  version: 1.5.0+16
--        Es lo que la app reporta como versión instalada (`package_info_plus`).
--     2. Recomendado: alinear `assets/changelog.json` a "current_version": "1.5.0"
--        y "build": 16. Ya no decide la versión que se comprueba, pero es el
--        historial que se ve sin conexión: conviene que no se contradiga.
--     3. Compilar y subir el APK (el enlace de descarga no cambia: `apk/goreservas.apk`).
--     4. Pegar este archivo en el SQL Editor de Supabase (como `postgres`, que es
--        lo que usa el editor por defecto: tras la RLS de la 75 nadie más escribe).
--
--   Si compilas otra versión, cambia los valores marcados << AJUSTA >> en el
--   bloque `datos`. Regla: build_number SIEMPRE mayor que 15.
--
-- QUE HACE
--   · Publica la 1.5.0 (build 16) con su titular y sus novedades escritas para el
--     USUARIO FINAL, sin tecnicismos.
--   · Es idempotente: si ya existe esa fila, refresca los textos en vez de
--     duplicarla (y, como no hay INSERT, tampoco se dispara nada).
--
-- SOBRE EL AVISO AUTOMATICO
--   La tabla tiene `trigger_notificar_nueva_version` (AFTER INSERT WHEN activa
--   = true), pero su cuerpo SOLO trata `ventiq_app` y `ventiq_admin`: para
--   `inventtia_flow` registra un NOTICE de "App desconocida" y no crea ninguna
--   notificación. Publicar aquí no molesta a nadie; cada usuario ve el aviso al
--   abrir la app.
--
-- NO SE FUERZA LA ACTUALIZACIÓN
--   `actualizacion_obligatoria = false` y `version_minima = '1.0.0'`: los usuarios
--   ven el aviso con las novedades y actualizan cuando quieran. Para obligarlos,
--   bloque 3.a.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0. Comprobación previa ─────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('public.app_versiones') is null then
    raise exception 'Falta public.app_versiones: aplica antes la migración 75.';
  end if;

  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'app_versiones'
         and column_name in ('titulo','novedades','url_descarga')) <> 3 then
    raise exception 'Faltan las columnas titulo/novedades/url_descarga: aplica antes la migración 75.';
  end if;
end
$pre$;

-- ══ 1. PUBLICAR (inserta si no existe; si ya existe, refresca los textos) ═══
--
-- Los datos van UNA sola vez, en el CTE `datos`. El UPDATE cubre el caso de que
-- la fila ya exista (por ejemplo, creada desde el panel) y el INSERT el caso
-- nuevo. El trigger de avisos es AFTER INSERT: solo actúa en la inserción.
--
-- Los interruptores (obligatoria, versión mínima y fecha de lanzamiento) NO se
-- tocan en el UPDATE: si los cambias desde el panel, se respetan. Lo que SÍ hace
-- el UPDATE es refrescar los textos y el enlace y volver a poner `activa = true`
-- (este archivo es para publicar; si retiras la versión desde el panel y lo
-- vuelves a pegar, se republica).

with datos as (
  select
    'inventtia_flow'::varchar                as app_name,
    '1.5.0'::varchar                         as version_actual,   -- << AJUSTA >>
    16                                       as build_number,     -- << AJUSTA: > 15 >>
    '1.0.0'::varchar                         as version_minima,
    '🎉 Estrena cobros por adelantado, planes a tu medida y novedades'::text as titulo,
    'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/goreservas.apk'::text as url_descarga,
    '[
      {"type":"feature",
       "title":"Cobra antes de la cita, sin complicarte",
       "description":"El pago por adelantado de tus servicios ya tiene su propia pantalla. Ahí pones tu número de Transfermóvil y ves los pagos que tus clientes reportan, listos para confirmarlos con un toque."},

      {"type":"feature",
       "title":"Tu plan, siempre a la vista",
       "description":"En la cabecera de tu panel tienes el acceso a tu suscripción. Cuando estén por acabarse los días se enciende un aviso, para que renueves a tiempo y no se te corte el servicio."},

      {"type":"feature",
       "title":"Planes que se adaptan a lo que tienes",
       "description":"Elige Inicio, Plus o Profesional: cada uno te dice cuántos locales, cuántos servicios por local y cuántas personas incluye. ¿Necesitas algo distinto? Pide un plan a medida y hablas con ventas desde la propia app."},

      {"type":"feature",
       "title":"Te avisamos antes de que te falte espacio",
       "description":"Si llegas al límite de tu plan —locales, servicios o personas—, la app te lo explica claro y te propone subir de plan. Nunca te deja a mitad de camino sin decirte por qué."},

      {"type":"feature",
       "title":"Planes hechos solo para ti",
       "description":"Si llegas a un acuerdo especial, tu plan aparece únicamente en tu cuenta: nadie más lo ve ni puede contratarlo."},

      {"type":"improvement",
       "title":"Ahora pagas tu plan en pesos",
       "description":"El pago se hace siempre en CUP, al cambio del día, con Transfermóvil. Antes de abrir la app del banco ves exactamente cuánto vas a transferir, aunque tu plan esté publicado en dólares."},

      {"type":"improvement",
       "title":"Cada cosa en su sitio",
       "description":"El cobro de tus servicios y el plan de tu negocio estaban mezclados en la misma pantalla. Ahora los cobros tienen su propio cuadro en el inicio y tu plan está en la cabecera: encuentras lo que buscas a la primera."},

      {"type":"feature",
       "title":"Novedades: entérate de todo lo que cambia",
       "description":"Cuando haya una versión nueva te lo decimos y te contamos qué trae, explicado claro. Puedes consultar el historial completo de cambios cuando quieras."},

      {"type":"fix",
       "title":"El aviso de versión nueva ahora sí aparece",
       "description":"Antes la app se creía siempre al día y no te avisaba cuando había una versión mejor. Ya lo detecta de verdad."}
    ]'::jsonb as novedades
),
actualizada as (
  update public.app_versiones v
     set version_actual = d.version_actual,
         titulo         = d.titulo,
         novedades      = d.novedades,
         url_descarga   = d.url_descarga,
         activa         = true
    from datos d
   where v.app_name = d.app_name
     and v.build_number = d.build_number
  returning v.id
)
insert into public.app_versiones (
  app_name, version_actual, version_minima, build_number,
  actualizacion_obligatoria, fecha_lanzamiento, activa,
  titulo, novedades, url_descarga
)
select d.app_name, d.version_actual, d.version_minima, d.build_number,
       false, now(), true,
       d.titulo, d.novedades, d.url_descarga
  from datos d
 where not exists (select 1 from actualizada);

notify pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════════════════════
-- 2. VERIFICACIÓN (ejecutar a mano después)
-- ════════════════════════════════════════════════════════════════════════════
--
-- 2.1 Quedó publicada con su changelog (1 fila, 9 cambios, el enlace del APK).
-- select id, version_actual, build_number, activa, actualizacion_obligatoria,
--        titulo, jsonb_array_length(novedades) as cambios, url_descarga
--   from public.app_versiones
--  where app_name = 'inventtia_flow'
--  order by build_number desc
--  limit 3;
--
-- 2.2 Cómo lo verá un usuario con la app vieja (1.4.0 build 8): hay actualización
--     y le llegan las novedades.
-- select public.fn_check_update('inventtia_flow', '1.4.0', 8);
--
-- 2.3 Cómo lo verá un usuario ya actualizado (1.5.0 build 16): sin actualización.
-- select public.fn_check_update('inventtia_flow', '1.5.0', 16);
--
-- 2.4 El historial que pinta la pantalla de Novedades.
-- select public.fn_app_versiones('inventtia_flow', 5);

-- ════════════════════════════════════════════════════════════════════════════
-- 3. OPCIONES (comentadas)
-- ════════════════════════════════════════════════════════════════════════════
--
-- 3.a FORZAR la actualización de todo el mundo (no podrán usar la app sin
--     instalarla). Con el flag, o subiendo el mínimo por encima de lo instalado:
--
-- update public.app_versiones
--    set actualizacion_obligatoria = true,
--        version_minima = '1.5.0'
--  where app_name = 'inventtia_flow' and build_number = 16;
--
-- 3.b RETIRAR una versión del historial sin borrarla (deja de anunciarse):
--
-- update public.app_versiones set activa = false
--  where app_name = 'inventtia_flow' and build_number = 16;
--
-- 3.c PUBLICAR LA SIGUIENTE: cambia versión y build en el bloque `datos`, sube
--     `pubspec.yaml` a la misma versión ANTES de compilar y vuelve a pegar el
--     archivo (el UPDATE no toca los flags que hayas puesto en el panel).

-- ════════════════════════════════════════════════════════════════════════════
-- 4. REVERSIÓN (comentada)
-- ════════════════════════════════════════════════════════════════════════════
--
-- delete from public.app_versiones
--  where app_name = 'inventtia_flow' and build_number = 16;
--
-- notify pgrst, 'reload schema';
