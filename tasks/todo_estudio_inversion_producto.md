# Tasks: Estudio de inversión del producto

Spec: `tasks/SPEC-estudio-inversion-producto.md`. Plan: `tasks/plan_estudio_inversion_producto.md`.

- [x] Task 1: Función pura del estudio
  - Acceptance: parte recepciones cuando el stock del producto, sumando variantes y ubicaciones en unidades base, llega a 0; convierte la venta CUP con la tasa de esa fecha y la venta USD sin volver a dividir; `cumplimiento` es null si falta la tasa o la meta es 0.
  - Verify: queda cubierta por la tarea 2.
  - Files: `ventiq_admin_app/lib/models/estudio_inversion.dart`.

- [x] Task 2: Tests del cálculo
  - Acceptance: 5.000 × 0,30 y 2.000 a 0,60 dan 0,80; la misma venta en USD no se divide por 850; una recepción con stock positivo se suma a la meta; una recepción después del cero abre otro tramo y no cambia el 80 %; sin tasa el cumplimiento es null.
  - Verify: `flutter.bat test --no-pub test/estudio_inversion_test.dart` desde `ventiq_admin_app`.
  - Files: `ventiq_admin_app/test/estudio_inversion_test.dart`.
  - Dependencies: Task 1.

- [x] Checkpoint: el cálculo del ejemplo y del corte pasa sin red.

- [x] Task 3: Lectura histórica
  - Acceptance: carga todas las recepciones, ventas, movimientos y precios del producto en la tienda, sin el rango de fechas de Tiempo real, y se las pasa a la función pura. Una recepción sin factor de presentación no entra y deja el tramo incompleto.
  - Verify: analyze del servicio.
  - Files: `ventiq_admin_app/lib/services/estudio_inversion_service.dart`.
  - Dependencies: Task 1.

- [x] Task 4: Vista y botón
  - Acceptance: el historial cronológico conserva su rango; con `_canViewGanancias` la cabecera abre el estudio; sin ese permiso el botón no está. Cada tramo muestra sus recepciones, la meta, lo recaudado y el porcentaje, solo en USD. No hay un total que sume tramos.
  - Verify: `flutter.bat analyze` de los archivos nuevos y de `sales_screen.dart`.
  - Files: `ventiq_admin_app/lib/screens/estudio_inversion_producto_dialog.dart`, `ventiq_admin_app/lib/screens/sales_screen.dart`.
  - Dependencies: Task 3.

- [x] Checkpoint: el historial no cambia y el estudio se abre desde él.
