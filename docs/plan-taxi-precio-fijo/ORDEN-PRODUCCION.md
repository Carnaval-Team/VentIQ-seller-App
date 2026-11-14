# Orden de ejecución en producción

> Proyecto: `vsieeihstajlrdvpuooh` · Fecha: 2026-11-14
> Detalle largo, si hace falta: [`14-despliegue-y-cutover.md`](14-despliegue-y-cutover.md)

---

## 0 · Antes de empezar

- [ ] Backup completo de la base de datos.
- [ ] Ventana de ~1 h, con un responsable de BD y uno de apps.
- [ ] Crear el secreto del QR (si no existe, compartir viaje falla cerrado):

```sql
select vault.create_secret('<cadena-larga-aleatoria>', 'seguridad_token_pepper',
                           'Pepper de tokens de seguridad');
-- comprobar: select muevete.fn_token_hash('x');  → 64 caracteres
```

> Anotar el valor: se necesita igual en el build de la app (paso 2).

---

## 1 · Base de datos — migraciones que NO rompen las apps viejas

Una por una. Si una falla, parar y no seguir.

| # | Archivo |
|---|---|
| 01 | `030_baseline_sync_produccion.sql` |
| 02 | `031_taxi_zonas_tarifas.sql` |
| 03 | `032_taxi_geo_y_cotizacion.sql` |
| 04 | `033_taxi_seed_santa_clara.sql` |
| 05 | `034_taxi_rls_tarifas.sql` |
| 06 | `035_taxi_vehiculos_catalogo.sql` |
| 07 | `036_taxi_identidad_consentimiento.sql` |
| 08 | `037_taxi_seguridad.sql` |
| 09 | `038_taxi_rpc_solicitud.sql` |
| 10 | `039_taxi_rpc_lista_y_toma.sql` |
| 11 | `040_taxi_rpc_cierre_y_recarga.sql` |
| 12 | `042_taxi_docs_legales_texto_real.sql` |
| 13 | `043_taxi_consentimientos_inmutables.sql` |
| 14 | `044_taxi_documento_contacto_emergencia.sql` |
| 15 | `045_taxi_retencion_alineada_con_politica.sql` |
| 16 | `046_documentos_legales_lectura_publica.sql` |
| 17 | `047_roles_permisos_rutas_muevete.sql` |

**`041` y `048` NO van aquí** (van en el paso 4).

Comprobar:

```sql
select taxi_precio_fijo_activo from muevete.configuracion_tarifas;      -- false
select count(*) from muevete.documentos_legales where publicado;        -- 4
select count(*) from muevete.vehicle_type;                              -- 7
```

---

## 2 · Apps

- [ ] Rellenar `download_url_apk` y `download_url_web` en los dos `assets/changelog.json`.
- [ ] Compilar **muevete 1.1.0+2** y **superadmin 1.4.0+140**:
      `--dart-define=MUEVETE_QR_SECRET=<el mismo secreto del paso 0>`
- [ ] Publicar y confirmar que descargan.
- [ ] Superadmin: cerrar sesión y volver a entrar (refresca las rutas nuevas del menú).
- [ ] Comprobar que el admin que probará las zonas tiene fila activa en `public.app_dat_superadmin`.

---

## 3 · Bloquear las builds viejas

- [ ] Insertar en `public.app_versiones` la fila de `inventtia_muevete`:
      `build_number = 2`, `actualizacion_obligatoria = true`, `activa = true`, `novedades` con el changelog.

> ⚠️ Hoy **no existe ninguna fila de `inventtia_muevete`** en esa tabla. Sin este paso nadie se ve obligado a actualizar y las apps viejas siguen circulando.

---

## 4 · Cerrar el flujo viejo

- [ ] `041_taxi_rls_hardening.sql` ← a partir de aquí las apps viejas ya no pueden escribir.
- [ ] En el panel: **aprobar a todos los clientes pendientes de KYC**.
- [ ] `048_kyc_obligatorio_para_clientes.sql`
- [ ] Encender el servicio:

```sql
update muevete.configuracion_tarifas set taxi_precio_fijo_activo = true where id = 1;
```

---

## 5 · Verificar (5 min)

- [ ] Cliente pide viaje → ve **1 500 CUP** y no hay campo de oferta.
- [ ] Chofer lo ve en la lista con "se te descontarán 225 CUP de tu wallet" y lo toma.
- [ ] Al cerrar, el chofer queda con −225 de deuda en la wallet.
- [ ] Un viaje pagado con wallet, cancelado → el saldo vuelve.
- [ ] Superadmin: `/muevete/zonas` abre, dibuja un polígono y el simulador da precio.

---

## Rollback

- **Si aún no aplicaste `041`**: apagar `taxi_precio_fijo_activo` devuelve el flujo viejo.
- **Si ya aplicaste `041`**: **no revertir** (reabre los agujeros de dinero). Corregir hacia adelante; como máximo, apagar el flag para dejar de aceptar solicitudes nuevas.

---

## Fuera de tu control (no bloquea el arranque)

- Firma legal del documento KYC e identificación registral del responsable.