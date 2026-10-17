# OpenWA — copia local de la documentación

Esta carpeta es una **copia sincronizada** de la documentación oficial de
[rmyndharis/OpenWA](https://github.com/rmyndharis/OpenWA), no documentación propia.

| Dato | Valor |
|---|---|
| Repositorio | [`rmyndharis/OpenWA`](https://github.com/rmyndharis/OpenWA) |
| Rama / ref sincronizado | `main` |
| Versión upstream (`package.json`) | `0.25.0` |
| Última sincronización | 2026-10-17 |
| Archivos | 41 |

## Cómo actualizarla

```bash
node ventiq_admin_app/scripts/sync_wapi_docs.mjs
node ventiq_admin_app/scripts/sync_wapi_docs.mjs --ref v0.25.0
```

## Aviso

Antes de fiarte de esta documentación para tocar las Edge Functions, lee
[`../docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md`](../docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md):
ahí está el **delta** entre lo que decía la copia vieja (era `v0.11.1`) y lo que
dice la actual, además de las rutas y payloads que en la práctica devuelven
otra cosa (p. ej. `send-image` espera el payload plano, y `/restart` no existe).
