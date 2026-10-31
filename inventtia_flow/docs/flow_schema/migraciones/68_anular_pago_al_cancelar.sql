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