---
name: ventiq-flutter-workspace
description: Mapa del monorepo Flutter de VentiQ/Inventtia (7 apps, provider + supabase_flutter) y cómo analizarlas con el MCP de Dart ya configurado. Úsala antes de explorar, analizar, corregir o modificar cualquier app Flutter de este workspace.
---

# Workspace Flutter VentiQ / Inventtia

Monorepo con 7 apps Flutter independientes (cada una con su propio `pubspec.yaml`,
`lib/` y `test/`) más migraciones y SQL de Supabase compartido. No hay melos ni
workspace pub: cada app se resuelve por separado.

## Mapa de apps

| Directorio | Paquete | Qué es | Versión | SDK |
|---|---|---|---|---|
| `ventiq_app/` | `ventiq_app` | Inventtia Caja — TPV: ventas, caja, turnos | 2.6.0+850 | ^3.7.0 |
| `ventiq_admin_app/` | `ventiq_admin_app` | Inventtia Gestión — inventarios, productos, ventas | 2.9.1+290 | ^3.10.0 |
| `ventiq_superadmin/` | `ventiq_superadmin` | Inventtia Super Admin — administración global de tiendas | 1.0.0+1 | ^3.7.0 |
| `ventiq_marketplace/` | `ventiq_marketplace` | Catálogo de la suite Inventtia | 1.6.0+15 | ^3.8.1 |
| `ventiq_licencer_express/` | `ventiq_licencer_express` | Licenciamiento / express | 1.0.0+1 | ^3.8.1 |
| `inventtia_flow/` | `inventtia_flow` | GoReserva — colas y turnos de servicios | 1.3.3+7 | ^3.8.1 |
| `inventtia_muevete/` | `inventtia_muevete` | Muevete — ride-hailing de pasajeros | 1.0.0+1 | ^3.8.1 |

## Stack y arquitectura

- **Toolchain**: Flutter 3.44.0 / Dart 3.12.0, SDK en `C:\Users\cesar\Documents\develop\flutter`.
- **Estado**: `provider` (`ChangeNotifier`) en las 7 apps. No hay riverpod, bloc, getx ni mobx.
- **Backend**: `supabase_flutter` en las 7. El backend compartido vive en `supabase/`
  (`migrations/`, `functions/`) y hay mucho SQL suelto en la raíz del repo
  (`*.sql`, `sql_updates/`, `sql_triggers/`, `SQL_OPTIMIZATION/`).
- **Layout típico por app**: `lib/{config, models, screens, services, widgets}` con
  variantes: `providers/` en `inventtia_flow`, `inventtia_muevete` y `ventiq_marketplace`;
  `ventiq_admin_app` añade `sql/` y `widgets_home/`; `ventiq_licencer_express` añade
  `auth/`, `data/` y `theme/`.
- **Docs de producto**: `docs/` (planes y tutoriales de cocina, servicentro,
  presentaciones de inventario), `CAPABILITY-MAP.md`, `SPEC-*.md`, `PLAN_OFFLINE_COMPLETO.md`.

## Analizar el código con el MCP de Dart

El servidor MCP `dart` (Dart/Flutter tooling) está configurado en el perfil de DSH.
Sus herramientas se llaman `mcp__dart__*`.

**Paso obligatorio primero**: `analyze_files`, `lsp` y el resto de herramientas por
proyecto solo existen después de registrar al menos un *root*. Con cero roots el
servidor solo expone `dtd`, `pub`, `pub_dev_search`, `read_package_uris`,
`rip_grep_packages`, `roots` y las de runtime.

```
mcp__dart__roots  { "command": "add", "uris": ["file:///C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_app"] }
```

Registra solo las apps que vayas a tocar: cada root levanta su propio contexto de
análisis. Tras añadirlo aparecen `analyze_files` y `lsp` (y `run_tests`, `dart_fix`,
`dart_format`, que están habilitadas explícitamente en la configuración).

| Necesidad | Herramienta |
|---|---|
| Errores/warnings de una app | `mcp__dart__analyze_files` con `roots: [{root: "file:///.../<app>"}]` |
| Docs, tipos y firmas de un símbolo | `mcp__dart__lsp` `hover` / `signatureHelp` (requiere `uri`, `line`, `column`) |
| Buscar un símbolo por nombre | `mcp__dart__lsp` `resolveWorkspaceSymbol` con `query` |
| Tests | `mcp__dart__run_tests` con `roots` |
| Lint/fixes y formato | `mcp__dart__dart_fix`, `mcp__dart__dart_format` |
| Dependencias | `mcp__dart__pub` (`get`, `deps`, `outdated`, `upgrade`), `mcp__dart__pub_dev_search` |
| Leer un paquete del pub cache | `mcp__dart__read_package_uris`, `mcp__dart__rip_grep_packages` |

Para apps **en ejecución** (el usuario lanza `flutter run`, o VS Code), usa
`mcp__dart__dtd` → `listDtdUris` y luego `connect`; a partir de ahí funcionan
`get_runtime_errors` (stack traces reales), `hot_reload`, `hot_restart` y
`widget_inspector` (`get_widget_tree`). Es más fiable que adivinar la causa de un
error de runtime leyendo el código.

## Comandos de shell

`flutter` y `dart` están en el PATH. **En el shell de DSH hay que redirigir
`APPDATA`** o el CLI de Dart falla al escribir su telemetría (el sandbox bloquea
`%APPDATA%\.dart-tool`) y el proceso muere con `PathAccessException`:

```powershell
$env:APPDATA = 'C:\Users\cesar\Documents\VentIQ-seller-App\.dsh\dart-tool'
cd ventiq_app
flutter analyze    # o: flutter test, dart format .
```

La primera invocación de `flutter` en una sesión puede tardar minutos (check de
versión y locks); lánzala como job en background en vez de bloquear.

## Precauciones

- Las 7 apps comparten backend Supabase: un cambio de esquema o de RLS afecta a
  todas. Revisa `supabase/migrations/` y los `*.sql` de la raíz antes de tocar datos.
- `veniq_admin_app` usa `sdk: ^3.10.0`; varias apps usan `^3.7.0`, así que no
  asumas APIs nuevas de Dart disponibles en todas.
- `analysis_options.yaml` puede diferir por app: verifica el linter efectivo de la
  app concreta antes de aplicar `dart fix`.
