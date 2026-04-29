#!/bin/bash
# ──────────────────────────────────────────────────────────────
# Obtener los primeros 500 productos de una tienda
# Usa la función RPC: get_productos_marketplace
# ──────────────────────────────────────────────────────────────
#
# INSTRUCCIONES:
#   1. Cambia STORE_ID por el ID numérico de la tienda
#   2. Ejecuta: bash curl_get_500_products.sh
#
# RESPUESTA incluye por cada producto:
#   - id_producto, sku, denominacion, descripcion, imagen
#   - precio_venta, stock_disponible, tiene_stock
#   - categoria, subcategoria, metadata (tienda, rating, presentaciones)
# ──────────────────────────────────────────────────────────────

STORE_ID=1  # <-- Cambia esto por el ID de la tienda

curl -s -X POST \
  "https://vsieeihstajlrdvpuooh.supabase.co/rest/v1/rpc/get_productos_marketplace" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NDUzMjIwNiwiZXhwIjoyMDcwMTA4MjA2fQ.d9fKCcunP_J0tdlZF8eg0vAD-bsK3XfemavnZWT3Ro8" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NDUzMjIwNiwiZXhwIjoyMDcwMTA4MjA2fQ.d9fKCcunP_J0tdlZF8eg0vAD-bsK3XfemavnZWT3Ro8" \
  -H "Content-Type: application/json" \
  -d "{
    \"id_tienda_param\": 177,
    \"id_categoria_param\": null,
    \"solo_disponibles_param\": false,
    \"search_query_param\": null,
    \"limit_param\": 500,
    \"offset_param\": 0
  }" \
  | python -m json.tool
