-- =============================================================================
-- Verificacion del Go Live de tienda (SOLO LECTURA).
--
-- ESTADO: pensado para newa. Se puede correr en main igual, no escribe nada.
--
-- Se ejecuta DESPUES de `sql_updates/fn_m01_activar_tienda.sql` para comprobar
-- que la RPC quedo bien desplegada y que la columna geografica `estado` sigue
-- intacta. No sustituye a las pruebas transaccionales de la RPC: esas SI
-- escriben y van al final del archivo, comentadas, en bloques BEGIN ... ROLLBACK
-- que se pegan uno a uno cuando se quiere reproducir el resultado.
--
-- Que comprueba, en este orden:
--   1. La funcion existe con la firma, DEFINER y search_path esperados.
--   2. Los permisos de ejecucion: authenticated/service_role si, anon no.
--   3. Que el cuerpo apunta a `estado_onboarding` y NO a `estado` geografico.
--      Esto se mira en el texto de la funcion porque es el error que hunde la
--      base: un UPDATE a `estado` pisa el codigo de provincia de todas las
--      tiendas y no lo detecta ningun test funcional.
--   4. Que las columnas y tablas que consulta la RPC existen (si alguien
--      renombra `deleted_at`, el gate se rompe en silencio).
--   5. Estado actual de las tiendas: reparto por estado_onboarding, tiendas
--      activas sin fecha (fallo) y la columna `estado` geografica.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. La funcion: firma, DEFINER y search_path
-- -----------------------------------------------------------------------------
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       pg_get_function_result(p.oid) AS devuelve,
       p.prosecdef AS security_definer,
       p.provolatile,
       p.proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_m01_activar_tienda';

-- Esperado: 1 fila.
--   argumentos      p_id_tienda bigint
--   devuelve        jsonb
--   security_definer   true
--   provolatile     v (VOLATILE: hace un UPDATE)
--   proconfig       {"search_path=pg_catalog, public"}

-- -----------------------------------------------------------------------------
-- 2. Permisos de ejecucion
-- -----------------------------------------------------------------------------
SELECT r.rolname AS rol,
       has_function_privilege(r.oid, 'public.fn_m01_activar_tienda(bigint)', 'EXECUTE') AS puede_ejecutar
FROM pg_roles r
WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
ORDER BY r.rolname;

-- Esperado:
--   anon           false   <- el REVOKE ALL ... FROM PUBLIC, anon
--   authenticated  true
--   service_role   true

-- -----------------------------------------------------------------------------
-- 3. El cuerpo escribe `estado_onboarding` y NO `estado`
-- -----------------------------------------------------------------------------
-- 3a. Debe contener el UPDATE correcto. Esperado: true.
SELECT pg_get_functiondef('public.fn_m01_activar_tienda(bigint)'::regprocedure)
       LIKE '%SET estado_onboarding = ''activa''%' AS actualiza_estado_onboarding;

-- 3b. NO debe tocar la columna geografica. Se busca un SET sobre `estado` que
--     no sea `estado_onboarding`. Esperado: false. Si sale true, PARAR: el
--     siguiente Go Live borra la provincia de la tienda.
--
--     Se usa una clase de caracteres `[[:space:]]` en vez de `\s` a proposito:
--     en un E-string de Postgres, un `\s` se queda en `s`, con lo que el patron
--     acabaria buscando "SETs+estados*=" y NO casaria nunca. Una comprobacion
--     que no puede casar es peor que no tenerla: da un falso verde. Por eso 3d
--     comprueba que el patron casaria de verdad si el error existiera.
SELECT pg_get_functiondef('public.fn_m01_activar_tienda(bigint)'::regprocedure)
       ~ 'SET[[:space:]]+estado[[:space:]]*=' AS escribe_estado_geografico;

-- 3c. La firma no expone ningun parametro de estado: el cliente no puede pedir
--     "activa con otro nombre". Esperado: 0 filas.
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS argumentos
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_m01_activar_tienda'
  AND pg_get_function_identity_arguments(p.oid) <> 'p_id_tienda bigint';

-- 3d. Autotest del patron de 3b: debe casar el error y NO casar lo correcto.
--     Esperado: debe_ser_true = true, debe_ser_false = false. Si esto falla, el
--     falso verde de 3b no significa nada y hay que reescribir el patron.
SELECT ('SET estado = ''activa'''::text
        ~ 'SET[[:space:]]+estado[[:space:]]*=')            AS debe_ser_true,
       ('SET estado_onboarding = ''activa'''::text
        ~ 'SET[[:space:]]+estado[[:space:]]*=')            AS debe_ser_false;

-- -----------------------------------------------------------------------------
-- 4. Dependencias del gate: columnas y tablas que la RPC consulta
-- -----------------------------------------------------------------------------
-- Si esta consulta devuelve alguna fila con existe = false, la RPC fallara en
-- tiempo de ejecucion (no en el CREATE: plpgsql no valida el cuerpo hasta que
-- se llama, asi que el error apareceria en el primer Go Live real).
SELECT esperado.tabla, esperado.columna,
       (c.column_name IS NOT NULL) AS existe
FROM (VALUES
        ('app_dat_tienda', 'estado_onboarding'),
        ('app_dat_tienda', 'activada_en'),
        ('app_dat_tienda', 'tipo_negocio'),
        ('app_dat_almacen', 'deleted_at'),
        ('app_dat_almacen', 'id_tienda'),
        ('app_dat_producto', 'id_tienda'),
        ('app_dat_producto', 'deleted_at'),
        ('app_dat_vendedor', 'id_tpv'),
        ('app_dat_tpv', 'id_tienda'),
        ('app_dat_layout_almacen', 'id_almacen'),
        ('app_dat_trabajadores', 'deleted_at'),
        ('app_dat_cocina', 'deleted_at'),
        ('app_dat_mesas', 'id_tienda'),
        ('app_dat_configuracion_tienda', 'modo_restaurante'),
        ('app_dat_configuracion_tienda', 'cocina_activa')
     ) AS esperado(tabla, columna)
LEFT JOIN information_schema.columns c
       ON c.table_schema = 'public'
      AND c.table_name = esperado.tabla
      AND c.column_name = esperado.columna
ORDER BY esperado.tabla, esperado.columna;

-- Esperado: 15 filas, todas con existe = true.

-- 4b. Las funciones de permiso que usa existen (no se crean aqui).
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS argumentos
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_user_is_dueno')
ORDER BY p.proname;

-- Esperado: fn_user_is_dueno(p_id_tienda bigint).

-- -----------------------------------------------------------------------------
-- 5. Estado actual de las tiendas
-- -----------------------------------------------------------------------------
-- 5a. Reparto por estado de onboarding.
SELECT estado_onboarding, count(*) AS tiendas,
       count(activada_en) AS con_fecha_de_activacion
FROM public.app_dat_tienda
GROUP BY estado_onboarding
ORDER BY estado_onboarding;

-- 5b. Coherencia: una tienda 'activa' sin fecha es un fallo (la RPC y el
--     backfill de la fase 1 la rellenan). Esperado: 0 filas.
SELECT id, denominacion, estado_onboarding, activada_en
FROM public.app_dat_tienda
WHERE estado_onboarding = 'activa'
  AND activada_en IS NULL
ORDER BY id;

-- 5c. LA COMPROBACION CLAVE: la columna geografica `estado` sigue guardando
--     codigos de provincia, no estados de onboarding. Si aqui aparece
--     'borrador', 'activa' o 'suspendida', alguien escribio en la columna
--     equivocada y hay que restaurar los valores desde un backup.
SELECT id, denominacion, estado AS codigo_provincia, estado_onboarding
FROM public.app_dat_tienda
ORDER BY id;

-- Esperado: codigo_provincia con valores tipo '02', '04', '16' (o NULL en una
-- tienda que aun no lo declaro), y NUNCA 'borrador'/'activa'/'suspendida'.

-- 5d. Cuantas tiendas cumplen ya los 4 esenciales. Es el mismo conteo que hace
--     la RPC, repetido aqui para poder auditar sin llamarla (llamarla activa).
SELECT t.id, t.denominacion, t.estado_onboarding,
       (SELECT count(*) FROM public.app_dat_almacen a
         WHERE a.id_tienda = t.id AND a.deleted_at IS NULL) > 0 AS tiene_almacen,
       (SELECT count(*) FROM public.app_dat_tpv tp
         WHERE tp.id_tienda = t.id) > 0 AS tiene_tpv,
       (SELECT count(*) FROM public.app_dat_producto pr
         WHERE pr.id_tienda = t.id AND pr.deleted_at IS NULL) > 0 AS tiene_producto,
       (SELECT count(*) FROM public.app_dat_vendedor v
          JOIN public.app_dat_tpv tp ON tp.id = v.id_tpv
         WHERE tp.id_tienda = t.id) > 0 AS tiene_vendedor_en_caja
FROM public.app_dat_tienda t
ORDER BY t.id;

-- Esperado: las tiendas que hoy estan 'activa' pueden perfectamente NO cumplir
-- los 4 esenciales: el backfill de la fase 1 las marco activas sin pasar por
-- el gate, a proposito, para no romper las tiendas que ya operaban. Esta tabla
-- sirve para decidir a mano si alguna merece un aviso.

-- -----------------------------------------------------------------------------
-- 6. Prueba funcional (comentada: este script no escribe)
-- -----------------------------------------------------------------------------
-- Los bloques de abajo se pegan uno a uno en el SQL Editor. Todos acaban en
-- ROLLBACK, asi que dejan la base como estaba. Sustituye los uuid por duenos
-- reales (`SELECT uuid, id_tienda FROM app_dat_dueno;`).
--
-- 6a. Un usuario que NO es dueno de la tienda debe recibir 42501.
--     BEGIN;
--     SET LOCAL ROLE authenticated;
--     SELECT set_config('request.jwt.claims',
--       '{"sub":"<uuid_dueno_de_OTRA_tienda>","role":"authenticated"}', true);
--     SELECT public.fn_m01_activar_tienda(<id_tienda_ajena>);
--     ROLLBACK;
--     Esperado: ERROR 42501 Solo un Dueno o un superadmin ...
--
-- 6b. El dueno de una tienda incompleta debe recibir 22023 nombrando lo que
--     falta, y la tienda debe seguir como estaba.
--     BEGIN;
--     UPDATE public.app_dat_tienda SET estado_onboarding='borrador', activada_en=NULL
--      WHERE id = <id_tienda_a_probar>;
--     SET LOCAL ROLE authenticated;
--     SELECT set_config('request.jwt.claims',
--       '{"sub":"<uuid_dueno>","role":"authenticated"}', true);
--     SELECT public.fn_m01_activar_tienda(<id_tienda_a_probar>);
--     ROLLBACK;
--     Esperado: ERROR 22023 con el motivo concreto (p.ej. "falta un vendedor
--     asignado a la caja ...") y DETAIL "esenciales_faltantes: cobro".
--
-- 6c. El dueno de una tienda completa debe activarla, y llamar dos veces no
--     puede mover `activada_en`.
--     BEGIN;
--     UPDATE public.app_dat_tienda SET estado_onboarding='borrador', activada_en=NULL
--      WHERE id = <id_tienda_completa>;
--     SET LOCAL ROLE authenticated;
--     SELECT set_config('request.jwt.claims',
--       '{"sub":"<uuid_dueno>","role":"authenticated"}', true);
--     SELECT public.fn_m01_activar_tienda(<id_tienda_completa>);  -- success true
--     SELECT public.fn_m01_activar_tienda(<id_tienda_completa>);  -- idempotente
--     RESET ROLE;
--     SELECT estado AS provincia, estado_onboarding, activada_en
--       FROM public.app_dat_tienda WHERE id = <id_tienda_completa>;
--     ROLLBACK;
--     Esperado: estado_onboarding='activa', activada_en no nulo y sin cambiar
--     entre las dos llamadas, y `estado` (provincia) con su valor original.
