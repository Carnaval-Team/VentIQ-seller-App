set local check_function_bodies = off;

alter default privileges for role "postgres" in schema "carnavalapp" revoke all on sequences from "anon";

alter default privileges for role "postgres" in schema "carnavalapp" revoke all on sequences from "authenticated";

alter default privileges for role "postgres" in schema "carnavalapp" revoke all on sequences from "service_role";

alter default privileges for role "postgres" in schema "carnavalapp" revoke all on tables from "anon";

alter default privileges for role "postgres" in schema "carnavalapp" revoke all on tables from "authenticated";

alter default privileges for role "postgres" in schema "carnavalapp" revoke all on tables from "service_role";

alter default privileges for role "postgres" in schema "flow" revoke all on sequences from "authenticated";

alter default privileges for role "postgres" in schema "flow" grant execute on FUNCTIONS to public;

alter default privileges for role "postgres" in schema "flow" revoke all on FUNCTIONS from "authenticated";

alter default privileges for role "postgres" in schema "flow" revoke all on tables from "anon";

alter default privileges for role "postgres" in schema "flow" revoke all on tables from "authenticated";

alter default privileges for role "postgres" in schema "muevete" revoke all on sequences from "authenticated";

alter default privileges for role "postgres" in schema "muevete" revoke all on sequences from "service_role";

alter default privileges for role "postgres" in schema "muevete" revoke all on tables from "anon";

alter default privileges for role "postgres" in schema "muevete" revoke all on tables from "authenticated";

alter default privileges for role "postgres" in schema "muevete" revoke all on tables from "service_role";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on sequences from "service_role";

alter default privileges for role "postgres" in schema "public" revoke all on FUNCTIONS from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on FUNCTIONS from "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on FUNCTIONS from "service_role";

alter default privileges for role "postgres" in schema "public" revoke all on tables from "anon";

alter default privileges for role "postgres" in schema "public" revoke all on tables from "authenticated";

alter default privileges for role "postgres" in schema "public" revoke all on tables from "service_role";

revoke all on function "public"."fn_registrar_cambio_estado_operacion"(bigint, smallint, uuid) from "anon";

revoke all on function "public"."fn_registrar_cambio_estado_operacion"(bigint, smallint, uuid) from "authenticated";

revoke all on function "public"."fn_registrar_cambio_estado_operacion"(bigint, smallint, uuid) from "service_role";

revoke all on function "public"."fn_registrar_cambio_estado_operacion_mejorado"(bigint, smallint, uuid) from "anon";

revoke all on function "public"."fn_registrar_cambio_estado_operacion_mejorado"(bigint, smallint, uuid) from "authenticated";

revoke all on function "public"."fn_registrar_cambio_estado_operacion_mejorado"(bigint, smallint, uuid) from "service_role";

comment on function "public"."fn_registrar_cambio_estado_operacion"(bigint, smallint, uuid) is null;

comment on function "public"."fn_registrar_cambio_estado_operacion_mejorado"(bigint, smallint, uuid) is null;

alter publication "supabase_realtime" drop table "carnavalapp"."Orders";

alter publication "supabase_realtime" drop table "carnavalapp"."notificaciones_usuario";

alter publication "supabase_realtime" drop table "flow"."notificaciones";

alter publication "supabase_realtime" drop table "muevete"."notificaciones";

alter publication "supabase_realtime" drop table "muevete"."ofertas_chofer";

alter publication "supabase_realtime" drop table "muevete"."place";

alter publication "supabase_realtime" drop table "muevete"."solicitudes_transporte";

alter publication "supabase_realtime" drop table "muevete"."vehicle_type";

alter publication "supabase_realtime" drop table "muevete"."viajes";

alter publication "supabase_realtime" drop table "public"."app_dat_notificaciones";

drop policy "carrito_insert_propio" on "carnavalapp"."Carrito";

drop policy "agenda_delete_dueño_y_admins" on "flow"."agenda";

drop policy "agenda_select_dueño_y_admins" on "flow"."agenda";

drop policy "agenda_update_dueño_y_admins" on "flow"."agenda";

drop policy "locales_delete_admin" on "flow"."app_dat_locales";

drop policy "locales_insert_admin" on "flow"."app_dat_locales";

drop policy "locales_update_admin" on "flow"."app_dat_locales";

drop policy "servicios_delete_admin" on "flow"."app_dat_servicios";

drop policy "servicios_insert_admin" on "flow"."app_dat_servicios";

drop policy "servicios_update_admin" on "flow"."app_dat_servicios";

drop policy "entidad_admin_delete" on "flow"."entidad_admin";

drop policy "entidad_admin_insert" on "flow"."entidad_admin";

drop policy "entidad_admin_select" on "flow"."entidad_admin";

drop policy "vendedor_delete" on "flow"."entidad_vendedor";

drop policy "vendedor_insert" on "flow"."entidad_vendedor";

drop policy "vendedor_select" on "flow"."entidad_vendedor";

drop policy "local_servicio_delete_admin" on "flow"."local_servicio";

drop policy "local_servicio_insert_admin" on "flow"."local_servicio";

drop policy "local_servicio_update_admin" on "flow"."local_servicio";

drop policy "plan_config_delete" on "flow"."plan_config";

drop policy "plan_config_insert" on "flow"."plan_config";

drop policy "plan_config_update" on "flow"."plan_config";

drop policy "plan_servicios_delete" on "flow"."plan_servicios";

drop policy "plan_servicios_insert" on "flow"."plan_servicios";

drop policy "plan_servicios_update" on "flow"."plan_servicios";

drop policy "plan_tramo_write" on "flow"."plan_tramo";

drop policy "recurso_delete" on "flow"."recurso";

drop policy "recurso_insert" on "flow"."recurso";

drop policy "recurso_update" on "flow"."recurso";

drop policy "tramo_write" on "flow"."tramo";

drop policy "turno_write" on "flow"."turno";

drop policy "turno_tramo_write" on "flow"."turno_tramo";

drop policy "dat_estado_select_participantes" on "muevete"."app_dat_estado_carga";

drop policy "carriers_see_available" on "muevete"."cargas";

drop policy "carrier_read_equipo_manejo" on "muevete"."cargas_equipo_manejo";

drop policy "shipper_equipo_manejo" on "muevete"."cargas_equipo_manejo";

drop policy "carroceria_delete" on "muevete"."carrocerias";

drop policy "carroceria_insert" on "muevete"."carrocerias";

drop policy "carroceria_select" on "muevete"."carrocerias";

drop policy "carroceria_update" on "muevete"."carrocerias";

drop policy "superadmin_all_configuracion_navegacion" on "muevete"."configuracion_navegacion";

drop policy "driver_delete_fleet" on "muevete"."drivers";

drop policy "driver_insert_fleet" on "muevete"."drivers";

drop policy "driver_select_own_and_fleet" on "muevete"."drivers";

drop policy "driver_update_own_and_fleet" on "muevete"."drivers";

drop policy "superadmin_all_drivers" on "muevete"."drivers";

drop policy "superadmin_all_notificaciones" on "muevete"."notificaciones";

drop policy "carrier_own_ofertas" on "muevete"."ofertas_carga";

drop policy "shipper_sees_ofertas" on "muevete"."ofertas_carga";

drop policy "clients_see_their_ofertas" on "muevete"."ofertas_chofer";

drop policy "drivers_own_ofertas" on "muevete"."ofertas_chofer";

drop policy "ofertas_insert_driver" on "muevete"."ofertas_chofer";

drop policy "ofertas_select_own_client" on "muevete"."ofertas_chofer";

drop policy "ofertas_select_own_driver" on "muevete"."ofertas_chofer";

drop policy "ofertas_update_client" on "muevete"."ofertas_chofer";

drop policy "superadmin_all_ofertas_chofer" on "muevete"."ofertas_chofer";

drop policy "Clients can read stops for their trips" on "muevete"."paradas_viaje";

drop policy "drivers_upsert_own_place" on "muevete"."place";

drop policy "place_insert_own" on "muevete"."place";

drop policy "place_update_own" on "muevete"."place";

drop policy "superadmin_all_place" on "muevete"."place";

drop policy "solicitudes_select_pending_driver" on "muevete"."solicitudes_transporte";

drop policy "superadmin_all_solicitudes_transporte" on "muevete"."solicitudes_transporte";

drop policy "superadmin_all_suscription_plan" on "muevete"."suscription_plan";

drop policy "superadmin_all_suscription_plan_user_history" on "muevete"."suscription_plan_user_history";

drop policy "superadmin_all_suscription_user" on "muevete"."suscription_user";

drop policy "superadmin_all_transacciones_wallet" on "muevete"."transacciones_wallet";

drop policy "transacciones_insert_client" on "muevete"."transacciones_wallet";

drop policy "transacciones_select_driver" on "muevete"."transacciones_wallet";

drop policy "superadmin_all_users" on "muevete"."users";

drop policy "superadmin_all_valoraciones_viaje" on "muevete"."valoraciones_viaje";

drop policy "superadmin_all_vehicle_type" on "muevete"."vehicle_type";

drop policy "superadmin_all_vehiculos" on "muevete"."vehiculos";

drop policy "driver_own_viajes" on "muevete"."viajes";

drop policy "superadmin_all_viajes" on "muevete"."viajes";

drop policy "viajes_select_driver" on "muevete"."viajes";

drop policy "viajes_update_driver" on "muevete"."viajes";

drop policy "superadmin_all_wallet_drivers" on "muevete"."wallet_drivers";

drop policy "wallet_drivers_insert_own" on "muevete"."wallet_drivers";

drop policy "wallet_drivers_select_own" on "muevete"."wallet_drivers";

drop policy "wallet_drivers_update_own" on "muevete"."wallet_drivers";

drop policy "cliente_cxc_tienda_all" on "public"."app_dat_cliente_cxc";

drop policy "Consignador can view and confirm liquidations" on "public"."app_dat_liquidacion_consignacion";

drop policy "Consignatario can manage liquidations" on "public"."app_dat_liquidacion_consignacion";

drop policy "liquidacion_cxc_admin_all" on "public"."app_dat_liquidacion_cxc";

drop policy "pago_venta_admin_delete" on "public"."app_dat_pago_venta";

drop policy "pago_venta_admin_insert" on "public"."app_dat_pago_venta";

drop policy "pago_venta_admin_select" on "public"."app_dat_pago_venta";

drop policy "pago_venta_admin_update" on "public"."app_dat_pago_venta";

drop policy "servicentro_producto_delete" on "public"."app_dat_servicentro_producto";

drop policy "servicentro_producto_insert" on "public"."app_dat_servicentro_producto";

drop policy "servicentro_producto_select" on "public"."app_dat_servicentro_producto";

drop policy "servicentro_producto_update" on "public"."app_dat_servicentro_producto";

drop policy "superadmin_delete_full_access" on "public"."app_dat_superadmin";

drop policy "superadmin_insert_full_access" on "public"."app_dat_superadmin";

drop policy "superadmin_select_own_or_full" on "public"."app_dat_superadmin";

drop policy "superadmin_update_full_access" on "public"."app_dat_superadmin";

drop policy "superadmin_update_role_full_access" on "public"."app_dat_superadmin";

drop policy "superadmin_roles_write_full_access" on "public"."app_dat_superadmin_roles";

drop policy "app_inf_presentacion_producto_delete" on "public"."app_inf_presentacion_producto";

drop policy "app_inf_presentacion_producto_insert" on "public"."app_inf_presentacion_producto";

drop policy "app_inf_presentacion_producto_select" on "public"."app_inf_presentacion_producto";

drop policy "app_inf_presentacion_producto_update" on "public"."app_inf_presentacion_producto";

drop policy "campanas_tienda_policy" on "public"."app_mkt_campanas";

drop policy "comunicaciones_tienda_policy" on "public"."app_mkt_comunicaciones";

drop policy "eventos_fidelizacion_tienda_policy" on "public"."app_mkt_eventos_fidelizacion";

drop policy "segmentos_tienda_policy" on "public"."app_mkt_segmentos";

drop policy "wapi_destinatario_access" on "public"."app_wapi_destinatario";

drop policy "wapi_log_select" on "public"."app_wapi_envio_log";

drop policy "wapi_lic_insert_propia" on "public"."app_wapi_licencia";

drop policy "wapi_programacion_access" on "public"."app_wapi_programacion";

drop policy "wapi_prog_dest_access" on "public"."app_wapi_programacion_destinatario";

drop policy "wapi_prog_prod_access" on "public"."app_wapi_programacion_producto";

drop policy "Storage: allow authenticated delete own objects" on "storage"."objects";

drop policy "Storage: allow authenticated insert to own or public bucket" on "storage"."objects";

drop policy "flow_imagenes_delete_auth" on "storage"."objects";

drop policy "flow_imagenes_insert_auth" on "storage"."objects";

drop policy "flow_imagenes_read_public" on "storage"."objects";

drop policy "flow_imagenes_update_auth" on "storage"."objects";

drop policy "images_back_delete_authenticated" on "storage"."objects";

drop policy "images_back_insert_authenticated" on "storage"."objects";

drop policy "images_back_select_public" on "storage"."objects";

drop policy "images_back_update_authenticated" on "storage"."objects";

drop materialized view "public"."app_mv_reconciliacion_optimizada";

drop view "carnavalapp"."v_bitacora_capitan";

drop view "muevete"."v_cargas_con_nomencladores";

drop view "muevete"."v_cargas_estado_actual";

drop view "public"."app_vw_reconciliacion_inventario";

drop view "public"."v_consignacion_envio_productos";

drop view "public"."v_consignacion_envios";

drop view "public"."v_devoluciones_consignacion";

drop view "public"."v_tienda_catalogo_info";

drop view "public"."vista_almacenes_tienda_layout";

drop view "public"."vista_cocinas_tienda";

drop view "public"."vista_precios_productos";

drop view "public"."vw_analisis_ventas";

drop view "public"."vw_descuentos_devoluciones";

drop view "public"."vw_estado_inventarios";

drop view "public"."vw_operaciones_consignacion";

drop view "public"."vw_producto_utilidad_bruta";

drop view "public"."vw_resumen_financiero";

alter table "carnavalapp"."Carrito"
  drop constraint "carrito_product_id_fkey";

alter table "carnavalapp"."Carrito"
  drop constraint "carrito_proveedor_fkey";

alter table "carnavalapp"."Carrito"
  drop constraint "carrito_uuid_fkey";

alter table "carnavalapp"."Direcciones"
  drop constraint "direcciones_uuid_fkey";

alter table "carnavalapp"."OrderDetails"
  drop constraint "orderdetails_order_id_fkey";

alter table "carnavalapp"."OrderDetails"
  drop constraint "orderdetails_product_id_fkey";

alter table "carnavalapp"."Orders"
  drop constraint "Orders_user_id_fkey";

alter table "carnavalapp"."Orders"
  drop constraint "orders_direccion_id_fkey";

alter table "carnavalapp"."Productos"
  drop constraint "productos_category_id_fkey";

alter table "carnavalapp"."Productos"
  drop constraint "productos_proveedor_fkey";

alter table "carnavalapp"."Reviews"
  drop constraint "reviews_orden_id_fkey";

alter table "carnavalapp"."Usuarios"
  drop constraint "usuarios_tienda_fkey";

alter table "carnavalapp"."Usuarios"
  drop constraint "usuarios_uuid_fkey";

alter table "carnavalapp"."horarios_tienda"
  drop constraint "horarios_tienda_tienda_id_fkey";

alter table "carnavalapp"."inventarioLogs"
  drop constraint "inventariologs_proveedor_fkey";

alter table "carnavalapp"."municipios"
  drop constraint "municipios_provincia_fkey";

alter table "carnavalapp"."order_status_history"
  drop constraint "order_status_history_order_id_fkey";

alter table "carnavalapp"."posicion_repartidor"
  drop constraint "posicion_repartidor_repartidor_id_fkey";

alter table "carnavalapp"."posicion_repartidor_history"
  drop constraint "posicion_repartidor_history_repartidor_id_fkey";

alter table "carnavalapp"."preOrden"
  drop constraint "preorden_producto_fkey";

alter table "carnavalapp"."repartidores"
  drop constraint "repartidores_uuid_fkey";

alter table "carnavalapp"."sub_categorias"
  drop constraint "sub_categorias_id_cat_padre_fkey";

alter table "carnavalapp"."transacciones"
  drop constraint "transacciones_num_orden_fkey";

alter table "carnavalapp"."user_tokens"
  drop constraint "user_tokens_user_id_fkey";

alter table "flow"."agenda"
  drop constraint "agenda_id_estado_fkey";

alter table "flow"."agenda"
  drop constraint "agenda_id_local_servicio_fkey";

alter table "flow"."agenda"
  drop constraint "agenda_id_turno_fkey";

alter table "flow"."agenda"
  drop constraint "agenda_uuid_usuario_fkey";

alter table "flow"."app_dat_locales"
  drop constraint "app_dat_locales_id_entidad_fkey";

alter table "flow"."app_dat_servicios"
  drop constraint "app_dat_servicios_id_entidad_fkey";

alter table "flow"."app_dat_servicios"
  drop constraint "app_dat_servicios_id_tipo_actividad_fkey";

alter table "flow"."entidad"
  drop constraint "entidad_owner_uuid_fkey";

alter table "flow"."entidad_admin"
  drop constraint "entidad_admin_asignado_por_fkey";

alter table "flow"."entidad_admin"
  drop constraint "entidad_admin_id_entidad_fkey";

alter table "flow"."entidad_admin"
  drop constraint "entidad_admin_uuid_usuario_fkey";

alter table "flow"."entidad_vendedor"
  drop constraint "entidad_vendedor_asignado_por_fkey";

alter table "flow"."entidad_vendedor"
  drop constraint "entidad_vendedor_id_entidad_fkey";

alter table "flow"."entidad_vendedor"
  drop constraint "entidad_vendedor_uuid_usuario_fkey";

alter table "flow"."local_servicio"
  drop constraint "local_servicio_id_local_fkey";

alter table "flow"."local_servicio"
  drop constraint "local_servicio_id_servicio_fkey";

alter table "flow"."notificaciones"
  drop constraint "notificaciones_id_local_servicio_fkey";

alter table "flow"."notificaciones"
  drop constraint "notificaciones_uuid_usuario_fkey";

alter table "flow"."plan_config"
  drop constraint "plan_config_id_local_servicio_fkey";

alter table "flow"."plan_servicios"
  drop constraint "plan_servicios_id_local_servicio_fkey";

alter table "flow"."plan_tramo"
  drop constraint "plan_tramo_id_tramo_fkey";

alter table "flow"."recurso"
  drop constraint "recurso_id_local_servicio_fkey";

alter table "flow"."sala_espera"
  drop constraint "sala_espera_id_local_servicio_fkey";

alter table "flow"."sala_espera"
  drop constraint "sala_espera_id_turno_fkey";

alter table "flow"."sala_espera"
  drop constraint "sala_espera_uuid_usuario_fkey";

alter table "flow"."sala_espera_fraude"
  drop constraint "sala_espera_fraude_uuid_fkey";

alter table "flow"."tramo"
  drop constraint "tramo_id_recurso_fkey";

alter table "flow"."turno"
  drop constraint "turno_id_recurso_fkey";

alter table "flow"."turno_tramo"
  drop constraint "turno_tramo_id_tramo_fkey";

alter table "flow"."turno_tramo"
  drop constraint "turno_tramo_id_turno_fkey";

alter table "flow"."ultimo_numero"
  drop constraint "ultimo_numero_id_local_servicio_fkey";

alter table "muevete"."app_dat_estado_carga"
  drop constraint "app_dat_estado_carga_carga_id_fkey";

alter table "muevete"."app_dat_estado_carga"
  drop constraint "app_dat_estado_carga_driver_id_fkey";

alter table "muevete"."app_dat_estado_carga"
  drop constraint "app_dat_estado_carga_estado_codigo_fkey";

alter table "muevete"."app_dat_estado_carga"
  drop constraint "app_dat_estado_carga_usuario_uuid_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_carrier_driver_id_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_carrier_uuid_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_commodity_nom_id_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_id_tipo_vehiculo_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_shipper_id_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_tipo_carga_id_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_tipo_equipo_id_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_tipo_mercancia_id_fkey";

alter table "muevete"."cargas"
  drop constraint "cargas_unidad_peso_id_fkey";

alter table "muevete"."cargas_equipo_manejo"
  drop constraint "cargas_equipo_manejo_carga_id_fkey";

alter table "muevete"."cargas_equipo_manejo"
  drop constraint "cargas_equipo_manejo_equipo_manejo_id_fkey";

alter table "muevete"."carrocerias"
  drop constraint "carrocerias_driver_fkey";

alter table "muevete"."direcciones_rapidas"
  drop constraint "direcciones_rapidas_user_fkey";

alter table "muevete"."drivers"
  drop constraint "drivers_dispatcher_id_fkey";

alter table "muevete"."drivers"
  drop constraint "drivers_uuid_fkey";

alter table "muevete"."drivers"
  drop constraint "drivers_vehiculo_fkey";

alter table "muevete"."ofertas_carga"
  drop constraint "ofertas_carga_carga_id_fkey";

alter table "muevete"."ofertas_carga"
  drop constraint "ofertas_carga_driver_id_fkey";

alter table "muevete"."ofertas_carga"
  drop constraint "ofertas_carga_vehiculo_id_fkey";

alter table "muevete"."ofertas_chofer"
  drop constraint "ofertas_chofer_driver_id_fkey";

alter table "muevete"."ofertas_chofer"
  drop constraint "ofertas_chofer_solicitud_id_fkey";

alter table "muevete"."paradas_viaje"
  drop constraint "paradas_viaje_driver_fkey";

alter table "muevete"."paradas_viaje"
  drop constraint "paradas_viaje_viaje_fkey";

alter table "muevete"."place"
  drop constraint "place_driver_fkey";

alter table "muevete"."place"
  drop constraint "place_vehiculo_id_fkey";

alter table "muevete"."push_tokens"
  drop constraint "push_tokens_user_uuid_fkey";

alter table "muevete"."solicitudes_plan"
  drop constraint "solicitudes_plan_admin_uuid_fkey";

alter table "muevete"."solicitudes_plan"
  drop constraint "solicitudes_plan_plan_codigo_fkey";

alter table "muevete"."solicitudes_plan"
  drop constraint "solicitudes_plan_usuario_uuid_fkey";

alter table "muevete"."solicitudes_transporte"
  drop constraint "solicitudes_transporte_user_id_fkey";

alter table "muevete"."sub_usuarios"
  drop constraint "sub_usuarios_propietario_fkey";

alter table "muevete"."sub_usuarios"
  drop constraint "sub_usuarios_sub_driver_fkey";

alter table "muevete"."sub_usuarios"
  drop constraint "sub_usuarios_sub_uuid_fkey";

alter table "muevete"."suscripciones"
  drop constraint "suscripciones_plan_codigo_fkey";

alter table "muevete"."suscripciones"
  drop constraint "suscripciones_usuario_uuid_fkey";

alter table "muevete"."transacciones_wallet"
  drop constraint "transacciones_wallet_driver_id_fkey";

alter table "muevete"."transacciones_wallet"
  drop constraint "transacciones_wallet_user_id_fkey";

alter table "muevete"."transacciones_wallet"
  drop constraint "transacciones_wallet_viaje_id_fkey";

alter table "muevete"."users"
  drop constraint "clientes_uuid_fkey";

alter table "muevete"."valoraciones_viaje"
  drop constraint "valoraciones_viaje_driver_fkey";

alter table "muevete"."valoraciones_viaje"
  drop constraint "valoraciones_viaje_user_fkey";

alter table "muevete"."valoraciones_viaje"
  drop constraint "valoraciones_viaje_viaje_fkey";

alter table "muevete"."vehiculos"
  drop constraint "vehiculos_id_tipo_vehiculo_fkey";

alter table "muevete"."vehiculos"
  drop constraint "vehiculos_tipo_equipo_id_fkey";

alter table "muevete"."verificacion_operacion_recarga"
  drop constraint "verificacion_operacion_recarga_tx_fkey";

alter table "muevete"."viajes"
  drop constraint "viajes_driver_fkey";

alter table "muevete"."wallet_drivers"
  drop constraint "wallet_drivers_driver_id_fkey";

alter table "public"."app_cont_asignacion_costos"
  drop constraint "app_cont_asignacion_costos_id_centro_costo_fkey";

alter table "public"."app_cont_asignacion_costos"
  drop constraint "app_cont_asignacion_costos_id_producto_fkey";

alter table "public"."app_cont_asignacion_costos"
  drop constraint "app_cont_asignacion_costos_id_tienda_fkey";

alter table "public"."app_cont_asignacion_costos"
  drop constraint "app_cont_asignacion_costos_id_tipo_costo_fkey";

alter table "public"."app_cont_centro_costo"
  drop constraint "app_cont_centro_costo_id_tienda_fkey";

alter table "public"."app_cont_egresos_procesados"
  drop constraint "app_cont_egresos_procesados_id_egreso_fkey";

alter table "public"."app_cont_egresos_procesados"
  drop constraint "app_cont_egresos_procesados_procesado_por_fkey";

alter table "public"."app_cont_gasto_asignacion"
  drop constraint "app_cont_gasto_asignacion_id_asignacion_fkey";

alter table "public"."app_cont_gasto_asignacion"
  drop constraint "app_cont_gasto_asignacion_id_gasto_fkey";

alter table "public"."app_cont_gastos"
  drop constraint "app_cont_gastos_id_centro_costo_fkey";

alter table "public"."app_cont_gastos"
  drop constraint "app_cont_gastos_id_subcategoria_gasto_fkey";

alter table "public"."app_cont_gastos"
  drop constraint "app_cont_gastos_id_tienda_fkey";

alter table "public"."app_cont_gastos"
  drop constraint "app_cont_gastos_id_tipo_costo_fkey";

alter table "public"."app_cont_gastos"
  drop constraint "app_cont_gastos_origen_operacion_fkey";

alter table "public"."app_cont_gastos"
  drop constraint "app_cont_gastos_uuid_fkey";

alter table "public"."app_cont_historial_actividades"
  drop constraint "app_cont_historial_actividades_tienda_fkey";

alter table "public"."app_cont_historial_actividades"
  drop constraint "app_cont_historial_actividades_usuario_fkey";

alter table "public"."app_cont_historial_asignacion_costos"
  drop constraint "app_cont_historial_asignacion_costos_id_tipo_costo_fkey";

alter table "public"."app_cont_historial_gastos"
  drop constraint "app_cont_historial_gastos_id_centro_costo_fkey";

alter table "public"."app_cont_historial_gastos"
  drop constraint "app_cont_historial_gastos_id_subcategoria_gasto_fkey";

alter table "public"."app_cont_historial_gastos"
  drop constraint "app_cont_historial_gastos_id_tienda_fkey";

alter table "public"."app_cont_historial_gastos"
  drop constraint "app_cont_historial_gastos_id_tipo_costo_fkey";

alter table "public"."app_cont_historial_gastos"
  drop constraint "app_cont_historial_gastos_realizado_por_fkey";

alter table "public"."app_cont_log_costos"
  drop constraint "app_cont_log_costos_id_asignacion_fkey";

alter table "public"."app_cont_log_costos"
  drop constraint "app_cont_log_costos_id_historico_fkey";

alter table "public"."app_cont_margen_comercial"
  drop constraint "app_cont_margen_comercial_id_producto_fkey";

alter table "public"."app_cont_margen_comercial"
  drop constraint "app_cont_margen_comercial_id_tienda_fkey";

alter table "public"."app_cont_margen_comercial"
  drop constraint "app_cont_margen_comercial_id_variante_fkey";

alter table "public"."app_cont_tipo_costo"
  drop constraint "app_cont_tipo_costo_naturaleza_fkey";

alter table "public"."app_dat_ajuste_inventario"
  drop constraint "app_dat_ajuste_inventario_id_control_fkey";

alter table "public"."app_dat_ajuste_inventario"
  drop constraint "app_dat_ajuste_inventario_id_operacion_fkey";

alter table "public"."app_dat_ajuste_inventario"
  drop constraint "app_dat_ajuste_inventario_id_producto_fkey";

alter table "public"."app_dat_almacen"
  drop constraint "app_dat_almacen_id_tienda_fkey";

alter table "public"."app_dat_almacen_limites"
  drop constraint "app_dat_almacen limites_id_almacen_fkey";

alter table "public"."app_dat_almacen_limites"
  drop constraint "app_dat_almacen limites_id_producto_fkey";

alter table "public"."app_dat_almacenero"
  drop constraint "app_dat_almacenero_id_almacen_fkey";

alter table "public"."app_dat_almacenero"
  drop constraint "app_dat_almacenero_id_trabajador_fkey";

alter table "public"."app_dat_almacenero"
  drop constraint "app_dat_almacenero_uuid_fkey";

alter table "public"."app_dat_application_rating"
  drop constraint "app_dat_tienda_rating_id_usuario_fkey";

alter table "public"."app_dat_atributo_opcion"
  drop constraint "app_dat_atributo_opcion_id_atributo_fkey";

alter table "public"."app_dat_caja_turno"
  drop constraint "app_dat_caja_turno_cerrado_por_fkey";

alter table "public"."app_dat_caja_turno"
  drop constraint "app_dat_caja_turno_creado_por_fkey";

alter table "public"."app_dat_caja_turno"
  drop constraint "app_dat_caja_turno_estado_fkey";

alter table "public"."app_dat_caja_turno"
  drop constraint "app_dat_caja_turno_id_operacion_apertura_fkey";

alter table "public"."app_dat_caja_turno"
  drop constraint "app_dat_caja_turno_id_operacion_cierre_fkey";

alter table "public"."app_dat_caja_turno"
  drop constraint "app_dat_caja_turno_id_tpv_fkey";

alter table "public"."app_dat_caja_turno"
  drop constraint "app_dat_caja_turno_id_vendedor_fkey";

alter table "public"."app_dat_cambio_precio"
  drop constraint "fk_producto";

alter table "public"."app_dat_cambio_precio"
  drop constraint "fk_tpv";

alter table "public"."app_dat_cambio_precio"
  drop constraint "fk_usuario";

alter table "public"."app_dat_cambio_precio"
  drop constraint "fk_variante";

alter table "public"."app_dat_categoria_tienda"
  drop constraint "app_dat_categoria_tienda_id_categoria_fkey";

alter table "public"."app_dat_categoria_tienda"
  drop constraint "app_dat_categoria_tienda_id_cocina_fkey";

alter table "public"."app_dat_categoria_tienda"
  drop constraint "app_dat_categoria_tienda_id_tienda_fkey";

alter table "public"."app_dat_cliente_cxc"
  drop constraint "app_dat_cliente_cxc_id_tienda_fkey";

alter table "public"."app_dat_cocina"
  drop constraint "app_dat_cocina_almacen_fkey";

alter table "public"."app_dat_cocina"
  drop constraint "app_dat_cocina_tienda_fkey";

alter table "public"."app_dat_codigos_barras"
  drop constraint "app_dat_codigos_barras_created_by_fkey";

alter table "public"."app_dat_codigos_barras"
  drop constraint "app_dat_codigos_barras_opcion_fkey";

alter table "public"."app_dat_codigos_barras"
  drop constraint "app_dat_codigos_barras_presentacion_fkey";

alter table "public"."app_dat_codigos_barras"
  drop constraint "app_dat_codigos_barras_producto_fkey";

alter table "public"."app_dat_codigos_barras"
  drop constraint "app_dat_codigos_barras_variante_fkey";

alter table "public"."app_dat_comanda"
  drop constraint "app_dat_comanda_id_cocina_fkey";

alter table "public"."app_dat_comanda"
  drop constraint "app_dat_comanda_id_cuenta_fkey";

alter table "public"."app_dat_comanda"
  drop constraint "app_dat_comanda_id_mesa_fkey";

alter table "public"."app_dat_comanda"
  drop constraint "app_dat_comanda_id_tienda_fkey";

alter table "public"."app_dat_comanda"
  drop constraint "app_dat_comanda_id_tpv_fkey";

alter table "public"."app_dat_comanda_item"
  drop constraint "app_dat_comanda_item_id_comanda_fkey";

alter table "public"."app_dat_comanda_item"
  drop constraint "app_dat_comanda_item_id_item_cuenta_fkey";

alter table "public"."app_dat_comanda_item"
  drop constraint "app_dat_comanda_item_id_producto_fkey";

alter table "public"."app_dat_configuracion_tienda"
  drop constraint "app_dat_configuracion_tienda_id_tienda_fkey";

alter table "public"."app_dat_consignacion_envio"
  drop constraint "app_dat_consignacion_envio_id_contrato_consignacion_fkey";

alter table "public"."app_dat_consignacion_envio"
  drop constraint "app_dat_consignacion_envio_id_operacion_extraccion_fkey";

alter table "public"."app_dat_consignacion_envio"
  drop constraint "app_dat_consignacion_envio_id_operacion_recepcion_fkey";

alter table "public"."app_dat_consignacion_envio"
  drop constraint "app_dat_consignacion_envio_id_usuario_aceptador_fkey";

alter table "public"."app_dat_consignacion_envio"
  drop constraint "app_dat_consignacion_envio_id_usuario_configurador_fkey";

alter table "public"."app_dat_consignacion_envio"
  drop constraint "app_dat_consignacion_envio_id_usuario_creador_fkey";

alter table "public"."app_dat_consignacion_envio"
  drop constraint "app_dat_consignacion_envio_id_usuario_rechazador_fkey";

alter table "public"."app_dat_consignacion_envio_movimiento"
  drop constraint "app_dat_consignacion_envio_movimiento_id_envio_fkey";

alter table "public"."app_dat_consignacion_envio_movimiento"
  drop constraint "app_dat_consignacion_envio_movimiento_id_usuario_fkey";

alter table "public"."app_dat_consignacion_envio_producto"
  drop constraint "app_dat_consignacion_envio_produc_id_producto_consignacion_fkey";

alter table "public"."app_dat_consignacion_envio_producto"
  drop constraint "app_dat_consignacion_envio_producto_id_envio_fkey";

alter table "public"."app_dat_consignacion_envio_producto"
  drop constraint "app_dat_consignacion_envio_producto_id_inventario_fkey";

alter table "public"."app_dat_consignacion_envio_producto"
  drop constraint "app_dat_consignacion_envio_producto_id_producto_fkey";

alter table "public"."app_dat_consignacion_envio_producto"
  drop constraint "fk_envio_producto_inventario_original";

alter table "public"."app_dat_consignacion_envio_producto"
  drop constraint "fk_envio_producto_presentacion_original";

alter table "public"."app_dat_consignacion_envio_producto"
  drop constraint "fk_envio_producto_ubicacion_original";

alter table "public"."app_dat_consignacion_envio_producto"
  drop constraint "fk_envio_producto_variante_original";

alter table "public"."app_dat_consignacion_zona"
  drop constraint "app_dat_consignacion_zona_contrato_fkey";

alter table "public"."app_dat_consignacion_zona"
  drop constraint "app_dat_consignacion_zona_tienda_consignadora_fkey";

alter table "public"."app_dat_consignacion_zona"
  drop constraint "app_dat_consignacion_zona_tienda_consignataria_fkey";

alter table "public"."app_dat_consignacion_zona"
  drop constraint "app_dat_consignacion_zona_zona_fkey";

alter table "public"."app_dat_contactos_clientes"
  drop constraint "app_dat_contactos_clientes_id_cliente_fkey";

alter table "public"."app_dat_contrato_consignacion"
  drop constraint "app_dat_contrato_consignacion_almacen_destino_fkey";

alter table "public"."app_dat_contrato_consignacion"
  drop constraint "app_dat_contrato_consignacion_id_layout_destino_fkey";

alter table "public"."app_dat_contrato_consignacion"
  drop constraint "app_dat_contrato_consignacion_id_tienda_consignadora_fkey";

alter table "public"."app_dat_contrato_consignacion"
  drop constraint "app_dat_contrato_consignacion_id_tienda_consignataria_fkey";

alter table "public"."app_dat_control_productos"
  drop constraint "app_dat_control_productos_id_opcion_variante_fkey";

alter table "public"."app_dat_control_productos"
  drop constraint "app_dat_control_productos_id_operacion_fkey";

alter table "public"."app_dat_control_productos"
  drop constraint "app_dat_control_productos_id_presentacion_fkey";

alter table "public"."app_dat_control_productos"
  drop constraint "app_dat_control_productos_id_producto_fkey";

alter table "public"."app_dat_control_productos"
  drop constraint "app_dat_control_productos_id_ubicacion_fkey";

alter table "public"."app_dat_control_productos"
  drop constraint "app_dat_control_productos_id_variante_fkey";

alter table "public"."app_dat_conversion_presentacion"
  drop constraint "app_dat_conversion_presentacion_operacion_fkey";

alter table "public"."app_dat_conversion_presentacion"
  drop constraint "app_dat_conversion_presentacion_pres_destino_fkey";

alter table "public"."app_dat_conversion_presentacion"
  drop constraint "app_dat_conversion_presentacion_pres_origen_fkey";

alter table "public"."app_dat_conversion_presentacion"
  drop constraint "app_dat_conversion_presentacion_producto_fkey";

alter table "public"."app_dat_conversion_presentacion"
  drop constraint "app_dat_conversion_presentacion_ubicacion_fkey";

alter table "public"."app_dat_conversion_presentacion_evento"
  drop constraint "app_dat_conversion_presentacion_evento_id_opcion_variante_fkey";

alter table "public"."app_dat_conversion_presentacion_evento"
  drop constraint "app_dat_conversion_presentacion_evento_id_operacion_fkey";

alter table "public"."app_dat_conversion_presentacion_evento"
  drop constraint "app_dat_conversion_presentacion_evento_id_producto_fkey";

alter table "public"."app_dat_conversion_presentacion_evento"
  drop constraint "app_dat_conversion_presentacion_evento_id_ubicacion_fkey";

alter table "public"."app_dat_conversion_presentacion_evento"
  drop constraint "app_dat_conversion_presentacion_evento_id_variante_fkey";

alter table "public"."app_dat_conversion_presentacion_pata"
  drop constraint "app_dat_conversion_presentacion_pata_id_conversion_evento_fkey";

alter table "public"."app_dat_conversion_presentacion_pata"
  drop constraint "app_dat_conversion_presentacion_pata_id_presentacion_fkey";

alter table "public"."app_dat_cumplimiento_inventario_solicitud"
  drop constraint "app_dat_cumplimiento_inventario_solicit_id_opcion_variante_fkey";

alter table "public"."app_dat_cumplimiento_inventario_solicitud"
  drop constraint "app_dat_cumplimiento_inventario_solicitud_id_presentacion_fkey";

alter table "public"."app_dat_cumplimiento_inventario_solicitud"
  drop constraint "app_dat_cumplimiento_inventario_solicitud_id_producto_fkey";

alter table "public"."app_dat_cumplimiento_inventario_solicitud"
  drop constraint "app_dat_cumplimiento_inventario_solicitud_id_ubicacion_fkey";

alter table "public"."app_dat_cumplimiento_inventario_solicitud"
  drop constraint "app_dat_cumplimiento_inventario_solicitud_id_variante_fkey";

alter table "public"."app_dat_entregas_parciales_caja"
  drop constraint "app_dat_entregas_parciales_caja_id_medio_pago_fkey";

alter table "public"."app_dat_entregas_parciales_caja"
  drop constraint "app_dat_entregas_parciales_caja_id_turno_fkey";

alter table "public"."app_dat_estado_operacion"
  drop constraint "app_dat_estado_operacion_estado_fkey";

alter table "public"."app_dat_estado_operacion"
  drop constraint "app_dat_estado_operacion_id_operacion_fkey";

alter table "public"."app_dat_estado_operacion"
  drop constraint "app_dat_estado_operacion_uuid_fkey";

alter table "public"."app_dat_extraccion_productos"
  drop constraint "app_dat_extraccion_productos_id_opcion_variante_fkey";

alter table "public"."app_dat_extraccion_productos"
  drop constraint "app_dat_extraccion_productos_id_operacion_fkey";

alter table "public"."app_dat_extraccion_productos"
  drop constraint "app_dat_extraccion_productos_id_presentacion_fkey";

alter table "public"."app_dat_extraccion_productos"
  drop constraint "app_dat_extraccion_productos_id_producto_fkey";

alter table "public"."app_dat_extraccion_productos"
  drop constraint "app_dat_extraccion_productos_id_ubicacion_fkey";

alter table "public"."app_dat_extraccion_productos"
  drop constraint "app_dat_extraccion_productos_id_variante_fkey";

alter table "public"."app_dat_extraccion_v2_solicitud"
  drop constraint "app_dat_extraccion_v2_solicitud_actor_uuid_fkey";

alter table "public"."app_dat_extraccion_v2_solicitud"
  drop constraint "app_dat_extraccion_v2_solicitud_id_operacion_fkey";

alter table "public"."app_dat_extraccion_v2_solicitud"
  drop constraint "app_dat_extraccion_v2_solicitud_id_tienda_fkey";

alter table "public"."app_dat_garantia_uso"
  drop constraint "fk_garantia_uso_devolucion";

alter table "public"."app_dat_garantia_uso"
  drop constraint "fk_garantia_uso_garantia";

alter table "public"."app_dat_garantia_venta"
  drop constraint "fk_garantia_venta_producto";

alter table "public"."app_dat_garantia_venta"
  drop constraint "fk_garantia_venta_tipo";

alter table "public"."app_dat_garantia_venta"
  drop constraint "fk_garantia_venta_venta";

alter table "public"."app_dat_gerente"
  drop constraint "app_dat_dueños_id_tienda_fkey";

alter table "public"."app_dat_gerente"
  drop constraint "app_dat_dueños_uuid_fkey";

alter table "public"."app_dat_gerente"
  drop constraint "app_dat_gerente_id_trabajador_fkey";

alter table "public"."app_dat_historial_pre_asignaciones"
  drop constraint "fk_historial_operacion";

alter table "public"."app_dat_historial_pre_asignaciones"
  drop constraint "fk_historial_pre_asignacion";

alter table "public"."app_dat_historial_pre_asignaciones"
  drop constraint "fk_historial_tipo_operacion";

alter table "public"."app_dat_historial_pre_asignaciones"
  drop constraint "fk_historial_usuario";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_conversion_evento_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_control_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_conversion_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_extraccion_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_opcion_variante_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_presentacion_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_producto_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_recepcion_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_ubicacion_fkey";

alter table "public"."app_dat_inventario_productos"
  drop constraint "app_dat_inventario_productos_id_variante_fkey";

alter table "public"."app_dat_jefe_cocina"
  drop constraint "app_dat_jefe_cocina_id_cocina_fkey";

alter table "public"."app_dat_jefe_cocina"
  drop constraint "app_dat_jefe_cocina_id_trabajador_fkey";

alter table "public"."app_dat_layout_abc"
  drop constraint "app_dat_layout_abc_id_layout_fkey";

alter table "public"."app_dat_layout_almacen"
  drop constraint "app_dat_layout_almacen_id_almacen_fkey";

alter table "public"."app_dat_layout_almacen"
  drop constraint "app_dat_layout_almacen_id_tipo_layout_fkey";

alter table "public"."app_dat_layout_condiciones"
  drop constraint "app_dat_layout_condiciones_id_condicion_fkey";

alter table "public"."app_dat_layout_condiciones"
  drop constraint "app_dat_layout_condiciones_id_layout_fkey";

alter table "public"."app_dat_liquidacion_consignacion"
  drop constraint "app_dat_liquidacion_consignacion_confirmed_by_fkey";

alter table "public"."app_dat_liquidacion_consignacion"
  drop constraint "app_dat_liquidacion_consignacion_contrato_fkey";

alter table "public"."app_dat_liquidacion_consignacion"
  drop constraint "app_dat_liquidacion_consignacion_created_by_fkey";

alter table "public"."app_dat_liquidacion_cxc"
  drop constraint "app_dat_liquidacion_cxc_creado_por_fkey";

alter table "public"."app_dat_liquidacion_cxc"
  drop constraint "app_dat_liquidacion_cxc_id_cliente_cxc_fkey";

alter table "public"."app_dat_liquidacion_cxc"
  drop constraint "app_dat_liquidacion_cxc_id_cliente_fkey";

alter table "public"."app_dat_liquidacion_cxc"
  drop constraint "app_dat_liquidacion_cxc_id_medio_pago_fkey";

alter table "public"."app_dat_liquidacion_cxc"
  drop constraint "app_dat_liquidacion_cxc_id_tienda_fkey";

alter table "public"."app_dat_log_modificacion_orden"
  drop constraint "app_dat_log_modificacion_orden_id_operacion_fkey";

alter table "public"."app_dat_mesa_cuenta_abierta"
  drop constraint "app_dat_mesa_cuenta_mesa_fkey";

alter table "public"."app_dat_mesa_cuenta_abierta"
  drop constraint "app_dat_mesa_cuenta_tienda_fkey";

alter table "public"."app_dat_mesa_cuenta_item"
  drop constraint "app_dat_mesa_cuenta_item_cuenta_fkey";

alter table "public"."app_dat_mesa_cuenta_item"
  drop constraint "app_dat_mesa_cuenta_item_id_cocina_fkey";

alter table "public"."app_dat_mesa_cuenta_item"
  drop constraint "app_dat_mesa_cuenta_item_id_comanda_item_fkey";

alter table "public"."app_dat_mesas"
  drop constraint "app_dat_mesas_id_tienda_fkey";

alter table "public"."app_dat_movimiento_consignacion"
  drop constraint "app_dat_movimiento_consignacion_producto_fkey";

alter table "public"."app_dat_movimiento_consignacion"
  drop constraint "app_dat_movimiento_consignacion_usuario_fkey";

alter table "public"."app_dat_movimiento_consignacion"
  drop constraint "app_dat_movimiento_consignacion_venta_fkey";

alter table "public"."app_dat_notificaciones"
  drop constraint "app_dat_notificaciones_user_id_fkey";

alter table "public"."app_dat_numero_paquete_tienda"
  drop constraint "app_dat_numero_paquete_tienda_id_tienda_fkey";

alter table "public"."app_dat_operacion_contabilizacion_historial"
  drop constraint "app_dat_operacion_contabilizacion_historial_id_operacion_fkey";

alter table "public"."app_dat_operacion_extraccion"
  drop constraint "app_dat_operacion_extraccion_id_motivo_operacion_fkey";

alter table "public"."app_dat_operacion_extraccion"
  drop constraint "app_dat_operacion_extraccion_id_operacion_fkey";

alter table "public"."app_dat_operacion_recepcion"
  drop constraint "app_dat_operacion_recepcion_id_operacion_fkey";

alter table "public"."app_dat_operacion_transferencia"
  drop constraint "app_dat_operacion_transferencia_id_extraccion_fkey";

alter table "public"."app_dat_operacion_transferencia"
  drop constraint "app_dat_operacion_transferencia_id_operacion_fkey";

alter table "public"."app_dat_operacion_transferencia"
  drop constraint "app_dat_operacion_transferencia_id_recepcion_fkey";

alter table "public"."app_dat_operacion_venta"
  drop constraint "app_dat_operacion_venta_id_cliente_cxc_fkey";

alter table "public"."app_dat_operacion_venta"
  drop constraint "app_dat_operacion_venta_id_cliente_fkey";

alter table "public"."app_dat_operacion_venta"
  drop constraint "app_dat_operacion_venta_id_mesa_fkey";

alter table "public"."app_dat_operacion_venta"
  drop constraint "app_dat_operacion_venta_id_promocion_fkey";

alter table "public"."app_dat_operacion_venta"
  drop constraint "app_dat_operacion_venta_id_turno_apertura_fkey";

alter table "public"."app_dat_operacion_venta"
  drop constraint "app_operacion_extraccion_id_operacion_fkey";

alter table "public"."app_dat_operacion_venta"
  drop constraint "app_operacion_extraccion_id_tpv_fkey";

alter table "public"."app_dat_operaciones"
  drop constraint "app_dat_operaciones_id_tienda_fkey";

alter table "public"."app_dat_operaciones"
  drop constraint "app_dat_operaciones_id_tipo_operacion_fkey";

alter table "public"."app_dat_operaciones"
  drop constraint "app_dat_operaciones_uuid_fkey";

alter table "public"."app_dat_pago_venta"
  drop constraint "app_dat_pago_venta_creado_por_fkey";

alter table "public"."app_dat_pago_venta"
  drop constraint "app_dat_pago_venta_id_liquidacion_fkey";

alter table "public"."app_dat_pago_venta"
  drop constraint "app_dat_pago_venta_id_medio_pago_fkey";

alter table "public"."app_dat_pago_venta"
  drop constraint "app_dat_pago_venta_id_operacion_venta_fkey";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_confirmado_por";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_creado_por";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_opcion";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_presentacion";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_producto";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_tienda_destino";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_ubicacion_destino";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_ubicacion_origen";

alter table "public"."app_dat_pre_asignaciones"
  drop constraint "fk_pre_asignacion_variante";

alter table "public"."app_dat_precio_costo"
  drop constraint "app_dat_precio_costo_id_presentacion_fkey";

alter table "public"."app_dat_precio_costo"
  drop constraint "app_dat_precio_costo_id_producto_fkey";

alter table "public"."app_dat_precio_general_tienda"
  drop constraint "app_dat_precio_general_tienda_id_tienda_fkey";

alter table "public"."app_dat_precio_tpv"
  drop constraint "app_dat_precio_tpv_id_producto_fkey";

alter table "public"."app_dat_precio_tpv"
  drop constraint "app_dat_precio_tpv_id_tpv_fkey";

alter table "public"."app_dat_precio_venta"
  drop constraint "app_dat_precio_venta_id_producto_fkey";

alter table "public"."app_dat_precio_venta"
  drop constraint "app_dat_precio_venta_id_variante_fkey";

alter table "public"."app_dat_preferencias_notificaciones"
  drop constraint "app_dat_preferencias_notificaciones_id_usuario_fkey";

alter table "public"."app_dat_presentacion_unidad_medida"
  drop constraint "fk_presentacion_um_presentacion";

alter table "public"."app_dat_presentacion_unidad_medida"
  drop constraint "fk_presentacion_um_producto";

alter table "public"."app_dat_presentacion_unidad_medida"
  drop constraint "fk_presentacion_um_unidad_medida";

alter table "public"."app_dat_produccion_tanda"
  drop constraint "app_dat_produccion_tanda_id_almacen_fkey";

alter table "public"."app_dat_produccion_tanda"
  drop constraint "app_dat_produccion_tanda_id_cocina_fkey";

alter table "public"."app_dat_produccion_tanda"
  drop constraint "app_dat_produccion_tanda_id_producto_fkey";

alter table "public"."app_dat_produccion_tanda"
  drop constraint "app_dat_produccion_tanda_id_ubicacion_fkey";

alter table "public"."app_dat_producto"
  drop constraint "app_dat_producto_id_categoria_fkey";

alter table "public"."app_dat_producto"
  drop constraint "app_dat_producto_id_cocina_fkey";

alter table "public"."app_dat_producto"
  drop constraint "app_dat_producto_id_proveedor_fkey";

alter table "public"."app_dat_producto"
  drop constraint "app_dat_producto_id_tienda_fkey";

alter table "public"."app_dat_producto_abc"
  drop constraint "app_dat_producto_abc_id_producto_fkey";

alter table "public"."app_dat_producto_abc"
  drop constraint "app_dat_producto_abc_id_proveedor_fkey";

alter table "public"."app_dat_producto_consignacion"
  drop constraint "app_dat_producto_consignacion_contrato_fkey";

alter table "public"."app_dat_producto_consignacion"
  drop constraint "app_dat_producto_consignacion_operacion_extraccion_fkey";

alter table "public"."app_dat_producto_consignacion"
  drop constraint "app_dat_producto_consignacion_operacion_recepcion_fkey";

alter table "public"."app_dat_producto_consignacion"
  drop constraint "app_dat_producto_consignacion_presentacion_fkey";

alter table "public"."app_dat_producto_consignacion"
  drop constraint "app_dat_producto_consignacion_producto_fkey";

alter table "public"."app_dat_producto_consignacion"
  drop constraint "app_dat_producto_consignacion_ubicacion_fkey";

alter table "public"."app_dat_producto_consignacion"
  drop constraint "app_dat_producto_consignacion_variante_fkey";

alter table "public"."app_dat_producto_consignacion_duplicado"
  drop constraint "app_dat_producto_consignacion_dup_id_contrato_consignacion_fkey";

alter table "public"."app_dat_producto_consignacion_duplicado"
  drop constraint "app_dat_producto_consignacion_duplic_id_producto_duplicado_fkey";

alter table "public"."app_dat_producto_consignacion_duplicado"
  drop constraint "app_dat_producto_consignacion_duplica_id_producto_original_fkey";

alter table "public"."app_dat_producto_consignacion_duplicado"
  drop constraint "app_dat_producto_consignacion_duplicado_id_tienda_destino_fkey";

alter table "public"."app_dat_producto_consignacion_duplicado"
  drop constraint "app_dat_producto_consignacion_duplicado_id_tienda_origen_fkey";

alter table "public"."app_dat_producto_consignacion_duplicado"
  drop constraint "fk_pcd_presentacion_duplicada";

alter table "public"."app_dat_producto_consignacion_duplicado"
  drop constraint "fk_pcd_presentacion_original";

alter table "public"."app_dat_producto_etiquetas"
  drop constraint "app_dat_producto_etiquetas_id_producto_fkey";

alter table "public"."app_dat_producto_garantia"
  drop constraint "fk_producto_garantia_producto";

alter table "public"."app_dat_producto_garantia"
  drop constraint "fk_producto_garantia_tipo";

alter table "public"."app_dat_producto_ingredientes"
  drop constraint "app_dat_producto_ingredientes_id_producto_elaborado_fkey";

alter table "public"."app_dat_producto_ingredientes"
  drop constraint "app_dat_producto_ingredientes_ingrediente_fkey";

alter table "public"."app_dat_producto_multimedias"
  drop constraint "app_producto_multimedias_id_producto_fkey";

alter table "public"."app_dat_producto_presentacion"
  drop constraint "app_dat_producto_presentacion_id_presentacion_fkey";

alter table "public"."app_dat_producto_presentacion"
  drop constraint "app_dat_producto_presentacion_id_producto_fkey";

alter table "public"."app_dat_producto_rating"
  drop constraint "app_dat_producto_rating_id_producto_fkey";

alter table "public"."app_dat_producto_rating"
  drop constraint "app_dat_producto_rating_id_usuario_fkey";

alter table "public"."app_dat_producto_unidades"
  drop constraint "app_dat_producto_unidades_producto_fkey";

alter table "public"."app_dat_producto_unidades"
  drop constraint "app_dat_producto_unidades_unidad_fkey";

alter table "public"."app_dat_productos_subcategorias"
  drop constraint "app_dat_productos_subcategorias_id_producto_fkey";

alter table "public"."app_dat_productos_subcategorias"
  drop constraint "app_dat_productos_subcategorias_id_sub_categoria_fkey";

alter table "public"."app_dat_proveedor"
  drop constraint "app_dat_proveedor_idtienda_fkey";

alter table "public"."app_dat_recepcion_productos"
  drop constraint "app_dat_recepcion_productos_id_opcion_variante_fkey";

alter table "public"."app_dat_recepcion_productos"
  drop constraint "app_dat_recepcion_productos_id_operacion_fkey";

alter table "public"."app_dat_recepcion_productos"
  drop constraint "app_dat_recepcion_productos_id_presentacion_fkey";

alter table "public"."app_dat_recepcion_productos"
  drop constraint "app_dat_recepcion_productos_id_producto_fkey";

alter table "public"."app_dat_recepcion_productos"
  drop constraint "app_dat_recepcion_productos_id_proveedor_fkey";

alter table "public"."app_dat_recepcion_productos"
  drop constraint "app_dat_recepcion_productos_id_ubicacion_fkey";

alter table "public"."app_dat_recepcion_productos"
  drop constraint "app_dat_recepcion_productos_id_variante_fkey";

alter table "public"."app_dat_recursos_humanos"
  drop constraint "app_dat_recursos_humanos_id_tienda_fkey";

alter table "public"."app_dat_recursos_humanos"
  drop constraint "app_dat_recursos_humanos_id_trabajador_fkey";

alter table "public"."app_dat_recursos_humanos"
  drop constraint "app_dat_recursos_humanos_uuid_fkey";

alter table "public"."app_dat_servicentro_producto"
  drop constraint "app_dat_servicentro_producto_id_producto_fkey";

alter table "public"."app_dat_servicentro_producto"
  drop constraint "app_dat_servicentro_producto_id_tienda_fkey";

alter table "public"."app_dat_servicentro_producto"
  drop constraint "app_dat_servicentro_producto_id_tpv_fkey";

alter table "public"."app_dat_subcategorias"
  drop constraint "app_dat_subcategorias_idcategoria_fkey";

alter table "public"."app_dat_superadmin"
  drop constraint "app_dat_superadmin_id_rol_fkey";

alter table "public"."app_dat_superadmin"
  drop constraint "app_dat_superadmin_uuid_fkey";

alter table "public"."app_dat_supervisor"
  drop constraint "app_dat_supervisor_id_tienda_fkey";

alter table "public"."app_dat_supervisor"
  drop constraint "app_dat_supervisor_id_trabajador_fkey";

alter table "public"."app_dat_supervisor"
  drop constraint "app_dat_supervisor_uuid_fkey";

alter table "public"."app_dat_suscripcion_notificaciones_producto"
  drop constraint "app_dat_suscripcion_notificaciones_producto_id_producto_fkey";

alter table "public"."app_dat_suscripcion_notificaciones_producto"
  drop constraint "app_dat_suscripcion_notificaciones_producto_id_usuario_fkey";

alter table "public"."app_dat_suscripcion_notificaciones_tienda"
  drop constraint "app_dat_suscripcion_notificaciones_tienda_id_tienda_fkey";

alter table "public"."app_dat_suscripcion_notificaciones_tienda"
  drop constraint "app_dat_suscripcion_notificaciones_tienda_id_usuario_fkey";

alter table "public"."app_dat_tienda"
  drop constraint "fk_tienda_layout_catalogo";

alter table "public"."app_dat_tienda_rating"
  drop constraint "app_dat_tienda_rating_id_tienda_fkey";

alter table "public"."app_dat_tienda_rating"
  drop constraint "app_dat_tienda_rating_id_usuario_fkey";

alter table "public"."app_dat_tpv"
  drop constraint "app_dat_tpv_id_almacen_fkey";

alter table "public"."app_dat_tpv"
  drop constraint "app_dat_tpv_id_tienda_fkey";

alter table "public"."app_dat_tpv_cocina"
  drop constraint "app_dat_tpv_cocina_cocina_fkey";

alter table "public"."app_dat_tpv_cocina"
  drop constraint "app_dat_tpv_cocina_tpv_fkey";

alter table "public"."app_dat_tpv_dispositivos"
  drop constraint "app_dat_tpv_dispositivos_fkey";

alter table "public"."app_dat_trabajadores"
  drop constraint "app_dat_trabajadores_id_roll_fkey";

alter table "public"."app_dat_trabajadores"
  drop constraint "app_dat_trabajadores_id_tienda_fkey";

alter table "public"."app_dat_trabajadores"
  drop constraint "app_dat_trabajadores_uuid_fkey";

alter table "public"."app_dat_turno_trabajadores"
  drop constraint "app_dat_turno_trabajadores_id_trabajador_fkey";

alter table "public"."app_dat_turno_trabajadores"
  drop constraint "app_dat_turno_trabajadores_id_turno_fkey";

alter table "public"."app_dat_turno_trabajadores"
  drop constraint "app_dat_turno_trabajadores_manual_changed_fkey";

alter table "public"."app_dat_variantes"
  drop constraint "app_dat_variantes_id_atributo_fkey";

alter table "public"."app_dat_variantes"
  drop constraint "app_dat_variantes_id_sub_categoria_fkey";

alter table "public"."app_dat_vendedor"
  drop constraint "app_dat_vendedor_id_tpv_fkey";

alter table "public"."app_dat_vendedor"
  drop constraint "app_dat_vendedor_id_trabajador_fkey";

alter table "public"."app_dat_vendedor"
  drop constraint "app_dat_vendedor_uuid_fkey";

alter table "public"."app_dat_vendedor_productos_default"
  drop constraint "app_dat_vendedor_productos_default_id_producto_fkey";

alter table "public"."app_dat_vendedor_productos_default"
  drop constraint "app_dat_vendedor_productos_default_id_tienda_fkey";

alter table "public"."app_dat_vendedor_productos_default"
  drop constraint "app_dat_vendedor_productos_default_uuid_fkey";

alter table "public"."app_inf_presentacion_producto"
  drop constraint "app_inf_presentacion_producto_id_presentacion_fkey";

alter table "public"."app_inf_presentacion_producto"
  drop constraint "app_inf_presentacion_producto_id_producto_fkey";

alter table "public"."app_licencias_offline"
  drop constraint "app_licencias_offline_plan_id_fkey";

alter table "public"."app_mkt_campanas"
  drop constraint "app_mkt_campanas_id_tienda_fkey";

alter table "public"."app_mkt_campanas"
  drop constraint "app_mkt_campanas_id_tipo_campana_fkey";

alter table "public"."app_mkt_cliente_promociones"
  drop constraint "app_mkt_cliente_promociones_id_cliente_fkey";

alter table "public"."app_mkt_cliente_promociones"
  drop constraint "app_mkt_cliente_promociones_id_operacion_fkey";

alter table "public"."app_mkt_cliente_promociones"
  drop constraint "app_mkt_cliente_promociones_id_promocion_fkey";

alter table "public"."app_mkt_comunicacion_clientes"
  drop constraint "app_mkt_comunicacion_clientes_id_cliente_fkey";

alter table "public"."app_mkt_comunicacion_clientes"
  drop constraint "app_mkt_comunicacion_clientes_id_comunicacion_fkey";

alter table "public"."app_mkt_comunicaciones"
  drop constraint "app_mkt_comunicaciones_id_campana_fkey";

alter table "public"."app_mkt_comunicaciones"
  drop constraint "app_mkt_comunicaciones_id_segmento_fkey";

alter table "public"."app_mkt_comunicaciones"
  drop constraint "app_mkt_comunicaciones_id_tienda_fkey";

alter table "public"."app_mkt_comunicaciones"
  drop constraint "app_mkt_comunicaciones_id_tipo_campana_fkey";

alter table "public"."app_mkt_eventos_fidelizacion"
  drop constraint "app_mkt_eventos_fidelizacion_id_cliente_fkey";

alter table "public"."app_mkt_eventos_fidelizacion"
  drop constraint "app_mkt_eventos_fidelizacion_id_operacion_fkey";

alter table "public"."app_mkt_eventos_fidelizacion"
  drop constraint "app_mkt_eventos_fidelizacion_id_tienda_fkey";

alter table "public"."app_mkt_promocion_productos"
  drop constraint "app_mkt_promocion_productos_id_categoria_fkey";

alter table "public"."app_mkt_promocion_productos"
  drop constraint "app_mkt_promocion_productos_id_producto_fkey";

alter table "public"."app_mkt_promocion_productos"
  drop constraint "app_mkt_promocion_productos_id_promocion_fkey";

alter table "public"."app_mkt_promocion_productos"
  drop constraint "app_mkt_promocion_productos_id_subcategoria_fkey";

alter table "public"."app_mkt_promocion_segmento"
  drop constraint "app_mkt_promocion_segmento_id_promocion_fkey";

alter table "public"."app_mkt_promocion_segmento"
  drop constraint "app_mkt_promocion_segmento_id_segmento_fkey";

alter table "public"."app_mkt_promociones"
  drop constraint "app_mkt_promociones_id_campana_fkey";

alter table "public"."app_mkt_promociones"
  drop constraint "app_mkt_promociones_id_tienda_fkey";

alter table "public"."app_mkt_promociones"
  drop constraint "app_mkt_promociones_id_tipo_promocion_fkey";

alter table "public"."app_mkt_promociones"
  drop constraint "fk_promocion_medio_pago";

alter table "public"."app_mkt_segmentos"
  drop constraint "app_mkt_segmentos_id_tienda_fkey";

alter table "public"."app_nom_conversiones_unidades"
  drop constraint "app_nom_conversiones_unidades_destino_fkey";

alter table "public"."app_nom_conversiones_unidades"
  drop constraint "app_nom_conversiones_unidades_origen_fkey";

alter table "public"."app_nom_motivo_recepcion"
  drop constraint "app_nom_motivo_recepcion_id_tipo_operacion_fkey";

alter table "public"."app_nom_subcategoria_gasto"
  drop constraint "app_nom_subcategoria_gasto_id_categoria_gasto_fkey";

alter table "public"."app_suscripciones"
  drop constraint "app_suscripciones_creado_por_fkey";

alter table "public"."app_suscripciones"
  drop constraint "app_suscripciones_id_agente_fkey";

alter table "public"."app_suscripciones"
  drop constraint "app_suscripciones_id_plan_fkey";

alter table "public"."app_suscripciones"
  drop constraint "app_suscripciones_id_tienda_fkey";

alter table "public"."app_suscripciones_historial"
  drop constraint "app_suscripciones_historial_cambiado_por_fkey";

alter table "public"."app_suscripciones_historial"
  drop constraint "app_suscripciones_historial_id_suscripcion_fkey";

alter table "public"."app_suscripciones_renovaciones_resumen"
  drop constraint "app_suscripciones_renovaciones_resumen_id_plan_fkey";

alter table "public"."app_suscripciones_renovaciones_resumen"
  drop constraint "app_suscripciones_renovaciones_resumen_id_tienda_fkey";

alter table "public"."app_wapi_destinatario"
  drop constraint "app_wapi_destinatario_id_sesion_fkey";

alter table "public"."app_wapi_destinatario"
  drop constraint "app_wapi_destinatario_id_tienda_fkey";

alter table "public"."app_wapi_envio_log"
  drop constraint "app_wapi_envio_log_id_producto_fkey";

alter table "public"."app_wapi_envio_log"
  drop constraint "app_wapi_envio_log_id_programacion_fkey";

alter table "public"."app_wapi_envio_log"
  drop constraint "app_wapi_envio_log_id_sesion_fkey";

alter table "public"."app_wapi_envio_log"
  drop constraint "app_wapi_envio_log_id_tienda_fkey";

alter table "public"."app_wapi_licencia"
  drop constraint "app_wapi_licencia_id_plan_fkey";

alter table "public"."app_wapi_licencia"
  drop constraint "app_wapi_licencia_id_tienda_fkey";

alter table "public"."app_wapi_programacion"
  drop constraint "app_wapi_programacion_id_sesion_fkey";

alter table "public"."app_wapi_programacion"
  drop constraint "app_wapi_programacion_id_tienda_fkey";

alter table "public"."app_wapi_programacion_destinatario"
  drop constraint "app_wapi_programacion_destinatario_id_destinatario_fkey";

alter table "public"."app_wapi_programacion_destinatario"
  drop constraint "app_wapi_programacion_destinatario_id_programacion_fkey";

alter table "public"."app_wapi_programacion_producto"
  drop constraint "app_wapi_programacion_producto_id_producto_fkey";

alter table "public"."app_wapi_programacion_producto"
  drop constraint "app_wapi_programacion_producto_id_programacion_fkey";

alter table "public"."app_wapi_sesion"
  drop constraint "app_wapi_sesion_created_by_fkey";

alter table "public"."app_wapi_sesion"
  drop constraint "app_wapi_sesion_id_tienda_fkey";

alter table "public"."auditor"
  drop constraint "app_dat_auditor_id_tienda_fkey";

alter table "public"."auditor"
  drop constraint "app_dat_auditor_id_trabajador_fkey";

alter table "public"."auditor"
  drop constraint "app_dat_auditor_uuid_fkey";

alter table "public"."codigo_producto"
  drop constraint "codigo_producto_created_by_fkey";

alter table "public"."codigo_producto"
  drop constraint "codigo_producto_id_producto_fkey";

alter table "public"."dep_dat_banco"
  drop constraint "dep_dat_banco_id_moneda_fkey";

alter table "public"."dep_dat_deposito"
  drop constraint "dep_dat_deposito_id_banco_fkey";

alter table "public"."dep_dat_deposito"
  drop constraint "dep_dat_deposito_id_estado_fkey";

alter table "public"."dep_dat_deposito"
  drop constraint "dep_dat_deposito_id_tipo_extraccion_fkey";

alter table "public"."dep_dat_deposito_foto"
  drop constraint "dep_dat_deposito_foto_id_deposito_fkey";

alter table "public"."dep_dat_recarga_saldo"
  drop constraint "dep_dat_recarga_saldo_id_banco_fkey";

alter table "public"."dep_dat_saldo"
  drop constraint "dep_dat_saldo_id_banco_fkey";

alter table "public"."dep_hist_estado_deposito"
  drop constraint "dep_hist_estado_deposito_id_deposito_fkey";

alter table "public"."dep_hist_estado_deposito"
  drop constraint "dep_hist_estado_deposito_id_estado_anterior_fkey";

alter table "public"."dep_hist_estado_deposito"
  drop constraint "dep_hist_estado_deposito_id_estado_nuevo_fkey";

alter table "public"."dep_hist_saldo"
  drop constraint "dep_hist_saldo_id_banco_fkey";

alter table "public"."dep_hist_saldo"
  drop constraint "dep_hist_saldo_id_recarga_fkey";

alter table "public"."hr_dat_asistencia"
  drop constraint "hr_dat_asistencia_cerrado_por_fkey";

alter table "public"."hr_dat_asistencia"
  drop constraint "hr_dat_asistencia_id_tienda_fkey";

alter table "public"."hr_dat_asistencia"
  drop constraint "hr_dat_asistencia_id_trabajador_fkey";

alter table "public"."hr_dat_asistencia"
  drop constraint "hr_dat_asistencia_registrado_por_fkey";

alter table "public"."hr_dat_auditoria_salario"
  drop constraint "hr_dat_auditoria_salario_id_tienda_fkey";

alter table "public"."hr_dat_auditoria_salario"
  drop constraint "hr_dat_auditoria_salario_id_trabajador_fkey";

alter table "public"."hr_dat_auditoria_salario"
  drop constraint "hr_dat_auditoria_salario_modificado_por_fkey";

alter table "public"."imp_dat_factura"
  drop constraint "imp_dat_factura_id_estado_fkey";

alter table "public"."imp_dat_factura_foto"
  drop constraint "imp_dat_factura_foto_id_factura_fkey";

alter table "public"."imp_hist_estado_factura"
  drop constraint "imp_hist_estado_factura_id_estado_anterior_fkey";

alter table "public"."imp_hist_estado_factura"
  drop constraint "imp_hist_estado_factura_id_estado_nuevo_fkey";

alter table "public"."imp_hist_estado_factura"
  drop constraint "imp_hist_estado_factura_id_factura_fkey";

alter table "public"."imp_hist_saldo"
  drop constraint "imp_hist_saldo_id_recarga_fkey";

alter table "public"."municipios"
  drop constraint "municipios_provincia_fkey";

alter table "public"."paqueteria_ordenes"
  drop constraint "paqueteria_ordenes_id_operacion_fkey";

alter table "public"."paqueteria_ordenes"
  drop constraint "paqueteria_ordenes_id_orden_carnaval_fkey";

alter table "public"."prv_dat_factura"
  drop constraint "prv_dat_factura_id_estado_fkey";

alter table "public"."prv_dat_factura"
  drop constraint "prv_dat_factura_id_proveedor_fkey";

alter table "public"."prv_dat_factura_foto"
  drop constraint "prv_dat_factura_foto_id_factura_fkey";

alter table "public"."prv_dat_proveedor_config"
  drop constraint "prv_dat_proveedor_config_id_moneda_fkey";

alter table "public"."prv_dat_proveedor_config"
  drop constraint "prv_dat_proveedor_config_id_proveedor_fkey";

alter table "public"."prv_dat_recarga_saldo"
  drop constraint "prv_dat_recarga_saldo_id_proveedor_fkey";

alter table "public"."prv_dat_saldo"
  drop constraint "prv_dat_saldo_id_proveedor_fkey";

alter table "public"."prv_hist_estado_factura"
  drop constraint "prv_hist_estado_factura_id_estado_anterior_fkey";

alter table "public"."prv_hist_estado_factura"
  drop constraint "prv_hist_estado_factura_id_estado_nuevo_fkey";

alter table "public"."prv_hist_estado_factura"
  drop constraint "prv_hist_estado_factura_id_factura_fkey";

alter table "public"."prv_hist_saldo"
  drop constraint "prv_hist_saldo_id_proveedor_fkey";

alter table "public"."prv_hist_saldo"
  drop constraint "prv_hist_saldo_id_recarga_fkey";

alter table "public"."relation_products_carnaval"
  drop constraint "fk__products_carnaval_id_producto_carnaval";

alter table "public"."relation_products_carnaval"
  drop constraint "fk__products_carnaval_id_producto";

alter table "public"."relation_products_carnaval"
  drop constraint "fk__products_carnaval_id_ubicacion";

alter table "public"."seg_roll"
  drop constraint "seg_roll_id_tienda_fkey";

alter table "public"."tasa_cambio_extraoficial"
  drop constraint "tasa_cambio_extraoficial_id_moneda_destino_fkey";

alter table "public"."tasa_cambio_extraoficial"
  drop constraint "tasa_cambio_extraoficial_id_moneda_origen_fkey";

alter table "public"."tasa_cambio_extraoficial"
  drop constraint "tasa_cambio_extraoficial_id_tienda_fkey";

alter table "public"."tasas_conversion"
  drop constraint "tasas_conversion_moneda_destino_fkey";

alter table "public"."tasas_conversion"
  drop constraint "tasas_conversion_moneda_origen_fkey";

drop function "carnavalapp"."delete_proveedor_completo"(bigint);

drop function "carnavalapp"."destacados_activos"(integer);

drop function "carnavalapp"."fn_admin_config_get"();

drop function "carnavalapp"."fn_admin_kpi_by_rail"(date, date);

drop function "carnavalapp"."fn_admin_kpi_overview"(date, date);

drop function "carnavalapp"."fn_analytics_ingest"(jsonb);

drop function "carnavalapp"."fn_assert_usuario_uuid"(uuid);

drop function "carnavalapp"."fn_carrito_clear"(bigint);

drop function "carnavalapp"."fn_carrito_delete_line"(bigint);

drop function "carnavalapp"."fn_carrito_find_line"(bigint, uuid);

drop function "carnavalapp"."fn_carrito_list"(uuid);

drop function "carnavalapp"."fn_carrito_update_line"(bigint, smallint, numeric, numeric, smallint, boolean);

drop function "carnavalapp"."fn_carrito_upsert_line"(bigint, smallint, bigint, numeric, numeric, smallint, boolean, uuid);

drop function "carnavalapp"."fn_categorias_alimentos"();

drop function "carnavalapp"."fn_categorias_home"(integer);

drop function "carnavalapp"."fn_categorias_list"();

drop function "carnavalapp"."fn_coord_valida"(text);

drop function "carnavalapp"."fn_crear_operacion_desde_orden"();

drop function "carnavalapp"."fn_crear_orden_carnaval"(bigint, jsonb, real, text, text, text, text, text, numeric, text, numeric, real, real, text, real, boolean, text, text, boolean, integer, text);

drop function "carnavalapp"."fn_crear_orden_mine"(jsonb, real, text, text, text, text, text, numeric, text, numeric, real, real, text, real, boolean, text, text, boolean, integer, text, bigint);

drop function "carnavalapp"."fn_current_usuario_id"();

drop function "carnavalapp"."fn_direcciones_delete"(bigint);

drop function "carnavalapp"."fn_direcciones_insert"(jsonb, bigint);

drop function "carnavalapp"."fn_direcciones_list"(bigint);

drop function "carnavalapp"."fn_direcciones_update"(bigint, jsonb);

drop function "carnavalapp"."fn_estampar_referal_en_ordenes_abiertas"(bigint, text, integer);

drop function "carnavalapp"."fn_kpi_daily_rebuild"(date);

drop function "carnavalapp"."fn_municipio_get"(bigint);

drop function "carnavalapp"."fn_municipios_by_provincia"(integer);

drop function "carnavalapp"."fn_notificaciones_list"(text);

drop function "carnavalapp"."fn_notificaciones_mark_all_read"(text);

drop function "carnavalapp"."fn_notificaciones_mark_read"(bigint);

drop function "carnavalapp"."fn_ordenes_ruta"(bigint, text[], date, date);

drop function "carnavalapp"."fn_order_crear_paquete"(real, text, text, text, text, text, numeric, numeric, text, text, text, text, text, text);

drop function "carnavalapp"."fn_order_crear_paquete"(real, text, text, text, text, text, numeric, numeric, text, text, text, text, text, text, real, real, real);

drop function "carnavalapp"."fn_order_details_by_order"(bigint);

drop function "carnavalapp"."fn_order_get"(bigint);

drop function "carnavalapp"."fn_order_patch"(bigint, jsonb);

drop function "carnavalapp"."fn_order_resolve_direccion"(bigint);

drop function "carnavalapp"."fn_order_resolve_direccion_row"(bigint);

drop function "carnavalapp"."fn_order_resolve_direccion_row_v2"(bigint);

drop function "carnavalapp"."fn_order_resolve_direccion_v2"(bigint);

drop function "carnavalapp"."fn_order_update_status"(bigint, text, jsonb);

drop function "carnavalapp"."fn_orders_by_referral"(text);

drop function "carnavalapp"."fn_orders_list_mine"();

drop function "carnavalapp"."fn_parse_coordenadas"(text);

drop function "carnavalapp"."fn_password_reset_cerrar_sesiones"(uuid);

drop function "carnavalapp"."fn_password_reset_crear"(text, text);

drop function "carnavalapp"."fn_password_reset_limpiar"();

drop function "carnavalapp"."fn_password_reset_validar"(text, text);

drop function "carnavalapp"."fn_posicion_repartidor_by_repartidor"(integer);

drop function "carnavalapp"."fn_producto_first_in_category"(integer);

drop function "carnavalapp"."fn_producto_get"(bigint);

drop function "carnavalapp"."fn_producto_social_proof"(bigint);

drop function "carnavalapp"."fn_productos_by_category"(integer, integer, boolean);

drop function "carnavalapp"."fn_productos_by_ids"(bigint[]);

drop function "carnavalapp"."fn_productos_by_proveedor"(bigint);

drop function "carnavalapp"."fn_productos_mas_vendidos"(integer, integer);

drop function "carnavalapp"."fn_productos_page"(integer, integer, integer, boolean, boolean, bigint, numeric, numeric, text);

drop function "carnavalapp"."fn_productos_regalos"(integer, integer);

drop function "carnavalapp"."fn_productos_search"(text, integer, integer, bigint, numeric, numeric, boolean, text);

drop function "carnavalapp"."fn_productos_sugerencias"(integer);

drop function "carnavalapp"."fn_proveedor_get"(bigint);

drop function "carnavalapp"."fn_proveedores_activos"();

drop function "carnavalapp"."fn_proveedores_list"(boolean, text);

drop function "carnavalapp"."fn_provincias_list"();

drop function "carnavalapp"."fn_recs_for_cart"(bigint[], integer);

drop function "carnavalapp"."fn_referidos_stats"(text);

drop function "carnavalapp"."fn_reparar_ubicaciones_direcciones"();

drop function "carnavalapp"."fn_repartidor_nombre"(bigint);

drop function "carnavalapp"."fn_require_auth_uid"();

drop function "carnavalapp"."fn_resolver_ubicacion"(text, text);

drop function "carnavalapp"."fn_ruta_coords"(bigint, text[], date, date);

drop function "carnavalapp"."fn_sub_categorias_by_ids"(bigint[]);

drop function "carnavalapp"."fn_ubicacion_por_coordenadas"(text);

drop function "carnavalapp"."fn_ubicacion_por_nombre"(text);

drop function "carnavalapp"."fn_usuario_apply_referral"(text, uuid);

drop function "carnavalapp"."fn_usuario_ensure_referral_code"(text, uuid);

drop function "carnavalapp"."fn_usuario_get_by_uuid"(uuid);

drop function "carnavalapp"."fn_usuario_insert_profile"(text, text, text, text, jsonb, text, uuid);

drop function "carnavalapp"."fn_usuario_referral_exists"(text);

drop function "carnavalapp"."fn_usuario_update_currency"(text, uuid);

drop function "carnavalapp"."fn_usuario_update_profile"(text, text, text, jsonb, uuid);

drop function "carnavalapp"."productos_relacionados"(integer, text, integer, integer, integer);

drop function "carnavalapp"."recien_llegados"(integer);

drop function "carnavalapp"."verificar_stock_real_inventtia"(bigint);

drop function "flow"."_admin_puede_local_servicio"(uuid, integer);

drop function "flow"."_admin_puede_recurso"(uuid, integer);

drop function "flow"."_descontar_tramos_turno"(integer, date, integer);

drop function "flow"."_liberar_tramos_turno"(integer, date, integer);

drop function "flow"."_ls_tiene_recursos"(integer);

drop function "flow"."_resolver_perfil_tercero"(text, text, text, text);

drop function "flow"."_upsert_plan_tramos_recurso"(integer, date, integer);

drop function "flow"."admin_actualizar_datos_reserva"(integer, jsonb);

drop function "flow"."admin_cancelar_agenda"(integer);

drop function "flow"."admin_crear_reserva_directa"(integer, date, integer, jsonb, uuid, integer);

drop function "flow"."admin_create_perfil"(uuid, text, text, text, text);

drop function "flow"."admin_create_plan_servicio"(integer, date, integer);

drop function "flow"."admin_create_user"(text, text, text, text, text, text);

drop function "flow"."admin_delete_plan_servicio"(integer);

drop function "flow"."admin_eliminar_recurso"(uuid, integer);

drop function "flow"."admin_eliminar_tramo"(uuid, integer);

drop function "flow"."admin_eliminar_turno"(uuid, integer);

drop function "flow"."admin_entidades_de_usuario"(uuid);

drop function "flow"."admin_existe_ci"(text, uuid);

drop function "flow"."admin_existe_plan_fecha"(integer, date, integer);

drop function "flow"."admin_generar_plan_mensual"(uuid, integer, integer, integer);

drop function "flow"."admin_get_perfil"(uuid);

drop function "flow"."admin_get_plan_dias"(uuid, integer, date, date);

drop function "flow"."admin_get_plan_servicios"(integer);

drop function "flow"."admin_guardar_config_plan"(uuid, integer, jsonb, boolean);

drop function "flow"."admin_guardar_datos_servicio"(uuid, integer, jsonb, boolean, jsonb);

drop function "flow"."admin_guardar_recurso"(uuid, integer, text, integer, integer, boolean, integer);

drop function "flow"."admin_guardar_tramo"(uuid, integer, text, integer, integer, boolean, integer);

drop function "flow"."admin_guardar_tramo_transporte"(uuid, integer, text, character varying, integer, boolean);

drop function "flow"."admin_guardar_turno"(uuid, integer, text, jsonb, integer, boolean, integer, jsonb);

drop function "flow"."admin_listar_admins"(integer);

drop function "flow"."admin_listar_agendas"(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone);

drop function "flow"."admin_listar_agendas_por_estado"(uuid, integer, integer, integer, integer);

drop function "flow"."admin_listar_entidades"(uuid);

drop function "flow"."admin_listar_locales"(uuid, integer);

drop function "flow"."admin_listar_locales_servicios"(uuid, integer, integer);

drop function "flow"."admin_listar_recursos"(uuid, integer);

drop function "flow"."admin_listar_salas_espera"(uuid, integer, integer, integer);

drop function "flow"."admin_listar_servicios"(uuid, integer);

drop function "flow"."admin_listar_vendedores"(integer);

drop function "flow"."admin_obtener_config_plan"(uuid, integer);

drop function "flow"."admin_planificar_dia"(uuid, integer, date, jsonb, integer);

drop function "flow"."admin_reservar_pasaje_omnibus"(uuid, integer, character varying, date, integer, date, integer, integer, jsonb, text);

drop function "flow"."admin_set_reserva_directa"(uuid, integer, boolean);

drop function "flow"."admin_update_perfil"(uuid, text, text, text, text);

drop function "flow"."admin_update_plan_servicio"(integer, date, integer);

drop function "flow"."bot_procesar_plan"(bigint);

drop function "flow"."bot_procesar_recurso_dia"(integer, date);

drop function "flow"."bot_sweep"();

drop function "flow"."calcular_precio_reserva"(integer, jsonb, text, integer);

drop function "flow"."calcular_precio_turno"(integer, integer, jsonb, text, integer);

drop function "flow"."cliente_actualizar_fecha_regla"(uuid, integer, date);

drop function "flow"."cliente_cancelar_reserva"(uuid, integer);

drop function "flow"."cliente_entrar_sala_espera"(uuid, integer, timestamp without time zone, jsonb, boolean, text, text, text, text);

drop function "flow"."cliente_entrar_sala_espera"(uuid, integer, timestamp without time zone, jsonb, boolean, text, text, text, text, integer);

drop function "flow"."cliente_listar_servicios"(integer);

drop function "flow"."cliente_obtener_agendas"(uuid, integer);

drop function "flow"."cliente_obtener_disponibilidad"(integer, date, date);

drop function "flow"."cliente_obtener_disponibilidad_transporte"(integer, date, character varying);

drop function "flow"."cliente_obtener_fechas_disponibles_transporte"(integer, character varying);

drop function "flow"."cliente_obtener_locales"(integer);

drop function "flow"."cliente_obtener_salas_espera"(uuid);

drop function "flow"."cliente_obtener_servicios"(integer, integer, integer, text, text, text, text);

drop function "flow"."cliente_reservar_directo"(uuid, integer, date, integer, jsonb, boolean, text, text, text, text, text, integer);

drop function "flow"."cliente_reservar_pasaje_omnibus"(uuid, integer, character varying, date, integer, date, integer, integer, jsonb, text, boolean, text, text, text, text);

drop function "flow"."cliente_salir_sala_espera"(uuid, integer);

drop function "flow"."es_admin_o_dueño_de_entidad_de_agenda"(integer);

drop function "flow"."get_uuid_by_email"(text);

drop function "flow"."is_entidad_admin"(integer);

drop function "flow"."staff_cancelar_reserva"(integer);

drop function "flow"."staff_marcar_estado_agenda"(integer, integer);

drop function "flow"."vendedor_entidades_de_usuario"(uuid);

drop function "flow"."vendedor_listar_agendas"(uuid, integer, integer, integer, integer, timestamp without time zone, timestamp without time zone);

drop function "flow"."vendedor_listar_agendas_por_estado"(uuid, integer, integer, integer, integer);

drop function "muevete"."complete_ride_payment"(text, uuid, bigint, bigint, numeric);

drop function "muevete"."complete_ride_payment"(text, uuid, bigint, bigint, numeric, numeric);

drop function "muevete"."fn_aprobar_solicitud_plan"(bigint, uuid, text, text, date);

drop function "muevete"."fn_cambiar_estado_carga"(bigint, text, uuid, bigint, text, jsonb);

drop function "muevete"."fn_crear_suscripcion_gratis"(uuid, text);

drop function "muevete"."fn_crear_suscripcion_trial"(uuid, text);

drop function "muevete"."fn_marcar_carga_tomada"(bigint, bigint, uuid, uuid, text);

drop function "muevete"."fn_proximo_dia_2"(date);

drop function "muevete"."fn_rechazar_solicitud_plan"(bigint, uuid, text);

drop function "muevete"."fn_registrar_perfil_driver"(jsonb, jsonb, jsonb);

drop function "muevete"."get_my_driver_id"();

drop function "muevete"."is_superadmin"();

drop function "public"."_fn_distribuir_pagos_orden"(bigint, numeric);

drop function "public"."_fn_recalcular_estado_comanda"(bigint);

drop function "public"."aceptar_envio_consignacion"(bigint, uuid, jsonb);

drop function "public"."aceptar_envio_consignacion_parcial"(bigint, uuid, jsonb);

drop function "public"."actualizar_mostrar_en_catalogo"(integer, integer, boolean);

drop function "public"."actualizar_precios_envio"(bigint, uuid, jsonb);

drop function "public"."admin_change_user_password"(text, text);

drop function "public"."app_actividad_resumen"();

drop function "public"."app_fn_analisis_tipos_operacion_json"(bigint, date, date);

drop function "public"."app_fn_diagnostico_conciliacion_json"(bigint, date, date);

drop function "public"."app_fn_plan_mejora_conciliacion_json"(bigint);

drop function "public"."app_fn_refresh_mv_reconciliacion"();

drop function "public"."app_fn_resumen_logistica_json"(bigint, date, date);

drop function "public"."app_fn_seguimiento_conciliacion_json"(bigint, integer);

drop function "public"."app_fn_timeline_inventario_json"(bigint, bigint, bigint, date, date);

drop function "public"."aprobar_devolucion_consignacion"(bigint, bigint, uuid);

drop function "public"."aprobar_devolucion_consignacion_v2"(bigint, bigint, uuid, bigint);

drop function "public"."aprobar_devolucion_consignacion_v3"(bigint, bigint, uuid);

drop function "public"."asignar_uuid_desde_roles"(bigint);

drop function "public"."bulk_get_presentaciones_base"(bigint[]);

drop function "public"."bulk_import_productos_excel"(bigint, jsonb[]);

drop function "public"."bulk_update_precios_costo"(jsonb[]);

drop function "public"."buscar_producto_por_codigo_barras"(character varying);

drop function "public"."buscar_producto_por_codigo_barras_v2"(text);

drop function "public"."buscar_producto_por_codigo_barras_v3"(text);

drop function "public"."cambiar_estado_operacion"(bigint, integer, uuid);

drop function "public"."cancelar_envio_consignacion"(bigint, uuid, text);

drop function "public"."check_auth_user_exists"(uuid);

drop function "public"."check_product_movements_operation"(bigint, bigint);

drop function "public"."check_user_has_access_to_any_tienda"();

drop function "public"."check_user_has_access_to_tienda"(bigint);

drop function "public"."check_user_is_superadmin_or_general_manager"(uuid);

drop function "public"."completar_operacion_extraccion"(bigint, text);

drop function "public"."completar_operacion_recepcion"(bigint, text);

drop function "public"."complete_ride_payment"(text, uuid, bigint, bigint, numeric);

drop function "public"."complete_ride_payment"(text, uuid, bigint, bigint, numeric, numeric);

drop function "public"."configurar_precios_recepcion_consignacion"(bigint, bigint);

drop function "public"."configurar_precios_recepcion_consignacion"(bigint, bigint, jsonb);

drop function "public"."configurar_precios_recepcion_consignacion_v2"(bigint, bigint, jsonb);

drop function "public"."crear_devolucion_consignacion"(bigint, bigint, uuid, jsonb, text);

drop function "public"."crear_devolucion_consignacion_v2"(bigint, bigint, uuid, jsonb, text, bigint);

drop function "public"."crear_envio_consignacion"(bigint, bigint, bigint, uuid, jsonb, text, bigint);

drop function "public"."crear_envio_consignacion_v2"(bigint, bigint, bigint, uuid, jsonb, text, bigint);

drop function
  "public"."crear_estructura_tienda"(uuid, character varying, character varying, character varying, character varying, character varying, character varying, character varying, numeric, numeric, jsonb,
  jsonb, jsonb, jsonb);

drop function "public"."crear_liquidacion_consignacion2"(bigint, numeric, text, uuid);

drop function "public"."crear_tpv_completo"(bigint, bigint, character varying, jsonb, jsonb[], jsonb[], uuid);

drop function "public"."create_gerente_from_email"(text, text, text, bigint);

drop function "public"."debug_crear_envio_consignacion"(bigint, bigint, bigint, uuid, jsonb, character varying, bigint);

drop function "public"."delete_tienda_completa"(bigint);

drop function "public"."dep_establecer_banco_predeterminado"(integer, bigint);

drop function "public"."descontar_devolucion_del_contrato"(bigint, numeric);

drop function "public"."descontar_devolucion_envio"(bigint);

drop function "public"."duplicar_producto_consignacion"(bigint, bigint, integer, bigint, uuid);

drop function "public"."duplicar_producto_si_necesario"(bigint, bigint, integer, bigint, uuid);

drop function "public"."duplicar_productos_contrato_consignacion"(integer, bigint, bigint, uuid);

drop function "public"."egresos_por_turno"(bigint);

drop function "public"."egresos_por_turno_especifico"(bigint);

drop function "public"."eliminar_producto_completo"(bigint);

drop function "public"."es_operacion_recepcion_consignacion"(bigint);

drop function "public"."fn_abrir_cuenta_mesa"(bigint, bigint, bigint, smallint, boolean);

drop function "public"."fn_abrir_turno_tpv"(bigint, numeric, bigint, uuid, jsonb);

drop function "public"."fn_actualizar_atributo"(uuid, bigint, text, text);

drop function "public"."fn_actualizar_campana"(bigint, character varying, text, smallint, date, date, numeric, smallint);

drop function "public"."fn_actualizar_cantidad_producto_orden"(bigint, numeric, uuid);

drop function "public"."fn_actualizar_cocina"(bigint, text, text, text, smallint, boolean);

drop function "public"."fn_actualizar_comunicacion"(bigint, character varying, text, timestamp with time zone, smallint);

drop function "public"."fn_actualizar_datos_rol_trabajador"(bigint, text, bigint, bigint, text, bigint, boolean);

drop function "public"."fn_actualizar_denominacion_corta_masivo"(bigint, json);

drop function "public"."fn_actualizar_denominacion_corta_por_denominacion"(bigint, text, text);

drop function "public"."fn_actualizar_item_cuenta_mesa"(bigint, numeric);

drop function "public"."fn_actualizar_mesa"(bigint, text, smallint, text, text, boolean);

drop function "public"."fn_actualizar_metodo_pago_item_cuenta"(bigint, bigint);

drop function "public"."fn_actualizar_opcion_atributo"(bigint, uuid, character varying, text);

drop function "public"."fn_actualizar_operacion_contabilizada"(bigint, boolean);

drop function "public"."fn_actualizar_operacion_recepcion"(bigint, character varying, character varying, numeric, character varying, character varying, date, numeric, character, text, text, jsonb);

drop function "public"."fn_actualizar_precio_promedio_recepcion_v2"(bigint, jsonb);

drop function "public"."fn_actualizar_precio_promedio_recepcion_v3"(bigint, jsonb);

drop function "public"."fn_actualizar_presentaciones_recepciones"(bigint);

drop function
  "public"."fn_actualizar_promocion"(bigint, uuid, character varying, text, character varying, numeric, timestamp without time zone, timestamp without time zone, numeric, integer, boolean, boolean,
  integer, boolean, integer);

drop function "public"."fn_actualizar_proveedor_producto"(bigint, integer);

drop function "public"."fn_actualizar_segmentacion_clientes"(uuid, bigint, jsonb);

drop function "public"."fn_actualizar_segmento"(bigint, character varying, text, jsonb);

drop function "public"."fn_admin_caja_actualizar_precios_offline"(uuid, bigint, bigint, numeric, numeric);

drop function "public"."fn_admin_caja_ajuste_inventario_offline"(uuid, bigint, bigint, bigint, numeric, numeric, text, text, uuid, bigint);

drop function "public"."fn_admin_caja_crear_producto_offline"(uuid, bigint, text, numeric, numeric, bigint);

drop function "public"."fn_admin_caja_extraccion_offline"(uuid, text, integer, bigint, bigint, text, jsonb, uuid);

drop function "public"."fn_admin_caja_precio_tpv_offline"(uuid, bigint, bigint, numeric, date, bigint);

drop function "public"."fn_admin_caja_recepcion_offline"(uuid, text, bigint, numeric, integer, text, jsonb, text, uuid, text);

drop function "public"."fn_admin_caja_tpv_create_offline"(uuid, text, bigint, bigint);

drop function "public"."fn_admin_caja_tpv_update_offline"(uuid, bigint, text);

drop function "public"."fn_admin_caja_transferencia_offline"(uuid, bigint, bigint, jsonb, text, text, text, text, text, bigint, uuid, boolean, text);

drop function "public"."fn_admin_caja_vendor_assign_tpv_offline"(uuid, bigint, bigint);

drop function "public"."fn_admin_caja_vendor_flags_offline"(uuid, bigint, boolean);

drop function "public"."fn_admin_caja_venta_acuerdo_offline"(uuid, text, integer, bigint, text, jsonb, uuid, bigint, numeric);

drop function "public"."fn_agregar_item_cuenta_mesa"(bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint, numeric, bigint, jsonb, jsonb, text, character varying, character varying);

drop function "public"."fn_agregar_producto_orden_pendiente"(bigint, jsonb, uuid);

drop function "public"."fn_agregar_producto_promocion"(uuid, bigint, bigint, bigint, bigint);

drop function "public"."fn_agregar_rol_trabajador"(bigint, bigint, text, uuid, bigint, bigint, text, bigint, boolean);

drop function "public"."fn_ajustar_inventario_desde_control"(bigint, uuid, text);

drop function "public"."fn_almacen_de_extraccion"(bigint);

drop function "public"."fn_almacen_de_operacion"(bigint);

drop function "public"."fn_almacenes_del_usuario"(bigint);

drop function "public"."fn_analisis_clientes"(bigint);

drop function "public"."fn_analisis_productos_venta3"(bigint, timestamp without time zone, timestamp without time zone);

drop function "public"."fn_analisis_promociones"(bigint, date, date);

drop function "public"."fn_analisis_ventas_filtrado"(bigint, bigint, bigint, date, date, bigint);

drop function "public"."fn_analisis_ventas_productos_turno"(bigint, date, date);

drop function "public"."fn_analytics_inventory_metrics"(date, date, integer);

drop function "public"."fn_analytics_product_movements"(date, date, integer, text, integer);

drop function "public"."fn_analytics_stock_alerts"(boolean, text[], text[], integer);

drop function "public"."fn_anular_tanda"(bigint, text);

drop function "public"."fn_apertura_turno_offline"(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamp with time zone);

drop function "public"."fn_apertura_turno_offline_usd"(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamp with time zone, numeric);

drop function "public"."fn_aplicar_cocina_categoria_a_platos"(bigint, bigint, text, boolean);

drop function "public"."fn_aplicar_cumplimiento_v2"(bigint, bigint, bigint, numeric, uuid, bigint, bigint, bigint, uuid, text, integer, bigint, bigint, bigint, bigint);

drop function "public"."fn_aplicar_plan_extraccion_v2"(jsonb, jsonb, bigint, uuid, text);

drop function "public"."fn_aplicar_promocion_segmento"(bigint, bigint, jsonb);

drop function "public"."fn_asignar_almacenero"(uuid, bigint, bigint);

drop function "public"."fn_asignar_cocina_categoria"(bigint, bigint, bigint);

drop function "public"."fn_asignar_como_almacenero"(bigint, bigint);

drop function "public"."fn_asignar_como_supervisor"(bigint, bigint);

drop function "public"."fn_asignar_como_vendedor"(bigint, bigint);

drop function "public"."fn_asignar_jefe_cocina"(uuid, bigint, bigint, boolean);

drop function "public"."fn_asignar_plato_cocina"(bigint, bigint, text, boolean);

drop function "public"."fn_asignar_rol_almacenero"(integer, integer);

drop function "public"."fn_asignar_supervisor"(uuid, bigint, bigint);

drop function "public"."fn_asignar_suscripcion_gratuita"(bigint, uuid);

drop function "public"."fn_asignar_tpv_cocina"(bigint, bigint);

drop function "public"."fn_asignar_vendedor"(uuid, bigint, bigint, bigint);

drop function "public"."fn_audit_carnaval_order_lines"(bigint, date, timestamp with time zone, text, boolean);

drop function "public"."fn_audit_inventtia_carnaval_lines"(bigint[], bigint);

drop function "public"."fn_auditar_recepcion_inventario"(bigint);

drop function "public"."fn_auditoria_promociones"();

drop function "public"."fn_buscar_empaques_exactos_v2"(jsonb, numeric, integer);

drop function "public"."fn_buscar_proveedores"(text, integer);

drop function "public"."fn_calcular_costo_promedio"(bigint);

drop function "public"."fn_calcular_disponibilidad_productos_elaborados"(bigint, bigint);

drop function "public"."fn_calcular_monto_contrato_desde_inventario"(bigint);

drop function "public"."fn_cambiar_almacen_almacenero"(integer, integer);

drop function "public"."fn_cambiar_estado_comanda"(bigint, smallint);

drop function "public"."fn_cambiar_estado_comanda_item"(bigint, smallint);

drop function "public"."fn_cambiar_estado_comanda_item_offline"(uuid, bigint, smallint);

drop function "public"."fn_cambiar_estado_promocion"(bigint, boolean, character varying);

drop function "public"."fn_cambiar_suscripcion"(bigint, smallint, text, uuid);

drop function "public"."fn_cancelar_cuenta_mesa"(bigint);

drop function "public"."fn_cancelar_item_pedido"(bigint, text);

drop function "public"."fn_cancelar_orden_carnaval"(bigint, text);

drop function "public"."fn_cantidad_en_base"(bigint, numeric);

drop function "public"."fn_carnaval_inventtia_kpis"(bigint);

drop function "public"."fn_carnaval_inventtia_prices_page"(bigint, integer, integer, text);

drop function "public"."fn_carnaval_inventtia_stock_page"(bigint, integer, integer, text);

drop function "public"."fn_carnaval_porcientos_tienda"(bigint);

drop function "public"."fn_carnaval_update_product_prices"(bigint, numeric, numeric);

drop function "public"."fn_carnaval_update_product_stock"(bigint, bigint);

drop function "public"."fn_catalogo_stock_meta"(bigint, bigint);

drop function "public"."fn_cerrar_tanda"(bigint, numeric, text);

drop function "public"."fn_cerrar_turno_offline"(uuid, bigint, numeric, uuid, jsonb, text, timestamp with time zone);

drop function "public"."fn_cerrar_turno_offline_usd"(uuid, bigint, numeric, uuid, jsonb, text, timestamp with time zone, numeric);

drop function "public"."fn_cerrar_turno_tpv"(bigint, numeric, uuid, jsonb, text);

drop function "public"."fn_cerrar_turno_tpv_usd"(bigint, numeric, uuid, jsonb, text, numeric);

drop function "public"."fn_check_is_hr_user"(uuid, integer);

drop function "public"."fn_check_update"(character varying, character varying, integer);

drop function "public"."fn_clientes_por_segmento"(bigint, integer);

drop function "public"."fn_cocina_por_defecto_producto"(bigint);

drop function "public"."fn_cocinas_del_usuario"();

drop function "public"."fn_comandas_abiertas_turno"(bigint);

drop function "public"."fn_combinar_factores_presentacion_v2"(numeric[], numeric[], boolean[], numeric, integer);

drop function "public"."fn_completar_recepcion_operacion"(bigint, uuid, text);

drop function "public"."fn_confirmar_liquidacion"(bigint, uuid, text);

drop function "public"."fn_confirmar_pago_sms"(bigint, jsonb, numeric);

drop function "public"."fn_confirmar_pre_asignacion"(bigint, uuid);

drop function "public"."fn_consultar_recepciones_sin_presentacion"(bigint, bigint);

drop function "public"."fn_contabilizar_linea_recepcion_inventario"(bigint);

drop function "public"."fn_contabilizar_operacion"(bigint, uuid, text);

drop function "public"."fn_contabilizar_recepcion_inventario"(bigint, boolean);

drop function "public"."fn_contabilizar_recepcion_inventario"(bigint, boolean, boolean);

drop function "public"."fn_conversion_inventario_es_interna_v2"(bigint, bigint);

drop function "public"."fn_convertir_unidades"(numeric, bigint, bigint, bigint);

drop function "public"."fn_costo_ingredientes_producto"(bigint);

drop function "public"."fn_count_pending_operations_optimized"(bigint, date, date, uuid);

drop function "public"."fn_crear_asignacion_costo"(bigint, bigint, bigint, bigint, numeric, smallint, uuid);

drop function "public"."fn_crear_atributo"(text, text, uuid, text);

drop function "public"."fn_crear_cocina"(bigint, text, text, text, smallint, bigint, text, bigint, text, text);

drop function "public"."fn_crear_extraccion_con_movimiento"(text, smallint, bigint, bigint, text, jsonb, uuid);

drop function "public"."fn_crear_extraccion_con_movimiento_v2"(text, bigint, bigint, text, jsonb, uuid);

drop function "public"."fn_crear_gerente"(bigint, uuid, bigint);

drop function "public"."fn_crear_liquidacion_consignacion"(bigint, numeric, text, uuid);

drop function "public"."fn_crear_notificacion"(uuid, character varying, character varying, text, jsonb, character varying, character varying, character varying, character varying, timestamp
  with time zone);

drop function "public"."fn_crear_opcion_atributo"(bigint, character varying, text, uuid);

drop function "public"."fn_crear_pre_asignacion"(bigint, bigint, numeric, uuid, bigint, bigint, bigint, bigint, bigint, smallint, text, timestamp with time zone);

drop function "public"."fn_crear_supervisor"(bigint, uuid, bigint);

drop function "public"."fn_crear_trabajador_almacenero"(integer, character varying, character varying, uuid, integer, numeric);

drop function "public"."fn_cxc_historial_cliente"(bigint);

drop function "public"."fn_cxc_listar_clientes"(bigint);

drop function "public"."fn_cxc_registrar_liquidacion"(bigint, bigint, numeric, smallint, character varying, uuid, text, jsonb);

drop function "public"."fn_cxc_saldo_cliente"(bigint);

drop function "public"."fn_cxc_set_bloqueo_cliente"(bigint, boolean);

drop function "public"."fn_dashboard_analisis_tienda"(bigint, text);

drop function "public"."fn_dashboard_carnaval_proveedor"(bigint, date, date);

drop function "public"."fn_dashboard_proveedores"(bigint);

drop function "public"."fn_dashboard_proveedores"(bigint, integer);

drop function "public"."fn_desarmar_bulto_venta_offline"(uuid, bigint, bigint, bigint, numeric, bigint, bigint, bigint, uuid, text);

drop function "public"."fn_desasignar_almacenero"(uuid, bigint);

drop function "public"."fn_desasignar_jefe_cocina"(uuid, bigint);

drop function "public"."fn_desasignar_supervisor"(uuid, bigint);

drop function "public"."fn_desasignar_tpv_cocina"(bigint, bigint);

drop function "public"."fn_desasignar_vendedor"(uuid, bigint);

drop function "public"."fn_descomponer_equivalente_presentacion_v2"(numeric[], boolean[], numeric, integer);

drop function "public"."fn_descontar_con_rebalanceo"(bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text);

drop function "public"."fn_descontar_con_rebalanceo_almacen"(bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text);

drop function "public"."fn_descontar_ingredientes_elaborado"(bigint, numeric, bigint, bigint, integer);

drop function "public"."fn_descontar_inventario_plato"();

drop function "public"."fn_descontar_inventario_plato"(bigint, bigint, uuid);

drop function "public"."fn_descontar_modificaciones"();

drop function "public"."fn_descontar_venta_enrutada"(bigint, numeric, bigint, bigint, integer, boolean);

drop function "public"."fn_detectar_inconsistencias_stock"(bigint, integer);

drop function "public"."fn_devolver_ingredientes_elaborado"(bigint, numeric, bigint, bigint, integer);

drop function "public"."fn_disparar_comanda"(bigint, bigint, numeric, bigint, bigint, bigint, uuid, text, jsonb, integer);

drop function "public"."fn_disponibilidad_plato"(bigint, bigint);

drop function "public"."fn_editar_trabajador_basico"(bigint, text, text, uuid);

drop function "public"."fn_editar_trabajador_completo"(bigint, bigint, character varying, character varying, character varying, uuid, bigint, bigint, character varying);

drop function "public"."fn_ejecutar_entrega_fisica_v2"(bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text);

drop function "public"."fn_eliminar_atributo"(bigint, uuid);

drop function "public"."fn_eliminar_campana"(bigint);

drop function "public"."fn_eliminar_cocina"(bigint, boolean);

drop function "public"."fn_eliminar_gasto"(bigint, uuid);

drop function "public"."fn_eliminar_item_cuenta_mesa"(bigint);

drop function "public"."fn_eliminar_mesa"(bigint);

drop function "public"."fn_eliminar_opcion_atributo"(bigint, uuid);

drop function "public"."fn_eliminar_order_detail_con_devolucion"(bigint, text);

drop function "public"."fn_eliminar_producto_orden"(bigint, uuid);

drop function "public"."fn_eliminar_promocion"(bigint, character varying);

drop function "public"."fn_eliminar_rol_trabajador"(bigint, text, bigint);

drop function "public"."fn_eliminar_segmento"(bigint);

drop function "public"."fn_eliminar_servicentro_producto"(bigint, bigint);

drop function "public"."fn_eliminar_trabajador_completo"(bigint, bigint);

drop function "public"."fn_eliminar_variante_subcategoria"(bigint, bigint);

drop function "public"."fn_envolver_texto"(text, integer, text);

drop function "public"."fn_equivalente_base"(bigint, bigint, bigint);

drop function "public"."fn_es_operacion_sin_actualizar_precio_costo"(bigint);

drop function "public"."fn_estadisticas_globales_ventiq"();

drop function "public"."fn_estadisticas_promociones"(integer, timestamp without time zone, timestamp without time zone);

drop function "public"."fn_estadisticas_trabajadores_completo"(integer);

drop function "public"."fn_estadisticas_trabajadores_tienda"(bigint);

drop function "public"."fn_expirar_suscripciones_catalogo"();

drop function "public"."fn_extraer_todo_inventario_tienda"(bigint, bigint, text, text);

drop function "public"."fn_extraer_todo_inventario_tienda2"(bigint, bigint, text, text);

drop function "public"."fn_fidelizacion_resumen"(bigint);

drop function "public"."fn_fmt_cantidad"(numeric);

drop function "public"."fn_formatear_stock_mixto"(jsonb, boolean, text);

drop function "public"."fn_get_carnaval_providers_for_deletion"(integer, integer);

drop function "public"."fn_get_historial_producto_dia"(bigint, bigint, bigint);

drop function "public"."fn_get_inventario_movimientos_tiempo_real"(bigint, integer, integer);

drop function "public"."fn_get_inventtia_stores_for_deletion"(integer, integer);

drop function "public"."fn_get_next_numero_paquete"(bigint);

drop function "public"."fn_get_operaciones_dia_tiempo_real"(bigint, integer, integer);

drop function "public"."fn_get_productos_mas_recientes"(integer, bigint);

drop function "public"."fn_get_productos_mas_vendidos"(integer, bigint);

drop function "public"."fn_get_productos_orden_default"(bigint);

drop function "public"."fn_get_productos_recomendados_v2"(uuid, integer, integer);

drop function "public"."fn_get_servicentro_config"(bigint);

drop function "public"."fn_get_tienda_by_operacion_venta"(bigint);

drop function "public"."fn_get_tiendas_destacadas"(integer);

drop function "public"."fn_get_usd_cup_rate"(bigint);

drop function "public"."fn_get_user_by_email"(text);

drop function "public"."fn_historial_contabilizacion_operacion"(bigint);

drop function "public"."fn_hr_assert_access"(bigint);

drop function "public"."fn_hr_attendance_history"(integer, date, date);

drop function "public"."fn_hr_batch_checkout"(bigint[], timestamp with time zone, boolean[], uuid, numeric[]);

drop function "public"."fn_hr_dashboard_summary"(integer, date, date);

drop function "public"."fn_hr_delete_attendance"(bigint, uuid, bigint);

drop function "public"."fn_hr_register_checkin"(integer, integer, timestamp with time zone, uuid);

drop function "public"."fn_hr_salary_report"(integer, date, date);

drop function "public"."fn_hr_top_workers_by_pay"(integer, date, date, integer);

drop function "public"."fn_hr_update_attendance_pay"(bigint, bigint, uuid, numeric, numeric, boolean, numeric, text);

drop function "public"."fn_hr_update_worker_salary"(integer, integer, numeric, numeric, uuid, text, text, numeric);

drop function "public"."fn_hr_worker_salary_detail"(integer, integer, date, date);

drop function "public"."fn_hr_workers_currently_working"(integer);

drop function "public"."fn_hr_workers_for_checkin"(integer);

drop function "public"."fn_info_contabilizacion_ordenes_carnaval"(bigint[]);

drop function "public"."fn_ingredientes_con_parada_tanda"(bigint, numeric);

drop function "public"."fn_ingresar_presentacion"(bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, character varying, character varying);

drop function "public"."fn_inicializar_inventario_productos_faltantes"(bigint, uuid);

drop function "public"."fn_inicializar_precio_promedio_desde_primera_recepcion"(bigint, bigint);

drop function "public"."fn_insert_campana"(bigint, smallint, character varying, timestamp with time zone, timestamp with time zone, smallint, text, numeric);

drop function "public"."fn_insert_segmento"(bigint, character varying, text, jsonb);

drop function "public"."fn_insertar_actualizar_margen"(bigint, bigint, numeric, smallint, bigint, date, date, uuid);

drop function "public"."fn_insertar_ajuste_inventario"(bigint, bigint, bigint, numeric, numeric, text, text, uuid, bigint);

drop function "public"."fn_insertar_ajuste_inventario2"(bigint, bigint, bigint, numeric, numeric, text, text, uuid, bigint);

drop function "public"."fn_insertar_asignacion_costos"(bigint, bigint, bigint, bigint, numeric, smallint, uuid);

drop function "public"."fn_insertar_campana"(bigint, character varying, text, smallint, date, date, numeric);

drop function "public"."fn_insertar_campana"(uuid, bigint, smallint, character varying, text, timestamp with time zone, timestamp with time zone, numeric, smallint);

drop function "public"."fn_insertar_centro_costo"(text, text, text, text, bigint, bigint, uuid);

drop function
  "public"."fn_insertar_cliente_con_contactos"(character varying, smallint, character varying, character varying, character varying, character varying, jsonb, date, character, numeric, jsonb);

drop function "public"."fn_insertar_cliente_cxc"(bigint, character varying, character varying, character varying);

drop function "public"."fn_insertar_comunicacion"(bigint, character varying, text, smallint, bigint, bigint, timestamp with time zone);

drop function "public"."fn_insertar_extraccion_completa"(bigint, uuid, bigint, jsonb, text, text, smallint);

drop function "public"."fn_insertar_mesa"(bigint, text, smallint, text, text);

drop function "public"."fn_insertar_promocion"(uuid, bigint, smallint, character varying, character varying, timestamp with time zone, bigint, text, numeric, timestamp
  with time zone, numeric, integer, boolean, boolean, smallint);

drop function "public"."fn_insertar_recepcion_completa"(bigint, uuid, jsonb, character varying, character varying, character varying, date, numeric, character, text, text);

drop function "public"."fn_insertar_recepcion_completa"(bigint, uuid, jsonb, text, text, text, numeric, smallint);

drop function "public"."fn_insertar_recepcion_completa_with_currency"(text, bigint, numeric, integer, text, jsonb, text, uuid, text);

drop function "public"."fn_insertar_recepcion_completa_with_currency2"(bigint, uuid, jsonb, text, text, text, numeric, integer, text);

drop function "public"."fn_insertar_segmento"(bigint, character varying, text, jsonb);

drop function "public"."fn_insertar_trabajador_basico"(bigint, character varying, character varying, uuid, integer);

drop function "public"."fn_insertar_trabajador_completo"(bigint, character varying, character varying, character varying, uuid, bigint, bigint, character varying);

drop function "public"."fn_insertar_transferencia_completa"(bigint, bigint, uuid, jsonb, text, text, smallint);

drop function "public"."fn_inventario_detallado_optimizado"(bigint, date, date, bigint, bigint);

drop function "public"."fn_inventario_movimiento_contabilizado"(bigint, bigint, bigint);

drop function "public"."fn_inventario_resumen_por_usuario"();

drop function "public"."fn_inventario_resumen_por_usuario_almacen"(bigint, bigint, text, boolean, character varying, integer, integer);

drop function "public"."fn_inventario_resumen_por_usuario_almacen2"(bigint, bigint, text, boolean, text, integer, integer);

drop function "public"."fn_inventario_resumen_por_usuario_almacen3"(bigint, bigint, text, boolean, text, integer, integer);

drop function "public"."fn_inventory_valuation_rows"(bigint);

drop function "public"."fn_is_superadmin_full_access"();

drop function "public"."fn_limpiar_notificaciones_expiradas"();

drop function "public"."fn_listar_almacenes_paginado"(uuid, integer, integer, text, text, bigint);

drop function "public"."fn_listar_atributos_con_opciones"(bigint);

drop function "public"."fn_listar_cambios_precio"(bigint, text, bigint, uuid, date, date, integer, integer);

drop function "public"."fn_listar_campanas"(bigint, boolean);

drop function "public"."fn_listar_campanas"(bigint, integer, integer);

drop function "public"."fn_listar_centros_costo"(bigint, text, integer, integer);

drop function "public"."fn_listar_centros_costo_con_jerarquia"(bigint, text, integer, integer);

drop function "public"."fn_listar_clientes_por_tienda"(bigint, text, smallint, smallint, boolean, boolean, character, integer, integer);

drop function "public"."fn_listar_cocinas"(bigint, boolean);

drop function "public"."fn_listar_cocinas_tpv"(bigint);

drop function "public"."fn_listar_comandas_cocina"(bigint, smallint[], integer);

drop function "public"."fn_listar_comunicaciones"(bigint);

drop function "public"."fn_listar_criterios_segmentacion"();

drop function "public"."fn_listar_cuentas_mesa"(bigint);

drop function "public"."fn_listar_entregas_por_fechas_usuario"(timestamp without time zone, timestamp without time zone, uuid);

drop function "public"."fn_listar_estructura_tipos_gastos"();

drop function "public"."fn_listar_eventos_fidelizacion"(bigint, integer);

drop function "public"."fn_listar_historial_inventario_producto"(bigint, integer);

drop function "public"."fn_listar_historial_inventario_producto_v2"(bigint, integer);

drop function
  "public"."fn_listar_inventario_productos"(bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, smallint, boolean, boolean, smallint, text, boolean, boolean, integer,
  integer);

drop function
  "public"."fn_listar_inventario_productos"(bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, smallint, text, boolean, boolean, boolean, smallint, boolean, integer,
  integer);

drop function
  "public"."fn_listar_inventario_productos_paged"(bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, smallint, boolean, boolean, smallint, text, boolean, boolean, integer,
  integer);

drop function
  "public"."fn_listar_inventario_productos_paged2"(integer, integer, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, smallint, boolean, boolean, smallint, boolean,
  boolean, text);

drop function
  "public"."fn_listar_inventario_productos_paged2_grouped"(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, text, boolean, boolean, integer,
  boolean, boolean, text);

drop function
  "public"."fn_listar_inventario_productos_paged2_grouped2"(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, smallint, boolean, boolean,
  smallint, boolean, boolean, text);

drop function
  "public"."fn_listar_inventario_productos_paged2_grouped2_optimiized"(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, smallint, boolean,
  boolean, smallint, boolean, boolean, text);

drop function
  "public"."fn_listar_inventario_productos_paged2_with_supplier"(integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, text, boolean, boolean,
  smallint, boolean, boolean, text);

drop function
  "public"."fn_listar_inventario_productos_paged3"(bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, text, boolean, boolean, smallint, text, boolean, boolean, boolean,
  boolean, integer, integer);

drop function
  "public"."fn_listar_inventario_productos_paged_withid"(bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, text, boolean, boolean, smallint, text, boolean, boolean,
  integer, integer);

drop function "public"."fn_listar_inventario_simple"(bigint, bigint, timestamp with time zone);

drop function "public"."fn_listar_medios_pago"();

drop function "public"."fn_listar_mesas_con_stats"(bigint, boolean);

drop function "public"."fn_listar_motivos_extraccion"();

drop function "public"."fn_listar_operaciones"(bigint, bigint, bigint, smallint[], date, date, uuid, text, boolean, integer, integer);

drop function "public"."fn_listar_operaciones_inventario"(integer, integer, bigint, bigint, bigint, smallint[], date, date, uuid, text);

drop function "public"."fn_listar_operaciones_inventario_new"(bigint, bigint, bigint, smallint[], date, date, uuid, text, integer, integer, bigint, boolean);

drop function "public"."fn_listar_operaciones_inventario_re"(bigint, bigint, bigint, smallint[], date, date, uuid, text, integer, integer);

drop function "public"."fn_listar_operaciones_inventario_reT"(bigint, bigint, bigint, smallint[], date, date, uuid, text, bigint, integer, integer);

drop function "public"."fn_listar_operaciones_producto_especifico"(bigint, integer, integer, bigint, text);

drop function "public"."fn_listar_operaciones_producto_recepcion"(bigint, bigint, date, integer, integer, bigint, text);

drop function "public"."fn_listar_ordenes"(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer);

drop function "public"."fn_listar_ordenesop"(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer);

drop function "public"."fn_listar_personal_cocina"(bigint);

drop function "public"."fn_listar_productos_para_promociones"(bigint);

drop function "public"."fn_listar_productos_por_atributo"(bigint, bigint);

drop function "public"."fn_listar_promociones"(bigint, boolean);

drop function "public"."fn_listar_promociones2"(bigint, boolean);

drop function "public"."fn_listar_promociones_producto"(bigint);

drop function "public"."fn_listar_promociones_producto_nueva"(bigint);

drop function "public"."fn_listar_promociones_productos_batch"(bigint[]);

drop function "public"."fn_listar_promocionesv2"(integer, boolean);

drop function "public"."fn_listar_segmentos"(bigint);

drop function "public"."fn_listar_servicentro_productos"(bigint);

drop function "public"."fn_listar_subcategorias_por_atributo"(bigint);

drop function "public"."fn_listar_tandas_cocina"(bigint, smallint[], integer, integer);

drop function "public"."fn_listar_tiendas_gerente"(uuid);

drop function "public"."fn_listar_tipos_campana"();

drop function "public"."fn_listar_tipos_layout_almacen"();

drop function "public"."fn_listar_tipos_promocion"();

drop function "public"."fn_listar_todos_tipos_condiciones"();

drop function "public"."fn_listar_tpv_por_tienda"(bigint, text, integer, integer);

drop function "public"."fn_listar_trabajadores_completo"(integer, uuid);

drop function "public"."fn_listar_trabajadores_eliminados"(integer, uuid);

drop function "public"."fn_listar_trabajadores_por_tienda"(bigint);

drop function "public"."fn_listar_trabajadores_tienda"(bigint, uuid);

drop function "public"."fn_listar_turnos"(bigint, bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."fn_listar_turnos_admin"(bigint, bigint, bigint, smallint, timestamp with time zone, timestamp with time zone, boolean, text, integer, integer);

drop function "public"."fn_listar_usos_promocion_cliente"(bigint);

drop function "public"."fn_marcar_cuenta_cerrada"(bigint, bigint);

drop function "public"."fn_marcar_notificacion_leida"(bigint);

drop function "public"."fn_marcar_todas_notificaciones_leidas"();

drop function "public"."fn_marketing_dashboard_resumen"(bigint);

drop function "public"."fn_marketing_metricas_rendimiento"(bigint, date, date);

drop function "public"."fn_metricas_proveedor"(bigint);

drop function "public"."fn_metricas_proveedor_completas"(bigint, bigint, date, date);

drop function "public"."fn_modificar_asignacion_costo"(bigint, bigint, bigint, bigint, bigint, numeric, smallint, uuid);

drop function "public"."fn_modificar_gasto"(bigint, bigint, numeric, bigint, bigint, bigint, text, text, uuid);

drop function "public"."fn_modificar_gasto"(bigint, uuid, bigint, numeric, date, bigint, bigint, bigint, text, text);

drop function "public"."fn_notify_stock_mismatch"();

drop function "public"."fn_obtener_almacenes_tienda"(bigint);

drop function "public"."fn_obtener_cuenta_mesa"(bigint);

drop function "public"."fn_obtener_detalle_trabajador"(bigint, bigint);

drop function "public"."fn_obtener_ingredientes_recursivos"(bigint, numeric);

drop function "public"."fn_obtener_inventario_producto"(integer, integer);

drop function "public"."fn_obtener_licencia_firmada"(bigint);

drop function "public"."fn_obtener_limites_seguros"();

drop function "public"."fn_obtener_notificaciones"(integer, integer, boolean);

drop function "public"."fn_obtener_reporte_inventario_completo4"(bigint, bigint, date, date, boolean);

drop function "public"."fn_obtener_roles_tienda"(bigint);

drop function "public"."fn_obtener_tpvs_tienda"(bigint);

drop function "public"."fn_obtener_ubicaciones_prodcuto"(integer, integer);

drop function "public"."fn_obtener_utilidad_producto"(bigint, bigint, bigint);

drop function "public"."fn_ordenes_carnaval_por_contabilizacion"(bigint, boolean);

drop function "public"."fn_ordenes_producto_proveedor"(bigint, bigint, timestamp with time zone, timestamp with time zone, bigint);

drop function "public"."fn_pago_proveedores_carnaval_lineas"(date, date, bigint);

drop function
  "public"."fn_pedir_item_cuenta"(bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint, numeric, bigint, jsonb, jsonb, text, character varying, character varying, uuid, boolean);

drop function "public"."fn_pedir_item_cuenta_offline"(uuid, bigint, bigint, numeric, numeric, bigint, bigint, bigint, bigint, numeric, bigint, jsonb, jsonb, text, text, text, uuid, boolean);

drop function "public"."fn_planificar_cumplimiento_presentaciones_v2"(bigint, bigint, bigint, numeric, bigint, bigint);

drop function "public"."fn_planificar_entrega_fisica_v2"(jsonb, jsonb, bigint, numeric);

drop function "public"."fn_platos_por_tanda_cocina"(bigint);

drop function "public"."fn_plural_presentacion"(text, numeric);

drop function "public"."fn_presentacion_item_json"(bigint, numeric);

drop function "public"."fn_presentacion_tiene_movimientos"(bigint);

drop function "public"."fn_presentaciones_producto"(bigint);

drop function "public"."fn_presentaciones_producto_editable"(bigint);

drop function "public"."fn_presentaciones_producto_v2"(bigint);

drop function "public"."fn_preview_cumplimiento_v2"(bigint, bigint, bigint, numeric, bigint, bigint);

drop function "public"."fn_preview_entrega_fisica_v2"(bigint, bigint, bigint, numeric, bigint, bigint);

drop function "public"."fn_preview_rebalanceo"(bigint, bigint, bigint, numeric, bigint, bigint);

drop function "public"."fn_producir_tanda"(bigint, bigint, numeric, text, numeric);

drop function "public"."fn_producto_califica_promocion"(bigint, bigint, bigint);

drop function "public"."fn_producto_json_a_presentacion_base"(jsonb);

drop function "public"."fn_productos_cocina_tpv"(bigint, bigint, bigint, text, boolean);

drop function "public"."fn_productos_json_a_presentacion_base"(jsonb);

drop function "public"."fn_productos_relacionados"(bigint, integer, integer);

drop function "public"."fn_productos_utilidad_negativa"(integer, bigint, bigint);

drop function "public"."fn_productos_vendidos_por_turno"(bigint);

drop function "public"."fn_productos_vendidos_por_turno_v2"(bigint);

drop function "public"."fn_programar_comunicacion"(uuid, bigint, bigint, smallint, character varying, text, timestamp with time zone);

drop function "public"."fn_proponer_segmentacion_clientes"(bigint, integer, integer, numeric);

drop function "public"."fn_puede_tener_cantidad_negativa"(bigint);

drop function "public"."fn_rebalancear_presentaciones"(bigint, bigint, bigint, numeric, bigint, bigint, bigint, uuid, text);

drop function "public"."fn_rechazar_liquidacion"(bigint, uuid, text);

drop function "public"."fn_registrar_actualizar_layout_almacen"(bigint, bigint, character varying, character varying, bigint, bigint);

drop function "public"."fn_registrar_cambio_estado_offline"(uuid, bigint, smallint, uuid);

drop function "public"."fn_registrar_control_inventario"(bigint, uuid, text, jsonb, text, smallint);

drop function
  "public"."fn_registrar_conversion_presentacion"(bigint, bigint, bigint, bigint, numeric, numeric, text, numeric, numeric, bigint, bigint, bigint, uuid, text, character varying, character varying);

drop function "public"."fn_registrar_conversion_v2"(bigint, bigint, text, jsonb, bigint, bigint, bigint, uuid, text);

drop function "public"."fn_registrar_egreso_fondo_caja"(uuid, integer, bigint, numeric, character varying, character varying, text, smallint, uuid);

drop function "public"."fn_registrar_egreso_offline"(uuid, bigint, numeric, character varying, character varying, text, smallint, uuid);

drop function "public"."fn_registrar_evento_fidelizacion"(bigint, bigint, character varying, integer, text, bigint);

drop function "public"."fn_registrar_gasto"(bigint, numeric, bigint, bigint, bigint, uuid, date, text, text);

drop function "public"."fn_registrar_orden_paqueteria"(jsonb);

drop function "public"."fn_registrar_orden_paqueteria_v2"(jsonb);

drop function "public"."fn_registrar_pago_venta"(bigint, jsonb);

drop function "public"."fn_registrar_pago_venta_offline"(uuid, bigint, jsonb, uuid);

drop function "public"."fn_registrar_recepcion_con_inventario"(text, bigint, numeric, integer, text, jsonb, text, uuid, text);

drop function "public"."fn_registrar_uso_promocion"(bigint, bigint, bigint, numeric);

drop function "public"."fn_registrar_uso_promocion"(uuid, bigint, character varying, bigint, numeric);

drop function "public"."fn_registrar_venta"(bigint, uuid, jsonb, text, text, text, smallint, bigint);

drop function "public"."fn_registrar_venta_mesa"(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint);

drop function "public"."fn_registrar_venta_mesa_v2"(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint);

drop function "public"."fn_registrar_venta_offline"(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamp with time zone);

drop function "public"."fn_registrar_venta_offline"(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamp with time zone, jsonb);

drop function "public"."fn_registrar_venta_offline_v2"(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamp with time zone, jsonb);

drop function "public"."fn_registrar_venta_old"(bigint, uuid, jsonb, text, text, text, smallint);

drop function "public"."fn_registrar_venta_v2"(bigint, uuid, jsonb, text, text, text, smallint, bigint);

drop function "public"."fn_reordenar_servicentro_productos"(bigint, bigint[]);

drop function "public"."fn_reparar_recepcion_inventario_faltante"(bigint);

drop function "public"."fn_reporte_cronologico_producto"(bigint, bigint, date, date, text);

drop function "public"."fn_reporte_ventas_con_proveedor"(bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."fn_reporte_ventas_con_proveedor2"(bigint, timestamp with time zone, timestamp with time zone, bigint);

drop function "public"."fn_reporte_ventas_con_proveedor3"(bigint, date, date, bigint);

drop function "public"."fn_reporte_ventas_con_proveedor4"(bigint, date, date, bigint, text);

drop function "public"."fn_reporte_ventas_con_proveedor5"(bigint, date, date, bigint, text);

drop function "public"."fn_reporte_ventas_con_proveedor_precios_actuales"(bigint, date, date, bigint, text);

drop function "public"."fn_reporte_ventas_ganancias"(integer, date, date);

drop function "public"."fn_reporte_ventas_ganancias_simple"(integer, date, date);

drop function "public"."fn_reporte_ventas_gananciasv2"(integer, date, date);

drop function "public"."fn_reporte_ventas_gananciasv3"(integer, date, date);

drop function "public"."fn_reporte_ventas_gananciasv4"(integer, date, date);

drop function "public"."fn_reporte_ventas_gananciasv5"(integer, date, date);

drop function "public"."fn_reporte_ventas_por_turno"(uuid, date, date, bigint);

drop function "public"."fn_reporte_ventas_por_vendedor"(uuid, date, date, bigint);

drop function "public"."fn_reporte_ventas_por_vendedor_sch"(uuid, date, date, bigint, boolean);

drop function "public"."fn_reporte_ventas_por_vendedor_v2"(uuid, date, date, bigint);

drop function "public"."fn_reporte_ventas_proveedor"(bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."fn_require_gerente_tienda"(bigint);

drop function "public"."fn_require_gerente_tpv"(bigint);

drop function "public"."fn_resolver_origen_venta"(bigint, bigint);

drop function "public"."fn_restaurar_trabajador"(bigint, bigint);

drop function "public"."fn_resumen_diario_cierre"(bigint, uuid);

drop function "public"."fn_resumen_diario_cierre_v2"(bigint, uuid);

drop function "public"."fn_resumen_diario_cierre_v3"(bigint, uuid);

drop function "public"."fn_resumen_mesas"(bigint);

drop function "public"."fn_resumen_turno_kpi"(bigint, bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."fn_resumen_turno_kpi_corregido"(bigint);

drop function "public"."fn_resumen_turno_por_id"(bigint);

drop function "public"."fn_set_modo_servicentro"(bigint, boolean, smallint);

drop function "public"."fn_set_productos_orden_default"(bigint, jsonb);

drop function "public"."fn_siguiente_numero_comanda"(bigint);

drop function "public"."fn_stock_breakdown_by_locations"(bigint[], bigint[]);

drop function "public"."fn_stock_breakdown_by_products"(bigint[], bigint);

drop function "public"."fn_stock_mixto_almacen"(bigint, bigint);

drop function "public"."fn_stock_mixto_json"(bigint, bigint, bigint);

drop function "public"."fn_stock_mixto_producto_por_ubicacion"(bigint, bigint);

drop function "public"."fn_stock_producto_almacen"(bigint, bigint);

drop function "public"."fn_stock_producto_almacen_detalle"(bigint, bigint);

drop function "public"."fn_stock_real_productos_cierre"(bigint, bigint, bigint[]);

drop function "public"."fn_stock_saldos_presentacion"(bigint, bigint, bigint, boolean);

drop function "public"."fn_sync_carnaval_stock"();

drop function "public"."fn_ticket_comanda"(bigint, integer);

drop function "public"."fn_top_proveedores"(timestamp with time zone, timestamp with time zone, integer);

drop function "public"."fn_top_utilidad_productos"(integer, bigint, bigint);

drop function "public"."fn_transferir_inventario_entre_layouts"(bigint, bigint, jsonb, text, text, bigint, uuid, boolean, text, text, text, text);

drop function "public"."fn_ubicacion_destino_devolucion"(bigint, bigint);

drop function "public"."fn_ultima_cuenta_abierta_tpv"(bigint, bigint);

drop function "public"."fn_update_daily_prices_carnaval"();

drop function "public"."fn_upsert_actividad_usuario"(uuid, text);

drop function "public"."fn_upsert_servicentro_producto"(bigint, bigint, smallint, text);

drop function "public"."fn_user_can_access_tienda"(bigint);

drop function "public"."fn_user_can_read_tienda"(bigint);

drop function "public"."fn_user_is_gerente_or_superadmin"(bigint);

drop function "public"."fn_usuario_puede_operar_cocina"(bigint, boolean);

drop function "public"."fn_validar_acceso_tienda"(bigint, uuid);

drop function "public"."fn_validar_criterios_segmentacion"(jsonb);

drop function "public"."fn_validar_eliminacion_proveedor"(bigint);

drop function "public"."fn_validar_id_presentacion"(bigint, bigint);

drop function "public"."fn_validar_ingredientes_elaborado"(bigint, numeric, bigint);

drop function "public"."fn_validar_linea_recepcion_inventario"(bigint);

drop function "public"."fn_validar_metricas_campana"(jsonb);

drop function "public"."fn_validar_parametros_entrada"(bigint, character varying, text);

drop function "public"."fn_validar_promocion_venta"(text, bigint, jsonb);

drop function "public"."fn_validar_stock_plato"(bigint, integer);

drop function "public"."fn_ventas_por_vendedor"(bigint, date, date, bigint);

drop function "public"."fn_verificar_disponibilidad_plato"(bigint, bigint, integer);

drop function "public"."fn_verificar_permisos_usuario"(uuid, bigint);

drop function "public"."fn_vista_precios_productos"(integer, date, date);

drop function "public"."fn_vista_precios_productos2"(bigint, date, date);

drop function "public"."fn_vista_precios_productos3"(bigint, date, date);

drop function "public"."fn_vista_precios_productos4"(bigint, date, date);

drop function "public"."fn_wapi_dispatch_debug"(bigint);

drop function "public"."fn_wapi_dispatch_diario"();

drop function "public"."fn_wapi_force_dispatch"(bigint);

drop function "public"."fn_wapi_get_dashboard"(bigint);

drop function "public"."fn_wapi_inspect_vault_token"();

drop function "public"."fn_warehouse_valuation_zones"(bigint, bigint);

drop function "public"."fn_warehouses_valuation_summary"(bigint);

drop function "public"."fn_zone_valuation_products"(bigint, bigint);

drop function "public"."generar_numero_envio"(bigint);

drop function "public"."generar_reporte_ipb"(integer, integer, date, date);

drop function "public"."get_bcg_productos_sin_log"(bigint);

drop function "public"."get_categorias_by_tienda"(bigint);

drop function "public"."get_categorias_by_tienda_complete"(bigint);

drop function "public"."get_categorias_by_tienda_tpv"(bigint, bigint);

drop function "public"."get_categorias_by_tienda_tpv2"(bigint, bigint);

drop function "public"."get_contratos_pendientes_confirmacion"(integer);

drop function "public"."get_dashboard_ventas_stats"();

drop function "public"."get_detalle_almacen_completo"(bigint);

drop function "public"."get_detalle_operacion"(bigint);

drop function "public"."get_detalle_producto"(bigint);

drop function "public"."get_detalle_producto_marketplace"(bigint);

drop function "public"."get_detalles_productos_batch"(bigint[]);

drop function "public"."get_estadisticas_producto_rating"(bigint);

drop function "public"."get_estadisticas_productos_rating"(bigint);

drop function "public"."get_estadisticas_tienda_rating"(bigint);

drop function "public"."get_estadisticas_ventas_consignacion"(bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."get_estadisticas_ventas_consignacion2"(bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."get_gerentes_completo"();

drop function "public"."get_historial_duplicaciones_contrato"(integer);

drop function "public"."get_interacciones_productos_paginado"(bigint, integer, integer);

drop function "public"."get_interacciones_tienda_paginado"(bigint, integer, integer);

drop function "public"."get_inventario_analisis_tienda_json"(bigint);

drop function "public"."get_margenes_comerciales_by_tienda"(bigint);

drop function "public"."get_movimientos_consignacion"(bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."get_movimientos_consignacion_detallado"(bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."get_operaciones_consignacion_relacionadas"(bigint);

drop function "public"."get_paginated_users_summary"(integer, integer, text, text);

drop function "public"."get_precios_productos_tienda"(bigint);

drop function "public"."get_product_movements_optimized"(bigint, date, date, bigint, integer, integer);

drop function "public"."get_product_movements_optimized_with_warehouse"(bigint, date, date, bigint, bigint, integer, integer);

drop function "public"."get_product_movements_optimized_with_warehouse2"(bigint, date, date, bigint, bigint, integer, integer);

drop function "public"."get_product_movements_v2"(bigint, date, date, bigint, bigint, integer, integer);

drop function "public"."get_product_movements_v3"(bigint, date, date, bigint, bigint, integer, integer);

drop function "public"."get_product_movements_v4"(bigint, date, date, bigint, bigint, integer, integer);

drop function "public"."get_producto_duplicado"(bigint, bigint);

drop function "public"."get_productos_by_categoria"(bigint, bigint, boolean);

drop function "public"."get_productos_by_categoria_tpv"(bigint, bigint, bigint, boolean);

drop function "public"."get_productos_by_categoria_tpv_meta"(bigint, bigint, bigint, boolean);

drop function "public"."get_productos_by_categoria_tpv_meta2"(bigint, bigint, bigint, boolean);

drop function "public"."get_productos_by_categoria_tpv_search_meta"(bigint, bigint, bigint, text, boolean);

drop function "public"."get_productos_by_categoria_tpv_search_meta_v2"(bigint, bigint, bigint, text, boolean, boolean);

drop function "public"."get_productos_by_categoria_tpv_search_meta_v3"(bigint, bigint, bigint, text, boolean);

drop function "public"."get_productos_by_categoria_tpv_v2"(bigint, bigint, bigint, boolean);

drop function "public"."get_productos_by_subcategoria"(bigint, bigint);

drop function "public"."get_productos_by_subcategoria"(bigint, bigint, boolean);

drop function "public"."get_productos_catalogo_validacion"(integer);

drop function "public"."get_productos_completos_by_tienda_optimized"(integer, integer, boolean);

drop function "public"."get_productos_completos_by_tienda_optimized2"(bigint, bigint, boolean, boolean);

drop function "public"."get_productos_completos_by_tienda_optimized_provider"(bigint, bigint, boolean, integer);

drop function "public"."get_productos_completos_by_tienda_optimized_provider2"(bigint, bigint, boolean, integer);

drop function "public"."get_productos_completos_by_tienda_optimized_provider2"(bigint, bigint, boolean, integer, boolean);

drop function "public"."get_productos_completos_by_tienda_optimized_v2"(bigint, bigint, boolean, boolean);

drop function "public"."get_productos_completos_by_tienda_with_supplier"(integer, integer, boolean, integer);

drop function "public"."get_productos_consignacion_optimizado"(integer);

drop function "public"."get_productos_count_por_tienda"();

drop function "public"."get_productos_marketplace"(bigint, bigint, boolean, text, integer, integer);

drop function "public"."get_productos_marketplace2"(bigint, bigint, boolean, text, integer, integer);

drop function "public"."get_productos_pendientes_consignacion_optimizado"(integer);

drop function "public"."get_productos_tienda_para_filtro"(bigint);

drop function "public"."get_productos_zona_consignacion"(integer);

drop function "public"."get_proveedores_by_tienda2"(integer);

drop function "public"."get_ratings_producto_paginado"(bigint, integer, integer);

drop function "public"."get_resumen_ventas_consignacion"(bigint, timestamp with time zone, timestamp with time zone);

drop function "public"."get_sale_payments"(bigint);

drop function "public"."get_sale_payments2"(bigint);

drop function "public"."get_stock_real_by_location_presentation"(bigint, bigint, bigint);

drop function "public"."get_subcategorias_by_categoria"(bigint);

drop function "public"."get_synced_products_with_location"(integer);

drop function "public"."get_synced_products_with_location_v2"(bigint);

drop function "public"."get_tienda_estado_tpvs"(bigint);

drop function "public"."get_tiendas_con_estadisticas"();

drop function "public"."get_trabajadores_count_por_tienda"();

drop function "public"."get_ultimas_interacciones_productos"(bigint, integer);

drop function "public"."get_ultimas_interacciones_tienda"(bigint, integer);

drop function "public"."get_user_access_options"();

drop function "public"."get_user_email"(uuid);

drop function "public"."get_users_count_summary"();

drop function "public"."get_users_summary"();

drop function "public"."get_uuid_by_email"(text);

drop function "public"."get_ventas_mes_por_tienda"(timestamp without time zone);

drop function "public"."get_ventas_stats_por_tienda"();

drop function "public"."inicializar_inventario_productos_faltantes"(bigint);

drop function "public"."insert_auth_user"(jsonb);

drop function "public"."insert_codigo_barras_producto"(bigint, character varying, bigint, bigint, bigint, boolean, character varying);

drop function "public"."insert_producto_completo"(jsonb, jsonb[], jsonb[], jsonb[], jsonb[], jsonb[], jsonb[]);

drop function "public"."insert_producto_completo_v2"(jsonb, jsonb[], jsonb[], jsonb[], jsonb[], jsonb[], jsonb[]);

drop function "public"."insert_producto_completo_v3"(jsonb, jsonb[], jsonb[], jsonb[], jsonb[], jsonb[], jsonb[]);

drop function "public"."listar_almacenes_acceso_usuario"(uuid, integer, integer, character varying, character varying, bigint);

drop function
  "public"."listar_inventario_productos"(integer, integer, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, bigint, smallint, boolean, boolean, smallint, text, boolean, boolean);

drop function "public"."listar_ordenes"(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer);

drop function "public"."listar_ordenes2"(timestamp with time zone, timestamp with time zone, integer, bigint, integer, bigint, uuid, integer, integer, boolean);

drop function "public"."listar_ordenes_mesa"(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer, bigint);

drop function "public"."listar_ordenes_venta_filtradas"(bigint, uuid, smallint, bigint, timestamp without time zone, timestamp without time zone, integer, integer);

drop function "public"."listar_productos_promocion"(bigint);

drop function "public"."listar_tiendas_acceso_usuario"(uuid, integer, integer, character varying, character varying);

drop function "public"."listar_tipos_operacion"();

drop function "public"."make_slug"(text);

drop function "public"."marcar_envio_en_transito"(bigint, uuid);

drop function "public"."obtener_analisis_tienda"(bigint, text);

drop function "public"."obtener_datos_originales_producto"(bigint, bigint);

drop function "public"."obtener_detalle_envio"(bigint);

drop function "public"."obtener_detalles_envio"(bigint);

drop function "public"."obtener_envios_consignacion"(bigint, integer, bigint);

drop function "public"."obtener_envios_consignacion_con_totales"(bigint, integer, bigint);

drop function "public"."obtener_envios_por_contrato"(bigint);

drop function "public"."obtener_historial_envio"(bigint);

drop function "public"."obtener_ipv"(bigint, bigint, text, text, boolean);

drop function "public"."obtener_ipv2"(bigint, bigint, text, text, boolean);

drop function "public"."obtener_operaciones_envio"(bigint);

drop function "public"."obtener_precio_promedio_presentacion"(bigint, bigint);

drop function "public"."obtener_productos_envio"(bigint);

drop function "public"."obtener_productos_envio2"(integer);

drop function "public"."obtener_productos_envio3"(integer);

drop function "public"."obtener_productos_envio_detallado"(bigint);

drop function "public"."obtener_productos_envio_para_aceptacion"(bigint);

drop function "public"."obtener_productos_que_usan_ingrediente_detallado"(bigint);

drop function "public"."obtener_reporte_inventario"(bigint, timestamp without time zone, timestamp without time zone, bigint);

drop function "public"."obtener_reporte_inventario2"(bigint, timestamp without time zone, timestamp without time zone, bigint);

drop function "public"."obtener_reporte_inventario_completo"(bigint, date, timestamp without time zone, bigint);

drop function "public"."obtener_reporte_inventario_completo2"(bigint, date, date, bigint, boolean);

drop function "public"."obtener_reporte_inventario_completo3"(bigint, date, date, bigint, boolean);

drop function "public"."obtener_reporte_inventario_completo4"(bigint, text, text, bigint, boolean);

drop function "public"."obtener_reporte_inventario_completo5"(bigint, text, text, bigint, boolean);

drop function "public"."obtener_reporte_inventario_completo5_completadas_en_periodo"(bigint, text, text, bigint, boolean);

drop function "public"."producto_existe_en_tienda"(bigint, bigint);

drop function "public"."rechazar_envio_consignacion"(bigint, uuid, text);

drop function "public"."rechazar_producto_envio_consignacion"(bigint, bigint, uuid, text);

drop function "public"."rechazar_producto_envio_consignacion2"(bigint, bigint, uuid, text);

drop function "public"."registrar_almacen_completo"(bigint, character varying, character varying, character varying, jsonb[], bigint[], jsonb[], uuid[], uuid);

drop function "public"."registrar_apertura_turno"(bigint, bigint, numeric, uuid, jsonb);

drop function "public"."registrar_apertura_turno_usd"(numeric, bigint, bigint, uuid, boolean, jsonb, text, numeric);

drop function "public"."registrar_apertura_turno_v2"(bigint, bigint, numeric, uuid, jsonb, boolean);

drop function "public"."registrar_apertura_turno_v3"(numeric, bigint, bigint, uuid, boolean, jsonb, text);

drop function "public"."registrar_egreso_parcial"(bigint, numeric, character varying, character varying, text);

drop function "public"."registrar_egreso_parcial_v2"(bigint, numeric, character varying, character varying, text, smallint);

drop function "public"."registrar_garantia_producto"(bigint, smallint, text, boolean);

drop function "public"."registrar_garantia_venta"(bigint, bigint, smallint, date, bigint, smallint);

drop function "public"."registrar_operacion_inventario_generica"(bigint, bigint, uuid, character varying, jsonb, jsonb);

drop function "public"."registrar_uso_garantia"(bigint, bigint, text, smallint, text);

drop function "public"."registrar_usuario_simple"(text, text, text);

drop function "public"."reporte_ordenes_json"(bigint, timestamp with time zone, timestamp with time zone, bigint);

drop function "public"."rpc_apply_global_price_change"(bigint, numeric, numeric, numeric);

drop function "public"."rpc_apply_selected_price_change"(bigint, integer[], text, numeric, numeric, numeric);

drop function "public"."rpc_get_products_last_price"(bigint);

drop function "public"."rpc_get_products_last_price2"(bigint);

drop function "public"."sync_bundle"(bigint, bigint);

drop function "public"."tiene_plan_catalogo"(integer);

drop function "public"."tiene_plan_pro"(integer);

drop function "public"."validar_orden_operaciones_consignacion"(bigint);

drop function "public"."validar_recepcion_consignacion_antes_completar"(bigint);

drop function "public"."validar_tienda_para_catalogo"(bigint);

drop table "carnavalapp"."Carrito";

drop function "carnavalapp"."check_producto_activo"();

drop function "carnavalapp"."check_stock_before_cart_insert"();

drop table "carnavalapp"."Categorias";

drop table "carnavalapp"."Direcciones";

drop function "carnavalapp"."fn_block_direcciones_restricted_provinces"();

drop function "carnavalapp"."fn_direcciones_autocompletar_ubicacion"();

drop function "carnavalapp"."fn_direcciones_validar_ubicacion"();

drop table "carnavalapp"."OrderDetails";

drop function "carnavalapp"."check_stock_before_order_detail_insert"();

drop function "carnavalapp"."fn_crear_operacion_desde_orden2"();

drop function "carnavalapp"."fn_orderdetails_ajustar_erp"();

drop function "carnavalapp"."fn_orderdetails_topar_cantidad"();

drop function "carnavalapp"."prevent_completion_change_if_order_completed"();

drop function "carnavalapp"."update_product_stock"();

drop table "carnavalapp"."Orders";

drop function "carnavalapp"."fn_actualizar_estado_operacion"();

drop function "carnavalapp"."fn_block_orders_for_restricted_provinces"();

drop function "carnavalapp"."fn_log_order_status_history"();

drop function "carnavalapp"."fn_notificar_cliente_cambio_estado"();

drop function "carnavalapp"."fn_orders_autocompletar_ubicacion"();

drop function "carnavalapp"."fn_orders_completar_referal"();

drop function "carnavalapp"."fn_prevent_order_status_regression"();

drop function "carnavalapp"."fn_update_direccion_on_order_insert"();

drop function "carnavalapp"."handle_order_cancel_stripe"();

drop function "carnavalapp"."update_order_details_on_order_completion"();

drop function "carnavalapp"."update_ordersdetails_on_status_change"();

drop function "carnavalapp"."update_product_stock_on_order_cancel"();

drop table "carnavalapp"."Productos";

drop function "carnavalapp"."block_proveedor_3"();

drop table "carnavalapp"."Provincias";

drop table "carnavalapp"."Reviews";

drop table "carnavalapp"."Usuarios";

drop function "carnavalapp"."fn_usuarios_estampar_referal"();

drop table "carnavalapp"."analytics_events";

drop table "carnavalapp"."app_versiones";

drop table "carnavalapp"."configuraciones_admin";

drop function "carnavalapp"."update_municipios_price"();

drop table "carnavalapp"."extras_productos";

drop table "carnavalapp"."horarios_tienda";

drop table "carnavalapp"."inventarioLogs";

drop function "carnavalapp"."actualizar_fecha_entrada"();

drop table "carnavalapp"."kpi_daily";

drop table "carnavalapp"."kpi_rec_rail_daily";

drop table "carnavalapp"."municipios";

drop table "carnavalapp"."notificaciones_usuario";

drop table "carnavalapp"."notificaciones";

drop table "carnavalapp"."order_details_bitacora";

drop table "carnavalapp"."order_status_history";

drop table "carnavalapp"."password_reset_codes";

drop table "carnavalapp"."payments";

drop table "carnavalapp"."posicion_repartidor_history";

drop table "carnavalapp"."posicion_repartidor";

drop table "carnavalapp"."preOrden";

drop table "carnavalapp"."proveedores";

drop function "carnavalapp"."fn_desactivar_productos_proveedor"();

drop table "carnavalapp"."repartidores";

drop table "carnavalapp"."sub_categorias";

drop table "carnavalapp"."transacciones";

drop table "carnavalapp"."user_tokens";

drop table "flow"."agenda";

drop table "flow"."app_dat_locales";

drop table "flow"."app_dat_servicios";

drop table "flow"."bot_log";

drop table "flow"."entidad_admin";

drop table "flow"."entidad_vendedor";

drop table "flow"."entidad";

drop table "flow"."local_servicio";

drop table "flow"."nom_estado_agenda";

drop table "flow"."nom_tipo_actividad_servicio";

drop table "flow"."notificaciones";

drop table "flow"."perfil";

drop table "flow"."plan_config";

drop table "flow"."plan_servicios";

drop function "flow"."trg_plan_servicio_procesar"();

drop table "flow"."plan_tramo";

drop function "flow"."trg_plan_tramo_procesar"();

drop table "flow"."recurso";

drop table "flow"."sala_espera_fraude";

drop table "flow"."sala_espera";

drop table "flow"."tramo";

drop table "flow"."turno_tramo";

drop table "flow"."turno";

drop table "flow"."ultimo_numero";

drop function "flow"."update_updated_at_column"();

drop table "muevete"."app_dat_estado_carga";

drop table "muevete"."app_nom_commodity";

drop table "muevete"."app_nom_equipo_manejo_carga";

drop table "muevete"."app_nom_estado";

drop table "muevete"."app_nom_tipo_carga";

drop table "muevete"."app_nom_tipo_equipo";

drop table "muevete"."app_nom_tipo_mercancia";

drop table "muevete"."app_nom_unidad_peso";

drop table "muevete"."cargas_equipo_manejo";

drop table "muevete"."cargas";

drop table "muevete"."carrocerias";

drop function "muevete"."set_updated_at"();

drop table "muevete"."configuracion_navegacion";

drop table "muevete"."direcciones_rapidas";

drop table "muevete"."drivers";

drop table "muevete"."notificaciones";

drop table "muevete"."ofertas_carga";

drop table "muevete"."ofertas_chofer";

drop table "muevete"."paradas_viaje";

drop table "muevete"."place";

drop table "muevete"."planes";

drop table "muevete"."push_tokens";

drop table "muevete"."solicitudes_plan";

drop table "muevete"."solicitudes_transporte";

drop table "muevete"."sub_usuarios";

drop table "muevete"."suscripciones";

drop table "muevete"."suscription_plan_user_history";

drop table "muevete"."suscription_plan";

drop table "muevete"."suscription_user";

drop table "muevete"."track_place_history";

drop table "muevete"."transacciones_wallet";

drop table "muevete"."users";

drop table "muevete"."valoraciones_viaje";

drop table "muevete"."vehicle_type";

drop table "muevete"."vehiculos";

drop table "muevete"."verificacion_operacion_recarga";

drop table "muevete"."viajes";

drop table "muevete"."wallet_drivers";

drop table "public"."app_cont_asignacion_costos";

drop table "public"."app_cont_centro_costo";

drop table "public"."app_cont_egresos_procesados";

drop table "public"."app_cont_gasto_asignacion";

drop table "public"."app_cont_gastos";

drop function "public"."fn_actualizar_asignaciones_gasto"();

drop function "public"."fn_registrar_asignaciones_gasto"();

drop table "public"."app_cont_historial_actividades";

drop table "public"."app_cont_historial_asignacion_costos";

drop table "public"."app_cont_historial_gastos";

drop table "public"."app_cont_log_costos";

drop table "public"."app_cont_margen_comercial";

drop table "public"."app_cont_tipo_costo";

drop table "public"."app_dat_actividad_usuario";

drop table "public"."app_dat_agente";

drop table "public"."app_dat_ajuste_inventario";

drop table "public"."app_dat_almacen_limites";

drop table "public"."app_dat_almacenero";

drop table "public"."app_dat_almacen";

drop table "public"."app_dat_application_rating";

drop table "public"."app_dat_atributo_opcion";

drop table "public"."app_dat_atributos";

drop table "public"."app_dat_caja_turno";

drop table "public"."app_dat_cambio_precio";

drop table "public"."app_dat_categoria_tienda";

drop table "public"."app_dat_categoria";

drop table "public"."app_dat_cliente_cxc";

drop table "public"."app_dat_clientes";

drop table "public"."app_dat_cocina";

drop function "public"."fn_cocina_marcar_almacen"();

drop function "public"."fn_touch_updated_at"();

drop table "public"."app_dat_codigos_barras";

drop table "public"."app_dat_comanda_item";

drop table "public"."app_dat_comanda";

drop function "public"."trg_comanda_touch"();

drop function "public"."trg_validar_comanda_cocina"();

drop table "public"."app_dat_configuracion_tienda";

drop function "public"."update_app_dat_configuracion_tienda_updated_at"();

drop table "public"."app_dat_consignacion_envio_movimiento";

drop table "public"."app_dat_consignacion_envio_producto";

drop table "public"."app_dat_consignacion_envio";

drop table "public"."app_dat_consignacion_zona";

drop table "public"."app_dat_contactos_clientes";

drop table "public"."app_dat_contrato_consignacion";

drop table "public"."app_dat_control_productos";

drop table "public"."app_dat_conversion_presentacion_evento";

drop table "public"."app_dat_conversion_presentacion_pata";

drop table "public"."app_dat_conversion_presentacion";

drop table "public"."app_dat_cumplimiento_inventario_solicitud";

drop table "public"."app_dat_denominaciones_moneda";

drop table "public"."app_dat_descuentos_vendedor";

drop table "public"."app_dat_entregas_parciales_caja";

drop table "public"."app_dat_estado_operacion";

drop function "public"."actualizar_estado_envio_aceptado"();

drop function "public"."actualizar_estado_envio_en_transito"();

drop function "public"."fn_registrar_gasto_por_recepcion"();

drop function "public"."fn_sincronizar_estado_orden_inverso"();

drop function "public"."trigger_validar_recepcion_consignacion"();

drop table "public"."app_dat_extraccion_productos";

drop table "public"."app_dat_extraccion_v2_solicitud";

drop table "public"."app_dat_garantia_uso";

drop table "public"."app_dat_garantia_venta";

drop table "public"."app_dat_gerente";

drop table "public"."app_dat_historial_pre_asignaciones";

drop table "public"."app_dat_inventario_productos";

drop function "public"."fn_notificar_producto_agotado"();

drop function "public"."fn_notificar_producto_disponible"();

drop function "public"."fn_sincronizar_stock_producto"();

drop function "public"."fn_validar_cantidad_final_inventario"(bigint, numeric);

drop table "public"."app_dat_jefe_cocina";

drop table "public"."app_dat_layout_abc";

drop table "public"."app_dat_layout_almacen";

drop table "public"."app_dat_layout_condiciones";

drop table "public"."app_dat_licencia_offline_secreto";

drop table "public"."app_dat_liquidacion_consignacion_backup";

drop table "public"."app_dat_liquidacion_consignacion";

drop table "public"."app_dat_liquidacion_cxc";

drop table "public"."app_dat_log_modificacion_orden";

drop table "public"."app_dat_mesa_cuenta_abierta";

drop table "public"."app_dat_mesa_cuenta_item";

drop table "public"."app_dat_mesas";

drop table "public"."app_dat_migracion_ajustes";

drop table "public"."app_dat_movimiento_consignacion";

drop table "public"."app_dat_notificaciones";

drop function "public"."update_notificaciones_updated_at"();

drop table "public"."app_dat_numero_paquete_tienda";

drop table "public"."app_dat_operacion_contabilizacion_historial";

drop table "public"."app_dat_operacion_extraccion";

drop table "public"."app_dat_operacion_offline_idempotencia";

drop table "public"."app_dat_operacion_recepcion";

drop table "public"."app_dat_operacion_transferencia";

drop table "public"."app_dat_operacion_venta";

drop function "public"."fn_actualizar_eliminar_pre_asignacion"();

drop table "public"."app_dat_operaciones";

drop function "public"."fn_auditar_operacion_contabilizada"();

drop table "public"."app_dat_pago_venta";

drop table "public"."app_dat_pre_asignaciones";

drop table "public"."app_dat_precio_costo";

drop table "public"."app_dat_precio_general_tienda";

drop table "public"."app_dat_precio_tpv";

drop table "public"."app_dat_precio_venta";

drop function "public"."sync_price_to_carnaval"();

drop function "public"."trg_convert_price_update_to_insert"();

drop function "public"."trg_round_precio_venta_cup"();

drop table "public"."app_dat_preferencias_notificaciones";

drop table "public"."app_dat_presentacion_unidad_medida";

drop function "public"."update_presentacion_um_updated_at"();

drop table "public"."app_dat_produccion_tanda";

drop table "public"."app_dat_producto_abc";

drop table "public"."app_dat_producto_consignacion_duplicado";

drop table "public"."app_dat_producto_consignacion";

drop table "public"."app_dat_producto_etiquetas";

drop table "public"."app_dat_producto_garantia";

drop table "public"."app_dat_producto_ingredientes";

drop table "public"."app_dat_producto_multimedias";

drop table "public"."app_dat_producto_presentacion";

drop function "public"."fn_trg_congelar_factor_presentacion"();

drop function "public"."fn_trg_registrar_precio_costo"();

drop table "public"."app_dat_producto_rating";

drop table "public"."app_dat_producto_unidades";

drop table "public"."app_dat_productos_subcategorias";

drop table "public"."app_dat_producto";

drop function "public"."fn_notificar_producto_nuevo"();

drop function "public"."fn_sincronizar_estado_producto"();

drop function "public"."fn_sincronizar_producto_carnaval"();

drop function "public"."fn_sync_producto_carnaval_nombre_descripcion"();

drop function "public"."fn_validar_producto_cocina"();

drop table "public"."app_dat_proveedor";

drop table "public"."app_dat_recepcion_productos";

drop table "public"."app_dat_recursos_humanos";

drop table "public"."app_dat_servicentro_producto";

drop function "public"."fn_trg_servicentro_producto_valido"();

drop table "public"."app_dat_subcategorias";

drop table "public"."app_dat_superadmin_roles";

drop function "public"."update_superadmin_roles_updated_at"();

drop table "public"."app_dat_superadmin";

drop table "public"."app_dat_supervisor";

drop table "public"."app_dat_suscripcion_catalogo";

drop table "public"."app_dat_suscripcion_notificaciones_producto";

drop table "public"."app_dat_suscripcion_notificaciones_tienda";

drop table "public"."app_dat_tienda_rating";

drop function "public"."update_updated_at_column"();

drop table "public"."app_dat_tienda";

drop table "public"."app_dat_tpv_cocina";

drop function "public"."fn_validar_tpv_cocina"();

drop table "public"."app_dat_tpv_dispositivos";

drop table "public"."app_dat_tpv";

drop table "public"."app_dat_trabajadores";

drop function "public"."fn_sync_trabajador_user_mail"();

drop table "public"."app_dat_turno_trabajadores";

drop function "public"."update_turno_trabajadores_updated_at"();

drop table "public"."app_dat_variantes";

drop table "public"."app_dat_vendedor_productos_default";

drop table "public"."app_dat_vendedor";

drop table "public"."app_inf_presentacion_producto";

drop function "public"."trg_app_inf_presentacion_producto_updated_at"();

drop table "public"."app_licencias_offline";

drop table "public"."app_mkt_campanas";

drop function "public"."trg_validar_campana"();

drop table "public"."app_mkt_cliente_promociones";

drop table "public"."app_mkt_comunicacion_clientes";

drop table "public"."app_mkt_comunicaciones";

drop table "public"."app_mkt_criterios_segmentacion";

drop table "public"."app_mkt_eventos_fidelizacion";

drop table "public"."app_mkt_function_logs";

drop table "public"."app_mkt_promocion_productos";

drop table "public"."app_mkt_promocion_segmento";

drop table "public"."app_mkt_promociones_audit";

drop table "public"."app_mkt_promociones";

drop function "public"."fn_before_upsert_app_mkt_promociones"();

drop table "public"."app_mkt_segmentos";

drop function "public"."trg_validar_segmento"();

drop table "public"."app_mkt_tipo_campana";

drop table "public"."app_mkt_tipo_promocion";

drop table "public"."app_nom_categoria_gasto";

drop table "public"."app_nom_conversiones_unidades";

drop table "public"."app_nom_estado_operacion";

drop table "public"."app_nom_medio_pago";

drop table "public"."app_nom_motivo_extraccion";

drop table "public"."app_nom_motivo_recepcion";

drop table "public"."app_nom_naturaleza_costo";

drop table "public"."app_nom_presentacion";

drop table "public"."app_nom_subcategoria_gasto";

drop table "public"."app_nom_tipo_condicion";

drop table "public"."app_nom_tipo_garantia";

drop table "public"."app_nom_tipo_layout_almacen";

drop table "public"."app_nom_tipo_operacion";

drop table "public"."app_nom_unidades_medida";

drop table "public"."app_suscripciones_historial";

drop table "public"."app_suscripciones_plan";

drop table "public"."app_suscripciones_renovaciones_resumen";

drop table "public"."app_suscripciones";

drop function "public"."trg_app_suscripciones_insert_catalogo"();

drop table "public"."app_versiones";

drop function "public"."fn_notificar_nueva_version"();

drop table "public"."app_wapi_destinatario";

drop table "public"."app_wapi_envio_log";

drop table "public"."app_wapi_licencia_plan";

drop table "public"."app_wapi_licencia";

drop table "public"."app_wapi_programacion_destinatario";

drop table "public"."app_wapi_programacion_producto";

drop table "public"."app_wapi_programacion";

drop function "public"."fn_wapi_recalc_next_run"();

drop table "public"."app_wapi_sesion";

drop function "public"."fn_wapi_set_updated_at"();

drop table "public"."auditor";

drop table "public"."codigo_producto";

drop table "public"."config_asistant_model";

drop function "public"."config_asistant_model_set_updated_at"();

drop table "public"."dep_dat_banco";

drop table "public"."dep_dat_deposito_foto";

drop table "public"."dep_dat_deposito";

drop table "public"."dep_dat_recarga_saldo";

drop table "public"."dep_dat_saldo";

drop table "public"."dep_hist_estado_deposito";

drop table "public"."dep_hist_saldo";

drop table "public"."dep_nom_estado_deposito";

drop table "public"."dep_nom_moneda";

drop table "public"."dep_nom_tipo_extraccion";

drop table "public"."hr_dat_asistencia";

drop table "public"."hr_dat_auditoria_salario";

drop table "public"."imp_dat_factura_foto";

drop table "public"."imp_dat_factura";

drop table "public"."imp_dat_recarga_saldo";

drop table "public"."imp_dat_saldo";

drop table "public"."imp_hist_estado_factura";

drop table "public"."imp_hist_saldo";

drop table "public"."imp_nom_estado_factura";

drop table "public"."monedas";

drop table "public"."municipios";

drop table "public"."paqueteria_ordenes";

drop table "public"."precio_global_productos_carnaval";

drop function "public"."fn_update_carnaval_product_prices"();

drop table "public"."project_docs";

drop table "public"."provincias";

drop table "public"."prv_dat_factura_foto";

drop table "public"."prv_dat_factura";

drop table "public"."prv_dat_proveedor_config";

drop table "public"."prv_dat_recarga_saldo";

drop table "public"."prv_dat_saldo";

drop table "public"."prv_hist_estado_factura";

drop table "public"."prv_hist_saldo";

drop table "public"."prv_nom_estado_factura";

drop table "public"."prv_nom_moneda";

drop table "public"."relation_products_carnaval";

drop table "public"."seg_roll";

drop table "public"."suscription_user";

drop table "public"."tasa_cambio_extraoficial";

drop function "public"."fn_actualizar_precios_cup_por_tasa"();

drop function "public"."fn_sync_valor_usd_carnaval"();

drop table "public"."tasas_conversion";

drop table "public"."tipos_moneda";

drop sequence "carnavalapp"."proveedor_serial";

drop sequence "flow"."entidad_vendedor_id_seq";

drop extension "pg_cron";

drop extension "pg_trgm";

drop extension "unaccent";

drop schema "carnavalapp";

drop schema "flow";

drop schema "muevete";

create or replace function public.fn_registrar_cambio_estado_operacion_mejorado (
  p_id_operacion bigint,
  p_nuevo_estado smallint,
  p_uuid_usuario uuid     default null::uuid
)
  returns jsonb
  language plpgsql
  AS $function$
DECLARE
    v_productos_extraidos RECORD;
    v_existente_estado RECORD;
    v_inventario_actual RECORD;
    v_ingrediente RECORD;
    v_cantidad_ingrediente_devolver NUMERIC;
    v_ultimo_inventario RECORD;
    v_es_recepcion BOOLEAN := FALSE;
    v_id_tienda BIGINT;
    v_cambiar_fecha_creacion BOOLEAN;
    v_response jsonb;
BEGIN
    -- Inicializar respuesta
    v_response := jsonb_build_object(
        'success', false,
        'message', '',
        'operation_id', p_id_operacion,
        'new_state', p_nuevo_estado
    );

    -- Primero, validar que el estado sea válido
    IF p_nuevo_estado NOT IN (1, 2, 3, 4) THEN
        v_response := jsonb_set(v_response, '{success}', 'false');
        v_response := jsonb_set(v_response, '{message}', '"Estado de operación inválido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)"');
        RETURN v_response;
    END IF;

    -- Verificar si ya existe un estado para esta operación
    SELECT * INTO v_existente_estado
    FROM app_dat_estado_operacion
    WHERE id_operacion = p_id_operacion
    ORDER BY created_at DESC
    LIMIT 1;

    -- Si el estado es el mismo que el último registrado, no hacer nada
    IF v_existente_estado.estado = p_nuevo_estado THEN
        v_response := jsonb_set(v_response, '{success}', 'true');
        v_response := jsonb_set(v_response, '{message}', '"La operación ya tiene este estado"');
        RETURN v_response;
    END IF;

    -- Insertar nuevo estado de operación
    INSERT INTO app_dat_estado_operacion (
        id_operacion,
        estado,
        uuid,
        created_at
    ) VALUES (
        p_id_operacion,
        p_nuevo_estado,
        p_uuid_usuario,
        NOW()
    );

    -- Si la operación se está completando y la tienda tiene activo el flag
    -- 'cambiar_fecha_creacion_operacion_al_cierre', actualizar la fecha de creación
    -- de la operación a la fecha/hora actual.
    IF p_nuevo_estado = 2 THEN
        SELECT id_tienda INTO v_id_tienda
        FROM app_dat_operaciones
        WHERE id = p_id_operacion;

        IF v_id_tienda IS NOT NULL THEN
            SELECT COALESCE(cambiar_fecha_creacion_operacion_al_cierre, false)
            INTO v_cambiar_fecha_creacion
            FROM app_dat_configuracion_tienda
            WHERE id_tienda = v_id_tienda;

            IF v_cambiar_fecha_creacion THEN
                UPDATE app_dat_operaciones
                SET created_at = NOW()
                WHERE id = p_id_operacion;
            END IF;
        END IF;
    END IF;

    -- Recepciones: al cancelar (4) o devolver (3) NO se retorna stock al inventario.
    -- Cancelar una recepción revierte el hecho de haber recibido mercancía, no debe sumar existencias.
    SELECT EXISTS (
        SELECT 1
        FROM app_dat_operacion_recepcion orp
        WHERE orp.id_operacion = p_id_operacion
    ) INTO v_es_recepcion;

    -- Si es devolución o cancelación de una operación con EXTRACCIÓN, devolver stock.
    -- Las recepciones solo cambian de estado; no insertan movimientos de inventario aquí.
    IF p_nuevo_estado IN (3, 4) AND NOT v_es_recepcion THEN
        -- Recuperar los productos extraídos originalmente
        FOR v_productos_extraidos IN (
            SELECT
                id_producto,
                id_variante,
                id_opcion_variante,
                id_presentacion,
                id_ubicacion,
                cantidad,
                sku_producto,
                sku_ubicacion
            FROM app_dat_extraccion_productos
            WHERE id_operacion = p_id_operacion
        ) LOOP

            -- Obtener inventario actual más reciente
            SELECT * INTO v_inventario_actual
            FROM app_dat_inventario_productos
            WHERE id_producto = v_productos_extraidos.id_producto
              AND COALESCE(id_variante, 0) = COALESCE(v_productos_extraidos.id_variante, 0)
              AND COALESCE(id_opcion_variante, 0) = COALESCE(v_productos_extraidos.id_opcion_variante, 0)
              AND COALESCE(id_presentacion, 0) = COALESCE(v_productos_extraidos.id_presentacion, 0)
              AND COALESCE(id_ubicacion, 0) = COALESCE(v_productos_extraidos.id_ubicacion, 0)
            ORDER BY created_at DESC
            LIMIT 1;

            -- Si no existe inventario previo, usar 0
            IF v_inventario_actual.cantidad_final IS NULL THEN
                v_inventario_actual.cantidad_final := 0;
            END IF;

            -- Actualizar inventario para devolver los productos
            INSERT INTO app_dat_inventario_productos (
                id_producto,
                id_variante,
                id_opcion_variante,
                id_presentacion,
                id_ubicacion,
                cantidad_inicial,
                cantidad_final,
                sku_producto,
                sku_ubicacion,
                origen_cambio,
                created_at
            ) VALUES (
                v_productos_extraidos.id_producto,
                v_productos_extraidos.id_variante,
                v_productos_extraidos.id_opcion_variante,
                v_productos_extraidos.id_presentacion,
                v_productos_extraidos.id_ubicacion,
                v_inventario_actual.cantidad_final,
                v_inventario_actual.cantidad_final + v_productos_extraidos.cantidad,
                v_productos_extraidos.sku_producto,
                v_productos_extraidos.sku_ubicacion,
                CASE
                    WHEN p_nuevo_estado = 3 THEN 4  -- Devolución
                    WHEN p_nuevo_estado = 4 THEN 5  -- Cancelación
                END,
                NOW()
            );
        END LOOP;

        -- Procesar productos elaborados para devolver ingredientes
        FOR v_productos_extraidos IN (
            SELECT
                ep.id_producto,
                ep.cantidad
            FROM app_dat_extraccion_productos ep
            INNER JOIN app_dat_producto p ON ep.id_producto = p.id
            WHERE ep.id_operacion = p_id_operacion
              AND p.es_elaborado = true
        ) LOOP

            -- Para cada producto elaborado, devolver sus ingredientes
            FOR v_ingrediente IN (
                SELECT
                    id_ingrediente,
                    cantidad_necesaria
                FROM app_dat_producto_ingredientes
                WHERE id_producto_elaborado = v_productos_extraidos.id_producto
            ) LOOP

                -- Calcular cantidad total de ingrediente a devolver
                v_cantidad_ingrediente_devolver := v_ingrediente.cantidad_necesaria * v_productos_extraidos.cantidad;

                -- Obtener el ÚLTIMO registro de inventario del ingrediente para obtener el id_presentacion
                SELECT * INTO v_ultimo_inventario
                FROM app_dat_inventario_productos
                WHERE id_producto = v_ingrediente.id_ingrediente
                ORDER BY created_at DESC
                LIMIT 1;

                -- Si no existe inventario previo del ingrediente, usar valores por defecto
                IF v_ultimo_inventario IS NULL THEN
                    v_ultimo_inventario.cantidad_final := 0;
                    v_ultimo_inventario.id_presentacion := NULL;
                    v_ultimo_inventario.id_ubicacion := NULL;
                    v_ultimo_inventario.sku_producto := NULL;
                    v_ultimo_inventario.sku_ubicacion := NULL;
                END IF;

                -- Devolver ingrediente al inventario usando el id_presentacion del último registro
                INSERT INTO app_dat_inventario_productos (
                    id_producto,
                    id_variante,
                    id_opcion_variante,
                    id_presentacion,
                    id_ubicacion,
                    cantidad_inicial,
                    cantidad_final,
                    sku_producto,
                    sku_ubicacion,
                    origen_cambio,
                    created_at
                ) VALUES (
                    v_ingrediente.id_ingrediente,
                    COALESCE(v_ultimo_inventario.id_variante, NULL),
                    COALESCE(v_ultimo_inventario.id_opcion_variante, NULL),
                    v_ultimo_inventario.id_presentacion,
                    COALESCE(v_ultimo_inventario.id_ubicacion, NULL),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0) + v_cantidad_ingrediente_devolver,
                    COALESCE(v_ultimo_inventario.sku_producto, NULL),
                    COALESCE(v_ultimo_inventario.sku_ubicacion, NULL),
                    CASE
                        WHEN p_nuevo_estado = 3 THEN 6  -- Devolución de ingredientes
                        WHEN p_nuevo_estado = 4 THEN 7  -- Cancelación de ingredientes
                    END,
                    NOW()
                );
            END LOOP;
        END LOOP;
    END IF;

    -- Retornar respuesta exitosa
    v_response := jsonb_set(v_response, '{success}', 'true');
    v_response := jsonb_set(v_response, '{message}', '"Operación actualizada exitosamente"');

    RETURN v_response;
EXCEPTION WHEN OTHERS THEN
    v_response := jsonb_set(v_response, '{success}', 'false');
    v_response := jsonb_set(v_response, '{message}', to_jsonb(SQLERRM));
    RETURN v_response;
END;
$function$;

alter default privileges for role "postgres" in schema "public" grant maintain, references, trigger, truncate on tables to "anon";

alter default privileges for role "postgres" in schema "public" grant maintain, references, trigger, truncate on tables to "authenticated";

alter default privileges for role "postgres" in schema "public" grant maintain, references, trigger, truncate on tables to "service_role";
