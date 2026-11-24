# Baseline main — reportes antes de C9–C13 / C11 (2026-11-24)

Solo lectura, tras bloque 1 `_m01`. Si hay que revertir reportes, restaurar estos cuerpos.

| proname | md5(prosrc) |
|---|---|
| fn_desglose_monedas_turno | cf1a65e43781e17fd384bf6866cad22c |
| fn_esperado_turno_por_moneda | 02ee5696eedf6aed4863f617d61d4934 |
| fn_listar_entregas_por_fechas_usuario | a71db9342efae2687c72c5bb6f84269d |
| fn_listar_turnos_admin | 32ca6176584c361c08d14b9618af2600 |
| fn_reporte_ventas_por_turno | 0323104c6d4ac18d0ffd071b0d449518 |
| fn_resumen_turno_por_id | dcaabbff20d14b1fed5623a3ed76460b |

Helpers ya creados en bloque 1 (no son reportes): `fn_operacion_en_turno`, `fn_operacion_completada`.
`fn_turnos_por_moneda` aún no existe (la crea C13).

Dry-run C12 en main: cadenas de `created_at <= fecha_cierre` coinciden (listar 3, resumen 2+1); aún no parcheado.
