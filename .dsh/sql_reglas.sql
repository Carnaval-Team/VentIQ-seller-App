select
  (select count(*) from flow.app_dat_servicios) as servicios,
  (select count(*) from flow.app_dat_servicios
     where jsonb_array_length(coalesce(config_precio->'reglas', '[]'::jsonb)) > 0) as con_reglas,
  (select count(*) from flow.app_dat_servicios
     where coalesce(config_precio, '{}'::jsonb) <> '{}'::jsonb) as con_config,
  (select count(*) from flow.turno) as turnos,
  (select count(*) from flow.recurso) as recursos;