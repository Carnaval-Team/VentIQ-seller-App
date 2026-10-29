-- ============================================================================
-- APLICAR EN RELEASE - MIGRACIONES 68, 69 Y 70, EN ESTE ORDEN
--
-- Pegar TODO este archivo de una vez en el SQL Editor y ejecutar.
-- Es idempotente: se puede volver a ejecutar sin duplicar nada.
--
-- QUE INCLUYE
--   68_anular_pago_al_cancelar.sql       P0: al cancelar se anulan los pagos vivos
--                                        + verificacion / reporte endurecidos
--   69_cobro_disponible_en_agendas.sql   campo `cobro_disponible` en las agendas
--   70_realtime_cobro.sql                publicacion en supabase_realtime
--                                        + replica identity full en reserva_pago
--
-- ORDEN: 68 -> 69 -> 70. Son independientes entre si, pero la 68 es el arreglo del
-- P0 y va primero: si algo hubiera que parar, se para sabiendo que el P0 ya quedo
-- cerrado.
--
-- NO INCLUYE (a proposito)
--   `fix_datos_pagos_reserva_canceladas.sql`: es un script de DATOS de un solo uso.
--   Se revisa su SELECT de diagnostico y se ejecuta A MANO despues de este bundle
--   (ver su cabecera; el resultado esperado es reserva_pago.id = 7 -> 'anulado').
--
-- ANTES DE APLICAR
--   * Revisar el diagnostico del P0 (seccion 6 de la 68): hoy debe devolver
--     reserva_pago.id = 7 sobre agenda.id = 302 (Cancelado).
--   * Nada de este bundle se ha ejecutado sobre la base todavia.
-- ============================================================================

-- #################### INICIO: 68_anular_pago_al_cancelar.sql ####################

-- ============================================================================
-- MIGRACION 68: cerrar el pago cuando la reserva se cancela (P0) + endurecer
--               reporte, verificacion y rechazo
--
-- QUE ARREGLA (P0)
--   Una reserva cancelada puede quedarse con un intento de pago VIVO
--   (`flow.reserva_pago.estado` en 'creado' o 'reportado'). Hoy nada los cierra,
--   y de ahi salen dos agujeros reales:
--
--     1. El admin puede VERIFICAR ese pago y dejar la reserva "confirmada y
--        pagada" aunque la reserva este muerta (turno ya liberado y al cliente
--        ya se le aviso de la cancelacion). `admin_verificar_pago_reserva`
--        valida el estado del PAGO, pero nunca mira el estado de la RESERVA.
--     2. El cliente puede pulsar "Ya he pagado" sobre una reserva cancelada:
--        el intento pasa a 'reportado' y se avisa al admin de un cobro que ya
--        no existe. El chip "Pago pendiente" se queda pegado a la reserva.
--
--   Caso vivo que lo demuestra (bloque 6, consulta de diagnostico):
--     reserva_pago.id = 7  -> estado 'creado', creado 2026-10-29 10:44:12
--     agenda.id      = 302 -> id_estado = 2 ('Cancelado'), cancelada 10:46:02,
--                             pago_estado = 'pendiente'
--   O sea: el cliente creo el intento con la reserva AUN activa y el staff
--   cancelo dos minutos despues; nadie cerro el pago. `reserva_pago_expirar` lo
--   cerraria recien al vencer su plazo (2026-10-30 10:44), asi que hasta entonces
--   el admin puede verificarlo: ese es el agujero.
--   Los otros 6 intentos que existen sobre reservas canceladas ya estan
--   cerrados (1, 2 y 3 'rechazado'; 4 y 5 'expirado'; 6 'verificado'): el unico
--   que sigue vivo es el 7. Ese dato lo arregla el script de datos
--   `fix_datos_pagos_reserva_canceladas.sql`, que NO va en esta migracion.
--
-- QUE HACE
--   1. Trigger `flow.trg_agenda_anular_pago` (BEFORE UPDATE OF id_estado en
--      `flow.agenda`): cuando la reserva pasa a `Cancelado`, los intentos vivos
--      de ESA reserva pasan a `estado = 'anulado'` y el chip de la reserva deja
--      de decir "pendiente".
--
--      Va en un trigger, y no parcheando cada funcion, por lo mismo que la 66:
--      las vias de cancelacion son cinco y todas terminan en el mismo
--      `update flow.agenda ... set id_estado = ...`. Comprobado con
--      `pg_get_functiondef` sobre la base desplegada:
--        * flow.cliente_cancelar_reserva
--        * flow.staff_cancelar_reserva        (delega en staff_marcar_estado_agenda)
--        * flow.staff_marcar_estado_agenda    (incluye el "regreso" del viaje)
--        * flow.admin_cancelar_agenda
--        * flow.reserva_pago_expirar          (cancelacion automatica del pago)
--      Un trigger cubre las cinco (y cualquier camino futuro, incluido un
--      `update` directo del cliente por PostgREST, que la RLS permite en sus
--      propias reservas con `agenda_update_own`).
--
--   2. `flow.admin_verificar_pago_reserva`: re-resuelve la reserva y la exige
--      ACTIVA. Nada mas: la guarda de estados se queda como esta hoy (el admin
--      puede verificar un intento 'creado' o 'reportado', sin cambios).
--   3. `flow.cliente_reportar_pago_reserva`: exige reserva activa y que el
--      cobro siga habilitado (servicio.cobro_adelantado AND cobro_config.activo).
--   4. `flow.admin_rechazar_pago_reserva`: NO SE TOCA. Es la via de escape y ya
--      funciona con la reserva cancelada porque no mira su estado; se reproduce
--      su cuerpo desplegado tal cual para que conste que no se le anade nada.
--
-- DELTAS (objetivo: "cuerpo desplegado + solo el endurecimiento del P0")
--   * (a) trigger `trg_agenda_anular_pago` + su funcion: TODO NUEVO.
--   * (b) admin_verificar_pago_reserva: al cuerpo desplegado se le agregan 2
--     declaraciones (v_agenda, v_activa), el `select ... for update` de la agenda
--     y el bloque "La reserva ya no esta activa...". La guarda de estados y todo
--     lo demas queda igual.
--   * (c) cliente_reportar_pago_reserva: al cuerpo desplegado se le agregan 4
--     declaraciones (v_agenda, v_activa, v_cobra_servicio, v_cobra_entidad), el
--     `select ... for update` de la agenda y los bloques "La reserva ya no esta
--     activa..." y "El pago por adelantado ya no esta disponible...". Sus guardas
--     originales (estado y plazo) quedan igual, antes de las nuevas.
--   * (d) admin_rechazar_pago_reserva: DELTA CERO (cuerpo identico al desplegado).
--
-- DECISIONES (y por que)
--   A) `agenda.pago_estado` NO admite 'anulado'. El CHECK real
--      (`agenda_pago_estado_chk`, verificado en pg_constraint sobre la base
--      desplegada) solo permite 'pendiente', 'reportado', 'verificado',
--      'rechazado' y 'expirado'. No se amplia el CHECK desde aqui: el valor
--      nuevo obligaria a tocar el vocabulario de la app (`EstadoPago`) y no hace
--      falta para arreglar el P0. El trigger mapea el chip asi:
--        * 'pendiente' | 'reportado' -> 'expirado'   (unico valor permitido que
--          significa "cerrado sin verificar"; en la app se pinta gris como
--          "Pago expirado" y no invita a pagar)
--        * 'verificado'  -> se deja: el dinero SI se cobro; la reserva se
--          cancela igual y el reembolso es una decision del negocio
--        * 'rechazado'   -> se deja: ya es terminal
--        * null          -> se deja: la reserva no pedia pago por adelantado
--      `pago_id`, `pago_monto` y `pago_moneda` se dejan intactos: son el rastro
--      de lo que se llego a intentar cobrar (el detalle auditable esta en
--      `flow.reserva_pago`).
--   B) Quien dice "la reserva esta activa" es `id_estado = <Reservado>`, igual
--      que hacen las funciones desplegadas. Se resuelve por NOMBRE
--      (`flow.nom_estado_agenda where nombre = 'Reservado'`) y no por id fijo.
--      El WHEN del trigger necesariamente usa un literal (no puede consultar
--      tablas): usa 2 = 'Cancelado', el mismo literal que ya usa la migracion 61
--      (`p_id_estado = 2`). Si el seed de `nom_estado_agenda` cambiara, hay que
--      tocar ese WHEN; el cuerpo del trigger vuelve a resolver el nombre.
--   C) Se cierran los intentos ANTES de seguir: el trigger es BEFORE, asi que la
--      anulacion ocurre en la MISMA transaccion que la cancelacion. Si algo
--      fallara al cerrar el pago, falla la cancelacion entera (no se queda a
--      medias). Es una tabla pequena con indice `idx_reserva_pago_agenda`.
--   D) Cerrojos en (b) y (c): se bloquea la fila de AGENDA (`for update`) antes
--      de comprobar y se mantiene hasta el UPDATE de esa misma fila; asi una
--      cancelacion concurrente no puede colarse entre el chequeo y la escritura.
--      Es el mismo orden que usa la cancelacion (UPDATE de agenda y, dentro del
--      trigger, UPDATE de reserva_pago). `reserva_pago_expirar` bloquea al reves
--      (pago -> agenda): si un intento esta venciendo justo mientras el admin
--      verifica, Postgres puede detectar un deadlock (40P01) y abortar una de las
--      dos transacciones; ambas son reintentables y no dejan estado raro.
--      (d) NO lleva cerrojo: no se modifica en absoluto.
--
-- LO QUE NO CAMBIA
--   * Firmas, tipos de retorno y defaults de las RPC: identicos.
--   * Contrato jsonb: `{ok:true,data:...}` / `{ok:false,error:'...'}`.
--   * Las guardas de estados/plazos desplegadas en (b) y (c): mismo texto, mismo
--     orden relativo. En (b) se puede seguir verificando un intento 'creado' y
--     uno 'reportado'; en (c) se sigue pudiendo reportar 'creado'/'reportado'.
--   * Las notificaciones de "Pago verificado" / "Pago rechazado" y el aviso al
--     admin de "Pago reportado": mismo texto, mismos datos.
--   * `reserva_pago_expirar`, `cliente_crear_pago_reserva`, `cliente_pago_reserva`,
--     `admin_listar_pagos_reserva` y `admin_rechazar_pago_reserva`: no se tocan.
--   * La cancelacion no se toca: el trigger es aditivo.
--
-- EFECTO EN LA APP (para quien toque Dart; esta migracion no cambia Dart)
--   * Un intento pasa a 'anulado' y el modelo ya lo conoce
--     (`PagoReserva.etiquetaEstado` -> "Anulado"), pero la bandeja del admin
--     reparte por estado en 4 pestanas (creado/reportado, verificado, rechazado,
--     expirado): las filas 'anulado' no salen en ninguna, o sea que
--     DESAPARECEN de la bandeja. Es el efecto buscado (ya no hay nada que
--     verificar), pero si el negocio quiere verlas hace falta una pestana
--     "Anulados" en Dart.
--   * `agenda.pago_estado` pasa a 'expirado' y el chip gris dice "Pago
--     expirado" en la reserva cancelada (antes decia "Pago pendiente"). Es el
--     unico valor permitido que no invita a pagar (ver DECISIONES A).
--   * El boton "Verificar" de la bandeja NO cambia de comportamiento: los
--     intentos 'creado' de reservas activas se siguen pudiendo verificar. Lo
--     unico que pasa a fallar es verificar el pago de una reserva que ya no esta
--     activa, que es el P0.
--
-- ORDEN DE APLICACION
--   1) esta migracion (o el bundle `_APLICAR_RELEASE_68.sql`),
--   2) `69_cobro_disponible_en_agendas.sql` (independiente),
--   3) `70_realtime_cobro.sql` (independiente),
--   4) `fix_datos_pagos_reserva_canceladas.sql` (datos, un solo uso; se revisa
--      su SELECT de diagnostico ANTES de ejecutarlo).
--
-- REVERSION
--   Al reaplicar los cuerpos de la migracion 62 vuelven las versiones viejas;
--   para quitar el trigger:
--     drop trigger if exists trg_agenda_anular_pago on flow.agenda;
--     drop function if exists flow.trg_agenda_anular_pago();
--   (Los intentos que el trigger ya marco 'anulado' no se revierten solos.)
--
-- IDEMPOTENTE: drop trigger if exists + create or replace + revoke/grant.
-- ============================================================================

-- ══ 1. TRIGGER: AL CANCELAR, ANULAR LOS PAGOS VIVOS DE ESA RESERVA ═════════

create or replace function flow.trg_agenda_anular_pago()
returns trigger
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_cancelado integer;
begin
  -- Se resuelve el id de 'Cancelado' por nombre para no depender del seed. En
  -- el caso normal el WHEN del trigger ya filtro; esto es la red de seguridad.
  select id into v_cancelado
  from flow.nom_estado_agenda
  where nombre = 'Cancelado'
  limit 1;

  if v_cancelado is null or new.id_estado is distinct from v_cancelado then
    return new;
  end if;

  -- Solo interesa la TRANSICION (reactivar una cancelada no cierra nada).
  if old.id_estado is not distinct from new.id_estado then
    return new;
  end if;

  -- [68] Cerrar los intentos vivos de esta reserva. 'anulado' es un estado
  -- permitido por `reserva_pago_estado_chk` (migracion 62) y el modelo de la app
  -- ya lo contempla (`PagoReserva.etiquetaEstado` -> "Anulado").
  update flow.reserva_pago
     set estado = 'anulado'
   where id_agenda = new.id
     and estado in ('creado', 'reportado');

  -- [68] Alinear el chip denormalizado de la agenda. 'anulado' no esta
  -- permitido en `agenda_pago_estado_chk`, asi que "cerrado sin verificar" se
  -- expresa con 'expirado' (ver DECISIONES A). Si el pago ya estaba verificado o
  -- rechazado, se respeta: eso es historia, no un pago en curso.
  if new.pago_estado in ('pendiente', 'reportado') then
    new.pago_estado := 'expirado';
  end if;

  return new;
end;
$function$;

comment on function flow.trg_agenda_anular_pago() is
  'Al pasar una reserva a Cancelado, anula sus intentos de pago vivos (creado/reportado) y cierra el chip pago_estado. Cubre las cinco vias de cancelacion porque todas hacen update flow.agenda.';

drop trigger if exists trg_agenda_anular_pago on flow.agenda;

create trigger trg_agenda_anular_pago
  before update of id_estado on flow.agenda
  for each row
  when (new.id_estado = 2 and old.id_estado is distinct from 2)
  execute function flow.trg_agenda_anular_pago();

-- ══ 2. ADMIN: VERIFICAR UN PAGO SOLO SI LA RESERVA SIGUE ACTIVA ════════════

create or replace function flow.admin_verificar_pago_reserva(
  p_id_pago       bigint,
  p_observaciones text default null
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_uid         uuid := auth.uid();
  v_pago        flow.reserva_pago%rowtype;
  v_agenda      flow.agenda%rowtype;
  v_activa      integer;
  v_serv        text;
  v_local       text;
begin
  select * into v_pago from flow.reserva_pago where id = p_id_pago;
  if v_pago.id is null then
    return jsonb_build_object('ok', false, 'error', 'Pago no encontrado');
  end if;

  if not flow._puede_ver_entidad(v_pago.id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  -- Guarda ORIGINAL (migracion 62), intacta: el admin puede verificar un intento
  -- 'creado' (cobro en persona / vio la transferencia antes de que el cliente
  -- reporte) y uno 'reportado'.
  if v_pago.estado not in ('creado', 'reportado') then
    return jsonb_build_object('ok', false, 'error',
      'Este pago ya esta ' || v_pago.estado);
  end if;

  -- [68] P0: exigir que la RESERVA siga ACTIVA. Este es el unico cambio de
  -- comportamiento de la funcion.
  -- La fila de agenda se bloquea ANTES de comprobar para que una cancelacion
  -- concurrente no se cuele entre el chequeo y el UPDATE de abajo (la
  -- cancelacion actualiza esa misma fila). Si la agenda no existiera,
  -- `v_agenda.id_estado` seria NULL y tambien cae en el error: no hace falta una
  -- guarda aparte.
  select * into v_agenda
  from flow.agenda
  where id = v_pago.id_agenda
  for update;

  select id into v_activa
  from flow.nom_estado_agenda
  where nombre = 'Reservado'
  limit 1;

  if v_activa is null or v_agenda.id_estado is distinct from v_activa then
    return jsonb_build_object('ok', false, 'error',
      'La reserva ya no esta activa; no se puede verificar este pago');
  end if;

  update flow.reserva_pago
     set estado = 'verificado',
         verificado_por = v_uid,
         verificado_at  = now(),
         motivo_rechazo = case when btrim(coalesce(p_observaciones, '')) = ''
                               then motivo_rechazo else btrim(p_observaciones) end
   where id = p_id_pago;

  update flow.agenda
     set pago_estado = 'verificado', updated_at = current_timestamp
   where id = v_pago.id_agenda;

  select s.nombre, l.nombre into v_serv, v_local
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales   l on l.id = ls.id_local
   where a.id = v_pago.id_agenda;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  select
    v_pago.uuid_usuario, 'pago', 'Pago verificado',
    'Tu pago por adelantado de ' || to_char(v_pago.monto, 'FM9999999990.00') || ' '
      || v_pago.moneda || ' para "' || coalesce(v_serv, 'el servicio') || '" en "'
      || coalesce(v_local, 'el local') || '" quedo verificado. Tu reserva esta confirmada.',
    a.id_local_servicio, v_pago.id_agenda,
    jsonb_build_object('id_pago', v_pago.id, 'estado', 'verificado',
                       'monto', v_pago.monto, 'moneda', v_pago.moneda)
  from flow.agenda a where a.id = v_pago.id_agenda;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id_pago, 'estado', 'verificado'));
end;
$function$;

comment on function flow.admin_verificar_pago_reserva(bigint, text) is
  'Igual que en la migracion 62 (acepta intentos creado y reportado) pero exige que la reserva siga activa (Reservado): si se cancelo/completo, devuelve ok:false y no toca nada.';

-- ══ 3. CLIENTE: REPORTAR SOLO SOBRE RESERVA ACTIVA Y COBRO HABILITADO ═════

create or replace function flow.cliente_reportar_pago_reserva(
  p_id_pago             bigint,
  p_codigo_confirmacion text default null,
  p_comprobante_url     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_uid            uuid := auth.uid();
  v_pago           flow.reserva_pago%rowtype;
  v_agenda         flow.agenda%rowtype;
  v_activa         integer;
  v_cobra_servicio boolean;
  v_cobra_entidad  boolean;
  v_admin          uuid;
  v_serv           text;
  v_local          text;
  v_cliente        text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  select * into v_pago from flow.reserva_pago where id = p_id_pago;
  if v_pago.id is null then
    return jsonb_build_object('ok', false, 'error', 'Pago no encontrado');
  end if;

  if v_pago.uuid_usuario <> v_uid then
    return jsonb_build_object('ok', false, 'error', 'No tienes permiso sobre este pago');
  end if;

  -- Guardas ORIGINALES (migracion 62), intactas y en el mismo orden.
  if v_pago.estado not in ('creado', 'reportado') then
    return jsonb_build_object('ok', false, 'error',
      'Este pago ya esta ' || v_pago.estado || ' y no se puede volver a reportar');
  end if;

  if v_pago.expira_at <= now() then
    return jsonb_build_object('ok', false, 'error',
      'El plazo de este pago vencio. Crea uno nuevo si sigues queriendo pagar por adelantado.');
  end if;

  -- [68] P0 (1/2): cerrojo de la reserva y exigir que siga ACTIVA. El cerrojo
  -- impide que una cancelacion concurrente se cuele entre el chequeo y el UPDATE
  -- de abajo. Si la agenda no existiera, `v_agenda.id_estado` seria NULL y
  -- tambien cae en el error: no hace falta una guarda aparte.
  select * into v_agenda
  from flow.agenda
  where id = v_pago.id_agenda
  for update;

  select id into v_activa
  from flow.nom_estado_agenda
  where nombre = 'Reservado'
  limit 1;

  if v_activa is null or v_agenda.id_estado is distinct from v_activa then
    return jsonb_build_object('ok', false, 'error',
      'La reserva ya no esta activa y no admite el pago por adelantado. Si ya hiciste la transferencia, contacta con el local.');
  end if;

  -- [68] P0 (2/2): el cobro pudo desactivarse despues de crear el intento
  -- (servicio o entidad). Sin esto el cliente reporta un pago que la app ya no
  -- ofrece.
  select coalesce(s.cobro_adelantado, false), coalesce(c.activo, false)
    into v_cobra_servicio, v_cobra_entidad
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  left join flow.cobro_config c on c.id_entidad = l.id_entidad
  where ls.id = v_agenda.id_local_servicio;

  if not coalesce(v_cobra_servicio, false) or not coalesce(v_cobra_entidad, false) then
    return jsonb_build_object('ok', false, 'error',
      'El pago por adelantado ya no esta disponible para este servicio. Si ya hiciste la transferencia, contacta con el local para que la registren.');
  end if;

  update flow.reserva_pago
     set estado = 'reportado',
         codigo_confirmacion = coalesce(nullif(btrim(coalesce(p_codigo_confirmacion, '')), ''), codigo_confirmacion),
         comprobante_url     = coalesce(nullif(btrim(coalesce(p_comprobante_url, '')), ''), comprobante_url),
         reportado_at        = now()
   where id = p_id_pago;

  update flow.agenda
     set pago_estado = 'reportado', updated_at = current_timestamp
   where id = v_pago.id_agenda;

  -- Aviso in-app a los administradores de la entidad.
  select s.nombre, l.nombre into v_serv, v_local
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales   l on l.id = ls.id_local
   where a.id = v_pago.id_agenda;

  select coalesce(p.nombre || ' ' || coalesce(p.apellidos, ''), 'Un cliente')
    into v_cliente
  from flow.perfil p
  where p.uuid_usuario = v_uid;

  for v_admin in
    select e.owner_uuid from flow.entidad e where e.id = v_pago.id_entidad
    union
    select ea.uuid_usuario from flow.entidad_admin ea where ea.id_entidad = v_pago.id_entidad
  loop
    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    select
      v_admin, 'pago', 'Pago reportado por verificar',
      btrim(v_cliente) || ' dice haber pagado ' || to_char(v_pago.monto, 'FM9999999990.00')
        || ' ' || v_pago.moneda || ' por "' || coalesce(v_serv, 'un servicio')
        || '" en "' || coalesce(v_local, 'tu local') || '". Verificalo en Reservas.',
      a.id_local_servicio, v_pago.id_agenda,
      jsonb_build_object(
        'id_pago', v_pago.id, 'monto', v_pago.monto, 'moneda', v_pago.moneda,
        'estado', 'reportado', 'id_transaccion', v_pago.id_transaccion
      )
    from flow.agenda a where a.id = v_pago.id_agenda;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id', p_id_pago, 'estado', 'reportado', 'reportado_at', now()
    )
  );
end;
$function$;

comment on function flow.cliente_reportar_pago_reserva(bigint, text, text) is
  'Marca el intento como reportado. Exige reserva activa y cobro habilitado (servicio + entidad). Si no, ok:false con mensaje accionable.';

-- ══ 4. ADMIN: RECHAZAR (VIA DE ESCAPE, SIN TOCAR) ══════════════════════════

-- ESTA FUNCION NO CAMBIA: se reproduce TAL CUAL el cuerpo desplegado (migracion
-- 62), solo para que quede explicito y para que nadie le anada la guarda de
-- "reserva activa". Es la via de escape: no mira el estado de la RESERVA, asi que
-- rechazar un pago de una reserva cancelada ya funciona hoy. Aqui no se agrega
-- nada (ni estados nuevos, ni cerrojos, ni mensajes).
--
-- Nota: un intento que el trigger de arriba deja 'anulado' ya no se puede
-- rechazar (solo entran 'creado'/'reportado'). Es correcto: ya esta cerrado y al
-- cliente le llego el aviso de la cancelacion. Si algun dia el negocio quiere un
-- rechazo formal con motivo sobre un intento anulado, seria otro cambio.

create or replace function flow.admin_rechazar_pago_reserva(
  p_id_pago bigint,
  p_motivo  text
)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_uid   uuid := auth.uid();
  v_pago  flow.reserva_pago%rowtype;
  v_mot   text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_serv  text;
  v_local text;
begin
  if v_mot is null then
    return jsonb_build_object('ok', false, 'error', 'Debes indicar el motivo del rechazo');
  end if;

  select * into v_pago from flow.reserva_pago where id = p_id_pago;
  if v_pago.id is null then
    return jsonb_build_object('ok', false, 'error', 'Pago no encontrado');
  end if;

  if not flow._puede_ver_entidad(v_pago.id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'No tiene permisos sobre esta entidad');
  end if;

  -- Guarda ORIGINAL (migracion 62), intacta.
  if v_pago.estado not in ('creado', 'reportado') then
    return jsonb_build_object('ok', false, 'error', 'Este pago ya esta ' || v_pago.estado);
  end if;

  update flow.reserva_pago
     set estado = 'rechazado', motivo_rechazo = v_mot,
         verificado_por = v_uid, verificado_at = now()
   where id = p_id_pago;

  update flow.agenda
     set pago_estado = 'rechazado', updated_at = current_timestamp
   where id = v_pago.id_agenda;

  select s.nombre, l.nombre into v_serv, v_local
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales   l on l.id = ls.id_local
   where a.id = v_pago.id_agenda;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  select
    v_pago.uuid_usuario, 'pago', 'Pago rechazado',
    'No pudimos verificar tu pago de ' || to_char(v_pago.monto, 'FM9999999990.00') || ' '
      || v_pago.moneda || ' para "' || coalesce(v_serv, 'el servicio') || '" en "'
      || coalesce(v_local, 'el local') || '". Motivo: ' || v_mot,
    a.id_local_servicio, v_pago.id_agenda,
    jsonb_build_object('id_pago', v_pago.id, 'estado', 'rechazado', 'motivo', v_mot)
  from flow.agenda a where a.id = v_pago.id_agenda;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id_pago, 'estado', 'rechazado'));
end;
$function$;

comment on function flow.admin_rechazar_pago_reserva(bigint, text) is
  'Rechaza un intento creado o reportado. NO valida el estado de la reserva: es la via de escape (funciona con la reserva cancelada). Cuerpo identico al desplegado en la migracion 62.';

-- ══ 5. GRANTS ══════════════════════════════════════════════════════════════

revoke all on function flow.trg_agenda_anular_pago() from public, anon;

revoke all on function flow.admin_verificar_pago_reserva(bigint, text) from public, anon;
revoke all on function flow.cliente_reportar_pago_reserva(bigint, text, text) from public, anon;
revoke all on function flow.admin_rechazar_pago_reserva(bigint, text) from public, anon;

grant execute on function flow.admin_verificar_pago_reserva(bigint, text) to authenticated;
grant execute on function flow.cliente_reportar_pago_reserva(bigint, text, text) to authenticated;
grant execute on function flow.admin_rechazar_pago_reserva(bigint, text) to authenticated;

notify pgrst, 'reload schema';

-- ══ 6. VERIFICACION (ejecutar a mano DESPUES de aplicar) ═══════════════════
--
-- 6.a DIAGNOSTICO DEL P0 (este select se puede correr ANTES de aplicar y debe
--     devolver 1 fila hoy: reserva_pago.id = 7 sobre agenda 302 Cancelada).
-- select rp.id,
--        rp.id_agenda,
--        rp.estado                        as estado_intento,
--        a.id_estado,
--        es.nombre                        as estado_reserva,
--        a.pago_estado,
--        rp.created_at,
--        rp.expira_at
--   from flow.reserva_pago rp
--   join flow.agenda a             on a.id  = rp.id_agenda
--   join flow.nom_estado_agenda es on es.id = a.id_estado
--  where es.nombre = 'Cancelado'
--    and rp.estado in ('creado', 'reportado')
--  order by rp.id;
--
-- 6.b El trigger existe, es BEFORE UPDATE OF id_estado y tiene el WHEN.
-- select tgname, tgtype, pg_get_triggerdef(oid) as definicion
--   from pg_trigger
--  where tgrelid = 'flow.agenda'::regclass
--    and tgname = 'trg_agenda_anular_pago';
--
-- 6.c PRUEBA END-TO-END (en una transaccion que se descarta):
-- begin;
--   -- Crear/escoger una reserva Reservado con un intento vivo (estado 'creado').
--   update flow.agenda set id_estado = 2, motivo_cancelacion = 'prueba 68'
--    where id = <id_agenda_con_pago_vivo>;
--   select id, estado from flow.reserva_pago where id_agenda = <id_agenda>;
--     -- estado = 'anulado'
--   select pago_estado from flow.agenda where id = <id_agenda>;
--     -- 'expirado' (o 'verificado'/'rechazado' si ese era el estado)
-- rollback;
--
-- 6.d Verificar un pago de una reserva cancelada ya NO se puede:
-- select flow.admin_verificar_pago_reserva(7, null);
--   -- {ok:false, error:"La reserva ya no esta activa; no se puede verificar este pago"}
--
-- 6.e Contrato conservado: un intento 'creado' de una reserva ACTIVA se sigue
--     pudiendo verificar igual que antes (busca un pago creado cuya reserva este
--     Reservado y pruebalo; el resultado es {ok:true, estado:"verificado"}).
--     En una transaccion que se descarta:
-- begin;
--   select flow.admin_verificar_pago_reserva(<id_pago_creado_de_reserva_activa>, null);
-- rollback;
--
-- 6.f Rechazar SI sigue funcionando sobre una reserva cancelada (via de escape).
--     Vale mientras el intento siga 'creado'/'reportado' (p.ej. el 7 ANTES del
--     script de datos; despues queda 'anulado' y ya no hay nada que rechazar):
-- select flow.admin_rechazar_pago_reserva(7, 'Pago no localizado en el banco');
--   -- {ok:true, data:{estado:"rechazado"}}   (en una transaccion de prueba)
--
-- 6.g Reportar un pago sobre una reserva cancelada se corta antes del update:
-- select flow.cliente_reportar_pago_reserva(7, 'ABC123', null);
--   -- {ok:false, error:"La reserva ya no esta activa y no admite el pago por adelantado..."}
-- #################### FIN: 68_anular_pago_al_cancelar.sql ####################

-- #################### INICIO: 69_cobro_disponible_en_agendas.sql ####################

-- ============================================================================
-- MIGRACION 69: `cobro_disponible` en las agendas del cliente
--
-- QUE RESUELVE
--   Para saber si una reserva se puede pagar por adelantado, la app tenia que
--   llamar aparte a `flow.cliente_cobro_info(id_local_servicio)` (una RPC por
--   cada servicio de la lista). Eso sobra: el dato depende solo de la reserva.
--   Ahora `flow.cliente_obtener_agendas` devuelve un campo mas por ticket:
--
--     "cobro_disponible": true | false
--
--   Es exactamente el mismo criterio que `cliente_cobro_info` (migracion 67):
--
--     coalesce(app_dat_servicios.cobro_adelantado, false)
--     and coalesce(cobro_config.activo, false)         -- por ENTIDAD
--
--   De modo que la app pinta el boton "Pagar por adelantado" sin preguntar nada
--   mas, y sin N+1 consultas.
--
-- DETALLE IMPORTANTE: POR QUE NO ES UN `left join flow.cobro_config` A SECAS
--   `flow.cliente_obtener_agendas` NO es `security definer` (correcto: filtra
--   por `p_uuid_usuario`, y si fuera definer cualquier cliente podria pasar el
--   uuid de otro y leer sus reservas). Al correr con los permisos del llamador,
--   la RLS se aplica, y `flow.cobro_config` solo deja leer al admin de la
--   entidad:
--
--     policy cobro_config_select_entidad: using (flow._puede_ver_entidad(id_entidad)
--                                                 or fn_is_superadmin_full_access())
--
--   Con un `left join` directo, a un CLIENTE la fila de `cobro_config` le sale
--   NULL y `cobro_disponible` seria SIEMPRE false, justo para quien lo necesita.
--   Las dos salidas obvias son peores:
--     * abrir la RLS de `cobro_config` a `authenticated`: expone la tabla entera
--       (numero de proveedor, WhatsApp, plantillas) por PostgREST;
--     * hacer `cliente_obtener_agendas` security definer: IDOR de reservas.
--
--   Por eso el criterio vive en un helper minimo `security definer` que solo
--   devuelve un boolean (no revela nada nuevo: `cliente_cobro_info` ya expone
--   esa misma disponibilidad, y mas, a cualquier usuario con sesion), y la RPC
--   sigue siendo invoker. El `left join flow.cobro_config` del criterio queda
--   dentro del helper.
--
-- LO QUE NO CAMBIA
--   * El cuerpo desplegado de `cliente_obtener_agendas` se reproduce TAL CUAL
--     (mismas claves, mismos joins, mismo `order by`, mismo filtro por
--     `p_uuid_usuario` / `reservado_por`); solo se agrega una clave.
--   * Su firma, su DEFAULT (`p_id_estado integer default null`), su volatilidad
--     (STABLE), su `search_path` y sus grants (authenticated) son los mismos.
--     El campo nuevo es aditivo: una app vieja lo ignora.
--
-- REVERSION
--   Volver a aplicar el cuerpo anterior de `cliente_obtener_agendas` (migracion
--   63) y:
--     drop function if exists flow._cobro_disponible(integer);
--   El campo extra en el jsonb no rompe a nadie: se puede dejar.
--
-- IDEMPOTENTE: create or replace + revoke/grant.
-- ============================================================================

-- ══ 1. HELPER: ¿ESTE LOCAL-SERVICIO PIDE PAGO POR ADELANTADO? ═══════════════
-- Exige las DOS condiciones (servicio + interruptor maestro de la entidad), el
-- mismo criterio de `flow.cliente_cobro_info` (migracion 67). Va como definer
-- para que la RLS de `cobro_config` no lo apague cuando lo llama un cliente.

create or replace function flow._cobro_disponible(p_id_local_servicio integer)
returns boolean
language sql
stable
security definer
set search_path = flow, public
as $function$
  select coalesce(s.cobro_adelantado, false) and coalesce(c.activo, false)
  from flow.local_servicio ls
  join flow.app_dat_locales   l on l.id = ls.id_local
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  left join flow.cobro_config c on c.id_entidad = l.id_entidad
  where ls.id = p_id_local_servicio;
$function$;

comment on function flow._cobro_disponible(integer) is
  'true si este local-servicio se puede pagar por adelantado: cobro_adelantado del servicio Y cobro_config.activo de la entidad. Security definer para que la RLS de cobro_config no lo apague al llamarlo un cliente.';

-- ══ 2. AGENDAS DEL CLIENTE (+ cobro_disponible) ════════════════════════════

create or replace function flow.cliente_obtener_agendas(
  p_uuid_usuario uuid,
  p_id_estado    integer default null
)
returns jsonb
language sql
stable
set search_path = flow, public
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                   a.id,
        'fecha_hora_reserva',   a.fecha_hora_reserva,
        'fecha_hora_atencion',  a.fecha_hora_atencion,
        'created_at',           a.created_at,
        'updated_at',           a.updated_at,
        'cantidad',             a.cantidad,
        'datos_adicionales',    a.datos_adicionales,
        'reservado_por',        a.reservado_por,
        'precio_total',         a.precio_total,
        'moneda',               a.moneda,
        'uuid_usuario',         a.uuid_usuario,
        'motivo_cancelacion',   a.motivo_cancelacion,
        'cancelado_por',        a.cancelado_por,
        'cancelado_por_rol',    a.cancelado_por_rol,
        'cancelado_at',         a.cancelado_at,
        'pago_estado',          a.pago_estado,
        'pago_monto',           a.pago_monto,
        'pago_moneda',          a.pago_moneda,
        -- [69] El cliente ya no tiene que preguntar por servicio: aqui viene si
        -- esta reserva se puede pagar por adelantado (servicio + entidad).
        'cobro_disponible',     coalesce(flow._cobro_disponible(ls.id), false),
        'estado', jsonb_build_object(
          'id',          e.id,
          'nombre',      e.nombre,
          'descripcion', e.descripcion
        ),
        'id_local_servicio', ls.id,
        'local_servicio', jsonb_build_object(
          'id',                     ls.id,
          'permite_reserva_directa', ls.permite_reserva_directa,
          'cantidad_default',       ls.cantidad_default,
          'cantidad_max_capacidad', ls.cantidad_max_capacidad
        ),
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',                             en.id,
          'denominacion',                   en.denominacion,
          'horas_anticipacion_cancelacion', en.horas_anticipacion_cancelacion
        ),
        -- Titular de la reserva (para mostrar "Para: <nombre>" si es un tercero)
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.nom_estado_agenda e  on e.id  = a.id_estado
  join flow.entidad          en on en.id = l.id_entidad
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  -- El usuario ve sus propias reservas Y las que hizo para terceros.
  where (a.uuid_usuario = p_uuid_usuario or a.reservado_por = p_uuid_usuario)
    and (p_id_estado is null or a.id_estado = p_id_estado);
$function$;

comment on function flow.cliente_obtener_agendas(uuid, integer) is
  'Tickets del cliente (propios y a nombre de terceros). Incluye desde la 69 `cobro_disponible`, que combina servicio.cobro_adelantado y cobro_config.activo. Invoker a proposito: la RLS filtra por cliente; NO hacerla security definer.';

-- ══ 3. GRANTS ══════════════════════════════════════════════════════════════

revoke all on function flow._cobro_disponible(integer) from public, anon;
revoke all on function flow.cliente_obtener_agendas(uuid, integer) from public, anon;

grant execute on function flow._cobro_disponible(integer) to authenticated;
grant execute on function flow.cliente_obtener_agendas(uuid, integer) to authenticated;

notify pgrst, 'reload schema';

-- ══ 4. VERIFICACION (ejecutar a mano DESPUES de aplicar) ═══════════════════
--
-- 4.a La firma no cambio y sigue siendo INVOKER (prosecdef = false).
-- select p.proname, p.prosecdef, pg_get_function_identity_arguments(p.oid) as args
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow'
--    and p.proname in ('cliente_obtener_agendas', '_cobro_disponible');
--   -- cliente_obtener_agendas: prosecdef = false; _cobro_disponible: true
--
-- 4.b El campo llega en el jsonb de cada ticket:
-- select e ->> 'cobro_disponible' as cobro_disponible
--   from jsonb_array_elements(flow.cliente_obtener_agendas('<uuid_cliente>', null)) e
--  limit 5;
--   -- true/false por reserva; NUNCA null
--
-- 4.c El criterio es el mismo que `cliente_cobro_info` (migracion 67).
--     Escoge un id_local_servicio y compara:
-- select flow._cobro_disponible(<id_local_servicio>)             as helper,
--        flow.cliente_cobro_info(<id_local_servicio>)
--          -> 'data' ->> 'disponible'                              as rpc;
--   -- true/false + null | "true"
--
-- 4.d Con el cobro apagado no aparece (se prueba desde una sesion de admin):
-- update flow.app_dat_servicios set cobro_adelantado = false where id = <id_servicio>;
-- select flow._cobro_disponible(<id_local_servicio>);   -- false
-- update flow.app_dat_servicios set cobro_adelantado = true  where id = <id_servicio>;
-- select flow._cobro_disponible(<id_local_servicio>);   -- true (si la entidad lo tiene activo)
--
-- 4.e PRUEBA CON SESION DE CLIENTE (la que de verdad importa): abrir "Mis
--     reservas" con un cliente y comprobar que el boton "Pagar por adelantado"
--     aparece en las reservas de servicios que cobran y NO en las demas. Desde
--     el SQL Editor el rol es `postgres` y la RLS de `cobro_config` no aplica,
--     asi que ese caso (cliente sin permisos sobre la entidad) solo se ve en la
--     app o con un JWT de cliente.
-- #################### FIN: 69_cobro_disponible_en_agendas.sql ####################

-- #################### INICIO: 70_realtime_cobro.sql ####################

-- ============================================================================
-- MIGRACION 70: Realtime del circuito de pago por adelantado
--
-- QUE RESUELVE
--   El pago por adelantado se "mueve solo" en varios sitios a la vez: el cliente
--   pulsa "Ya he pagado", el admin lo ve en su bandeja, el admin verifica o el
--   cron expira y cancela. Hoy todas esas pantallas solo se enteran al
--   recargar. Para que se actualicen solas, las tablas que mueven el estado
--   tienen que estar en la publicacion de Supabase Realtime y —las que se
--   filtran por columnas que no son la PK— con `replica identity full`.
--
-- QUE HACE
--   1. Publica en `supabase_realtime`:
--        * flow.reserva_pago    (el intento: creado -> reportado -> verificado...)
--        * flow.cobro_config    (el admin activa/cambia el cobro de la entidad)
--        * flow.app_dat_servicios (el admin marca que servicio cobra; columna
--                                  `cobro_adelantado` de la migracion 67)
--   2. `alter table flow.reserva_pago replica identity full`.
--   3. Documenta la advertencia de RLS-en-Realtime de la migracion 37 y deja una
--      politica de lectura adicional apta para Realtime (sin ampliar permisos).
--
-- POR QUE `replica identity full` EN reserva_pago (y NO en las otras dos)
--   Es la misma razon que documenta la migracion 37 para `flow.agenda`: el WAL
--   de un UPDATE, con la identidad por defecto, solo lleva la PK y las columnas
--   que cambiaron; la tupla VIEJA queda recortada a la PK. Realtime necesita la
--   fila para evaluar la RLS y los filtros, y `reserva_pago` se suscribe
--   filtrando por `uuid_usuario` (no es la PK) porque el cliente solo debe
--   recibir SUS pagos. Con `full`, cada evento lleva la fila entera.
--
--   `flow.cobro_config`: su PK es `id_entidad`, que es justo por lo que se
--   filtran los admin (o se lee la tabla entera); la identidad por defecto basta.
--   `flow.app_dat_servicios`: se filtra por `id` (PK). Tampoco hace falta.
--   Las dos son tablas pequenas y de baja escritura. Si algun dia se suscribe
--   por una columna que no es la PK **y** se depende del registro viejo
--   (UPDATE/DELETE), habria que ponerlas en `full` tambien.
--
-- ADVERTENCIA DE RLS EN REALTIME (lo que ya documenta la migracion 37)
--   Realtime evalua la RLS de la tabla con el rol `authenticated` del JWT. Las
--   politicas que llaman a funciones `security definer` pueden evaluarse mal en
--   ese contexto y hacer que el evento se descarte EN SILENCIO. En la 37 paso en
--   `flow.agenda`, que usa `es_admin_o_dueno_de_entidad_de_agenda`; la prueba de
--   fuego es en dispositivo, porque desde el SQL Editor no se puede simular un
--   websocket vivo.
--
--   Estado de las tres tablas de esta migracion frente a esa advertencia:
--     * flow.app_dat_servicios -> policy `servicios_select_all` es `using (true)`.
--       Segura para Realtime.
--     * flow.reserva_pago -> policy `reserva_pago_select_propio` es
--       `uuid_usuario = auth.uid() OR flow._puede_ver_entidad(id_entidad)`.
--       La parte del cliente es una columna simple; la del admin depende de una
--       funcion definer.
--     * flow.cobro_config -> policy `cobro_config_select_entidad` usa
--       `_puede_ver_entidad`. Los CLIENTES no pueden leer esta tabla a
--       proposito (solo el admin de la entidad), asi que un cliente NUNCA
--       recibira eventos de config: no los necesita, porque lo que le importa
--       llega en `agenda`/`cobro_disponible` y, si el cobro se apaga, las RPC
--       devuelven el error accionable de la 68.
--
--   Por eso se agrega en `flow.reserva_pago` una politica de SELECT extra,
--   `reserva_pago_select_realtime`, basada SOLO en una columna simple
--   (`uuid_usuario = auth.uid()`). Es un subconjunto exacto de la politica que
--   ya existe: no amplia ni un permiso, no cambia filas visibles y se puede
--   borrar sin efecto funcional. Sirve para que la comprobacion de RLS del
--   camino del CLIENTE no dependa de una funcion.
--
--     NOTA: Postgres combina las politicas SELECT permisivas con OR, asi que en
--     el camino del ADMIN la funcion `_puede_ver_entidad` se sigue evaluando.
--     Si en dispositivo se comprueba que los eventos de admin no llegan, la
--     salida NO es tocar esta politica: es hacer que la pantalla del admin
--     recargue al abrir/enfocar (como ya hace la app con la red de seguridad de
--     `didChangeAppLifecycleState`) o exponer una vista/tabla espejo con RLS
--     simple para la bandeja.
--
-- LO QUE NO CAMBIA
--   * No se toca ninguna politica existente ni ningun grant.
--   * Las tablas ya tienen `grant select` a `authenticated` (migracion 62), que
--     es lo que Realtime necesita para el rol del JWT.
--   * `flow.agenda` y `flow.notificaciones` ya estaban publicadas (37 y 7).
--
-- REVERSION
--   alter publication supabase_realtime drop table flow.reserva_pago;
--   alter publication supabase_realtime drop table flow.cobro_config;
--   alter publication supabase_realtime drop table flow.app_dat_servicios;
--   alter table flow.reserva_pago replica identity default;
--   drop policy if exists reserva_pago_select_realtime on flow.reserva_pago;
--
-- IDEMPOTENTE: `add table` falla si la tabla ya esta publicada y el bloque DO
-- captura `duplicate_object`; `replica identity` y `drop policy if exists` se
-- pueden repetir.
-- ============================================================================

-- ══ 1. PUBLICAR LAS TABLAS DEL COBRO ═══════════════════════════════════════

do $realtime$
declare
  v_tabla text;
begin
  foreach v_tabla in array array['cobro_config', 'app_dat_servicios', 'reserva_pago']
  loop
    begin
      execute format('alter publication supabase_realtime add table flow.%I', v_tabla);
    exception
      when duplicate_object then
        null;  -- ya estaba publicada: no hay nada que hacer
      when undefined_object then
        raise notice 'La publicacion supabase_realtime no existe; no se publico flow.%', v_tabla;
    end;
  end loop;
end
$realtime$;

-- ══ 2. REPLICA IDENTITY PARA PODER FILTRAR POR uuid_usuario ════════════════

alter table flow.reserva_pago replica identity full;

-- ══ 3. RLS APTA PARA REALTIME (ADITIVA, NO AMPLIA PERMISOS) ════════════════
-- Subconjunto exacto de `reserva_pago_select_propio`
-- (uuid_usuario = auth.uid() YA es una de sus dos ramas). Existe para que el
-- camino del cliente en Realtime evalue una columna simple y no una funcion
-- definer. Si alguna vez estorba, se borra sin cambiar nada visible.

drop policy if exists reserva_pago_select_realtime on flow.reserva_pago;

create policy reserva_pago_select_realtime on flow.reserva_pago
  for select to authenticated
  using (uuid_usuario = auth.uid());

notify pgrst, 'reload schema';

-- ══ 4. VERIFICACION (ejecutar a mano DESPUES de aplicar) ═══════════════════
--
-- 4.a Las tres tablas estan publicadas (ademas de agenda y notificaciones).
-- select schemaname, tablename
--   from pg_publication_tables
--  where pubname = 'supabase_realtime' and schemaname = 'flow'
--  order by tablename;
--   -- agenda, app_dat_servicios, cobro_config, notificaciones, reserva_pago
--
-- 4.b `reserva_pago` quedo en `full`; las otras dos siguen en `default`.
-- select c.relname,
--        case c.relreplident when 'd' then 'default' when 'f' then 'full'
--                             else c.relreplident::text end as replica_identity
--   from pg_class c
--   join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'flow'
--    and c.relname in ('reserva_pago', 'cobro_config', 'app_dat_servicios')
--  order by c.relname;
--   -- reserva_pago = full; las otras dos = default
--
-- 4.c La politica nueva es un subconjunto de la existente.
-- select polname, pg_get_expr(polqual, polrelid) as using_expr
--   from pg_policy
--  where polrelid = 'flow.reserva_pago'::regclass
--  order by polname;
--
-- 4.d Una tabla ya publicada no rompe si se reaplica la migracion:
--     ejecutar este archivo dos veces seguidas y comprobar que no hay error.
--
-- PRUEBA EN DISPOSITIVO (no se puede hacer desde el agente)
--   1. Cliente con sesion en "Mis reservas" con una reserva que cobra por
--      adelantado; dejar la pantalla a la vista.
--   2. Desde el panel del admin (u otra sesion), verificar/rechazar ese pago
--      (o ejecutar `select flow.admin_rechazar_pago_reserva(<id>, 'prueba')`).
--   3. El chip de pago del cliente debe cambiar SOLO, sin recargar.
--   4. Si no cambia: mirar si el cliente es el dueño del intento
--      (`uuid_usuario = auth.uid()`), que la tabla este publicada (4.a) y que
--      `replica identity` sea `full` (4.b). Con el filtro por `id_agenda` o
--      `uuid_usuario`, el evento no necesita la funcion definer.
--   5. Prueba equivalente del lado admin con la bandeja de pagos. Si falla, ver
--      la NOTA sobre `_puede_ver_entidad` de la cabecera: no se arregla con una
--      politica, se arregla con recarga al enfocar.
-- #################### FIN: 70_realtime_cobro.sql ####################

