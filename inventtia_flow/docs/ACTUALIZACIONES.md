# Actualizaciones y novedades de GoReserva

Cómo la app detecta que hay una versión nueva, cómo se entera el usuario **de lo que cambia** y qué hay que hacer en cada publicación.

---

## 1. El circuito

1. Al entrar en la app (y al pulsar **Buscar actualizaciones** en Perfil), `UpdateService` lee la **versión realmente instalada** con `package_info_plus` (`version:` de `pubspec.yaml` + su build) y llama a `public.fn_check_update(app_name, version, build)`.
2. El servidor compara ese build con la **última versión activa** de `public.app_versiones`. Marca `obligatoria` si el flag está puesto **o** si la versión instalada es menor que `version_minima`.
3. Si hay versión nueva, sale el **aviso** con: versión y build, fecha, título, **changelog completo** (con icono por tipo de cambio) y el botón **Descargar ahora** —que abre el mismo enlace de descarga que se usa en la web—. Si es **obligatoria**, el aviso no se puede cerrar: sin aspa, sin «Más tarde» y sin cierre por toque fuera.
4. El enlace **«Ver historial de cambios»** abre la pantalla **Novedades**, que lista todas las versiones publicadas (RPC `fn_app_versiones`) con la **instalada marcada**. Si falla la red, cae al historial que va empaquetado en `assets/changelog.json`, y el aviso lo dice («datos de la app»).

> El changelog no cuelga del binario: vive en la base de datos. Se puede publicar una versión **con sus novedades** sin recompilar nada para el texto.

---

## 2. Piezas

| Pieza | Dónde | Para qué |
|---|---|---|
| `public.app_versiones` | BD | Una fila por versión publicada. Columnas nuevas: `titulo`, `novedades` (array jsonb), `url_descarga`. |
| `public.fn_check_update` | BD | ¿Hay actualización? Conserva sus claves de siempre y añade `titulo`, `novedades`, `url_descarga`, `build_disponible`. |
| `public.fn_app_versiones` | BD | Historial (versiones activas, de la más nueva a la más vieja, límite 1..100). |
| `public.fn_app_version_guardar` / `_eliminar` | BD | Publicar/editar/borrar desde el panel (solo superadmin). |
| `lib/services/update_service.dart` | App | Versión instalada, aviso actual, historial, URL de descarga. |
| `lib/models/version_app.dart` | App | Un modelo para las tres fuentes (los dos RPC y el asset). |
| `lib/widgets/aviso_actualizacion.dart` | App | El diálogo y las tarjetas del changelog. |
| `lib/screens/novedades_screen.dart` | App | Historial completo + «Buscar actualizaciones». |
| `ventiq_superadmin → Versiones de las apps` | Panel | Publicar versiones con changelog, con vista previa de cómo lo verá el usuario. |

**Formato de `novedades`** (array jsonb, se dibuja como tarjetas):

```json
[
  {"type": "feature",     "title": "Cobros por adelantado", "description": "Configura y verifica los pagos desde su propia pantalla."},
  {"type": "improvement", "title": "Historial de cambios",  "description": "Consulta qué cambió en cada versión."},
  {"type": "fix",         "title": "Cálculo del cambio",    "description": "La suscripción se cobra siempre en CUP."}
]
```

`feature` = Novedad · `improvement` = Mejora · `fix` = Corrección. Cualquier otro tipo se pinta como «Cambio».

---

## 3. Publicar una versión (checklist)

1. **Sube el build** en `pubspec.yaml` (`version: 1.4.8+16`). Es el **build** lo que decide si salta el aviso; la versión en texto se usa para `version_minima` y para el historial.
2. `flutter build apk --release` y **sube el APK** al almacenamiento de Supabase.
3. **Changelog**: añade la entrada a `assets/changelog.json` (viaja dentro del APK, sirve de respaldo offline) **y** publícala en el panel para que el aviso llegue a quien todavía tiene la versión vieja.
4. **Panel → Versiones de las apps → Nueva versión**: app (`inventtia_flow`), versión, build, **versión mínima** (obligatoria; normalmente la misma que publicas), obligatoria sí/no, título, cambios (tipo + título + descripción) y **URL de descarga** solo si el APK no está en el enlace por defecto. La vista previa muestra cómo quedará en el móvil.
5. **Comprueba** con:

```sql
select public.fn_check_update('inventtia_flow', '1.4.7', 15);
select public.fn_app_versiones('inventtia_flow');
```

---

## 4. Avisos importantes

- **Un solo archivo de descarga.** `UpdateService.downloadUrl` apunta a `…/storage/v1/object/public/apk/goreservas.apk`, que **se sobrescribe** en cada subida: todos los avisos descargan el último APK, sin historial de binarios. Si quieres conservar versiones, súbelas con nombre por build (`flow-1.4.8-16.apk`) y rellena `url_descarga` en cada fila.
- **Desfase de versiones detectado (30-10-2026).** `assets/changelog.json` decía `1.4.8` build `16`, `pubspec.yaml` dice `1.4.0+8` y la última de la BD es `1.4.7` build `15`. Antes la app reportaba la del asset, así que se creía **más nueva que la BD y no avisaba nunca**. Ahora reporta la instalada de verdad; conviene alinear: subir `pubspec.yaml` a la versión que se publique y registrarla en el panel.
- **`package_info_plus`** se usa para leer la versión instalada y hoy llega como dependencia transitiva (vía `share_plus`). Funciona, pero lo correcto es declararla en `pubspec.yaml` (`package_info_plus: ^9.0.1`) y ejecutar `flutter pub get`.
- **Seguridad.** La migración 75 endurece `app_versiones`: antes cualquier usuario autenticado podía insertar/editar/borrar versiones (y, con `url_descarga`, publicar un APK falso). Ahora solo hay lectura para `authenticated`; la escritura pasa por los RPC con guard de superadmin.
- **Permisos del panel.** La ruta `/versiones` entra en las protegidas: si usas roles personalizados, hay que concederles el permiso.

---

## 5. Migración

Todo esto depende de [75_app_versiones_novedades.sql](flow_schema/migraciones/75_app_versiones_novedades.sql) (schema `public`, compartido con las otras apps del ecosistema: solo añade columnas y claves nuevas, no rompe a ninguna). Mientras no se aplique, la app funciona: el aviso se rellena con el changelog empaquetado y el historial cae al asset.
