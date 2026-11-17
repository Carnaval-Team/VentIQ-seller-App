# M07 — lo que falta después de los scripts 40 a 44

El flag sigue apagado. Este archivo no autoriza encenderlo, no elige una tienda y no se ejecuta como prueba de la app.

## MC-048 — lectura y rechazo

1. Pegar `m01_r23_revocar_anon_mesa_cxc_propuesta.sql`. Quita EXECUTE de `anon` en las siete funciones de mesa, deuda y devolución. No escribe ventas.
2. Pegar `m01_m07_harness_rechazo.sql`. Tiene que terminar con el aviso de rechazo y `ROLLBACK`. Si dice que `anon` todavía ejecuta una función, el paso 1 no quedó aplicado.
3. Volver a correr `verificar_m01_lote_40_44.sql`. `anon_pedir` tiene que pasar a `true`.

## Dos sesiones — no correr todavía

Hace falta una tienda de prueba autorizada y el flag encendido solo en esa tienda. Sin eso, las dos llamadas mueren en "Activacion de moneda por producto no autorizada" y no llegan al candado.

Cuando exista esa autorización, en dos pestañas del SQL Editor, la misma clave y la misma cuenta:

1. Pestaña A llama `fn_m01_pedir_item_mesa_v1` y no confirma.
2. Pestaña B llama la misma función con la misma `client_uuid` y otro cuerpo. Tiene que recibir `42501` y no descontar otra vez.
3. Pestaña A confirma. Pestaña B, con el mismo cuerpo, devuelve `idempotent: true` y el mismo `id_item`.
4. Las dos pestañas revierten si la tienda no es el fixture aprobado.

## MC-049 — recorridos

La decisión está en `ventiq_app/lib/money/piloto_v1.dart` y en `test/piloto_v1_test.dart`.

- Sin caché, una orden nueva no sale y una `producto-v1` se conserva.
- Otra tienda se rechaza.
- Una respuesta que no volvió reintenta la clave ya guardada.
- Un segundo cobro con otro medio no entra. El cierre no vuelve a descontar lo ya pedido.
- La lectura en newa no encontró ninguna venta `producto-v1` aceptada.

No hay tienda de prueba autorizada ni recorrido desde la app. Eso sigue pendiente.

## MC-050 — activación

`PilotoV1.puedeEncender` solo es verdadero con anon revocado, comanda corregida, pendientes identificados, ticket físico y un sí explícito. Hoy falta el sí y el ticket. La tienda no se enciende. `main` no se toca.

En newa, `verificar_m01_m07_piloto.sql` devolvió flag apagado, anon sin ejecutar, comanda solo al pedido y ninguna venta v1.

## MC-051 — apagado

Con el flag apagado, una venta nueva sin versión sigue el cobro anterior. Una orden `producto-v1` ya empezada se reintenta con su clave y, si no la tiene, se conserva. No se borra el esquema ni la cola. La guarda `m01_venta_legacy_con_flag` en newa es `BEFORE INSERT` y no reescribe la venta.
