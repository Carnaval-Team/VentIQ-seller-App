-- ============================================================================
-- MIGRACION: datos adicionales configurables + permitir terceros, por servicio.
--
-- app_dat_servicios.campos_adicionales: lista ORDENADA de campos que el cliente
--   debe llenar al reservar/entrar a la cola de ese servicio. Cada campo:
--     {
--       "clave":     "codigo_pais",        -- slug unico dentro del servicio
--       "etiqueta":  "Código de país",     -- texto visible
--       "tipo":      "numero",             -- 'texto' | 'numero' | 'select'
--       "requerido": true,
--       "opciones":  [],                   -- solo para 'select'
--       "min":       2,                    -- opcional (numero/texto: longitud/valor)
--       "max":       2
--     }
--
-- app_dat_servicios.permite_tercero: si true, el cliente puede reservar a nombre
--   de otra persona (no usuaria del sistema); se le piden los datos de perfil.
-- ============================================================================

alter table flow.app_dat_servicios
  add column if not exists campos_adicionales jsonb   not null default '[]'::jsonb,
  add column if not exists permite_tercero    boolean not null default false;

comment on column flow.app_dat_servicios.campos_adicionales is
  'Lista ordenada de campos extra (jsonb) que el cliente llena al reservar.';
comment on column flow.app_dat_servicios.permite_tercero is
  'Si true, se puede reservar a nombre de un tercero (no usuario del sistema).';
