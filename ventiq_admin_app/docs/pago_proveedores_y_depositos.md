# Pago a proveedores y Depósitos bancarios

## Resumen

Se agregaron dos módulos independientes en `ventiq_admin_app`, clonando la lógica de **Pagos a Importadora** (`imp_*`):

| Módulo | Prefijo SQL | Destinatario | Documento |
|---|---|---|---|
| Pagos a Importadora (existente) | `imp_` | Implícito (1) | Factura |
| **Pago a proveedores** (nuevo) | `prv_` | `app_dat_proveedor` (varios) | Factura |
| **Depósitos bancarios** (nuevo) | `dep_` | `dep_dat_banco` (varios) | Depósito |

- Importadora **no se modifica**; la migración a proveedores es opcional vía `migracion_importadora_a_proveedores.sql`.
- Ambos módulos empiezan vacíos (salvo que ejecutes la migración).
- Sin saldo negativo; al crear factura/depósito se descuenta el saldo.
- Mismos roles de acceso (drawer admin).
- Nada en caja/seller.

## SQL a ejecutar en Supabase

1. `ventiq_admin_app/lib/sql/pago_proveedores_schema.sql`
2. `ventiq_admin_app/lib/sql/depositos_bancarios_schema.sql`

## Menú / rutas

- `/pago-proveedores`, `/pago-proveedores-estados`, `/pago-proveedores-monedas`
- `/depositos-bancarios`, `/depositos-estados`, `/depositos-monedas`, `/depositos-bancos`

## Migración Importadora → Pago a proveedores

Script listo: `lib/sql/migracion_importadora_a_proveedores.sql`

### Datos actuales en Importadora (referencia)

| Tienda | Saldo | Facturas | Recargas |
|---|---|---|---|
| 174 – El Descuento Central | 2 393 400 | 1 | 6 |
| 177 – Carnaval Alimentos Surl RPT Escambray | 29 834.37 | 19 | 8 |
| 179 – Una | 515 132 | 4 | 2 |

### Pasos

1. Ejecutar `pago_proveedores_schema.sql` (si aún no).
2. Abrir `migracion_importadora_a_proveedores.sql` y poner el **nombre del proveedor** en `v_nombre_proveedor` (ej. `'Importadora Central'`).
3. Opcional: cambiar `v_moneda_codigo` (default `'USD'`).
4. Ejecutar el script en Supabase SQL Editor.
5. Verificar con las queries al final del archivo.

El script crea **un proveedor por tienda** con ese mismo nombre (`sku` `IMP-MIG-{idtienda}`), migra todo y deja `imp_*` intacto. Es idempotente.

### Checklist post-migración

- [ ] Saldo `prv_dat_saldo` = saldo `imp_dat_saldo` por tienda
- [ ] Conteo facturas / fotos / recargas coincide
- [ ] Abrir app: seleccionar el proveedor migrado, ver saldo/facturas
- [ ] Crear una factura de prueba (descuento de saldo)
- [ ] Solo entonces decidir si se desactiva el menú Importadora

## Archivos principales

### Pago a proveedores
- `lib/sql/pago_proveedores_schema.sql`
- `lib/models/pago_proveedores.dart`
- `lib/services/pago_proveedores_service.dart`
- `lib/screens/pago_proveedores/*`

### Depósitos bancarios
- `lib/sql/depositos_bancarios_schema.sql`
- `lib/models/depositos_bancarios.dart`
- `lib/services/depositos_bancarios_service.dart`
- `lib/screens/depositos_bancarios/*`
