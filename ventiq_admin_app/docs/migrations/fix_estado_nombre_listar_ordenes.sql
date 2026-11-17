-- ============================================================================
-- fix_estado_nombre_listar_ordenes.sql
--
-- El nombre de estado de las órdenes se resolvía con un CASE hardcodeado
-- (1 Pendiente / 2 Completada / 3 Cancelada / 4 'En Proceso'), que:
--   a) mapeaba 4 como 'En Proceso' cuando en app_nom_estado_operacion el id=4
--      es 'Cancelada' (la op 101 de newa salía como "En Proceso" estando
--      cancelada);
--   b) devolvía 'Desconocido' para cualquier código fuera de 1-4 (Anulada,
--      Facturada, Por Despachar, devoluciones, garantías...).
--
-- Este script recorre las funciones public afectadas y las recrea con su
-- misma firma:
--   * con CASE viejo        -> CASE por COALESCE + JOIN a la nomenclatura
--   * ya parcheadas sin cast -> añade ::text a es.denominacion (varchar no
--     coincide con la columna OUT `estado_nombre text`, 42804)
--
-- Cubre las dos formas de join al estado vistas en el repo:
--   LEFT JOIN app_dat_estado_operacion e ON e.id_operacion = o.id AND e.id=(...)
--   LEFT JOIN LATERAL ( ... ) e ON TRUE
-- ============================================================================

DO $$
DECLARE
    fn    RECORD;
    v_def TEXT;
    v_new TEXT;
BEGIN
    FOR fn IN
        SELECT p.oid::regprocedure::text AS firma
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND (
                 p.prosrc LIKE '%WHEN e.estado = 4 THEN%'
              OR (p.prosrc LIKE '%es.denominacion%'
                  AND p.prosrc NOT LIKE '%es.denominacion::text%')
           )
    LOOP
        v_def := pg_get_functiondef(fn.firma::regprocedure);
        v_new := v_def;

        -- A) Función ya parcheada pero sin el cast a text -> solo añadir ::text
        IF v_new LIKE '%es.denominacion%'
           AND v_new NOT LIKE '%WHEN e.estado = 4 THEN%' THEN
            v_new := replace(
                v_new,
                'es.denominacion',
                'es.denominacion::text'
            );

        -- B) CASE viejo -> denominación real (casteada) + JOIN a la nomenclatura
        ELSE
            v_new := regexp_replace(
                v_new,
                'CASE\s+WHEN e\.estado = 1 THEN ''Pendiente''\s+WHEN e\.estado = 2 THEN ''Completada''\s+WHEN e\.estado = 3 THEN ''Cancelada''\s+WHEN e\.estado = 4 THEN ''En Proceso''\s+ELSE ''Desconocido''\s+END(\s+AS)?\s+estado_nombre',
                'COALESCE(es.denominacion::text, ''Desconocido'') AS estado_nombre'
            );

            IF v_new = v_def THEN
                RAISE NOTICE 'CASE no encontrado en %, se omite', fn.firma;
                CONTINUE;
            END IF;

            IF position(') e ON TRUE' IN v_new) > 0 THEN
                -- Variante LATERAL (versiones optimizadas)
                v_new := replace(
                    v_new,
                    ') e ON TRUE',
                    E') e ON TRUE\n        LEFT JOIN app_nom_estado_operacion es ON e.estado = es.id'
                );
            ELSE
                -- Variante join plano (listar_ordenes y similares)
                v_new := regexp_replace(
                    v_new,
                    '(app_dat_estado_operacion e ON e\.id_operacion = o\.id AND e\.id = \(\s*SELECT MAX\(id\) FROM app_dat_estado_operacion er WHERE er\.id_operacion = o\.id\s*\))',
                    E'\\1\n        LEFT JOIN app_nom_estado_operacion es ON e.estado = es.id'
                );
            END IF;
        END IF;

        EXECUTE v_new;
        RAISE NOTICE 'Función parcheada: %', fn.firma;
    END LOOP;
END
$$;

NOTIFY pgrst, 'reload schema';
