# Alta de tienda: Dueño automático, diseño nuevo y tutorial guiado

Estado al 2026-11-24. Rama `feat/registro-tienda-tutorial`.

## 1. El creador queda como Dueño (`app_dat_dueno`)

### El defecto

`crear_estructura_tienda` metía al usuario principal en `app_dat_gerente` y
`app_dat_supervisor` (por el `personal_data` que manda el cliente), pero **nunca
escribía en `app_dat_dueno`**. Consecuencias reales, no cosméticas:

- `fn_user_is_dueno(tienda)` devolvía `false` → el creador no ve ganancias.
- `fn_m01_fuentes_puede_gestionar_duenos(tienda)` → `false` → no puede asignar
  el rol Dueño a nadie.
- El listado de personal no lo mostraba como Dueño.

Las tiendas 3, 5 y 6 de newa se crearon así: tienen gerente y supervisor, cero
filas de Dueño.

Segundo defecto, menor pero visible: la RPC insertaba los trabajadores **sin la
columna `uuid`**, aunque el cliente la manda en `personal_data`. El trigger
`fn_sync_trabajador_user_mail` no podía rellenar el correo (dispara sobre
`INSERT OR UPDATE OF uuid`) y el Dueño acababa con `id_trabajador` nulo.

### El arreglo

`sql_updates/fn_m01_crear_estructura_tienda_dueno.sql` reescribe el wrapper
`fn_m01_crear_estructura_tienda`, que **ya era `SECURITY DEFINER`** y ya conocía
el `auth.uid()` del creador. Tras crear la estructura:

1. Localiza el trabajador del creador por su posición en `personal_data` (la RPC
   los inserta en ese orden) o por `uuid` si ya lo tuviera, y le escribe el
   `uuid`. El trigger rellena el correo.
2. Inserta en `app_dat_dueno` con `NOT EXISTS` (idempotente).
3. Inserta en `app_dat_gerente` con `NOT EXISTS`, para que las RPC históricas
   que comprueban ese rol sigan autorizándolo.

Decisiones:

- **No se toca `crear_estructura_tienda`.** Es `INVOKER` (9 KB de cuerpo) y su
  `EXECUTE` está revocado a `authenticated`: un `INSERT` en `app_dat_dueno` desde
  ahí lo bloquearía la RLS (`app_dat_dueno_insert` exige
  `fn_m01_fuentes_puede_gestionar_duenos`, que consulta la propia tabla). En el
  wrapper `DEFINER` la escritura sí procede.
- **El alta del Dueño no tumba la tienda.** El `BEGIN ... EXCEPTION` interno
  deja `dueno_registrado: false` y `dueno_error` en el JSON. Una tienda creada
  sin Dueño es recuperable; una transacción abortada pierde el alta entera.
- **El cliente avisa.** `_createStore` en `store_registration_screen.dart` lee
  `store_data.dueno_registrado`; si es `false` muestra un diálogo que dice que
  la tienda se creó pero el rol no, y qué hacer (no reintentar el alta).

### Verificación

Ejecutado en newa (`qhprswhhfasrikhawjoz`) dentro de una transacción con
`SET LOCAL ROLE authenticated` y el claim del usuario, y revertido con
`ROLLBACK`:

```
tienda=12  dueno_trab=22  trab_uuid=3d7bae51-…  user_mail=aicemaria@gmail.com
es_dueno_creador=true   dueno_registrado=true
```

## 2. Diseño nuevo del asistente

Cuatro pasos, misma piel en todos: AppBar blanca con borde inferior fino, icono
de tutorial y de cerrar; stepper de 4 pasos sobre fondo blanco (el azul se
reserva para lo accionable); pie fijo con «Anterior» y «Siguiente».

Diseñado con Stitch sobre el design system **Executive Precision** (primario
`#194B8C`, secundario `#123A6B`, acento `#EFF4FF`, superficie `#F8F9FA`, texto
`#1F2937`/`#6B7280`, borde `#E5E7EB`). Proyecto Stitch
`12666774752023016284`:

- Paso 1 — `aaa8fb5d6d7f4eb4a06b52fe579de717`
- Paso 2 — `a63e3364f10b4b9093a5b1f7c46a969e`
- Login — `d99d3ec1d4a84fe1a91d2363ad62da57`

Cambios frente a lo anterior:

- Paso 1 a dos columnas en ≥1080 px: formulario + panel lateral de valor. En
  móvil el panel se cae y queda solo el formulario.
- Campos con **etiqueta propia encima** (no `labelText` flotante): el texto que
  explica el campo no compite con el título del input.
- Medidor de fuerza de contraseña (no bloquea, informa) y ojo para mostrar.
- Paso 2 con el mapa al lado en ≥1000 px y debajo en móvil.
- Paso 3 con las tarjetas de almacén/TPV/personal en la misma piel.
- Paso 4 como resumen en dos columnas con filas «etiqueta : valor».
- Login a dos paneles: marca a la izquierda, formulario a la derecha; en móvil
  el panel se cae y queda un encabezado compacto con el logo.

## 3. Tutorial guiado

El motor vive en `lib/widgets/tutorial_guiado.dart` (`PasoGuiado`,
`mostrarTutorialGuiado`, `AvisoTutorial`, `insertarAvisoTutorial`). El módulo
Compras ya lo usaba; `screens/compras/compra_tutorial.dart` queda como alias,
así que su contrato de pruebas no cambia.

Cómo se comporta:

- La burbuja «¿Tienes dudas?» aparece **sola** al entrar en el alta, colgada del
  icono del AppBar, y también al pulsarlo.
- Al aceptar, el recorrido resalta cada campo con un velo y un agujero
  (`CustomPaint` + `Path.combine(difference)`), dejando el resto en sombra.
- Cada paso lleva su `GlobalKey`; si el campo no está montado, se salta en vez
  de dejar un globo huérfano.
- **`PasoGuiado.alEntrar`** es lo que permite recorrer el asistente entero: el
  paso manda a la pantalla cambiar de página (o de pestaña) y el recorrido
  espera un frame antes de medir. Sin eso, los campos de los pasos 2, 3 y 4 no
  existirían en el `PageView` y el tutorial solo explicaría el paso 1.
- Hay 14 pasos: cuenta (nombre, teléfono, email, contraseña, confirmación, IA),
  tienda (nombre, dirección, país/provincia/ciudad, mapa), configuración
  (almacenes, TPVs, personal) y resumen.

## Pruebas

```
flutter test --no-pub test/store_registration_dueno_tutorial_test.dart \
                test/compra_ayuda_tutorial_test.dart \
                test/app_compile_test.dart
```

`test/store_registration_dueno_tutorial_test.dart` cubre: el SQL escribe en
`app_dat_dueno`, es idempotente, enlaza el trabajador, no tumba el alta; el
login y el paso 1 no desbordan a 390 px; la burbuja arranca el recorrido; un
paso con `alEntrar` cambia de página antes de medir; cerrar la burbuja dos veces
no lanza.

Las pruebas de contrato SQL inspeccionan el archivo; **no sustituyen** una
ejecución real en PostgreSQL. La verificación transaccional descrita arriba es
la que vale.

## Pendiente

- Las tiendas sin Dueño (3, 5, 6 y la 1 sin roles) se arreglan asignándolo a
  mano con la RPC existente. La consulta de identificación está al final del
  script.
- El pase a main sigue el procedimiento de `tasks/plan_promocion_main.md`; este
  cambio no se ha promovido.
