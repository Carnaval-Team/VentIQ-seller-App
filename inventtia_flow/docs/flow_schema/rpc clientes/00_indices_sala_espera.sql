-- ============================================================================
-- INDICES de apoyo para las RPC de sala_espera (entrar / salir)
-- Ejecutar UNA sola vez.
-- ============================================================================

-- Acelera MAX(numero_cola) por servicio y el UPDATE de reordenamiento al salir.
create index if not exists idx_sala_espera_ls_numero
  on flow.sala_espera (id_local_servicio, numero_cola);

-- Acelera la comprobacion "este usuario ya esta en la cola de este servicio".
create index if not exists idx_sala_espera_ls_usuario
  on flow.sala_espera (id_local_servicio, uuid_usuario);
