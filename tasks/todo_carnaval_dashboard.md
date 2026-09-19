# Tasks: Dashboard de proveedor Carnaval

- [ ] Task 1: Crear SQL/RPC `fn_dashboard_carnaval_proveedor`
  - Acceptance: función devuelve resumen, evolución diaria, top productos y métricas por método de pago para un proveedor + rango.
  - Verify: lectura del SQL, no errores de sintaxis, `flutter analyze` del servicio.
  - Files: `ventiq_admin_app/lib/sql/carnaval_provider_dashboard.sql`, `ventiq_admin_app/lib/services/carnaval_service.dart`.

- [ ] Task 2: Crear modelo de datos
  - Acceptance: tipos limpios para resumen, serie diaria, top productos, métodos de pago.
  - Verify: analyze del modelo.
  - Files: `ventiq_admin_app/lib/models/carnaval_provider_dashboard_data.dart`.

- [ ] Task 3: Crear pantalla `CarnavalProviderDashboardScreen`
  - Acceptance: muestra fecha, resumen, gráfico, top productos, estados, métodos de pago, ticket promedio.
  - Verify: analyze de la pantalla, sin errores de build.
  - Files: `ventiq_admin_app/lib/screens/carnaval_provider_dashboard_screen.dart`.

- [ ] Task 4: Integrar navegación
  - Acceptance: botón visible en `CarnavalTabView` cuando está sincronizado; ruta registrada.
  - Verify: analyze de widget y main, navegación compila.
  - Files: `ventiq_admin_app/lib/widgets/carnaval_tab_view.dart`, `ventiq_admin_app/lib/main.dart`.

- [ ] Checkpoint final: `flutter analyze` limpio en `ventiq_admin_app` para archivos nuevos.
