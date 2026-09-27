# Implementation Plan: Home Banners Superadmin

## Overview
Gestionar los banners del carrusel de inicio de la app Carnaval (`carnavalAPP`) desde `ventiq_superadmin`. Incluye el schema SQL en Supabase, RPCs de administración, y una pantalla en Flutter para listar, crear, editar, activar/desactivar y eliminar banners con upload de imágenes.

## Architecture Decisions
- Tabla en schema `carnavalapp`: `home_banners`.
- Acceso solo por RPCs `SECURITY DEFINER`; RLS bloquea acceso directo a `authenticated`/`anon` con policies explícitas.
- El superadmin sube la imagen a un bucket de Supabase Storage existente (`imagenes/banners/`) y guarda la URL pública en `image_url`.
- Bucket/path por defecto: `imagenes/banners/home_banner_<uuid>.<ext>`.
- Ruta en el superadmin: `/banners-inicio` bajo el grupo **Marketing**.
- El hard-delete solo está disponible para admins con `hasFullAccess()` (nivel 1).

## Task List

1. SQL migration: tabla + RPCs + RLS en `carnavalAPP/sql_updates/rpc-api/20_home_banners.sql`.
2. Modelo `HomeBanner` y servicio `HomeBannersService` con métodos list/upsert/delete/upload.
3. Registro de ruta `/banners-inicio`, entrada de menú `Marketing → Banners inicio` y `RouteGuard`.
4. Pantalla `HomeBannersScreen`: listado, preview, formulario create/edit, toggle activo, soft/hard delete.
5. Verificación: `flutter analyze` sobre archivos tocados sin errores nuevos.

## Risks and Mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| Bucket `imagenes` no existe en Supabase | Alto | Verificar/crear bucket antes de ejecutar la app; dejar documentado en el README |
| RPC no devuelve el tipo esperado | Medio | Servicio maneja `Map` y `List<Map>` como fallback |
| Permisos insuficientes para ejecutar RPCs | Alto | Grants a `authenticated` en el SQL; app requiere login de superadmin |

## Open Questions
- ¿El bucket de Storage debe crearse con este script o ya existe `imagenes` en producción?
- ¿Se requiere soporte drag-and-drop para ordenar o es suficiente el campo numérico `orden`? (se implementó el campo).
