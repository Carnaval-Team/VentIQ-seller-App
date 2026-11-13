# Contrato app ↔ RPC — flujo sin negociación

> Documento de implementación para las apps (`inventtia_muevete` cliente y chofer).
> Es la única fuente para nombrar métodos, leer claves JSON y traducir errores.
> Migraciones: `038`, `039`, `040`. Diseño: `04-diseno-tecnico.md` §5.
> **Regla de oro: la app nunca envía un precio.** No existe parámetro de precio en
> ninguna firma; si el cliente lo intentara, el servidor recotiza y lo ignora.

---

## 1. Interruptor de corte

```sql
select taxi_precio_fijo_activo from muevete.configuracion_tarifas where id = 1;
```

- `true` → flujo nuevo (estas RPC). La app debe usar SIEMPRE este camino.
- `false` → modo legacy mientras se despliega. La app nueva puede seguir
  llamando a las RPC (funcionan igual), pero `fn_crear_solicitud` lanza
  `P0003 servicio_en_mantenimiento` para que ninguna build vieja publique
  precios libres. **La app debe mostrar ese caso como "Servicio en
  mantenimiento", no como error genérico.**
- Se lee una vez al arrancar el módulo taxi y se cachea en memoria.

## 2. Catálogo de vehículos

```sql
select * from muevete.v_catalogo_vehiculos;  -- ya viene ordenado
```
Columnas: `id`, `tipo`, `nombre`, `orden`, `pasajeros_max`, `categoria`.
`id` es lo que se manda como `p_id_tipo`. `nombre` es la etiqueta visible
(incluye "Microbús" y "Triciclo Eléctrico"). **No** se usa `vehicle_type` directo.

## 3. RPCs

### 3.1 `fn_cotizar_viaje` — preview (no escribe nada)

```
fn_cotizar_viaje(p_lat_o, p_lon_o, p_lat_d, p_lon_d, p_id_tipo,
                 p_at := now(), p_km := null, p_provincia := null, p_municipio := null)
→ jsonb
```

### Forma REAL del jsonb (verificada contra la BD, no la del diseño original)

La RPC devuelve **dos niveles**. Esto se comprobó ejecutándola; el anexo 04 lo
describía en un solo nivel y por eso hubo que corregir el modelo de la app.

**Nivel raíz** — lo que la UI pinta en grande:

| clave | uso |
|---|---|
| `precio_plataforma` | **precio final al cliente** (número grande) |
| `comision_pct`, `comision_monto` | lo que se lleva la plataforma |
| `precio_chofer` | **lo que le toca al chofer** |
| `tarifa_modo` | `fijo` / `fijo_mas_km` / `por_km` |
| `zona_id`, `zona_nombre` | zona aplicada (`"Fuera de zona"` si no hubo) |
| `km_total`, `km_fuente` | distancia aplicada y su origen (`ruta` / `haversine`) |
| `es_nocturno`, `precio_corto` | **booleanos** de la raíz |
| `moneda`, `multiplicador_tipo`, `tipo_vehiculo` | contexto |
| `precio_vigente_desde`, `calculado_at` | vigencia del cálculo |
| `detalle` | objeto anidado con el desglose fino (abajo) |

**Dentro de `detalle`** — el desglose del cálculo:

| clave | uso |
|---|---|
| `dentro_de_zona` (bool), `fallback_municipio` (bool), `municipio_aplicado` | etiqueta de la fila "Tarifa de la zona" |
| `km_lineal` | distancia en línea recta (para explicar el desvío) |
| `recargo_nocturno`, `recargo_prima_distancia` | filas de recargo (`—` si son 0) |
| `precio_corto_aplicado` (bool) | fila "Precio corto" |
| `redondeo_cup`, `precio_antes_redondeo` | fila "Redondeo" y "Subtotal" |
| `base`, `modo`, `monto_fijo`, `precio_km`, `precio_minimo` | aritmética interna |
| `zona_origen_id`, `zona_origen_nombre`, `zona_destino_id`, `zona_destino_nombre` | zonas de cada extremo |

> Regla para el código: leer **primero la raíz** y si falta la clave, `detalle`
> (ver `Cotizacion.fromJson` en `lib/models/tarifa_model.dart`). El flag de precio
> corto se llama `precio_corto` en la raíz y `precio_corto_aplicado` en `detalle`.

> El precio del preview **coincide** con el cobrado porque es la misma función
> que usa `fn_crear_solicitud`. Si el preview se hace con `p_km` de la ruta y
> `fn_crear_solicitud` recibe el mismo `p_km`, no hay sorpresa.

### 3.2 `fn_crear_solicitud` — publicar

```
fn_crear_solicitud(p_lat_o, p_lon_o, p_lat_d, p_lon_d, p_id_tipo,
                   p_dir_o, p_dir_d, p_km, p_metodo_pago,      -- 'efectivo' | 'wallet'
                   p_provincia := null, p_municipio := null,
                   p_pasajeros := 1)
→ fila de muevete.solicitudes_transporte
```

Devuelve la fila completa. Para la UI basta: `id`, `estado` (`pendiente`),
`precio_plataforma`, `precio_chofer`, `comision_pct`, `pasajeros`,
`tarifa_detalle`, `expires_at` (TTL 15 min), `metodo_pago`.
`precio_oferta` es un espejo legacy: **no se usa en la UI nueva**.

### 3.3 `fn_viajes_disponibles` — lista del chofer

```
fn_viajes_disponibles(p_lat := null, p_lon := null, p_limite := 30)
→ setof jsonb
```

Por cada viaje:

| clave | significado para la UI |
|---|---|
| `solicitud_id` | id para tomar |
| `precio_plataforma` | **"El cliente paga"** |
| `metodo_pago` | `efectivo` \| `wallet` — **decide el texto del dinero** (ver §3.3.1) |
| `comision_pct`, `comision_monto` | comisión de la plataforma |
| `precio_chofer` | neto contable (`precio_plataforma - comision_monto`). **No es "lo que cobras"** |
| `pasajeros`, `capacidad_vehiculo` | "2 pasajeros · tu vehículo: 4" |
| `direccion_origen`, `direccion_destino`, `km` | tarjeta de ruta |
| `distancia_a_origen_km` | "a 1.2 km de ti" |
| `tipo_vehiculo`, `id_tipo_vehiculo` | icono y compatibilidad |
| `segundos_restantes` | cuenta atrás del TTL |
| `puede_tomar` | habilita/deshabilita el botón |
| `motivo_bloqueo` | texto del por qué NO puede (ver §4) |
| `desglose` | detalle crudo, opcional en un expandible |

**La lista filtra por zona del chofer**, no por tipo ni capacidad: el chofer ve
el viaje y `puede_tomar=false` con el motivo. La UI debe mostrar la tarjeta
atenuada + el motivo, no ocultarla (regla 4 del plan).

#### 3.3.1 Cómo se escribe el dinero (corrección de producto 2026-11-13)

**Nunca** poner "a ti te tocan X". El neto (`precio_chofer`) **no es lo que el
chofer cobra en mano**: el cobro real depende del método de pago, y la comisión
se mueve por la **wallet**, no restándola del pago.

| `metodo_pago` | Qué pasa de verdad | Texto en la tarjeta |
|---|---|---|
| `efectivo` | El chofer recibe **el total en mano**; la comisión se le **descuenta de la wallet** y queda como deuda hasta el tope configurado | Título: `El cliente paga 1 500 CUP en efectivo` · Caja destacada: **`Se te descontarán 225 CUP de tu wallet`** · Nota: "la comisión del 15 % se te cobra como deuda en la wallet" |
| `wallet` | Al cliente se le retiene el total; al chofer se le **abona el neto** en su wallet | Título: `El cliente paga 1 500 CUP con wallet` · Caja destacada: **`Se te acreditarán 1 275 CUP en tu wallet`** |

Además, si el viaje trae `deuda_disponible`, mostrar el margen que le queda:
`Margen de deuda disponible después de este viaje: X CUP`.

En el **cierre del viaje** (`fn_completar_viaje`), la línea grande no es "Tu
ganancia" sino:

- efectivo → **"Te queda en mano"** con el total, y debajo "la comisión de
  225 CUP se te descuenta de la wallet y queda como deuda" (el `saldo_chofer`
  que devuelve la RPC ya viene negativo).
- wallet → **"Se te acredita en tu wallet"** con `precio_chofer`.

Y en la **vista del cliente** no se muestra el neto del conductor: se muestra
`Incluye 225 CUP de servicio de la plataforma` (o "Sin cargo de servicio").

### 3.4 `fn_tomar_viaje` — el primero gana

```
fn_tomar_viaje(p_solicitud_id) → jsonb
{ success, solicitud_id, viaje_id, precio_plataforma, comision_pct,
  comision_monto, precio_chofer, metodo_pago, hold_cliente, saldo_chofer,
  capacidad_vehiculo }
```

Si otro chofer llegó primero → `P0020 ya_tomado`: la UI refresca la lista y
avisa "Ese viaje ya lo tomó otro conductor".

### 3.5 `fn_completar_viaje` — cerrar

```
fn_completar_viaje(p_viaje_id, p_espera_min := null) → jsonb
{ success, solicitud_id, viaje_id, precio_plataforma (TOTAL),
  precio_viaje, espera_min, espera_cobrada_min, espera_monto,
  comision_pct, comision_monto, precio_chofer, metodo_pago,
  saldo_chofer, deuda_chofer }
```

**No recibe precio.** `p_espera_min` sólo se usa si el viaje no trae
`tiempo_espera_segundos` medidos en servidor. Idempotente (`idempotente=true`
en reintentos): la cola offline puede repetir la llamada sin miedo.

### 3.6 `fn_cancelar_solicitud` — cancelar

```
fn_cancelar_solicitud(p_solicitud_id, p_motivo := null)
→ { success, solicitud_id, estado:'cancelada', viaje_id, reembolso, saldo }
```

Idempotente. Si el cliente pagó con wallet y ya se había retenido, `reembolso`
trae el monto devuelto y `saldo` el saldo resultante.

### 3.7 `fn_recargar_wallet`

```
fn_recargar_wallet(p_metodo, p_monto, p_evidencia := null)
→ { success, transaccion_id, monto_acreditar, total_a_pagar,
    recarga_pct, moneda, estado:'pendiente', es_recarga_chofer }
```

`total_a_pagar` ya incluye el % de recarga: **se acabó el literal `1.11` en
Dart**. Exige consentimiento (privacidad + términos) → `P0053` si falta.

## 4. Códigos de error → mensaje de UI

| SQLSTATE | mensaje servidor | texto sugerido en la app |
|---|---|---|
| `P0003` | `servicio_en_mantenimiento` | "El servicio está en mantenimiento. Intenta más tarde." |
| `P0005` | `solicitud_activa_existente` | "Ya tienes un viaje activo." + ir a la pantalla del viaje |
| `P0006` | `metodo_pago_invalido` | "Método de pago no válido." |
| `P0010` | `chofer_offline` | "Ponte en línea para tomar viajes." |
| `P0011` | `chofer_no_aprobado` | "Tu cuenta aún no está aprobada." |
| `P0012` | `chofer_con_viaje_activo` | "Termina el viaje que tienes en curso." |
| `P0020` | `ya_tomado` | "Otro conductor lo tomó primero." (refrescar) |
| `P0021` | `tipo_vehiculo_incompatible` | "El viaje pide otro tipo de vehículo." |
| `P0022` | `viaje_fuera_de_tu_zona` | "El viaje está fuera de tu zona." |
| `P0023` | `limite_de_deuda_alcanzado` | "Alcanzaste tu límite de deuda. Recarga para seguir." |
| `P0024` | `cliente_sin_saldo` / `..._para_espera` | "Saldo insuficiente." |
| `P0025` | `solicitud_legacy_sin_tarifa` | "Este viaje es de una versión anterior." |
| `P0026` | `solicitud_vencida` | "La solicitud expiró." (refrescar) |
| `P0030` | `viaje_no_existe` | "El viaje no existe." |
| `P0032` | `viaje_ya_completado` / `estado_invalido` | "El viaje ya se cerró." |
| `P0040` | `tipo_vehiculo_no_existe` | "Tipo de vehículo no disponible." |
| `P0041` | `metodo_invalido` | "Método no válido." |
| `P0050` | `perfil_incompleto` / `perfil_incompleto_chofer` | abrir onboarding KYC, mostrar `motivos` |
| `P0051` | `capacidad_excedida_tipo` | "Ese vehículo no admite tantos pasajeros." |
| `P0052` | `capacidad_insuficiente` | "Tu vehículo no tiene capacidad para ese viaje." |
| `P0053` | `consentimiento_pendiente` | "Acepta privacidad y términos para continuar." |
| `P0110` | `sin_contacto_emergencia` / `bloqueado` | abrir "Mi seguridad → Contacto de emergencia" |
| `P0112` | `emparejamiento_bloqueado` | "No puedes tomar viajes de este cliente." |

`motivos` de `P0050` es un array con las claves faltantes
(`ci`, `doc_frente`, `doc_dorso`, `poblado`, `kyc_pendiente_aprobacion`, …):
la UI de onboarding debe marcar exactamente esos campos.

## 5. Convenio de wallet (para pintar el historial)

`muevete.transacciones_wallet.tipo` sólo admite:
`recarga | cobro_viaje | pago_viaje | reembolso | comision_viaje`.

| momento | fila | signo |
|---|---|---|
| tomar viaje (wallet) | `cobro_viaje` | negativo = retención al cliente |
| cerrar con espera | `cobro_viaje` | negativo = espera extra |
| cerrar wallet (chofer) | `pago_viaje` | positivo = neto del chofer |
| cerrar efectivo (chofer) | `comision_viaje` | negativo = comisión descontada |
| cancelar con retención | `reembolso` | positivo = devolución |

## 6. Archivos a tocar (H4 cliente / H5 chofer)

| archivo | acción |
|---|---|
| `lib/services/transport_request_service.dart` | **REESCRIBIR**: RPCs de §3.1–3.6 (`cotizar`, `crearSolicitud`, `cancelarSolicitud`, `viajesDisponibles`, `tomarViaje`, `completarViaje`) |
| `lib/providers/transport_provider.dart` | **REESCRIBIR**: fuera `_calculatePrice`, `setOfferPrice`, `offerPrice`, `driverOffers`, `acceptedOffer`, `acceptOffer`, `declineOffer`, `pollOffers`; dentro `cotizacion`, `cotizar()`, `crearSolicitud()`, `viajesDisponibles`, `tomarViaje()`, `completarViaje()`, `cancelarSolicitud()` |
| `lib/screens/client/route_preview_screen.dart` | **REESCRIBIR** la zona de precio: desglose + tipo + pasajeros + pago + "Solicitar viaje · X CUP". Fuera "Tu Oferta" |
| `lib/screens/client/driver_offers_screen.dart` | **REEMPLAZAR** por "Buscando conductor…" (ya no hay ofertas que comparar) |
| `lib/screens/driver/incoming_requests_screen.dart` | **REEMPLAZAR** por "Viajes disponibles" (§3.3) |
| `lib/screens/driver/active_ride_screen.dart` | adaptar cierre a `fn_completar_viaje` |
| `lib/services/wallet_service.dart` | `addFunds`/`addDriverFunds` → `fn_recargar_wallet`; fuera el `1.11`; `completeRidePaymentRpc` queda `@Deprecated` y sin llamadas |
| `lib/widgets/driver_offer_card.dart` | **BORRAR** (o dejar de importar) |
| `lib/models/driver_offer_model.dart` | queda sólo para histórico/lectura; no se escribe |

Reglas de UI:
- Ningún `TextField` de precio, ningún slider, ningún botón de "ofertar".
- El monto se muestra siempre formateado `1 500 CUP` (separador de miles).
- El % y el neto del chofer son información de primer nivel (no letra pequeña).
- Realtime: la lista del chofer se refresca por `postgres_changes` sobre
  `muevete.solicitudes_transporte` (INSERT/UPDATE) y además cada 20 s como red
  de seguridad.

## 7. Estados vacío / carga / error

Cada pantalla de datos (lista de viajes, historial, wallet) necesita los tres
estados explícitos. La lista de viajes vacía NO es un error: es
"Esperando viajes en tu zona…" con un botón de refrescar.