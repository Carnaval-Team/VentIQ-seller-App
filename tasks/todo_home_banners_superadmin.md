# Tasks: Home Banners Superadmin

- [x] Task 1: Crear SQL de migración `20_home_banners.sql` (tabla + RPCs + RLS)
  - Acceptance: tabla `carnavalapp.home_banners` con RLS, policies de denegación directa, y 4 RPCs usables.
  - Verify: revisar script SQL y grants.
  - Files: `carnavalAPP/sql_updates/rpc-api/20_home_banners.sql`.

- [x] Task 2: Modelo y servicio en `ventiq_superadmin`
  - Acceptance: `HomeBanner.fromJson/toJson`, `HomeBannersService.listBanners/upsertBanner/deleteBanner/uploadImage`.
  - Verify: `flutter analyze` sin errores.
  - Files: `ventiq_superadmin/lib/models/home_banner.dart`, `ventiq_superadmin/lib/services/home_banners_service.dart`.

- [x] Task 3: Ruta y menú
  - Acceptance: `/banners-inicio` registrado, accesible desde drawer `Marketing → Banners inicio`, respetado por `RouteGuard`.
  - Verify: `flutter analyze` sobre `app_routes.dart`, `app_drawer.dart`, `main.dart`.
  - Files: `ventiq_superadmin/lib/config/app_routes.dart`, `ventiq_superadmin/lib/widgets/app_drawer.dart`, `ventiq_superadmin/lib/main.dart`.

- [x] Task 4: Pantalla `HomeBannersScreen`
  - Acceptance: listado, preview de imagen 16:7, formulario create/edit con upload, toggle activo, soft/hard delete, estados vacío/error/carga.
  - Verify: `flutter analyze` sin errores.
  - Files: `ventiq_superadmin/lib/screens/home_banners_screen.dart`.

- [x] Task 5: Verificación de análisis
  - Acceptance: archivos tocados sin warnings/errores nuevos.
  - Verify: `flutter analyze` sobre cada archivo modificado/creado.
  - Resultado: 0 issues en archivos del feature.
