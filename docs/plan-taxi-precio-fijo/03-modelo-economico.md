# 03 — Modelo económico del módulo taxi (Muevete, Santa Clara)

> Documento de análisis económico para el rediseño del precio de viaje a **precio fijado por la plataforma** (sin negociación), con zonas definidas por superadmin.
> Alcance: solo análisis y especificación de parámetros. No propone código.
> Fecha de análisis: 2026-11-12 (America/Havana).

**Decisiones vinculantes aplicadas (D1–D6, cerradas por el usuario):**

| # | Decisión | Efecto en este documento |
|---|---|---|
| D1 | Zonas = **polígono dibujado en mapa** por superadmin | Se elimina el modelo de radio; §8.2 propone polígonos concretos |
| D2 | **Multiplicador por tipo**: moto 0,6× · auto 1,0× · microbús 1,5× sobre la tarifa de zona | Se recalcula todo el modelo con estos factores |
| D3 | Modos por zona: `fijo` (contenido→fijo; si sale→km_total×precio_km), `fijo_mas_km` (fijo+km_total×precio_km), `por_km` | §2.1 reescrita con los tres modos |
| D4 | Fuera de toda zona: **fijo del municipio configurable** (1 500 CUP por defecto) | §2.4 y §8.2 |
| D5 | Comisión **15 % global configurable** (no por zona) | Se elimina la comisión por zona; §4 evaluada bajo 15 % plano |
| D6 | Efectivo: **deuda con límite configurable**; el chofer puede quedar negativo hasta el tope y luego se bloquea | §3.6 y §8.1; se recomienda el número con justificación |

> ⚠️ **Nota de incertidumbre (pedida explícitamente):** **no obtuve tarifas urbanas verificadas de Santa Clara en CUP.** Las fuentes externas disponibles son de mercado turístico en EUR/USD (interprovincial) o plantillas genéricas por país. Por lo tanto, la calibración del precio por km se apoya en (a) los **datos reales de la propia base de datos** del proyecto y (b) un **modelo de costo por km declarado como estimación**. Todo lo estimado está marcado como tal y con rango.

---

## 0. Resumen ejecutivo

1. Todos los montos del módulo taxi son **CUP**. Verificado en `muevete.vehicle_type` (300/200/250 CUP por km) y en `solicitudes_transporte` (ticket promedio **1 237 CUP**, mediana **800**, distancia media **3,30 km**). El símbolo `$` de la UI es decorativo.
2. El modelo actual **pierde dinero para el chofer en el viaje promedio**: 800 − 15 % = 680 netos contra ~1 089 CUP de costo. La reforma no es cosmética; es una corrección de sostenibilidad.
3. El fijo municipal de **1 500 CUP** es **+21 % sobre el ticket promedio** y **+87,5 % sobre la mediana**. Es viable para el casco urbano (≤ ~3,9 km), **no** como tarifa única de municipio.
4. **Recomendación de precio por km: 400 CUP/km** para Santa Clara (auto, ×1,0). Punto de equilibrio del costo del chofer: 388 CUP/km. El margen real lo aporta el `monto_fijo`.
5. **Modos recomendados:** `fijo` en zonas compactas (Centro, Condado); `fijo_mas_km` en zonas alargadas o de acceso (Virginia, Báez, UCLV, Aeropuerto, Periferia, Intermunicipal); `por_km` solo para corredores largos sin viajes internos.
6. **Ejemplo «fijo 300 + 80/km» del requerimiento: rechazado.** 80 CUP/km está **4,9× por debajo** del mínimo viable (388). En un viaje de 10 km deja al chofer con −2 025 CUP.
7. **Comisión 15 % global (D5):** correcta para el viaje corto, **distorsionante en el largo** (se lleva **50,8 %** del margen del intermunicipal vs **26,8 %** del corto). Se recomienda un `tope_comision_viaje = 2 500 CUP` — compatible con un % global — que baja el intermunicipal al 12,1 % efectivo.
8. **Tope de deuda recomendado: 1 000 CUP** (con **500 CUP** las 4 primeras semanas). Justificación: comisión de un viaje municipal = 225; 1 000 cubre 4,4 viajes impagos ≈ **la comisión de un día de trabajo**. Con 500 el bloqueo reaparece a los 3 viajes en efectivo y D6 pierde sentido.
9. El **11 % de recarga** encarece la comisión real en efectivo al **16,65 %** (0,15 × 1,11); en wallet la plataforma cobra **26 %** (15 % + 11 %). Recomendación: bajarla a **6 %**.
10. Plataforma rentable desde **~9 viajes/día** (contribución 401 CUP/viaje a 15 %). El problema no es la rentabilidad unitaria, es la **demanda**.

---

## 1. Marco de moneda y precios de referencia

### 1.1 Verificación de moneda y parámetros reales (código + BD)

| Evidencia | Archivo / objeto | Valor | Lectura |
|---|---|---|---|
| Precio por km por tipo | `muevete.vehicle_type.precio_km_default` (moto / auto / microbus) | **300 / 200 / 250** | CUP por km |
| Tarifa plana dentro del círculo de SC | `muevete.vehicle_type.precio_inside_sc` (moto / auto / microbus) | **500 / 800 / 800** | CUP por viaje contenido |
| Espera | `muevete.vehicle_type.precio_espera_min` (moto / auto / microbus) | **100 / 40 / 60** | CUP por minuto |
| Ticket real | `muevete.solicitudes_transporte` (n=55) | promedio **1 237,5** · mediana **800** · máx 9 600 | CUP |
| Distancia real | `muevete.solicitudes_transporte` | media **3,30 km** (auto: 3,10 km) | km |
| Precio realizado por km | `precio/distancia`, auto (n=43) | **549 CUP/km** prom. · mediana 800 | CUP/km |
| Comisión | `wallet_service.dart` L262, L304 · `complete_ride_payment_rpc.sql` L55, L71 · `transport_provider.dart` L487 | `× 0.15` | 15 % **global** |
| Recarga | `wallet_service.dart` L48, L98 · `wallet_screen.dart` L52 · `driver_wallet_screen.dart` L58 | `× 1.11` | 11 % |
| Formato | `helpers.dart` → `NumberFormat.currency(symbol: '$')` | símbolo `$` | **simbólico**, no USD |
| Círculo ciudad | `constants.dart` L72–74 | centro (22.40689, −79.96450), radio **2,53 km** | Reemplazado por polígonos (D1) |

**Conclusión verificada: el módulo taxi opera en CUP.** El dólar y el MLC no aparecen en ninguna ruta de precio de viaje.

> ⚠️ **Bug 1 (tarifa de espera muerta):** `vehicle_type_model.dart` L43 lee `json['precio_espera_minuto']`; la columna real es `precio_espera_min`. Resultado: `precioEsperaMinuto` siempre vale **0** y la espera nunca se cobra. Corregir antes de parametrizar.

> ⚠️ **Bug 2 (doble conteo):** `transport_provider.dart` L153–163 usa `minPrice = precio_inside_sc ?? (km × precio_km)` y fuera de la ciudad calcula `minPrice + km × precio_km`, es decir `precio_inside_sc + km × precio_km`: suma una tarifa plana y una por km. El rediseño de modos por zona (D3) reemplaza esta lógica.

> ⚠️ **Bug 3 (bloqueo en el momento de ofertar):** `incoming_requests_screen.dart` L527–543 valida saldo para la comisión **antes de enviar la oferta**; con D6 esta validación debe moverse al cierre del viaje y usar el tope de deuda.

### 1.2 Salario de referencia

| Indicador | Valor | Naturaleza | Fuente |
|---|---|---|---|
| Salario medio mensual Cuba 2025 | **6 930 CUP** (6 506,5 en abril 2025) | **Dato verificado** (ONEI) | [ACN](https://www.acn.cu/economia/informan-sobre-salario-medio-en-cuba-en-2025) · [Cubadebate](http://www.cubadebate.cu/especiales/2025/07/04/cuba-en-datos-salarios-en-2025-tendencias-y-disparidades/) |
| Equivalente en USD (cambio promedio 2025) | ~15 USD/mes | **Dato verificado** | [CiberCuba](https://www.cibercuba.com/noticias/2026-04-23-u1-e192519-s27061-nid326913-elias-amor-salario-medio-cubano-2025-6930-pesos-al) |

Referencia operativa: **6 930 CUP/mes ≈ 39,4 CUP/hora** (22 días × 8 h). Ancla con la que la opinión pública compara cualquier tarifa.

### 1.3 Combustible

**Tipo de cambio de referencia (12 nov 2026):**

| Tasa | USD → CUP | Fuente |
|---|---|---|
| BCC oficial | 24,00 | [Cuba Radar / BCC](https://www.cubaradar.com/dollar-today) |
| BCC pública (CADECA) | 120,00 | ídem |
| **BCC especial** (sectores diferenciados) | **820,00** | ídem |
| Informal (reportado) | ~910 | [CubaDivisas](https://cubadivisas.com/) |

**Precios oficiales CIMEX (USD/litro, 11 sep 2026) — dato verificado:**

| Combustible | Mayorista | Minorista |
|---|---|---|
| Gasolina Especial B100 | 2,50 USD | 2,60 USD |
| Gasolina Especial B94 | 1,90 USD | **2,00 USD** |
| Gasolina Regular B90 | 1,80 USD | 1,90–2,50 USD |
| Gasolina Motor B83 | 1,70 USD | 1,80 USD |
| Diésel Regular | 1,90 USD | 2,00 USD |

Fuente: [Directorio Cubano — precio del combustible](https://www.directoriocubano.info/precio-combustible-cuba-hoy/) (cita elToque y CIMEX).

**Equivalencias en CUP — elaboración propia, ESTIMACIÓN:**

| Producto | A 820 CUP/USD | **A 900 CUP/USD (blend)** | A 1 000 CUP/USD |
|---|---|---|---|
| Especial B94 (2,00 USD) | 1 640 | **1 800** | 2 000 |
| Regular B90 (1,90 USD) | 1 558 | **1 710** | 1 900 |
| Regular B90 (2,50 USD) | 2 050 | **2 250** | 2 500 |
| Motor B83 (1,80 USD) | 1 476 | **1 620** | 1 800 |
| Diésel (2,00 USD) | 1 640 | **1 800** | 2 000 |

**Mercado informal (calle) — dato reportado, alta volatilidad (11 sep 2026):**

| Combustible | Rango informal (CUP/L) |
|---|---|
| B-94 Especial | **7 000 – 8 000** |
| B-90 Regular | **3 200 – 4 000** |
| B-83 Motor | 3 300 |
| Petróleo / Diésel | 1 600 – 2 000 |

> **Inconsistencia declarada:** la razón entre precio oficial en USD y precio de calle no cuadra con ninguna tasa publicada (el especial oficial a 2 USD no puede costar 7 000–8 000 CUP si el USD está a 820–910). Se interpreta como **prima de escasez** (reventa, disponibilidad intermitente, falta de acceso al canal dolarizado), no como conversión. **Decisión de modelado: planificar con canal oficial (1 800–2 100 CUP/L) y testear sensibilidad a 3 600 CUP/L.** Es la incertidumbre más grande de todo el documento.

### 1.4 Costo por km por tipo de vehículo (ESTIMACIÓN — base del diseño de multiplicadores)

| Rubro | Auto | Moto | Microbús |
|---|---|---|---|
| Consumo asumido (L/100 km, ciudad) | 10,0 | 3,0 | 13,0 |
| Combustible (× 2 200 CUP/L blend) | 220 | 66 | 286 |
| Mantenimiento | 45 | 12 | 60 |
| Depreciación | 45 | 10 | 60 |
| Seguros, licencias, lavado, parqueo | 20 | 5 | 30 |
| **Costo total por km (blend 2 200 CUP/L)** | **330** | **93** | **436** |
| Costo por km con combustible oficial (1 800) | 290 | 81 | 406 |
| Costo por km con combustible de calle (3 600) | 470 | 135 | 604 |
| Chofer no propietario (solo combustible, oficial) | 180 | 54 | 234 |
| **Precio de plataforma necesario para cubrir costo con comisión 15 %** (`costo ÷ 0,85`) | **388** | **109** | **513** |
| **Ratio de costo vs auto (base de los multiplicadores)** | 1,00 | **0,28** | **1,32** |

**Multiplicadores D2 evaluados contra el costo real:**

| Tipo | Multiplicador (D2) | Precio efectivo por km con `precio_km` = 400 | Neto tras 15 % | Costo/km | Margen/km | Veredicto |
|---|---|---|---|---|---|---|
| Moto | **0,60** | 240 | 204 | 93 | **+111** | ✅ Holgado; el 0,60 (vs ratio de costo 0,28) es prudente y mantiene la moto atractiva para el usuario |
| Auto | **1,00** | 400 | 340 | 330 | **+10** | ⚠️ Suficiente pero fino: **el margen debe venir del `monto_fijo`**, no del km |
| Microbús | **1,50** | 600 | 510 | 436 | **+74** | ✅ Correcto; el 1,50 (vs ratio de costo 1,32) cubre capacidad y desgaste |
| *(extensión opcional)* Minivan | 1,75 | 700 | 595 | ~460 | +135 | Propuesto, no vinculante |
| *(extensión opcional)* Camioneta | 1,15 | 460 | 391 | ~350 | +41 | Propuesto |
| *(extensión opcional)* Tuktuk / Bicicleta | 0,45 / 0,30 | 180 / 120 | 153 / 102 | ~60 / ~10 | +93 / +92 | Propuesto |

> **Conclusión:** los multiplicadores de D2 son **coherentes con el costo real** y no necesitan corrección. El punto fino es el **auto**: a 400 CUP/km el margen variable es +10 CUP/km; por eso el `monto_fijo` **no puede eliminarse** en ninguna zona (ninguna zona debería ser `por_km` en el casco urbano).

### 1.5 Dotaciones de referencia (dato externo, NO verificado para Santa Clara urbana)

| Referencia | Valor | Naturaleza |
|---|---|---|
| Tarifas interprovinciales privadas en EUR: SC→Remedios (44 km) **70 EUR**; SC→Cayo Santa María (113 km) **120 EUR**; SC→Cienfuegos (73 km) **110 EUR** — [CubaLaislaProhibida](https://www.cubalaislaprohibida.org/tarifas/) | ≈ 1,06–1,59 EUR/km ≈ **965–1 450 CUP/km** | Mercado turístico en divisa |
| Traslado privado reservado HAV→Santa Clara (288 km) **195 USD** — [CubanTaxis](https://cubantaxis.com/es/blog/how-much-is-a-taxi-in-cuba) | ≈ 0,68 USD/km | Mercado turístico |
| Alquiler de auto económico **desde 77,25 USD/día** — [Periódico Cubano](https://www.periodicocubano.com/desde-3459-usd-al-dia-las-opciones-mas-baratas-para-moverte-por-cuba-con-carro-o-scooter/) | ≈ 63 000–70 000 CUP/día | Costo de referencia del vehículo |
| Estimador genérico Santa Clara: 1 USD base + 1 USD/km — [EstimaTaxi](https://estimataxi.com/es/america-del-norte/cuba/santa-clara/) | **Fiabilidad BAJA**: plantilla por país | No usado para calibrar |
| **Datos propios del proyecto (los únicos locales)** | mediana **800 CUP**, media **1 237 CUP**, **375–550 CUP/km** | **Verificado en BD** (n=55) |

**Declaración explícita:** no existe en las fuentes consultadas una tabla de tarifas urbanas de Santa Clara en CUP. La calibración usa los datos propios y el modelo de costo, no un tarifario local verificado.

---

## 2. Anatomía del precio del viaje

### 2.1 Fórmula general con los modos D3

La fórmula del requerimiento original, `precio = max(base, base + km × tarifa_km)`, es **redundante**: el segundo término es siempre ≥ el primero. Se reemplaza por la regla de modos por zona (D3):

```
# 0) Resolver zonas
z_origen  = zona_que_contiene(lat_origen, lon_origen)    # polígono D1
z_destino = zona_que_contiene(lat_destino, lon_destino)
#    Si ninguna contiene el origen → fallback municipio (D4)

# 1) Regla de la zona (sin multiplicador)
funcion regla(zona, km_total, origen_dentro, destino_dentro):
    match zona.modo:
        "fijo":          # D3
            if origen_dentro and destino_dentro:
                return zona.monto_fijo
            else:
                return km_total × zona.precio_km
        "fijo_mas_km":   # D3
            return zona.monto_fijo + km_total × zona.precio_km
        "por_km":        # D3
            return km_total × zona.precio_km

# 2) Precio por zona candidato (origen y destino), se toma el MAYOR
#    (evita arbitraje eligiendo la zona barata)
p_origen  = regla(z_origen,  km, origen_en_z_origen,  destino_en_z_origen)
p_destino = regla(z_destino, km, origen_en_z_destino, destino_en_z_destino)
p_zona    = max(p_origen, p_destino)

# 3) Multiplicador por tipo de vehículo (D2)
p_tipo = p_zona × multiplicador[tipo_vehiculo]     # moto 0,60 · auto 1,00 · microbús 1,50

# 4) Piso por tipo (se aplica DESPUÉS del multiplicador)
subtotal = max(precio_minimo[tipo_vehiculo], p_tipo)

# 5) Recargos
recargo_noche  = subtotal × recargo_nocturno_pct     si hora ∈ ventana_nocturna
recargo_espera = max(0, minutos_espera − gracia_espera) × tarifa_espera_min[tipo]

# 6) Tope de comisión (se aplica al cobrar, no al precio)
# 7) Redondeo hacia arriba
precio = ceil((subtotal + recargo_noche + recargo_espera) / redondeo_cup) × redondeo_cup
```

**Dos reglas de interpretación que el programador debe implementar tal cual:**
1. **`regla()` para el modo `fijo` devuelve `km_total × precio_km` cuando el viaje sale de la zona** (no `monto_fijo + km × precio_km`). Literal a D3: *«dentro de la zona se cobra fijo; al salir sería cantidad de kilómetros × precio por kilómetro»*. Por eso `precio_km` de una zona `fijo` debe ser ≥ 388 (auto) o la salida pierde dinero.
2. **Se toma el máximo entre la regla evaluada desde la zona de origen y desde la de destino.** Sin esto, un viaje Centro→Aeropuerto se puede facturar con la regla barata y el sistema queda arbitrable.

### 2.2 Selección de modo por zona

| Modo | Cuándo usarlo | Zonas recomendadas | Riesgo si se usa mal |
|---|---|---|---|
| **`fijo`** | Zona **pequeña y homogénea**: los viajes internos tienen distancia y costo similares | Centro, Condado–Santa Catalina. También el polígono del municipio y el fallback D4 | En zona alargada, el flat subsidia el extremo lejano; en la salida, obliga a que `precio_km` sea alto |
| **`fijo_mas_km`** | Zona **alargada o de acceso**, donde la distancia interna varía mucho | Reparto Virginia, Báez, UCLV, Aeropuerto, Periferia, corredores intermunicipales | Si `monto_fijo` es alto y `precio_km` bajo, el largo vuelve a perder |
| **`por_km`** | **Corredor sin viajes internos** relevantes (punto A → punto B siempre) | Solo tramos interurbanos puros; **no usar en casco urbano** | Sin fijo, el auto queda en +10 CUP/km de margen; el arranque no se paga |

### 2.3 Rol de cada parámetro

| Parámetro | Rol | Dónde actúa | Riesgo si se mal configura |
|---|---|---|---|
| `monto_fijo` | Cubre costo fijo: arranque, aproximación, pickup, desgaste | Zona | Alto ⇒ cortos muy rentables y largos ruinosos |
| `precio_km` | Cubre el **costo variable dominante (combustible)** y el tiempo | Zona | **< 388 (auto) ⇒ todo viaje que sale de la zona pierde dinero** |
| `modo` | Define si el fijo se suma, se reemplaza o se ignora | Zona | Modo mal elegido rompe la zona entera |
| `multiplicador_tipo` | Ajusta al costo real del vehículo (D2) | Global por tipo | Moto al 1,0 ⇒ moto carísima e inutilizable |
| `precio_minimo` | Piso duro por tipo; evita que una zona cobre menos que el municipio | Global por tipo | Sin piso, las zonas `fijo_mas_km` canibalizan el fijo municipal |
| `precio_corto` + `umbral_km_corto` | Válvula de elasticidad para el viaje muy corto | Global por tipo | Sin ella, el corto sube +87 % y migra al botero |
| `recargo_nocturno_pct` | Compensa menor oferta y mayor riesgo 22:00–06:00 | Global | Aplicarlo sobre la espera genera compounding |
| `tarifa_espera_min` + `gracia_espera_min` | Compensa minutos muertos (columna `viajes.cobro_espera`) | Por tipo | Gracia 0 ⇒ disputas con el cliente |
| `tope_cobro_espera` | Evita cobros abusivos | Global | Sin tope, una espera larga puede superar el viaje |
| `redondeo_cup` | Simplifica el efectivo | Global | Múltiplos de 500 ⇒ percepción de arbitrariedad |
| `tope_comision_viaje` | Protege el margen del viaje largo bajo un % global (D5) | Global | Sin tope, el 15 % se lleva 55 % del margen del intermunicipal |

### 2.4 ¿Es viable el fijo de 1 500 CUP del municipio (D4)?

**Sí, con tres condiciones.**

**A favor (datos duros):**
- El ticket promedio real ya es **1 237 CUP** y el precio realizado por km del auto es **549 CUP/km**. Un fijo de 1 500 está **+21 % sobre el promedio** y sigue por debajo de lo que el mercado ya paga por km.
- El fijo actual de **800 CUP** dentro del círculo de 2,53 km es una **pérdida**: 800 − 15 % = 680 netos contra **~1 089 CUP** de costo a 3,3 km. El modelo actual no es sostenible; 1 500 sí.
- Con 1 500, la comisión de 15 % (225 CUP) es holgada para cualquier saldo de wallet, lo que reduce la fricción operativa del bloqueo (relevante para D6).

**Condiciones en contra:**
- **C1 — El fijo solo es viable hasta ~3,9 km.** Con costo 330/km: `1 500 × 0,85 = 1 275 ÷ 330 = 3,86 km`. Con costo optimista (290) sube a 4,4 km. El círculo actual tiene diámetro máximo 5,06 km, y el **municipio real es muchísimo más grande** (aeropuerto a ~9,7 km, UCLV a ~8 km, Báez a ~7 km).
  → **Mitigación obligatoria: el polígono del municipio debe usar modo `fijo` con `precio_km = 400`, y los destinos de más de ~5 km deben tener polígono propio con `fijo_mas_km`.**
- **C2 — El fallback D4 (1 500 plano «fuera de toda zona») es un riesgo de pérdida** si captura viajes largos. → Recomiendo implementarlo como **zona virtual con modo `fijo` y `precio_km = 400`** (respetando el valor por defecto 1 500 de D4, pero cobrando por km si el recorrido excede el casco urbano). En la práctica, este fallback debe quedar casi vacío: si un viaje cae en él con más de 5 km, es señal de que falta dibujar un polígono.
- **C3 — Depende del combustible.** Si el chofer compra a precio de calle, el punto de equilibrio cae a ~2,7 km y el fijo de 1 500 deja de ser viable incluso en el Centro.

**Veredicto: viable como piso del casco urbano (≤3,9 km), inviable como tarifa única de municipio. Mantener 1 500 como `monto_fijo` de la zona municipal y del fallback, con revisión mensual indexada.**

---

## 3. Reparto: del precio bruto al margen del chofer

### 3.1 Cadena de reparto

```
Precio del viaje (cliente)
  − comisión plataforma 15 % (D5, global)   → ingreso plataforma
  = ingreso neto del chofer (acreditado si paga wallet; retenido si paga efectivo)
  − costo variable (combustible + mantenimiento + depreciación + fijos/km)
  = margen del chofer
```

### 3.2 El efecto del 11 % de recarga sobre la comisión

| Concepto | Fórmula | Sobre un viaje de 1 500 |
|---|---|---|
| Comisión nominal | 15 % × 1 500 | **225 CUP** |
| Recarga necesaria para tener 225 en wallet | 225 × 1,11 | **249,75 CUP pagados en efectivo** |
| **Comisión efectiva en viaje en efectivo** | 0,15 × 1,11 = **16,65 %** | **249,75 CUP** |

Y en el viaje con wallet la plataforma cobra dos veces:

| Origen | Tasa | Sobre 1 500 |
|---|---|---|
| Comisión al chofer (D5) | 15 % | 225 |
| Comisión de recarga al cliente | 11 % | 165 |
| **Take-rate combinado** | **26 %** | **390** |

**Incentivo invertido:** al cliente le conviene pagar en efectivo (evita el 11 %) y al chofer también (evita inmovilizar saldo). Es la combinación que maximiza la desintermediación (§5.3). **Recomendación: bajar `comision_recarga_pct` a 6 %.**

### 3.3 Tabla de escenarios — comisión 15 % global, costo auto 330 CUP/km

`Actual` = fórmula vigente (800 plano dentro del círculo; `800 + 200 × km` fuera). `Nuevo` = modos D3 con los valores recomendados en §8. Todos en CUP.

| # | Escenario | km | Precio actual | Neto actual | Costo | Margen actual | Precio nuevo | Com. 15 % | Neto | Margen nuevo |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Centro contenido, corto | 2,0 | 800 | 680 | 660 | **+20** | 1 500 (`fijo`) | 225 | 1 275 | **+615** |
| 2 | **Viaje promedio real** | 3,3 | 800 | 680 | 1 089 | **−409** | 1 500 (`fijo`) | 225 | 1 275 | **+186** |
| 3 | Centro → Reparto Virginia | 3,0 | 1 400 | 1 190 | 990 | +200 | 1 500 (`fijo_mas_km`/piso) | 225 | 1 275 | **+285** |
| 4 | Centro → Circunvalación | 5,0 | 1 800 | 1 530 | 1 650 | −120 | **2 400** (`fijo_mas_km`) | 360 | 2 040 | **+390** |
| 5 | Centro → UCLV (Camajuaní km 5,5) | 8,0 | 2 400 | 2 040 | 2 640 | −600 | **3 900** (`fijo_mas_km`) | 585 | 3 315 | **+675** |
| 6 | Centro → Aeropuerto Abel Santamaría | 9,7 | 2 740 | 2 329 | 3 201 | **−872** | **5 100** (`fijo_mas_km`) | 765 | 4 335 | **+1 134** |
| 7 | Centro → Báez | 7,0 | 2 200 | 1 870 | 2 310 | −440 | **3 450** (`fijo_mas_km`) | 518 | 2 932 | **+622** |
| 8 | SC → Remedios (intermunicipal) | 44,0 | — | — | 14 520 | — | **20 600** (`fijo_mas_km`) | 3 090 → **2 500 con tope** | 18 100 | **+3 580** |
| 9 | SC → Cayo Santa María | 113,0 | — | — | 37 290 | — | **51 650** | 7 748 → **2 500 con tope** | 49 150 | **+11 860** |
| 10 | **Ejemplo del requerimiento: fijo 300 + 80/km**, 10 km | 10,0 | — | — | 3 300 | — | 1 100 → **piso 1 500** | 225 | 1 275 | **−2 025** ❌ |
| 11 | Moto, Centro contenido | 2,0 | 500 | 425 | 186 | +239 | **900** (1500 × 0,60) | 135 | 765 | **+579** |
| 12 | Microbús, Centro contenido | 3,3 | 800 | 680 | 1 439 | **−759** | **2 250** (1500 × 1,50) | 338 | 1 913 | **+474** |
| 13 | Auto, 9 min de espera en Centro | 2,0 | 800 | 680 | 660 | +20 | 1 500 + (9−3)×40 = **1 800** | 270 | 1 530 | **+870** |

**Lecturas clave:**
- **(2) es el hallazgo central:** el viaje promedio actual **pierde 409 CUP** para el chofer. El problema no es la comisión: es que el precio base está por debajo del costo.
- **(4) a (7):** todo viaje fuera del círculo de 2,53 km pierde dinero hoy. Los modos `fijo_mas_km` con `precio_km` ≥ 400 lo corrigen.
- **(10):** el ejemplo «300 + 80/km» **debe rechazarse**. 80 CUP/km equivale a 68 CUP/km netos, contra 330 de costo.
- **(11) y (12):** la moto está subvalorada por km (cobra 300/km, más que el auto) y el microbús está claramente subvalorado (pierde 759 CUP en el viaje promedio). Los multiplicadores D2 corrigen ambos casos.
- **(9):** un viaje de 113 km deja 11 860 CUP de margen… pero el cliente paga 51 650. El `tope_comision_viaje` es el instrumento correcto para que el chofer reciba incentivo sin tocar el % global (D5).

### 3.4 Sensibilidad al precio del combustible (viaje de 3,3 km en Centro a 1 500)

| Escenario de combustible | CUP/L | Costo/km | Costo del viaje | Neto a 1 500 | Margen | Veredicto |
|---|---|---|---|---|---|---|
| Canal oficial | 1 800 | 290 | 957 | 1 275 | **+318** | ✅ Sano |
| Blend (base) | 2 200 | 330 | 1 089 | 1 275 | **+186** | ✅ Aceptable |
| Regular 2,5 USD al cambio especial | 2 050 | 315 | 1 040 | 1 275 | +235 | ✅ |
| Regular a 2 500 | 2 500 | 360 | 1 188 | 1 275 | +87 | ⚠️ Ajustado |
| Regular a 2 760 | 2 760 | **386** | **1 274** | 1 275 | **0** | 🔴 **Punto de quiebre** |
| Calle regular | 3 600 | 470 | 1 551 | 1 275 | **−276** | ❌ Pérdida |
| Calle especial | 7 000 | 810 | 2 673 | 1 275 | **−1 398** | ❌ Ruina |

> **El fijo de 1 500 CUP se sostiene hasta ~2 760 CUP/L.** Por encima, el viaje promedio pierde dinero. **Consecuencia operativa: el tarifario debe publicarse con `precio_vigente_desde` y revisarse cada 30 días.** En Cuba, un tarifario sin fecha de vigencia queda obsoleto en semanas.

### 3.5 Ingreso del chofer a escala (modelo recomendado)

Mezcla diaria asumida: 10 viajes municipales (precio prom. 1 650, 3,3 km) + 4 de zona interna (precio prom. 2 600, 5,5 km) + 1 aeropuerto (5 100, 9,7 km).

| Concepto | Valor/día | Valor/mes (22 días) |
|---|---|---|
| Ingreso bruto | 32 000 | 704 000 |
| Comisión 15 % (D5) | −4 800 | −105 600 |
| Ingreso neto | 27 200 | 598 400 |
| Costo de operación (64,7 km × 330) | −21 351 | −469 722 |
| **Margen del chofer** | **5 849** | **128 678** |

Comparación: **128 678 CUP/mes ≈ 18,6× el salario medio (6 930 CUP)**. Es coherente con la realidad del sector privado/informal cubano (el ingreso privado supera con creces el estatal), pero advierte que **el limitante del mercado es la demanda, no la oferta de choferes**: los choferes aparecerán; los pasajes a 1 500 CUP pueden no.

### 3.6 El chofer en efectivo: bloqueo vs deuda con límite (D6)

**Cómo funciona hoy:** `incoming_requests_screen.dart` L527–543 llama `driverHasEnoughForCommission()`; si `balance < precio × 0,15`, **no lo deja ni ofertar**. El RPC `complete_ride_payment` (L73–76) repite el bloqueo al cerrar y devuelve `success: false`.

**Datos reales del piloto:** 6 filas en `wallet_drivers`, saldo promedio **17 856 CUP**, mínimo **4 393**, ninguno en cero. Hoy el bloqueo no muerde; con volumen, sí.

**Justificación numérica del tope (pedida por el lead):**

| Referencia | Valor | Cobertura del tope |
|---|---|---|
| Comisión de un viaje municipal típico (15 % de 1 500) | **225 CUP** | — |
| Comisión de un viaje promedio (15 % de 2 000) | **300 CUP** | — |
| **Tope sugerido por el usuario: 500 CUP** | 500 | **2,2 viajes municipales** o 1,7 viajes promedio |
| **Tope recomendado: 1 000 CUP** | 1 000 | **4,4 viajes municipales** o 3,3 viajes promedio |
| Comisión que genera un chofer en un día de trabajo (15 viajes) | ~4 800 CUP | 1 000 = **21 % de la comisión de un día** |

**Recomendación: `deuda_max_chofer = 1 000 CUP` como valor operativo, con 500 CUP durante las primeras 4 semanas de lanzamiento (control de mora).** Un tope de 500 CUP equivale a 2,2 viajes: un chofer que haga 4 viajes en efectivo seguidos ya queda bloqueado, exactamente el problema que D6 busca eliminar. 1 000 CUP ≈ **la comisión de un día de trabajo** es el máximo razonable: es una cuenta por cobrar de un día, no de una semana.

| Opción | Ventaja | Riesgo | Cálculo |
|---|---|---|---|
| A. Bloqueo estricto (status quo) | Cero mora | Mata oferta; obliga a recargar y pagar 11 % ⇒ comisión real 16,65 % | Bloquea al agotarse el saldo |
| **B. Deuda con límite (D6)** ⭐ | Desacopla oferta del prepago; elimina la fricción del 11 % | Mora acotada | Con 1 000 CUP: 4,4 viajes municipales de colchón |

**Reglas de implementación recomendadas:**
1. `deuda_max_chofer = 1 000` (lanzamiento: 500).
2. Bloquear nuevas aceptaciones cuando `balance − comision_del_viaje < −deuda_max_chofer`.
3. Deuda solo para choferes con `kyc = true` y `estado = true`.
4. Si la deuda supera `dias_max_deuda = 7` o el tope, degradar a bloqueo estricto hasta la próxima recarga.
5. Bajar `comision_recarga_pct` de 11 % a 6 %: es lo que convierte un 15 % nominal en 16,65 % real.

> Con D6, el mensaje al chofer ya no puede ser «saldo insuficiente para comisión» en el momento de ofertar (bug 3). Debe ser: «te quedan X CUP de margen de deuda» en la tarjeta del viaje.

---

## 4. Comparativa de modelos de comisión (bajo D5: 15 % global configurable)

D5 fija un **15 % global configurable**. La comparativa se mantiene como análisis de la decisión y de sus alternativas futuras, pero **la recomendación es respetar el 15 % global** y corregir su distorsión con un tope, no cambiando el modelo.

### 4.1 Los cuatro modelos

| Modelo | Descripción | Ingreso plataforma/viaje (ticket 2 000) | Ventaja | Problema |
|---|---|---|---|---|
| **A. 15 % plano (D5)** ⭐ | `precio × 0,15` siempre | 300 | Simple, predecible, ya implementado; coherente con D5 | Castiga el viaje largo |
| B. Escalonado por volumen | 15 % hasta 40 viajes/mes, 12 % hasta 100, 10 % >100 | 300 → 240 | Premia dedicación, retiene flota | Requiere tracking mensual; complejidad |
| C. Suscripción / plan | Cuota fija mensual, 0 % comisión | cuota/mes | Elimina el bloqueo y la deuda; ingreso predecible | **Rompe la economía** (ver §4.3) |
| D. Comisión por zona | 15/12/10 % | 225–500 | Alinea incentivos del largo | **Contradice D5**; más parámetros |

### 4.2 Por qué el 15 % plano necesita un tope (cálculo)

| Viaje | Precio | Margen antes de comisión | Comisión 15 % | % del margen que se lleva | Con `tope_comision_viaje = 2 500` | % efectivo del margen |
|---|---|---|---|---|---|---|
| Corto 2 km Centro | 1 500 | 840 | 225 | **26,8 %** | 225 | 26,8 % |
| Medio 5 km Periferia | 2 400 | 750 | 360 | 48,0 % | 360 | 48,0 % |
| Aeropuerto 9,7 km | 5 100 | 1 899 | 765 | **40,3 %** | 765 | 40,3 % |
| Intermunicipal 44 km | 20 600 | 6 080 | 3 090 | **50,8 %** | **2 500** | **41,1 %** |
| Cayo Santa María 113 km | 51 650 | 14 360 | 7 748 | **54,0 %** | **2 500** | **17,4 %** |

**Un 15 % plano se lleva proporcionalmente más del margen del viaje largo**, que es el de menor densidad de demanda y el que más incentivo necesita. El `tope_comision_viaje` (parámetro global, compatible con D5) corrige el extremo sin cambiar el porcentaje: convierte el 15 % en 12,1 % efectivo para Remedios y 4,8 % para Cayo Santa María. **Recomendación: `tope_comision_viaje = 2 500 CUP`.**

### 4.3 Suscripción: por qué NO arrancar con ella (números)

- Viajes/mes por chofer activo (escenario base 100 viajes/día ÷ 15 choferes activos) ≈ **200 viajes/chofer/mes**.
- GMV/chofer/mes = 200 × 2 000 = **400 000 CUP**.
- Comisión equivalente al 15 % = **60 000 CUP/mes** (≈ 66 USD).
- Una cuota de ese orden por adelantado es **imposible de cobrar** en el mercado local.

Además, la suscripción **selecciona adversamente**: los choferes de baja actividad eligen comisión, los de alta eligen plan, y la plataforma queda con el peor mix. **Veredicto: suscripción útil como plan para flotas/dispatchers (ya existe el patrón en `muevete.planes`, 20–199 USD/mes para carrier/dispatcher), no para el chofer individual de taxi.**

### 4.4 Sensibilidad del ingreso de la plataforma a la comisión (D5 configurable)

Ticket promedio 2 000 CUP, sin recarga, 30 días/mes:

| Comisión | 20 viajes/día | 50/día | 100/día | 250/día | 500/día |
|---|---|---|---|---|---|
| **15 % (D5)** | 180 000 | 450 000 | 900 000 | 2 250 000 | 4 500 000 |
| 12 % | 144 000 | 360 000 | 720 000 | 1 800 000 | 3 600 000 |
| 10 % | 120 000 | 300 000 | 600 000 | 1 500 000 | 3 000 000 |

**Conclusión: la comisión no es la palanca principal.** Bajar del 15 % al 10 % cuesta 300 000 CUP/mes a 100 viajes/día, que es menos que el valor de duplicar el volumen. **Priorizar la conversión de demanda antes que el porcentaje.**

---

## 5. Elasticidad y riesgo

### 5.1 Demanda si el mínimo sube a 1 500

| Referencia | Valor |
|---|---|
| Ticket promedio actual | 1 237 CUP |
| Mediana actual | **800 CUP** |
| Salto de la mediana a 1 500 | **+87,5 %** |
| Salto del promedio a 1 500 | **+21,3 %** |
| Alternativa informal (botero / colectivo / guagua) | decenas de CUP |

**Análisis:**
- Para el viaje de **≥3 km**, el paso a 1 500 es **absorbible**: el precio realizado por km del auto ya es 549 CUP/km y el usuario ya paga eso.
- Para el viaje de **1–2 km**, el paso de ~500–800 a 1 500 es **+87 % a +200 %**. Aquí se concentra el riesgo de abandono y de migración al botero.
- **Mitigación:** `precio_corto` de **1 000 CUP para auto** en recorridos < 1,5 km. A 1 000 CUP el chofer igual gana: 1 000 × 0,85 = 850 − 495 (1,5 km × 330) = **+355 CUP en ~8 min = 2 660 CUP/h**. Se preserva el margen y la demanda corta.
- **Disparador de contingencia:** si en 30 días la conversión cae >25 % o la cancelación post-aceptación supera 30 %, bajar `monto_fijo_municipio` a **1 200 CUP** por 30 días y volver a medir.

### 5.2 Incentivo del chofer a aceptar viajes cortos

**Con fijo puro (sin componente por km, es decir modo `fijo` mal aplicado a todo):**

| Viaje | Precio | Neto | Costo | Margen | Tiempo (2 min/km + 5 min pickup) | Margen/hora |
|---|---|---|---|---|---|---|
| 2 km | 1 500 | 1 275 | 660 | **+615** | 9 min | **4 100** |
| 5 km | 1 500 | 1 275 | 1 650 | −375 | 15 min | **−1 500** |
| 9,7 km | 1 500 | 1 275 | 3 201 | −1 926 | 24,4 min | **−4 736** |

➡️ Con fijo puro el chofer **rechaza todo lo que pase de 3,9 km**. El cherry-picking no es una sospecha: es la consecuencia aritmética.

**Con el diseño recomendado (modos D3 + `precio_km` 400/420 + multiplicadores D2):**

| Viaje | Precio | Neto | Costo | Margen | Tiempo | Margen/hora |
|---|---|---|---|---|---|---|
| 2 km Centro (`fijo`) | 1 500 | 1 275 | 660 | +615 | 9 min | 4 100 |
| 3,3 km Centro (`fijo`) | 1 500 | 1 275 | 1 089 | +186 | 11,6 min | 962 |
| 5 km Periferia (`fijo_mas_km`) | 2 400 | 2 040 | 1 650 | +390 | 15 min | 1 560 |
| 9,7 km Aeropuerto (`fijo_mas_km`) | 5 100 | 4 335 | 3 201 | +1 134 | 24,4 min | 2 788 |
| 44 km Intermunicipal | 20 600 | 18 100 (con tope) | 14 520 | +3 580 | 93 min | 2 310 |

➡️ El diseño **elimina todos los márgenes negativos** y reduce la brecha corto/largo de 4,1× a 1,5×. Complemento: prioridad de despacho para largos y `prima_distancia_cup = 500` (>8 km).

### 5.3 Riesgo de colusión / regateo fuera de la app ⚠️ **RIESGO #1**

Con **precio fijo + pago en efectivo**, el incentivo a salirse de la app es máximo:

| Viaje | Precio en app | Neto chofer en app (incluye el costo efectivo del 11 % de recarga) | Precio fuera de la app | Gana el cliente | Gana el chofer si cobra lo mismo fuera |
|---|---|---|---|---|---|
| 2 km | 1 500 | 1 250 | ~1 300 | 200 (13 %) | +250 |
| 9,7 km | 5 100 | 4 251 | ~4 400 | 700 (14 %) | +849 |
| 44 km | 20 600 | 17 825 | ~18 000 | 2 600 (13 %) | +2 775 |

- **El cliente siempre gana** (ahorra 13–14 %). **El chofer gana si mantiene el mismo precio** fuera de la app. Los dos tienen incentivo.
- **La asimetría decisiva:** la comisión solo está garantizada cuando el dinero pasa por la app. En efectivo es una **cuenta por cobrar** — y con D6, una cuenta por cobrar con tope.

**Mitigaciones (en orden de impacto):**
1. **Empujar el pago con wallet** con descuento al cliente (`descuento_pago_wallet_pct = 5`), financiado con parte del 11 % de recarga. Hoy ya hay paridad: **28 wallet vs 27 efectivo** sobre 55 solicitudes.
2. **Penalizar la cancelación después de aceptar** (cliente y chofer) y registrar `cancelaciones_post_aceptacion` como KPI.
3. **Retener la comisión en origen** cuando haya saldo (no reclamarla a posteriori), reforzando la lógica de deuda de D6.
4. **No exponer el precio del viaje antes de confirmar** al chofer, para que el cliente no lo use como argumento de regateo.
5. **Auditoría de patrones:** viajes con duración anómala, cancelaciones repetidas con el mismo cliente, GPS que no coincide con el recorrido facturado.

### 5.4 Competencia informal

| Competidor | Precio percibido | Ventaja | Debilidad que la app explota |
|---|---|---|---|
| Botero / taxi colectivo | Decenas de CUP por tramo | Barato, frecuente, sin app | Sin puerta a puerta ni garantía |
| Guagua / transporte estatal | Mínimo | Precio | Colas, hacinamiento, sin horario |
| Grupos de WhatsApp / dispatch informal | Negociado | Confianza, sin comisión | Sin precio conocido, sin trazabilidad |
| Taxi turístico en EUR/USD | ~1 USD/km | Paga en divisa | No atiende demanda local en CUP |

**Implicación: la app no compite por precio con el botero (no puede). Compite por previsibilidad, puerta a puerta y garantía** — que es exactamente lo que un precio fijo entrega. Pero esa propuesta se destruye si el pasajero aprende que puede regatear por fuera.

---

## 6. KPIs económicos y simulación de ingresos

### 6.1 KPIs

| KPI | Fórmula | Objetivo inicial | Fuente |
|---|---|---|---|
| Viajes/día | `count(viajes completados)` diario | 30 → 100 en 90 días | `muevete.viajes` |
| Ticket promedio | `avg(precio_final)` | ≥ 2 000 CUP | `solicitudes_transporte` |
| GMV mensual | `Σ precio_final` | — | — |
| **Take-rate efectivo** | `ingresos_plataforma / GMV` | 13 – 15 % | `transacciones_wallet` |
| Ingreso por viaje | `comisión + recarga atribuible` | ≥ 400 CUP | ídem |
| **Margen del chofer por hora** | `(neto − costo) / horas_conectado` | ≥ 1 500 CUP/h | requiere GPS |
| Viajes por chofer/día | `viajes / choferes_activos` | ≥ 8 | ídem |
| Tasa de aceptación | `aceptados / publicados` | ≥ 60 % | `ofertas_chofer` |
| **Cancelación post-aceptación** | `cancelados_post_aceptacion / aceptados` | < 10 % | nuevo campo |
| % pagos con wallet | `wallet / total` | ≥ 60 % | `metodo_pago` |
| **Deuda pendiente de choferes** | `Σ min(0, balance)` | < 5 % de la comisión mensual | `wallet_drivers` |
| Choferes bloqueados por deuda | `count(balance ≤ −deuda_max)` | < 5 % | `wallet_drivers` |
| Recargas aprobadas/mes | `count(recarga)` | — | `transacciones_wallet` |
| Combustible implícito | `costo/km declarado` | monitor | encuesta/param |

**Baseline actual (verificado en BD):** 44 viajes totales, 55 solicitudes, 23 choferes registrados, 11 vehículos, 6 wallets de chofer, 18 recargas por 1 320 257 CUP, 12 transacciones de comisión por 2 497 CUP (promedio **208 CUP/viaje**, consistente con 15 % de un ticket de ~1 387). Es un **piloto**, no un mercado.

### 6.2 Simulación de ingreso de la plataforma (comisión 15 %, D5)

Supuestos: ticket promedio **2 000 CUP** (mezcla 70 % municipio 1 500 / 20 % zona interna 2 600 / 7 % periferia-UCLV 3 900 / 3 % aeropuerto 5 100), 30 días/mes, **50 % de los viajes pagados con wallet** (portando 11 % de recarga sobre el valor del viaje).

| Viajes/día | GMV/día | GMV/mes | Comisión 15 % | Recarga (11 % s/50 % wallet) | **Total 15 % + recarga** |
|---|---|---|---|---|---|
| **20** | 40 000 | 1 200 000 | 180 000 | 66 000 | **246 000** |
| **50** | 100 000 | 3 000 000 | 450 000 | 165 000 | **615 000** |
| **100** | 200 000 | 6 000 000 | 900 000 | 330 000 | **1 230 000** |
| **250** | 500 000 | 15 000 000 | 2 250 000 | 825 000 | **3 075 000** |
| **500** | 1 000 000 | 30 000 000 | 4 500 000 | 1 650 000 | **6 150 000** |

**Costo de la plataforma (estimación):**

| Rubro | CUP/mes | Base |
|---|---|---|
| Supabase (plan pro) | 22 500 | 25 USD × 900 |
| Routing / mapas | 18 000 | 0,01 USD/viaje × 2 000 viajes |
| Dominio, correo, herramientas | 5 000 | — |
| Soporte / atención (medio tiempo) | 50 000 | — |
| **Total fijo** | **~95 500** | |
| Variable | 9 CUP/viaje | 0,01 USD |

**Punto de equilibrio:** contribución por viaje = 15 % × 2 000 + 110 (recarga) − 9 = **401 CUP**. `95 500 ÷ 401 ≈ 238 viajes/mes` ≈ **8 viajes/día**.

➡️ **La plataforma es rentable desde volúmenes muy bajos.** El desafío no es la rentabilidad unitaria, es **alcanzar los 100 viajes/día**.

### 6.3 Escenarios a 12 meses (ilustrativo)

| Escenario | Viajes/día (mes 12) | Ticket | Ingreso plataforma/mes (15 % + recarga) | Margen chofer/mes |
|---|---|---|---|---|
| Conservador | 40 | 1 800 | 220 000 + 60 000 | ~85 000 |
| Base | 100 | 2 000 | 900 000 + 330 000 | ~128 000 |
| Optimista | 300 | 2 400 | 3 240 000 + 1 188 000 | ~150 000 |

---

## 7. Parámetros configurables en superadmin (listos para la migración)

### 7.1 Parámetros globales

| # | Parámetro | Tipo | Unidad | Valor recomendado | Rango válido | Quién | Justificación numérica |
|---|---|---|---|---|---|---|---|
| 1 | `moneda` | text | — | **`CUP`** | CUP | — | Verificado: `vehicle_type` y tickets reales están en CUP |
| 2 | `comision_pct` | numeric(5,2) | % | **15,00** | 0 – 30 | Superadmin | **D5.** 15 % de 1 500 = 225; de 2 000 = 300 |
| 3 | `comision_recarga_pct` | numeric(5,2) | % | **11,00 → bajar a 6,00** | 0 – 15 | Superadmin | 0,15 × 1,11 = **16,65 %** real; el doble cobro en wallet es 26 % |
| 4 | `tope_comision_viaje` | int | CUP | **2 500** | 0 – 20 000 | Superadmin | Baja el 15 % al 12,1 % en Remedios y 4,8 % en Cayo Santa María |
| 5 | `multiplicador_moto` | numeric(4,2) | × | **0,60** | 0,40 – 0,90 | Superadmin | **D2.** Costo moto 93/km vs auto 330 (ratio 0,28); 0,60 deja margen holgado |
| 6 | `multiplicador_auto` | numeric(4,2) | × | **1,00** | base | Superadmin | **D2** |
| 7 | `multiplicador_microbus` | numeric(4,2) | × | **1,50** | 1,20 – 2,00 | Superadmin | **D2.** Costo 436/km vs 330 (ratio 1,32) |
| 8 | `precio_minimo_auto` | int | CUP/viaje | **1 500** | 1 000 – 5 000 | Superadmin | = fijo municipal; corto equilibrio a 3,86 km |
| 9 | `precio_minimo_moto` | int | CUP/viaje | **900** | 600 – 3 000 | Superadmin | 0,60 × 1 500; costo moto 2 km = 186 |
| 10 | `precio_minimo_microbus` | int | CUP/viaje | **2 250** | 1 500 – 7 500 | Superadmin | 1,50 × 1 500; costo microbús 3,3 km = 1 439 |
| 11 | `precio_corto_auto` | int | CUP/viaje | **1 000** | 500 – 1 500 | Superadmin | Válvula de elasticidad; deja +355 CUP al chofer en 1,5 km |
| 12 | `umbral_km_corto` | numeric(4,1) | km | **1,5** | 0,5 – 3,0 | Superadmin | Frontera del precio corto |
| 13 | `redondeo_cup` | int | CUP | **50** | **5 / 25 / 50** | Superadmin | 1 500, 2 400, 3 900 y 5 100 ya son múltiplos de 50; 25 si se quiere precisión; **no usar 5** (ruido) |
| 14 | `recargo_nocturno_pct` | numeric(5,2) | % | **20,00** | 0 – 50 | Superadmin | Sobre el subtotal, nunca sobre espera (evita compounding) |
| 15 | `ventana_nocturna_inicio` | time | HH:MM | **22:00** | — | Superadmin | Demanda y riesgo |
| 16 | `ventana_nocturna_fin` | time | HH:MM | **06:00** | — | Superadmin | ídem |
| 17 | `tarifa_espera_min_auto` | int | CUP/min | **40** | 0 – 500 | Superadmin | **Ya en BD** (`precio_espera_min`); corregir el bug 1 |
| 18 | `tarifa_espera_min_moto` | int | CUP/min | **100** | 0 – 500 | Superadmin | Ya en BD |
| 19 | `tarifa_espera_min_microbus` | int | CUP/min | **60** | 0 – 500 | Superadmin | Ya en BD |
| 20 | `gracia_espera_min` | int | min | **3** | 0 – 15 | Superadmin | 0 min genera disputas con el cliente |
| 21 | `tope_cobro_espera` | int | CUP | **1 200** | 0 – 10 000 | Superadmin | ≈ 1 viaje municipal; evita abusos |
| 22 | **`deuda_max_chofer`** | int | CUP | **1 000** (lanzamiento **500**) | 0 – 5 000 | Superadmin | **D6.** 225/viaje municipal ⇒ 1 000 = 4,4 viajes ≈ comisión de un día. Con 500 el bloqueo llega a los 2,2 viajes |
| 23 | `dias_max_deuda` | int | días | **7** | 1 – 30 | Superadmin | Una semana es el máximo razonable para una cuenta por cobrar |
| 24 | `kyc_requerido_para_deuda` | bool | — | **true** | — | Superadmin | Solo KYC verificado acumula deuda |
| 25 | `monto_fijo_fallback_municipio` | int | CUP/viaje | **1 500** | 500 – 5 000 | Superadmin | **D4** |
| 26 | `modo_fallback` | text | enum | **`fijo`** | fijo/fijo_mas_km/por_km | Superadmin | Recomendado para que el fallback no pierda en largos |
| 27 | `precio_km_fallback` | int | CUP/km | **400** | 0 – 2 000 | Superadmin | Override de seguridad si el viaje sale del casco urbano |
| 28 | `prima_distancia_cup` | int | CUP | **500** | 0 – 5 000 | Superadmin | Incentivo explícito al viaje > 8 km |
| 29 | `umbral_prima_distancia_km` | numeric(4,1) | km | **8,0** | 3 – 50 | Superadmin | Frontera de la prima |
| 30 | `descuento_pago_wallet_pct` | numeric(5,2) | % | **5,00** | 0 – 20 | Superadmin | Antídoto contra la desintermediación (§5.3) |
| 31 | `revision_precio_dias` | int | días | **30** | 7 – 180 | Superadmin | Fijo de 1 500 se sostiene solo hasta ~2 760 CUP/L de combustible |
| 32 | `precio_vigente_desde` | timestamptz | ISO | — | — | Superadmin | Versionado obligatorio por inflación |
| 33 | `pct_visible_chofer` | numeric(5,2) | % | **85,00** | 50 – 100 | Superadmin | ⚠️ Debe ser siempre `100 − comision_pct` (§7.3) |

### 7.2 Zonas (polígonos D1) — valores recomendados

Distancias medidas desde el centro de Santa Clara (Parque Vidal, 22.40689, −79.96450). Los polígonos los dibuja el superadmin; aquí se dan las referencias y los parámetros.

| Código | Zona | Referencia / extensión | `modo` | `monto_fijo` | `precio_km` | Precio típico (auto) | Justificación |
|---|---|---|---|---|---|---|---|
| **MUN** | **Municipio Santa Clara** (zona base) | Polígono del municipio | **`fijo`** | **1 500** | **400** | 1 500 contenido; si sale, `km × 400` | Es la zona por defecto. Contenido = fijo; salida = km × 400 (≥ 388 de equilibrio) |
| **Z1** | **Centro** | Parque Vidal, Boulevard, Terminal, Hospital Milián (0–1,5 km) | **`fijo`** | **1 500** | **400** | **1 500** | Zona compacta y homogénea: el flat es correcto; todas las carreras internas cuestan igual |
| **Z2** | **Condado – Santa Catalina** | Norte, 1,5–3 km | **`fijo`** | **1 500** | **400** | **1 500** | Igual que el Centro: extensión pequeña, distancias internas parecidas |
| **Z3** | **Reparto Virginia** | Suroeste, 2–4 km | **`fijo_mas_km`** | **300** | **400** | 1 900 (4 km) · piso 1 500 (3 km) | Zona alargada: el flat castigaría el extremo alejado |
| **Z4** | **Báez** | Oeste (pueblo), ~7 km | **`fijo_mas_km`** | **500** | **420** | **3 450** (7 km) | Salida/entrada por Carretera Central; costo alto por km |
| **Z5** | **UCLV / Camajuaní km 5,5** | Noreste, ~8 km | **`fijo_mas_km`** | **500** | **420** | **3 900** (8 km) | Demanda estudiantil recurrente; km domina |
| **Z6** | **Aeropuerto Abel Santamaría** | Este, ~9,7 km | **`fijo_mas_km`** | **1 000** | **420** | **5 100** (9,7 km) | Viaje turístico con equipaje; necesita fijo alto y km |
| **Z7** | **Periferia / Circunvalación / Zona Industrial** | Anillo 4–6 km | **`fijo_mas_km`** | **300** | **420** | **2 400** (5 km) | Zona difusa y extensa |
| **Z8** | **Corredor intermunicipal** | Remedios, Camajuaní, Placetas, Sagua, Cienfuegos (24–73 km) | **`fijo_mas_km`** | **800** | **450** | **20 600** (44 km) | Modo mixto: el km domina. Con `tope_comision_viaje` el chofer retiene más |
| **Z9** | **Cayos (Cayo Santa María / Ensenachos)** | 113 km | **`fijo_mas_km`** | **800** | **450** | **51 650** (113 km) | Turístico de largo recorrido |
| **FB** | **Fallback (D4)** | Fuera de todo polígono | **`fijo`** | **1 500** | **400** | 1 500; si sale, `km × 400` | Recomendación: implementarlo con `precio_km` para no perder en largos. Debe quedar casi vacío |

**Verificación de cada zona contra el costo (auto, 15 % de comisión, 330 CUP/km):**

| Zona | Viaje de prueba | Precio | Neto | Costo | Margen | Margen % |
|---|---|---|---|---|---|---|
| Z1 Centro `fijo` | 3,3 km contenido | 1 500 | 1 275 | 1 089 | **+186** | 17 % |
| Z1 Centro `fijo` (salida) | 9,7 km a Z6 | 9,7 × 400 = 3 880 | — | 3 201 | **+97** | 3 % |
| Z3 Virginia `fijo_mas_km` | 4,0 km | 300 + 1 600 = 1 900 | 1 615 | 1 320 | **+295** | 22 % |
| Z4 Báez `fijo_mas_km` | 7,0 km | 500 + 2 940 = 3 440 → **3 450** | 2 933 | 2 310 | **+623** | 27 % |
| Z5 UCLV `fijo_mas_km` | 8,0 km | 500 + 3 360 = 3 860 → **3 900** | 3 315 | 2 640 | **+675** | 26 % |
| Z6 Aeropuerto `fijo_mas_km` | 9,7 km | 1 000 + 4 074 = 5 074 → **5 100** | 4 335 | 3 201 | **+1 134** | 35 % |
| Z7 Periferia `fijo_mas_km` | 5,0 km | 300 + 2 100 = 2 400 | 2 040 | 1 650 | **+390** | 24 % |
| Z8 Intermunicipal | 44 km | 800 + 19 800 = 20 600 | 18 100 (tope) | 14 520 | **+3 580** | 25 % |
| **Contraejemplo** «300 + 80/km» | 10 km | 300 + 800 = 1 100 → **piso 1 500** | 1 275 | 3 300 | **−2 025** | ❌ |

**El `precio_km` de una zona en modo `fijo` no puede bajar de 400 (auto):** su salida se cobra como `km_total × precio_km`, y 388 es el punto de equilibrio del auto.

### 7.3 El «% que ve el chofer»

El requerimiento pide mostrar «se cobrará tanto, a ti te toca tanto %». **Hoy ese texto no existe**: el único lugar donde el chofer ve la comisión es un mensaje de error (`incoming_requests_screen.dart` L536, «15 % de tu oferta»). `driver_offer_card.dart` muestra solo el precio.

Reglas:
- `pct_visible_chofer` **debe derivarse** de `comision_pct`: `100 − comision_pct` ⇒ **85 %** con 15 % global (D5).
- Si se aplica `tope_comision_viaje`, el porcentaje mostrado debe ser **el efectivo de ese viaje** (p. ej. 87,9 % en Remedios), no el nominal.
- Prohibido mostrar un porcentaje distinto al real. La diferencia se detecta en la primera liquidación y la confianza no se recupera.
- La tarjeta del viaje debe mostrar: **precio del viaje**, **comisión en CUP**, **lo que te toca (CUP y %)** y **saldo y margen de deuda disponible** (D6). Sin eso, el precio fijo es una caja negra y el chofer rechazará viajes por desconfianza, no por economía.

---

## 8. Recomendación final numérica para arrancar en Santa Clara

### 8.1 Valores concretos (auto, CUP)

| Parámetro | Valor recomendado | Alternativa si la demanda cae >25 % en 30 días |
|---|---|---|
| Moneda | **CUP** | — |
| Zona base: municipio Santa Clara, modo `fijo` | **`monto_fijo` 1 500 · `precio_km` 400** | fijo 1 200 · km 400 |
| **`precio_km` por defecto Santa Clara (todas las zonas urbanas)** | **400 CUP/km** | 400 (no bajar) |
| `precio_km` en zonas de acceso (Báez, UCLV, Aeropuerto, Periferia) | **420 CUP/km** | 420 |
| `precio_km` corredores intermunicipales | **450 CUP/km** | 450 |
| `precio_minimo` auto / moto / microbús | **1 500 / 900 / 2 250 CUP** | 1 200 / 720 / 1 800 |
| Precio corto (<1,5 km) | **1 000 CUP** | 800 CUP |
| **Comisión global (D5)** | **15 %** | 12 % |
| `tope_comision_viaje` | **2 500 CUP** | 2 000 |
| Comisión de recarga | **11 % → 6 % en 60 días** | 11 % |
| `pct_visible_chofer` | **85 %** (real) | — |
| Multiplicadores (D2) | **moto 0,60 · auto 1,00 · microbús 1,50** | igual |
| Recargo nocturno | **20 %** entre **22:00 y 06:00** | 15 % |
| Tarifa de espera | **40 / 100 / 60 CUP/min** (auto/moto/microbús) tras **3 min** de gracia, tope **1 200 CUP** | 30 CUP/min |
| **Redondeo** | **múltiplos de 50 CUP hacia arriba** | 25 |
| **Tope de deuda del chofer (D6)** | **1 000 CUP** (lanzamiento **500**), máximo **7 días**, solo KYC | 500 |
| Prima de distancia >8 km | **500 CUP** | 300 |
| Descuento por pago con wallet | **5 % al cliente** | 3 % |
| Revisión del tarifario | **cada 30 días** con `precio_vigente_desde` | 15 días |

### 8.2 Zonas a cargar inicialmente

Ver tabla completa en §7.2. Resumen operativo: **MUN (fijo 1 500 / km 400) · Z1 Centro (fijo) · Z2 Condado–Santa Catalina (fijo) · Z3 Reparto Virginia (`fijo_mas_km` 300+400) · Z4 Báez (`fijo_mas_km` 500+420) · Z5 UCLV (`fijo_mas_km` 500+420) · Z6 Aeropuerto (`fijo_mas_km` 1 000+420) · Z7 Periferia (`fijo_mas_km` 300+420) · Z8 Intermunicipal (`fijo_mas_km` 800+450) · Z9 Cayos (`fijo_mas_km` 800+450) · FB Fallback (fijo 1 500 / km 400).**

### 8.3 Ejemplos de precio calculados (con redondeo a 50)

| Viaje | Tipo | Cálculo | Precio final |
|---|---|---|---|
| 1,2 km Centro | auto | `precio_corto` | **1 000** |
| 2,0 km Centro (contenido) | auto | `fijo` → 1 500 | **1 500** |
| 3,3 km Centro (promedio real) | auto | `fijo` → 1 500 | **1 500** |
| 4,0 km Reparto Virginia | auto | 300 + 400×4 = 1 900 | **1 900** |
| 5,0 km Periferia | auto | 300 + 420×5 = 2 400 | **2 400** |
| 7,0 km Báez | auto | 500 + 420×7 = 3 440 | **3 450** |
| 8,0 km UCLV | auto | 500 + 420×8 = 3 860 | **3 900** |
| 9,7 km Aeropuerto | auto | 1 000 + 420×9,7 = 5 074 | **5 100** |
| 9,7 km Aeropuerto, 23:00 | auto | 5 074 × 1,20 = 6 089 | **6 100** |
| 44 km Remedios | auto | 800 + 450×44 = 20 600 | **20 600** |
| 113 km Cayo Santa María | auto | 800 + 450×113 = 51 650 | **51 650** |
| 2,0 km Centro | **moto** | 1 500 × 0,60 = 900 | **900** |
| 3,3 km Centro | **microbús** | 1 500 × 1,50 = 2 250 | **2 250** |
| 9,7 km Aeropuerto | **microbús** | 5 074 × 1,50 = 7 611 | **7 650** |
| 2,0 km Centro + 9 min espera | auto | 1 500 + 6×40 = 1 740 | **1 750** |

### 8.4 Qué cambia respecto de hoy

| Métrica | Hoy | Recomendado | Δ |
|---|---|---|---|
| Comisión | 15 % global | **15 % global (D5) + tope 2 500 CUP** | = en %; −2,9 pp efectivo en el largo |
| Comisión efectiva en efectivo | **16,65 %** | 16,65 % → **9,9 %** si la recarga baja a 6 % | −6,75 pp |
| Take combinado en viaje wallet | **26 %** | **21 %** (15 % + 6 %) | −5 pp |
| Margen del chofer (viaje promedio 3,3 km) | **−409 CUP** | **+186 CUP** | **+595** |
| Margen del chofer (9,7 km) | **−872 CUP** | **+1 134 CUP** | **+2 006** |
| Margen del chofer (moto 2 km) | +239 CUP | **+579 CUP** | +340 |
| Margen del chofer (microbús 3,3 km) | **−759 CUP** | **+474 CUP** | +1 233 |
| Bloqueo por saldo | Rígido, en el momento de ofertar | **Deuda hasta 1 000 CUP**, bloqueo al superar el tope | Habilita oferta |
| Ingreso plataforma/viaje (ticket 2 000) | 300 | 300 + recarga | = |

---

## Supuestos

1. **Todo el módulo taxi está en CUP.** Verificado por `vehicle_type` y por los precios reales de `solicitudes_transporte`. El símbolo `$` es decorativo.
2. **Tipo de cambio para convertir referencias externas:** 820 CUP/USD (BCC especial, 12-nov-2026) y 900 CUP/USD como blend. Las tasas BCC oficial (24) y pública (120) no se usan para bienes de mercado.
3. **Consumo de combustible (estimación):** auto 10 L/100 km en ciudad (rango 8–12), moto 3 L/100 km, microbús 13 L/100 km. No medido en la flota.
4. **Costo por km (estimación):** auto 330 (base blend), 290 oficial, 470 calle; moto 93; microbús 436. Incluye mantenimiento, depreciación y fijos. No incluye lucro cesante ni impuestos municipales.
5. **El chofer es propietario del vehículo** en el escenario base. Existe un escenario de chofer no propietario (costo marginal 180 CUP/km en auto) no modelado en detalle.
6. **Ticket promedio futuro:** 2 000 CUP (70 % municipio / 20 % zona interna / 7 % periferia-UCLV / 3 % aeropuerto). Proyección, no dato.
7. **Distancias y tiempos:** 2 min/km + 5 min de pickup. Velocidad media real no medida.
8. **Distancias desde el centro** (2,53 km círculo; Virginia 2–4; Báez ~7; UCLV ~8; Aeropuerto ~9,7) son estimaciones geográficas para dimensionar los polígonos, no mediciones de ruta real de la app.
9. **El precio de combustible informal es prima de escasez**, no conversión de divisa. El modelo se planifica con el canal oficial y se testea contra el informal.
10. **Las tarifas turísticas en EUR/USD** describen el segmento de divisa, no el mercado local en CUP; se usan solo como techo de referencia.
11. **NO hay tarifario urbano verificado de Santa Clara en CUP.** Los estimadores genéricos (EstimaTaxi) tienen fiabilidad baja y no se usaron para calibrar.
12. **Volumen actual:** piloto con 44 viajes y 55 solicitudes. La simulación es prospectiva.
13. **Elasticidad desconocida:** no hay medición antes/después de un cambio de tarifa; el umbral de −25 % es criterio de gestión.
14. **Costo de plataforma:** Supabase 25 USD, routing 0,01 USD/viaje, soporte 50 000 CUP/mes. Orden de magnitud.
15. **El % mostrado al chofer es el real**; se asume sin margen para mostrar otro.
16. **Los tres modos D3** se interpretan literalmente: en `fijo`, salir de la zona factura `km_total × precio_km` (sin sumar el fijo).
17. **Válvula de arbitraje:** se toma el máximo entre la regla de la zona de origen y la de destino.

## Riesgos

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| 1 | **Desintermediación: regateo fuera de la app con precio fijo + efectivo** | Alta | Crítico | `descuento_pago_wallet_pct` 5 %; penalizar cancelación post-aceptación; retener la comisión en origen; no exponer el precio antes de confirmar |
| 2 | **Combustible a precio de calle (3 200–8 000 CUP/L)** deja el modelo en pérdida (punto de quiebre ~2 760 CUP/L) | Alta | Crítico | Revisión tarifaria cada 30 días con `precio_vigente_desde`; acuerdos de canal oficial; tarifa en divisa para el turístico |
| 3 | **El fallback D4 (1 500 plano) captura viajes largos** y pierde dinero | Media | Alto | `precio_km_fallback = 400`; dejar el fallback casi vacío dibujando polígonos |
| 4 | **Elasticidad del viaje corto (<2 km): +87 %** sobre la mediana actual | Media-alta | Alto | `precio_corto_auto` 1 000; contingencia a fijo 1 200 |
| 5 | **Cherry-picking**: el chofer rechaza largos por menor margen/hora | Alta | Alto | `precio_km` ≥ 400; `tope_comision_viaje`; `prima_distancia_cup`; prioridad de despacho |
| 6 | **Inflación**: el tarifario en CUP queda obsoleto en semanas | Alta | Alto | Versionado, revisión mensual, recordatorio activo |
| 7 | **Zona `fijo` con `precio_km` bajo**: la salida se cobra mal y pierde | Media | Alto | Validación en superadmin: `precio_km ≥ 400` para zonas en modo `fijo` |
| 8 | **Arbitraje entre zonas** (facturar con la regla barata) | Media | Medio | Regla del máximo origen/destino |
| 9 | **Mora de choferes** con D6 | Media | Medio | Tope 1 000 (lanzamiento 500), 7 días, solo KYC, degradar a bloqueo |
| 10 | **Doble cobro del 26 % en wallet** empuja al efectivo | Alta | Medio-alto | Bajar `comision_recarga_pct` a 6 % |
| 11 | **Bugs de tarifa ya presentes** (espera no leída, doble conteo de `precio_inside_sc`, bloqueo al ofertar) | Cierta | Medio | Corregir antes de tocar precios |
| 12 | **Polígonos mal dibujados** (excluir UCLV, Báez o el aeropuerto deja viajes en el fallback plano) | Media | Alto | Checklist de cobertura antes de publicar el tarifario |
| 13 | **Competencia informal** (boteros, guagua, WhatsApp) | Alta | Medio | Competir con previsibilidad y garantía, no con precio |

## Recomendación

**Arrancar en Santa Clara con polígonos (D1), modo por zona (D3), multiplicador por tipo (D2), 15 % global (D5) y deuda con tope (D6), con estos valores:**

1. **`precio_km` por defecto = 400 CUP/km** para Santa Clara urbana; **420** en zonas de acceso (Báez, UCLV, Aeropuerto, Periferia); **450** en corredores intermunicipales. El punto de equilibrio del auto es **388 CUP/km** (costo 330 ÷ 0,85); 400 deja el margen variable en +10/km, por eso **el margen debe venir del `monto_fijo`**.
2. **Municipio Santa Clara (zona base y fallback D4): modo `fijo`, `monto_fijo` 1 500, `precio_km` 400.** El fijo de 1 500 **es viable** porque el ticket promedio real ya es 1 237 CUP y el precio realizado por km del auto es 549 CUP/km, pero **solo hasta 3,86 km**: no puede ser la única tarifa del municipio.
3. **Modos por zona:** `fijo` en **Centro** (1 500) y **Condado–Santa Catalina** (1 500) — zonas compactas y homogéneas. `fijo_mas_km` en **Reparto Virginia** (300 + 400), **Báez** (500 + 420), **UCLV** (500 + 420), **Aeropuerto** (1 000 + 420), **Periferia** (300 + 420), **Intermunicipal** (800 + 450) y **Cayos** (800 + 450) — zonas alargadas o de acceso donde el flat castigaría el extremo. `por_km` **no se recomienda en el casco urbano** (sin fijo, el arranque no se paga).
4. **Rechazar el ejemplo «fijo 300 + 80/km»:** 80 CUP/km está **4,9× por debajo** del mínimo viable y deja al chofer con **−2 025 CUP** en un viaje de 10 km.
5. **Multiplicadores D2 confirmados:** moto 0,60 (costo 93/km vs 330 del auto), auto 1,00, microbús 1,50 (costo 436/km). Corrigen tres anomalías actuales: la moto cobra 300/km (más que el auto) y el microbús pierde 759 CUP en el viaje promedio.
6. **Mínimos por tipo: 1 500 auto / 900 moto / 2 250 microbús**, con `precio_corto` de 1 000 para < 1,5 km. **Redondeo a múltiplos de 50 hacia arriba** (1 500, 2 400, 3 900 y 5 100 ya son múltiplos de 50). **Recargo nocturno 20 % (22:00–06:00)**. **Espera 40/100/60 CUP/min tras 3 min de gracia, tope 1 200.**
7. **Comisión: 15 % global (D5) + `tope_comision_viaje` = 2 500 CUP.** El tope es compatible con un % global y corrige la distorsión del largo: baja el efectivo a 12,1 % en Remedios y 4,8 % en Cayo Santa María, sin tocar el porcentaje.
8. **Tope de deuda: 1 000 CUP (500 en las primeras 4 semanas), 7 días máximo, solo KYC verificado.** Justificación: la comisión de un viaje municipal es 225 CUP, así que 1 000 cubre **4,4 viajes impagos ≈ la comisión de un día de trabajo**. Con 500 el bloqueo reaparece a los 2,2 viajes y D6 no resuelve nada.
9. **Bajar `comision_recarga_pct` de 11 % a 6 %** en 60 días: es lo que convierte el 15 % nominal en 16,65 % real y el 26 % combinado en wallet.
10. **Mostrar al chofer su porcentaje real (85 %), la comisión en CUP, su saldo y su margen de deuda disponible** en la tarjeta del viaje.
11. **Revisar el tarifario cada 30 días con `precio_vigente_desde`** y activar contingencia (fijo municipal 1 200, corto 800) si la conversión cae >25 % o la cancelación post-aceptación supera el 30 %.

**Veredicto económico global:** la reforma es necesaria y financieramente sólida para la plataforma (equilibrio en **~8 viajes/día**), y los números de D2, D3 y D6 están bien calibrados contra el costo real del vehículo. Los tres puntos donde el sistema puede fallar no son de comisión: **el acceso al combustible en canal oficial, la retención del pago dentro de la app (punto de quiebre: fijo viable hasta ~2 760 CUP/L y desintermediación del 13–14 % para el cliente), y la disposición a pagar 1 500 CUP por un viaje corto.**
