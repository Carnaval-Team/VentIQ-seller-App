# 02 · Modelo de negocio y UX — Taxi con precio fijo (sin negociación)

**Módulo:** Muevete · pasajeros
**Apps afectadas:** `inventtia_muevete/` (cliente y conductor), `ventiq_superadmin/` (zonas y tarifas)
**Documento:** modelo de producto, reglas de negocio, flujos, estados, casos borde, KPIs y requisitos funcionales
**Depende de:** `01-*.md` (mapa técnico del flujo actual) · **Alimenta:** `03-*.md` (economía de tarifas) y `04-*.md` (diseño técnico)

> **Decisión de producto que ordena todo el documento:** el precio deja de ser un dato que el cliente escribe y pasa a ser un dato que la plataforma calcula. El cliente **no negocia**; el conductor **no contraoferta**. Solo hay dos acciones posibles: el cliente publica, el conductor toma. Todo lo demás (visibilidad, expiración, comisión, cancelaciones) se deriva de esa decisión.

## Decisiones cerradas (vinculantes para este documento)

| # | Decisión | Cómo queda reflejada |
|---|---|---|
| **D1** | Las zonas son **polígonos dibujados en el mapa** por el superadmin | §2.2, RF-01 |
| **D2** | **Multiplicador por tipo de vehículo**: moto 0,6× · auto 1,0× · microbús 1,5× | §2.1, §2.4, RF-03 |
| **D3** | Regla: dentro de la zona se cobra fijo; al salir, km × precio_km. Modelos por zona: `fijo`, `fijo_mas_km`, `por_km` | §2.1, §2.3, RF-02 |
| **D4** | Fuera de toda zona: **fijo del municipio configurable**, 1 500 CUP por defecto | §2.1, §2.3, RF-07 |
| **D5** | Comisión **15 % global configurable** | §2.1, §4.2, RF-24 |
| **D6** | Efectivo: **deuda de comisión con límite configurable** (sugerido 500 CUP); el conductor puede tomar viajes con wallet en 0; al superar el tope se bloquea | §7.10, RF-25 |

---

## 0. Resumen ejecutivo

| # | Cambio | Antes (código actual) | Después |
|---|---|---|---|
| 1 | Quién fija el precio | El cliente escribe "Tu Oferta" (`route_preview_screen.dart`, campo editable `_offerController`) | El servidor lo calcula por zona + km + tipo de vehículo. El cliente solo ve y acepta |
| 2 | Cómo se asigna el viaje | Doble negociación: conductor contraoferta (`ofertas_chofer.precio`), cliente elige entre ofertas (`driver_offers_screen.dart`) | Lista de viajes tomables; **el primero que toca se lo lleva** |
| 3 | Alcance geográfico | Círculo hardcodeado de 2,53 km (`AppConstants.cityRadiusKm`) + expansión por radio en km | **Zonas = polígonos** dibujados por el superadmin, con prioridad para resolver solapes |
| 4 | Tarifa | `vehicle_type.precio_inside_sc` (plano dentro del círculo) o `precio_km_default × km` | Zona con **modelo de tarifa** (`fijo` / `fijo_mas_km` / `por_km`) × **multiplicador** del tipo de vehículo. Santa Clara arranca en **1 500 CUP fijo** (auto) |
| 5 | Comisión | 15 % hardcodeado en `wallet_service.dart` + validación de saldo al ofertar | 15 % configurable, **cobro sin bloquear al conductor** (deuda con tope de 500 CUP) |
| 6 | Estados del viaje | 5 estados en `solicitudes_transporte` (`pendiente/aceptada/cancelada/expirada/completada`) | 11 estados con actor, motivo y timestamps |

**Resultado esperado:** un viaje se publica en < 2 s, se asigna en < 60 s (p50) y se cobra siempre el mismo precio para el mismo trayecto y tipo de vehículo. El cliente no puede equivocarse al escribir un precio; el conductor no pierde tiempo negociando.

---

## 1. Propuesta de valor y reglas del juego

### 1.1 Por qué se elimina la negociación

La doble negociación actual no es un detalle de UI: es el eje del producto y arrastra cinco problemas medibles.

**Evidencia en el código actual:**

| Síntoma | Dónde se ve hoy |
|---|---|
| El precio depende de que el cliente escriba bien un número | `route_preview_screen.dart:499-546` — `TextFormField` "Tu Oferta", `_userEditedPrice` |
| Cada conductor fija su propio precio y el cliente compara 3-5 ofertas | `driver_offers_screen.dart:308` "N Conductores encontrados" + filtros "Menor Precio / Mas Rapido" |
| La oferta mínima se calcula distinto en cada pantalla | `route_preview_screen.dart:58-59` vs `incoming_requests_screen.dart:398` |
| El conductor **no puede ofertar** si no le alcanza el saldo para la comisión | `incoming_requests_screen.dart:532-536` — "Saldo insuficiente para comisión… (15% de tu oferta)" |
| Las solicitudes viejas se muestran a todos por igual, sin zona | `driver_service.dart:297-306` — `globalVisibilityDelay` de 1 minuto |
| El precio final puede diferir del ofertado (espera, renegociación) | `precioFinal = offer.precio + extraWaitingCharge` en `transport_provider.dart:494` |

Los cinco problemas que resuelve el precio fijo:

1. **Velocidad de asignación.** Negociar cuesta minutos: publicar → esperar ofertas → comparar → aceptar → esperar. Con precio fijo, publicar → alguien toma. Objetivo: p50 ≤ 60 s.
2. **Transparencia.** El mismo recorrido, con el mismo tipo de vehículo, cuesta lo mismo para todos, siempre. Elimina la sensación de "me cobraron de más porque soy turista".
3. **Menos fricción y menos abandono.** Un campo numérico obligatorio en el paso final es un embudo que pierde gente. Se sustituye por un precio ya calculado y un solo botón.
4. **Menos cancelaciones.** La mayoría nacen de una expectativa rota: el cliente creía que pagaba X y le cobran X+Y. Con precio congelado al publicar, esa causa desaparece.
5. **Operación escalable.** La negociación no se puede auditar ni liquidar automáticamente. Un precio calculado por el servidor sí: se puede conciliar, reembolsar y reportar.

### 1.2 Reglas del juego

| # | Regla | Consecuencia |
|---|---|---|
| **R1** | **Un precio, calculado por la plataforma.** El cliente no edita el importe. El servidor es la única fuente de verdad. | Se elimina todo campo de precio en la app del cliente |
| **R2** | **La tarifa se congela al publicar.** Ni el precio ni la comisión cambian después, aunque el superadmin edite la zona. | Cada viaje guarda un snapshot de la tarifa aplicada |
| **R3** | **El conductor toma, no oferta.** Ve precio al cliente, zona, su pago neto y su %. | Se elimina `ofertas_chofer` del flujo y la pantalla de ofertas del cliente |
| **R4** | **Un viaje, un conductor, un instante.** El primero que confirma se lo lleva. | Asignación atómica en servidor |
| **R5** | **La zona del origen manda.** Su modelo de tarifa decide cómo se cobra; el destino solo decide si el viaje "sale" de la zona. | Una sola regla, explicable en una frase |
| **R6** | **Sin choferes disponibles, el viaje no se cobra y no se pierde.** Escala de visibilidad y, si nadie toma, expira sin cargo. | Nunca se retiene dinero por un viaje que no ocurrió |
| **R7** | **El conductor nunca queda bloqueado por saldo cero.** Puede operar en efectivo con deuda de comisión hasta el tope. | La oferta no se ahoga por falta de saldo |

### 1.3 Qué gana cada actor

**Cliente**

- Sabe cuánto paga **antes** de pedir, y el número no se mueve.
- Ve un desglose comprensible: zona, tarifa, recorrido, tipo de vehículo.
- Deja de decidir entre ofertas: una pantalla, un botón.
- Repite el mismo trayecto y paga lo mismo: desaparece la lotería.
- Con wallet, el dinero se retiene al publicar y se devuelve completo si el viaje no ocurre.

**Conductor**

- No pierde tiempo escribiendo ofertas que quizá nadie acepta. Toma o sigue.
- Ve **su plata** de entrada: "Te toca $1 275 (15 %)". No hay sorpresa al liquidar.
- Ya no se le bloquea por no tener saldo para la comisión (hoy es un bloqueo duro al ofertar).
- Puede elegir el viaje que le conviene (cerca, largo, zona conocida) en vez de competir a ciegas.
- El precio no depende de su habilidad de negociación: cobra igual que los demás.

**Plataforma**

- Ingreso predecible: 15 % sobre un precio determinista.
- Datos limpios: precio, zona, km, multiplicador y comisión auditables por viaje.
- Menos soporte: la mitad de las disputas actuales son "no coincidía el precio".
- Palanca de negocio real: cambiar `monto_fijo`, `precio_km`, el multiplicador de un tipo de vehículo o dibujar una zona es una edición en el superadmin, no un release de app.

### 1.4 Trade-offs honestos

| Trade-off | Costo real | Mitigación propuesta |
|---|---|---|
| **Sin negociación, el cliente no puede "subir" para conseguir viaje más rápido** | En hora pico o lluvia, un cliente dispuesto a pagar más no tiene cómo señalizarlo | Escalado de visibilidad (más zonas, más tiempo) + fase 2: recargo por demanda **configurado por la plataforma**, nunca escrito por el cliente |
| **El conductor pierde poder de fijación de precio** | Conductores que hoy "ganan negociando" pueden sentir que ganan menos y marcharse | Transparencia del neto en la lista + garantía de ingreso en piloto + comparativa pública de que el viaje medio se asigna más rápido |
| **El multiplicador castiga al microbús si el mercado lo percibe caro** | 1,5× sobre 1 500 = 2 250; puede expulsar demanda de microbús | Medir aceptación y conversión por tipo de vehículo; el multiplicador es configurable sin release |
| **Sin saldo bloqueante se asume riesgo de crédito** | El conductor en efectivo acumula deuda de comisión que puede no pagar | Tope de 500 CUP + bloqueo blando + liquidación automática al recargar (§7.10) |
| **El cliente ya no elige conductor** | Se pierde la sensación de control ("elijo al mejor valorado") | Se mantiene la valoración posterior y el detalle del conductor asignado; el reparto se hace por cercanía, no por precio |
| **Más configuración para el superadmin** | Un polígono mal dibujado deja barrios fuera o duplica cobertura | Validación geométrica + vista previa "simular precio" por punto + alerta de solape (RF-01) |
| **Precio fijo puede sentirse caro en trayectos cortos** | 1 500 CUP por 800 m es peor percibido que 900 negociado | Comunicar "tarifa mínima de zona" como valor; opcional fase 2: subzona con base menor para el casco histórico |

---

## 2. Modelo de precio

### 2.1 Fórmula

El precio se calcula **en el servidor** al publicar, con la tarifa vigente de la **zona del origen** y el **multiplicador del tipo de vehículo**.

```
zona     = polígono que contiene el ORIGEN   (puede ser ninguno)
dentro   = el DESTINO cae dentro del mismo polígono
km       = distancia de ruta (una decimal)
tipo     = tipo de vehículo elegido por el cliente → multiplicador (D2)

# --- bloque de tarifa ---
si zona existe:
    según zona.modelo_tarifa:
      'fijo'        → dentro ? monto_fijo : km × precio_km          # D3
      'fijo_mas_km' → monto_fijo + km × precio_km
      'por_km'      → km × precio_km
si no existe zona:
    subtotal = fijo_municipio                                        # D4 · 1 500 por defecto

# --- multiplicador por tipo de vehículo (D2) ---
precio = redondear_hacia_arriba(subtotal × multiplicador, 5)         # múltiplos de 5 CUP
comision = redondear(precio × comision_pct, 2)                       # D5 · 15 %
pago_conductor = precio − comision
```

**Multiplicadores (D2), configurables por tipo en `vehicle_type`:**

| Tipo | Multiplicador | Sobre 1 500 CUP |
|---|---|---|
| Moto | 0,6× | **$900** |
| Auto | 1,0× | **$1 500** |
| Microbús | 1,5× | **$2 250** |

**Ejemplos completos (auto ×1,0 salvo indicación):**

| Zona | Modelo | Recorrido | Cálculo | Total |
|---|---|---|---|---|
| Santa Clara | `fijo` 1 500 · km 250 | 3,2 km, destino dentro | dentro → 1 500 | **$1 500** |
| Santa Clara | `fijo` 1 500 · km 250 | 12,4 km, destino fuera | fuera → 12,4 × 250 | **$3 100** |
| Aeropuerto | `fijo_mas_km` 2 000 · km 250 | 4,2 km | 2 000 + 4,2 × 250 | **$3 050** |
| Centro | `por_km` · km 300 | 5,0 km | 5,0 × 300 | **$1 500** |
| Fuera de toda zona | tarifa general | lo que sea | 1 500 | **$1 500** |

**Moto (×0,6):** 1 500 → **$900** · 3 050 → **$1 830** · 3 100 → **$1 860**
**Microbús (×1,5):** 1 500 → **$2 250** · 3 050 → **$4 575** · 3 100 → **$4 650**

**Notas de implementación**

- El campo de BD existente `vehicle_type.precio_inside_sc` deja de usarse para tarifa: pasa a mandar la zona. El tipo de vehículo solo aporta el multiplicador.
- La regla del modelo `fijo` al salir es **km total × precio_km** (no solo el tramo exterior). Cobrar únicamente el tramo que queda fuera del polígono exige intersección ruta∩polígono y queda para fase 2.
- `precio_km` es obligatorio (`> 0`) en los modelos `fijo` y `por_km`: sin él, un viaje que sale de la zona cobraría $0. Validación en el superadmin + salvaguarda en el servidor.

### 2.2 Zonas: polígonos dibujados en el mapa

```
Nivel 0 · Parámetros globales (una fila)
          comision_pct = 15 %            (D5)
          fijo_municipio = 1 500         (D4)
          tope_deuda_comision = 500      (D6)
          ttl_publicada_s = 90 · ttl_escalado_s = 90
          espera_gratis_min = 5 · espera_max_min = 15
              │
Nivel 1 · Zona municipio (polígono grande)  modelo 'fijo' · monto_fijo 1 500
              │
Nivel 2 · Subzonas (polígonos dentro)       cualquier modelo + prioridad mayor
```

- El superadmin **dibuja el polígono directamente en el mapa** (tocar para añadir vértices, arrastrar, cerrar). Mínimo 3 vértices, cerrado, sin auto-intersecciones.
- Cada zona define su **modelo de tarifa** completo (`fijo` | `fijo_mas_km` | `por_km`), `monto_fijo`, `precio_km` y `prioridad`.
- **Resolución de solapes:** si un punto cae en varias zonas, gana la de **mayor prioridad**; a igual prioridad, la de **menor área**. El superadmin avisa del solape al guardar, no lo impide (los solapes con prioridad explícita son legítimos: "Aeropuerto" encima de "Santa Clara").
- `fijo_municipio` no es una zona: es el valor de respaldo cuando el origen no cae en ningún polígono activo (D4).

### 2.3 Resolución según origen y destino

| Origen | Destino | Modelo aplicado | Precio |
|---|---|---|---|
| Zona A | Dentro de A | El de A, rama "dentro" | Ej. `fijo`: `monto_fijo` |
| Zona A | Fuera de A (otra zona u fuera de todo) | El de A, rama "sale" | Ej. `fijo`: `km × precio_km`; `fijo_mas_km`: `monto_fijo + km × precio_km` |
| Zona A (`por_km`) | Cualquiera | `por_km` | `km × precio_km` |
| Fuera de toda zona | Cualquiera | Tarifa general del municipio (D4) | `fijo_municipio` |

Y siempre, al final: **× multiplicador del tipo de vehículo** (D2).

### 2.4 Desglose visible al cliente

El desglose se muestra **siempre**, aunque alguna línea valga 0. Es lo que hace creíble el precio fijo: el cliente entiende de dónde sale el número.

**Caso 1 — zona `fijo`, destino dentro (el caso Santa Clara):**

```
Precio del viaje
Zona · Santa Clara (tarifa fija)                    $1 500
Recorrido · 3,2 km                       incluido en la tarifa
Auto ×1,0                                           $1 500
─────────────────────────────────────────────────────────────
Total a pagar                                       $1 500
Precio fijo. No se negocia y no cambia al llegar.
```

**Caso 2 — zona `fijo`, el viaje sale de la zona:**

```
Precio del viaje
Zona · Santa Clara (tarifa fija)                        $1 500
  El destino sale de la zona: se cobra por km.
Recorrido · 12,4 km × $250/km                          $3 100
Auto ×1,0                                              $3 100
─────────────────────────────────────────────────────────────
Total a pagar                                          $3 100
```

**Caso 3 — zona `fijo_mas_km`:**

```
Precio del viaje
Zona · Aeropuerto (fijo + $/km)                         $2 000
Recorrido · 4,2 km × $250/km                            $1 050
Moto ×0,6                                               $1 830
─────────────────────────────────────────────────────────────
Total a pagar                                           $1 830
```

**Caso 4 — zona `por_km`:**

```
Precio del viaje
Zona · Centro (solo por km)                                $0
Recorrido · 5,0 km × $300/km                            $1 500
Auto ×1,0                                               $1 500
─────────────────────────────────────────────────────────────
Total a pagar                                           $1 500
```

**Caso 5 — fuera de toda zona (D4):**

```
Precio del viaje
Fuera de la zona de cobertura. Se aplica la tarifa
general del municipio.
Tarifa general                                          $1 500
Auto ×1,0                                               $1 500
─────────────────────────────────────────────────────────────
Total a pagar                                           $1 500
```

**Formato de importes (regla de la app):** coma decimal, miles con espacio fino, sin decimales cuando el importe es múltiplo de 5. `$1 500` · `$875,50` · `$3 050`. El sufijo `CUP` aparece solo en el desglose y en el recibo, nunca en los botones.

### 2.5 Parámetros configurables

| Parámetro | Ámbito | Default | Quién lo cambia |
|---|---|---|---|
| `modelo_tarifa` | zona | `fijo` | Superadmin |
| `monto_fijo` | zona | 1 500 (Santa Clara) | Superadmin |
| `precio_km` | zona | 250 (obligatorio si `fijo`/`por_km`) | Superadmin |
| `prioridad` | zona | 0 municipio / 10 subzona | Superadmin |
| `geometria` (polígono) | zona | dibujado en mapa | Superadmin |
| `multiplicador` | tipo de vehículo | moto 0,6 · auto 1,0 · microbús 1,5 | Superadmin |
| `comision_pct` | global | 15 % | Superadmin |
| `fijo_municipio` | global | 1 500 | Superadmin |
| `tope_deuda_comision` | global | 500 | Superadmin |
| `ttl_publicada_s` / `ttl_escalado_s` | global | 90 / 90 | Superadmin |
| `espera_gratis_min` / `espera_max_min` | global | 5 / 15 | Superadmin |

Todo parámetro que afecte dinero se edita **solo** desde `ventiq_superadmin`; nada de precios en la app cliente ni en constantes de Dart.

### 2.6 Congelamiento de tarifa

Al publicar se guarda en la solicitud: `precio_total`, `subtotal_tarifa`, `precio_km_aplicado`, `km`, `multiplicador`, `tipo_vehiculo_id`, `comision_pct`, `comision_monto`, `zona_id`, `modelo_tarifa_aplicado`, `tarifa_version_id`. Si el superadmin cambia la tarifa un segundo después, **ese viaje conserva su precio**. Sin esto no se puede liquidar ni auditar nada.

---

## 3. Flujo cliente

> En la UI se usa **"conductor"**, no "chofer": es el término que ya usan las pantallas actuales (`driver_offers_screen.dart`, `ride_confirmed_screen.dart`, `driver_home_screen.dart`). Cambiar el vocabulario ahora obligaría a tocar media app sin ganancia de producto. En documentación se usan ambos como sinónimos.

### 3.1 Mapa de pantallas

| # | Pantalla | Archivo actual | Qué cambia |
|---|---|---|---|
| 1 | Inicio / mapa | `home_map_screen.dart` | Sin cambios de concepto; el botón "¿A dónde vas?" se mantiene |
| 2 | Elegir destino | `location_search_screen.dart` | Sin cambios |
| 3 | **Confirmar viaje** | `route_preview_screen.dart` | **Se elimina el campo "Tu Oferta"**. Aparece el bloque de precio con desglose (zona / km / multiplicador / total), el selector de vehículo con su precio por tipo y el selector de pago |
| 4 | **Buscando conductor** | `driver_offers_screen.dart` → `searching_driver_screen.dart` | **Se elimina la lista de ofertas**. Nueva pantalla de espera con mapa, timer y cancelar |
| 5 | Conductor asignado | `ride_confirmed_screen.dart` | Se mantiene; estados internos se alinean a la nueva máquina |
| 6 | En camino | `ride_confirmed_screen.dart` | Igual |
| 7 | En viaje | `ride_confirmed_screen.dart` | Igual |
| 8 | Completado + pago | `ride_confirmed_screen.dart` | Igual + recibo con desglose |
| 9 | Valoración | `rating_dialog.dart` | Sin cambios |

Pantallas que **desaparecen**: `driver_offers_screen.dart` (lista de ofertas) y `driver_offer_card.dart` (tarjeta de oferta).

### 3.2 Paso a paso con copy exacto

#### Paso 1 — Origen y destino

- Pantalla: mapa con marcador de origen. Botón inferior: **"¿A dónde vas?"**
- Al elegir destino, el sistema calcula la ruta (`RoutingService`) y navega al paso 2.

#### Paso 2 — Ruta y precio (pantalla clave)

Título de la hoja inferior: **"Confirma tu viaje"**

```
[Origen]  Calle Independencia #45, Santa Clara        (editar)
   │
[Destino] Terminal de Ómnibus, Santa Clara           (editar)
   └ 3,2 km · 12 min · Zona Santa Clara
```

Selector de tipo de vehículo (horizontal, igual que hoy). **Cada tarjeta muestra su precio ya multiplicado**, porque es la decisión que toma el cliente:

| Tarjeta | Copy |
|---|---|
| Moto | `Moto` · **$900** |
| Auto | `Auto` · **$1 500** |
| Microbús | `Microbús` · **$2 250** |

Bloque de precio (no editable, sin teclado, sin `TextFormField`):

```
Precio del viaje
Zona · Santa Clara (tarifa fija)                 $1 500
Recorrido · 3,2 km                    incluido en la tarifa
Auto ×1,0                                        $1 500
──────────────────────────────────────────────────────────
Total a pagar                                    $1 500
Precio fijo. No se negocia y no cambia al llegar.
```

Botón secundario: **"¿Cómo se calcula?"** → bottom sheet de 4 líneas:
> "El precio depende de la zona donde te recogemos. Dentro de Santa Clara la tarifa es fija: $1 500 para auto. Si el destino está fuera de la zona, el recorrido se cobra por kilómetro. La moto cuesta 0,6× y el microbús 1,5× de la tarifa del auto."

Selector de pago (mismos dos botones que hoy): **[Efectivo]** · **[Wallet · Saldo: $X]**

- Si elige **Wallet** y el saldo no alcanza:
  - Banner rojo: **"Saldo insuficiente. Tienes $800 y necesitas $1 500."**
  - Botones: **"Recargar wallet"** (navega a `wallet_screen.dart`) + **"Pagar en efectivo"**

Botón principal: **"Solicitar viaje a $1 500"** ← texto obligatorio; el importe va en el botón para que no haya ambigüedad.
Mientras publica: **"Publicando…"** (spinner, botón deshabilitado).

#### Paso 3 — Buscando conductor

Pantalla nueva: mapa con origen, pulso animado y sheet inferior.

```
        ● Buscando conductor…
     Avisamos a los conductores de Santa Clara

        Quedan 1:12          [Cancelar búsqueda]
```

- Contador visible con el TTL restante (`ttl_publicada_s + ttl_escalado_s`).
- Si escala a más zonas: el subtítulo cambia a **"Buscando en zonas cercanas…"**.
- Al llegar a 0 y sin conductor → Paso 3b.

**3b — Nadie tomó el viaje**

Sheet: **"No encontramos conductor disponible"**
> "No hay conductores conectados en tu zona ahora mismo. Puedes intentarlo de nuevo en un momento."

Botones: **[Reintentar]** · **[Cambiar método de pago]** · **[Cancelar]**

- Si pagó con wallet, la retención se libera automáticamente (§7.12).
- Se registra la demanda no atendida con zona + hora (alimenta métricas, §8.3).

#### Paso 4 — Conductor asignado

Push: **"¡Conductor asignado!"** · "Carlos te recoge en 4 min · Auto Lada 2107 · P123456"

Sheet:

```
  ✔ Conductor asignado
  Carlos Pérez · ★ 4,8
  Auto Lada 2107 · P123456
  Llega en 4 min · 1,2 km

  [Llamar]   [WhatsApp]
```

Estado interno: `asignada` → `en_camino`. Cancelación permitida con las reglas de §7.5.

#### Paso 5 — En camino

Título: **"Tu conductor va en camino"** · subtítulo dinámico: **"Llega en 4 min"** → **"Llegó"**.
Contador de espera a partir de la llegada: **"Espera: $<x>/min después de 5 min"** (solo si aplica).

#### Paso 6 — En viaje

Título: **"En viaje"** · muestra destino, ETA y el total congelado: **"Total a pagar: $1 500"**.
El botón "Completar viaje" es del conductor.

#### Paso 7 — Completado

```
✔ Viaje completado

Total pagado                    $1 500
Pagado en                       Efectivo

[Valorar a Carlos]      [Volver al inicio]
```

Con wallet, el recibo añade: **"Cobrado de tu wallet"** y `Saldo restante: $X`.
Si el viaje se completó fuera del destino marcado, nota: **"El viaje se completó antes de llegar al destino. Total cobrado: $X."** (misma lógica que `ride_confirmed_screen.dart:368`).

#### Paso 8 — Valoración

Estrellas 1-5 + tags (puntualidad, trato, limpieza, conducción) + comentario opcional.
Botón: **"Enviar valoración"** · **"Ahora no"**.
La valoración es la única señal de calidad del sistema: **no** se puede valorar dos veces el mismo viaje.

### 3.3 Microcopy de errores (cliente)

| Situación | Copy |
|---|---|
| Origen fuera de toda zona | "Estás fuera de la zona de cobertura. Se aplica la tarifa general del municipio: $1 500." (aviso, **no** bloqueo — D4) |
| Destino fuera de la zona con modelo `fijo` | "El destino sale de la zona: ese recorrido se cobra por km." (aviso en el desglose) |
| Ya tienes un viaje activo | "Ya tienes un viaje en curso. Cáncelalo o termínalo antes de pedir otro." |
| Saldo insuficiente | "Saldo insuficiente. Tienes $800 y necesitas $1 500." |
| Sin conexión al publicar | "Sin conexión. Guardamos tu solicitud y la enviamos cuando vuelvas a tener señal." |
| El conductor canceló | "Carlos canceló el viaje. Estamos buscando otro conductor." |
| Sin GPS | "Activa la ubicación para que el conductor te encuentre." |
| Sin vehículos de ese tipo | "No hay motos disponibles ahora. Prueba con auto." |

---

## 4. Flujo conductor

### 4.1 Conectarse

1. Pantalla principal (`driver_home_screen.dart`). Interruptor superior: **"Desconectado"** → **"En línea"**.
2. Validaciones al pasar a "En línea" (en este orden, con copy propio):
   - Sin vehículo registrado → **"Debes registrar un vehículo desde tu perfil antes de ponerte en línea"** (ya existe, `driver_home_screen.dart:456-462`).
   - KYC no aprobado → **"Tu cuenta está en revisión. Te avisamos cuando esté aprobada."**
   - Deuda de comisión ≥ tope (500) → **"Tienes una comisión pendiente de $500. Recarga tu wallet para volver a conectarte."** + botón "Recargar".
   - Sin GPS / permiso denegado → **"Activa la ubicación para recibir viajes."**
3. Al conectarse: se publica posición en `muevete.place` (`estado = true`) y se activa **"Aceptando viajes"** (nuevo interruptor, por defecto ON).
4. Banner persistente arriba: **"En línea · 0 viajes · $<ganado hoy>"**.

**Interruptor "Aceptando viajes"** (nuevo, RF-20): permite estar en línea (visible, recibiendo) sin recibir viajes nuevos — para terminar un turno, repostar o comer. Si está apagado, la lista se congela y no se publican viajes nuevos al conductor.

### 4.2 Lista de viajes tomables

Acceso: pestaña **"Viajes"** del home (reemplaza a `incoming_requests_screen.dart` "Pendientes"). Orden: ver §5.2.

**Cada tarjeta muestra, obligatoriamente, los siete datos pedidos:**

```
┌───────────────────────────────────────────────────────┐
│  🛵 Moto requerido                     Quedan 0:47    │
│  Zona: Santa Clara · tarifa fija                      │
│                                                        │
│  ● Calle Independencia #45, Santa Clara               │
│  │                                                     │
│  ◆ Terminal de Ómnibus, Santa Clara                   │
│  3,2 km de ruta                                        │
│                                                        │
│  Cliente paga  $900                                   │
│  Te toca  $765  (15%)                                 │
│                                                        │
│  A 1,2 km de ti · Recogida en ~4 min                  │
│                                           [ Tomar ]   │
└───────────────────────────────────────────────────────┘
```

| # | Dato | Por qué está |
|---|---|---|
| 1 | **Tipo de vehículo requerido** | Filtro mental inmediato ("esto no es para mi carro"). Va en el encabezado |
| 2 | **Zona aplicada** | Explica el precio; el conductor reconoce si le conviene |
| 3 | **Origen** (dirección) | Decide si le conviene |
| 4 | **Destino** (dirección) | Decide si le conviene el trayecto |
| 5 | **Distancia de la ruta** (km) | Contexto de esfuerzo real |
| 6 | **Precio que paga el cliente** | Cumple "se cobrará tanto" |
| 7 | **"Te toca $X (15%)"** y **%** | Cumple "a ti te toca tanto %". El neto es el número grande; el % es la comisión de la plataforma |
| — | Distancia al origen + ETA de recogida | Costo real de tomarlo |
| — | Countdown | Urgencia justa, no presión falsa |
| — | Botón **"Tomar"** | Única acción |

**Regla de legibilidad del %:** el número entre paréntesis es **siempre la comisión** de la plataforma (D5), no el porcentaje que recibe el conductor. Bajo el bloque económico, microcopy fijo: *"El % es la comisión de Muevete. El resto es tuyo."*

Reglas de la lista:

- Solo se muestran viajes **visibles para ese conductor** (regla §5.1).
- Nunca se muestra el nombre, teléfono ni foto del cliente antes de tomar (privacidad; se revela al asignar).
- Los viajes ya tomados **desaparecen de la lista en ≤ 2 s** por realtime; si se toca uno que ya no está, ver §4.5.
- Pull-to-refresh disponible; refresco automático por suscripción realtime.
- Estado vacío: **"No hay viajes por ahora"** / "Te avisamos en cuanto entre uno en tu zona." + indicador de zona actual: **"Zona: Santa Clara"**.

### 4.3 Detalle

Al tocar la tarjeta (fuera del botón): sheet con mapa de la ruta, direcciones completas, zona y el bloque económico ampliado:

```
Cliente paga                             $900
Comisión Muevete (15 %)                 −$135
──────────────────────────────────────────────
Tu pago                                  $765
```

Nota: **"El precio ya está fijado. No se negocia con el cliente."**

### 4.4 Tomar viaje

Botón **"Tomar"** → confirmación (un toque accidental asigna un viaje real; el paso extra se justifica):

```
¿Tomar este viaje?

Recojo en Calle Independencia #45
Destino: Terminal de Ómnibus
Zona: Santa Clara · 3,2 km
Cliente paga $900 · Tú recibes $765

[ Cancelar ]                    [ Sí, tomar viaje ]
```

Al confirmar:

1. RPC atómica: `UPDATE … SET estado='asignada', driver_id=… WHERE id=? AND estado='publicada'`.
2. Éxito → pantalla **"Viaje asignado"** con instrucciones: **"Ve al punto de recogida"** + **[Abrir navegación]** + **[Llamar al cliente]**.
3. Fallo por carrera → **"Ese viaje ya lo tomó otro conductor"** + la lista se refresca.
4. El viaje sale de la lista de todos los demás en ≤ 2 s.

### 4.5 Qué pasa si dos tocan a la vez

- Gana **el primero cuyo `UPDATE` afecte una fila**. El segundo recibe error de negocio, no error técnico.
- Copy al perdedor: **"Ese viaje ya lo tomó otro conductor."** Sin culpar, sin explicaciones técnicas.
- No hay compensación ni "reserva" previa. El botón se deshabilita al primer toque (previene doble-tap del mismo conductor).
- Si el conductor ya tenía un viaje activo: **"Ya tienes un viaje en curso. Termínalo antes de tomar otro."**

### 4.6 Ciclo operativo

| Paso | Acción del conductor | Copy en app |
|---|---|---|
| 1 | Ya asignado | **"Ve al punto de recogida"** · ETA · [Navegación] [Llamar] |
| 2 | Llega (automático por geocerca ≤ 60 m, o botón manual) | **"Llegaste. Espera al cliente."** · inicia contador de espera tras 5 min |
| 3 | Cliente sube → **"Iniciar viaje"** | **"En viaje"** · [Navegación al destino] |
| 4 | Llega al destino → **"Completar viaje"** | **"Viaje completado · Recibes $765"** |
| 5 | Si el cliente no aparece | **"El cliente no apareció"** (ver §4.7) |
| 6 | Si no puede continuar | **"Cancelar viaje"** con motivo (ver §4.8) |

### 4.7 Cliente no aparece

Disponible solo si: estado `en_origen`, han pasado **≥ 5 min** desde la llegada y hay **≥ 1 intento de llamada** registrado.

```
¿El cliente no apareció?

Esperaste 5 min en el punto de recogida.
Llamaste 1 vez.

[ Seguir esperando ]        [ Reportar ausencia ]
```

Al reportar: viaje → `no_show`, se cobra el cargo de espera que corresponda, y el conductor queda libre de inmediato. El cliente recibe push: **"No te encontramos en el punto de recogida. El viaje se canceló."** (ver §7.6).

### 4.8 Cancelación por el conductor

Permitida solo en `asignada` o `en_camino`. Motivos obligatorios (lista cerrada):

`No puedo llegar` · `El cliente no responde` · `Problema con el vehículo` · `Dirección incorrecta` · `Emergencia` · `Otro`

Copy: **"Si cancelas después de tomar el viaje, pierdes prioridad para los próximos. ¿Seguro?"** → consecuencia real descrita antes de aceptar.

Al cancelar: el viaje se **republica automáticamente** con prioridad alta (contador `intentos_asignacion` +1). Máximo 2 republicaciones; a la tercera, se cancela con disculpa al cliente y se marca para revisión de soporte.

---

## 5. Regla de visibilidad por zona

### 5.1 Quién ve el viaje

Un viaje `publicada` es visible para un conductor **si y solo si** cumple todo:

| # | Condición | Fuente |
|---|---|---|
| 1 | Cuenta **aprobada**: KYC y revisión OK | `drivers.kyc = true`, `drivers.revisado = true` |
| 2 | **En línea** | `place.estado = true` |
| 3 | **Aceptando viajes** (interruptor ON) | campo nuevo `aceptando_viajes` |
| 4 | **Sin viaje activo** | no tiene solicitud en `asignada/en_camino/en_origen/en_curso` |
| 5 | **Dentro del polígono de la zona del origen** (o, si el origen no cae en ninguna zona, dentro de la ciudad — D4) | punto del conductor ∈ polígono resuelto |
| 6 | **Vehículo compatible** | el tipo de vehículo del conductor coincide con `solicitud.id_tipo_vehiculo` |
| 7 | **Deuda de comisión bajo el tope** (500 CUP) | `deuda_comision < tope_deuda_comision` |
| 8 | **No suspendido** | sin bloqueo disciplinario vigente |

Un conductor **con wallet en 0 puede ver y tomar viajes en efectivo** dentro del tope (D6). Hoy esto no es así (bloqueo duro en `incoming_requests_screen.dart:532`), y es una de las mejoras de conversión más importantes del rediseño.

### 5.2 Orden de la lista

1. **Menor tiempo de recogida** (distancia conductor→origen ÷ velocidad media del tipo de vehículo).
2. Desempate: **mejor valoración**.
3. Desempate: **más tiempo sin viaje** (justicia de reparto).

No se ordena por precio: todos los conductores elegibles ven el mismo importe. Esto es deliberado y debe quedar claro en la comunicación interna (evita teorías de "la app me esconde viajes").

### 5.3 Escalado temporal

```
t = 0  ──▶ PUBLICADA · visible en el polígono del origen         (90 s)
t = 90 ──▶ ESCALADA · visible en zonas adyacentes + ciudad       (90 s)
t =180 ──▶ EXPIRADA · nadie la tomó                               (fin)
```

- El escalado **no cambia el precio** (R2). Solo amplía quién la ve.
- El cliente ve el escalado como cambio de subtítulo, nunca como alarma.
- Un viaje republicado por cancelación del conductor entra directo en `ESCALADA` (no vuelve a esperar 90 s).

### 5.4 Nadie toma el viaje

| Situación | Decisión |
|---|---|
| Sin conductores elegibles al publicar | Igual se publica (puede conectarse uno en 10 s). El sheet muestra "Buscando…" sin decir "no hay nadie" |
| Expira sin toma | `expirada`. Se libera retención wallet al instante. Cliente recibe push: **"No encontramos conductor. Tu dinero sigue en tu wallet."** |
| Cliente reintenta | Nueva solicitud, nuevo precio (tarifa vigente en ese momento), mismo contador de intentos |
| 3 intentos fallidos en 10 min | Se ofrece **"Avisarme cuando haya conductores"** (notificación push al volver a haber oferta en la zona) |

---

## 6. Estados y máquina de estados

### 6.1 Tabla de estados

| # | Código | Etiqueta UI (cliente) | Etiqueta UI (conductor) | Quién lo cambia | Siguiente(s) |
|---|---|---|---|---|---|
| 1 | `publicada` | "Buscando conductor…" | "Disponible" | Sistema (al confirmar el cliente) | `asignada`, `expirada`, `cancelada_cliente` |
| 2 | `asignada` | "Conductor asignado" | "Viaje asignado · ve a recoger" | Conductor (tomar) | `en_camino`, `cancelada_conductor`, `cancelada_cliente` |
| 3 | `en_camino` | "Tu conductor va en camino" | "En camino al cliente" | Conductor (inicia tras tomar) | `en_origen`, `cancelada_conductor`, `cancelada_cliente` |
| 4 | `en_origen` | "Tu conductor llegó" | "Esperando al cliente" | Conductor (geocerca ≤ 60 m o botón) | `en_curso`, `no_show`, `cancelada_cliente` |
| 5 | `en_curso` | "En viaje" | "En viaje" | Conductor ("Iniciar viaje") | `completada`, `cancelada_conductor` |
| 6 | `completada` | "Viaje completado" | "Viaje completado · cobras $M" | Conductor | `disputa` (ventana 72 h) |
| 7 | `cancelada_cliente` | "Cancelado por ti" | "El cliente canceló" | Cliente | — |
| 8 | `cancelada_conductor` | "El conductor canceló" | "Cancelaste el viaje" | Conductor | `publicada` (republicación, máx. 2) |
| 9 | `expirada` | "No encontramos conductor" | — | Sistema (TTL) | — |
| 10 | `no_show` | "No te encontramos" | "Cliente ausente" | Conductor | — |
| 11 | `disputa` | "En revisión" | "En revisión" | Cliente / conductor / soporte | `completada`, `cancelada_*` (con reembolso) |

> No existe un estado "fuera de cobertura": con D4, un origen fuera de toda zona **se cotiza con la tarifa general** y se publica igual. La falta de cobertura es un atributo del viaje (`fuera_de_zona = true`), no un estado.

### 6.2 Transiciones prohibidas

| Intento | Resultado |
|---|---|
| `publicada` → `en_curso` (saltarse la asignación) | Rechazado |
| `asignada` → `completada` (sin pasar por origen/viaje) | Rechazado, salvo completado forzado por soporte |
| `completada` → `publicada` | Rechazado |
| Cualquier estado final → otro | Rechazado (inmutables) |
| `cancelada_conductor` → `publicada` si `intentos_asignacion ≥ 2` | Rechazado → `cancelada_conductor` definitivo |
| Un conductor distinto intenta tomar un viaje `asignada` | Rechazado (RF-15) |

### 6.3 Timestamps obligatorios

Cada solicitud guarda, además del estado:

`publicada_at` · `asignada_at` · `llego_at` · `inicio_at` · `completada_at` · `cancelada_at` · `cancelada_por` (`cliente` | `conductor` | `sistema` | `soporte`) · `motivo_cancelacion` · `intentos_asignacion` · `zona_id` · `modelo_tarifa_aplicado` · `multiplicador` · `fuera_de_zona` · `tarifa_version_id`

Sin esto no hay métricas de duración ni auditoría de disputas. Es más barato que una tabla de eventos y cubre el 100 % de los KPIs de la sección 8.

---

## 7. Casos borde

| # | Caso | Decisión propuesta | Copy / dato |
|---|---|---|---|
| **7.1** | **Sin conductores en la zona** | Se publica igual y escala la visibilidad. Si expira: `expirada`, sin cargo. Nunca se avisa de que "no hay nadie" antes de intentarlo | "No encontramos conductor disponible" |
| **7.2** | **Origen fuera de toda zona** | **Se cotiza con `fijo_municipio` (D4) y se publica normalmente.** Se avisa al cliente y se marca `fuera_de_zona = true` para análisis de expansión | "Estás fuera de la zona de cobertura. Se aplica la tarifa general del municipio: $1 500." |
| **7.3** | **Destino fuera de la zona del origen** | Aplica la rama "sale" del modelo de la zona del origen (D3): `fijo` → km × precio_km; `fijo_mas_km` → fijo + km × precio_km. El recargo se muestra como línea propia | "El destino sale de la zona: se cobra por km" |
| **7.4** | **Viaje inter-zona** (origen zona A, destino zona B) | Manda A; para A el destino está "fuera", así que aplica su rama "sale". B no interviene en el precio | Ver §2.3 |
| **7.5** | **Cancelación del cliente** | Gratis en `publicada`, `asignada`, `en_camino` y en los primeros **2 min** desde `asignada`. Después: **cargo = 20 % del `monto_fijo` de la zona aplicada** (≈ $300 en Santa Clara), **solo si pagó con wallet**. En efectivo no se cobra: se registra en el historial del cliente | "Si cancelas ahora se te cobrará $300 de compensación al conductor. ¿Continuar?" |
| **7.6** | **Cliente no aparece (`no_show`)** | Conductor espera 5 min gratis + hasta 15 min con cargo de espera. Requiere ≥ 1 llamada registrada. 2 `no_show` en 30 días → el cliente debe pagar con wallet para publicar | "No te encontramos en el punto de recogida" |
| **7.7** | **Conductor no llega** | Si no marca llegada en **15 min** desde `asignada` → liberación automática + republicación + incidente. El cliente puede cancelar sin cargo desde el minuto 5 | "Buscando otro conductor" |
| **7.8** | **Disputa de cobro** | Ventana 72 h desde `completada`. Estado `disputa` congela la liquidación de la comisión de ese viaje. Resolución manual de soporte: reembolso total, parcial o rechazo, con nota | "Estamos revisando este cobro. Te respondemos en 48 h" |
| **7.9** | **Caída de red** | Publicar y **tomar** requieren conexión (decisiones irreversibles de asignación/dinero). Navegación, llegada y completar se **encolan offline** con clave de idempotencia y se reconcilian al reconectar. Cancelar sí se permite offline | "Sin conexión. Guardamos tu solicitud y la enviamos cuando vuelva la señal" |
| **7.10** | **Viaje en efectivo con wallet en 0** (D6) | **No se bloquea tomar el viaje.** Al completar, la comisión se descuenta del wallet; si no alcanza, se genera **deuda de comisión**. El conductor opera normalmente hasta el tope de 500 CUP; al alcanzarlo se bloquea la conexión con CTA de recarga. Con wallet **no hay deuda posible** (se cobra del neto) | "Tienes $225 de comisión pendiente. Se descontará de tu próxima recarga" |
| **7.11** | **Calibración del tope de deuda** | Con tope 500 y tarifa 1 500 (comisión $225), el auto acumula 2 viajes y se bloquea en el tercero; la moto (comisión $135) aguanta 3. Es un tope **de arranque**: subirlo a 1 000-1 500 reduce bloqueos pero aumenta el riesgo de crédito | Revisar semanalmente el % de conductores bloqueados (KPI 15) |
| **7.12** | **Liquidación de la comisión** | Efectivo: el cliente paga el total al conductor; el conductor debe la comisión. Wallet: se descuentan los retenidos al cliente y se acredita el neto al conductor. La comisión se registra siempre en `transacciones_wallet` con `viaje_id` para conciliación | — |
| **7.13** | **Reembolsos** | Wallet: retención liberada si el viaje no llega a `en_curso`. Si ya estaba `en_curso` y cancela el conductor → reembolso total. Si cancela el cliente en `en_curso` → total menos cargo de cancelación. Efectivo: no hay reembolso posible (no se cobró aún); se ajusta la deuda de comisión a 0 si el viaje no se completó | "Te devolvimos $1 500 a tu wallet" |
| **7.14** | **Conductor completa antes de llegar** | Permitido si está a ≤ 200 m del destino. Si no: confirmación extra **"Faltan $dist para llegar. ¿Completar de todas formas?"** (comportamiento actual de `ride_confirmed_screen.dart:368-390`) | — |
| **7.15** | **El tipo de vehículo elegido no tiene conductores** | Se avisa al elegir en el paso 2 y se sugiere el tipo con oferta. **No** se cambia el tipo silenciosamente: cambiaría el precio | "No hay motos disponibles ahora. Prueba con auto ($1 500)." |
| **7.16** | **Dos viajes al mismo conductor** | Imposible por la condición 4 de §5.1 + validación en la RPC de toma | "Ya tienes un viaje en curso" |
| **7.17** | **El cliente cierra la app durante la búsqueda** | La solicitud sigue viva hasta expirar. Push al asignarse. Al reabrir, la app restaura el viaje activo (`restoreActiveRequest`, ya existe) | — |
| **7.18** | **El conductor pierde señal a mitad de viaje** | El viaje no se cancela por el sistema; queda `en_curso` con el último punto conocido. Si pasan > 30 min sin actualización de posición, se marca para revisión de soporte | — |
| **7.19** | **Polígono mal dibujado** (hueco o solape sin prioridad) | El superadmin recibe alerta al guardar. Los viajes afectados se detectan por el KPI "viajes con tarifa general" y por reclamos de conductores que no ven viajes de su barrio | Vista de salud de zonas (§8.5) |

---

## 8. Métricas

### 8.1 North star

**Viajes completados por hora-vehículo en línea** (viajes / suma de minutos en línea).

Es la única métrica que resume si el modelo funciona: si el precio fijo asusta al cliente o al conductor, este número cae aunque las demás métricas se vean bien.

### 8.2 Embudo del cliente (donde se gana o se pierde el rediseño)

```
abre app  →  elige destino  →  ve el precio  →  solicita viaje  →  se asigna  →  se completa
                                                     ▲
                                     paso crítico: caída aquí = el precio fijo
                                     se percibe caro o la pantalla confunde
```

La métrica que valida el rediseño es **conversión "ve el precio" → "solicita"**.

### 8.3 Tabla de KPIs

| # | KPI | Fórmula | Fuente | Objetivo piloto |
|---|---|---|---|---|
| 1 | Viajes completados / hora-vehículo | `completada / horas_online` | timestamps + `place` | ↑ 20 % vs. hoy |
| 2 | Tiempo a asignación | `p50/asignada_at − publicada_at` | timestamps | p50 ≤ 60 s, p90 ≤ 150 s |
| 3 | Tasa de expiración | `expirada / publicada` | estados | < 5 % |
| 4 | Tasa de aceptación | `asignada / publicada` | estados | > 90 % |
| 5 | Conversión precio→solicitud | `publicada / vio_precio` | evento de UI | ≥ 65 % |
| 6 | Cancelación cliente | `cancelada_cliente / asignada` | estados | < 8 % |
| 7 | Cancelación conductor | `cancelada_conductor / asignada` | estados | < 5 % |
| 8 | `no_show` | `no_show / en_origen` | estados | < 3 % |
| 9 | ETA real vs. prometido | `llego_at − asignada_at` vs. ETA | timestamps | desvío < 2 min p50 |
| 10 | Precio medio / viaje | `avg(precio_total)` | solicitud | ≈ 1 500 (auto) |
| 11 | Precio medio por tipo de vehículo | `avg(precio_total) group by tipo` | solicitud | moto 900 · auto 1 500 · micro 2 250 |
| 12 | Mix por tipo de vehículo | `count group by tipo` | solicitud | medir |
| 13 | Km medio / viaje | `avg(km)` | solicitud | medir, no objetivo |
| 14 | Take rate efectivo | `sum(comision) / sum(precio_total)` | solicitud | 15 % ± 0,5 |
| 15 | Conductores bloqueados por deuda | `deuda ≥ tope / online` | wallet | < 10 % |
| 16 | Deuda de comisión total | `sum(deuda)` | `wallet_drivers` | < 1 día de comisión |
| 17 | % viajes fuera de zona (tarifa general) | `count(fuera_de_zona) / publicada` | solicitud | medir (dibujo de polígonos) |
| 18 | % wallet vs efectivo | `count(metodo_pago)` | solicitud | medir |
| 19 | Demanda no atendida | `expirada` por zona/hora | solicitud | < 5 % |
| 20 | Disputas por 100 viajes | `disputa / completada × 100` | estados | < 2 |
| 21 | Tiempo de resolución de disputa | mediana `resuelta_at − disputa_at` | soporte | < 48 h |
| 22 | Retención de conductores | % activos semana N que siguen en N+1 | `place` + viajes | > 70 % |
| 23 | Valoración media | `avg(estrellas)` | `valoraciones_viajes` | > 4,5 |
| 24 | Aceptación por tramo de km y tipo | `asignada / publicada` por bucket 0-2, 2-5, 5-10, >10 | solicitud | plana |

Los KPIs **17, 24 y 11** son los termómetros de las decisiones nuevas:
- **24** dice si la rama "sale de la zona" (km × precio_km) es aceptable o si los conductores rechazan los viajes largos.
- **17** dice si los polígonos cubren la ciudad real (un % alto = zona mal dibujada o barrios fuera).
- **11** dice si el multiplicador de microbús (1,5×) expulsa demanda.

### 8.4 Cómo instrumentarlo

1. **Timestamps de estado** (§6.3) → KPIs 2, 4, 5, 6, 7, 8, 9, 19, 20.
2. **Snapshot de tarifa en la solicitud** → KPIs 10, 11, 13, 14, 17.
3. **`transacciones_wallet` con `viaje_id`** → conciliación de comisión y deuda (15, 16).
4. **Vista materializada** `muevete.v_kpi_diario` (zona, tipo de vehículo, fecha, métricas) + pantalla en `ventiq_superadmin/lib/screens/muevete/muevete_dashboard_screen.dart`.
5. **Evento de UI "vio_precio"** (fila liviana o analytics local con flush) → KPI 5.
6. **Vista de salud de zonas**: viajes/día, % fuera de zona, expiraciones y conductores elegibles por polígono → detecta polígonos mal dibujados.

### 8.5 Alarmas (revisión diaria del piloto)

| Señal | Umbral | Acción |
|---|---|---|
| Tasa de expiración | > 15 % en una zona/día | Revisar oferta de conductores y tarifa de esa zona |
| Aceptación en tramos > 10 km | < 60 % | Bajar `precio_km` de la zona o cambiar el modelo a `fijo_mas_km` |
| % viajes fuera de zona | > 25 % | Revisar el polígono municipal: probablemente le falta área |
| Conductores bloqueados por deuda | > 25 % | Subir el tope (500 → 1 000) o revisar la mecánica de cobro |
| Disputas | > 5 por 100 viajes | Auditar precios y comportamiento de conductores |
| Conversión precio→solicitud | < 40 % | El precio se percibe caro: revisar nivel de tarifa o el multiplicador del tipo |
| Mix de tipo de vehículo | microbús < 5 % | El 1,5× puede ser excesivo: recalibrar |

---

## 9. Requisitos funcionales

> Formato listo para historia de usuario: cada RF tiene actor, regla y Gherkin. La numeración es estable; **(N)** = nuevo respecto al sistema actual.

### Grupo A · Configuración (superadmin)

#### RF-01 (N) · Zonas dibujadas como polígonos
El superadmin dibuja el polígono en el mapa, define prioridad y datos de tarifa, y el sistema valida la geometría.

```gherkin
Escenario: dibujar una zona
  Dado un superadmin en el editor de zonas
  Cuando marca 5 vértices en el mapa y cierra el polígono
  Entonces la zona queda guardada con su geometría
  Y el sistema valida que el polígono esté cerrado y sin auto-intersecciones

Escenario: solape entre zonas
  Dado que existe la zona "Santa Clara" con prioridad 0
  Cuando el superadmin crea "Aeropuerto" con prioridad 10 encima
  Entonces el sistema avisa del solape y lo permite
  Y un punto dentro del aeropuerto resuelve la zona "Aeropuerto"

Escenario: desactivar una zona
  Dada una zona activa con viajes publicados
  Cuando el superadmin la desactiva
  Entonces no se cotizan viajes nuevos con esa zona
  Y los viajes publicados conservan su precio congelado
```

#### RF-02 (N) · Modelo de tarifa por zona
Cada zona declara `fijo`, `fijo_mas_km` o `por_km`, con los campos obligatorios de cada modelo.

```gherkin
Escenario: zona con tarifa fija
  Dado un superadmin que crea una zona con modelo "fijo", monto fijo 1 500 y $/km 250
  Entonces el sistema exige que el $/km sea mayor que 0
  Y guarda la zona como activa

Escenario: zona solo por km
  Dado un superadmin que elige el modelo "por_km"
  Cuando no define monto fijo
  Entonces la zona se guarda con monto fijo 0 y $/km obligatorio

Escenario: falta el $/km
  Dado un superadmin que elige el modelo "fijo" sin $/km
  Cuando intenta guardar
  Entonces ve "El $/km es obligatorio: se usa cuando el viaje sale de la zona"
```

#### RF-03 (N) · Multiplicador por tipo de vehículo
Cada tipo de vehículo tiene un multiplicador configurable sobre la tarifa de la zona.

```gherkin
Escenario: precio de moto
  Dada una zona con tarifa fija de 1 500 y un multiplicador de moto de 0,6
  Cuando el cliente elige moto
  Entonces el total mostrado es $900

Escenario: cambio del multiplicador
  Dado un superadmin que cambia el multiplicador de moto de 0,6 a 0,7
  Entonces los viajes publicados a partir de ese momento usan 0,7
  Y los viajes ya publicados conservan 0,6
```

#### RF-04 (N) · Parámetros globales
El superadmin edita `comision_pct`, `fijo_municipio`, `tope_deuda_comision`, TTLs y tiempos de espera.

```gherkin
Escenario: cambiar la comisión
  Dado que la comisión global es 15 %
  Cuando el superadmin la cambia a 18 %
  Entonces los viajes publicados a partir de ese momento usan 18 %
  Y los viajes ya publicados conservan 15 %
```

#### RF-05 (N) · Versionado de tarifas
Cada cambio de tarifa o de multiplicador crea una versión inmutable; cada viaje apunta a la versión aplicada.

```gherkin
Escenario: auditar el precio de un viaje pasado
  Dado un viaje completado hace 3 días
  Cuando soporte consulta el viaje
  Entonces ve la tarifa exacta aplicada (modelo, monto fijo, $/km, multiplicador, comisión)
```

### Grupo B · Precio

#### RF-06 · Cálculo del precio en el servidor
El importe lo calcula la base de datos al publicar; el cliente no envía ni puede alterar el precio.

```gherkin
Escenario: el cliente no puede fijar el precio
  Dado un cliente en la pantalla de confirmación
  Cuando solicita el viaje
  Entonces la solicitud guarda el precio calculado por el servidor
  Y no existe ningún campo editable de importe en la app del cliente

Escenario: manipulación del cliente
  Dado un cliente que intenta enviar un precio propio por la API
  Cuando el servidor recibe la solicitud
  Entonces ignora el importe enviado y calcula el precio con la tarifa vigente
```

#### RF-07 (N) · Cálculo según modelo y salida de zona
Se aplica el modelo de la zona del origen; si el destino sale del polígono, se aplica la rama por km.

```gherkin
Escenario: viaje contenido en la zona fija
  Dado un origen y un destino dentro del polígono "Santa Clara" con modelo "fijo" de 1 500
  Cuando se calcula el precio de un auto
  Entonces el total es $1 500 sin importar la distancia

Escenario: viaje que sale de la zona fija
  Dado el mismo origen y un destino fuera del polígono
  Y un $/km de 250 para esa zona
  Cuando se calcula el precio de un auto para 12,4 km
  Entonces el total es $3 100
  Y el cliente ve la línea "El destino sale de la zona: se cobra por km"

Escenario: zona fijo + km
  Dada una zona con modelo "fijo_mas_km", monto fijo 2 000 y $/km 250
  Cuando se calcula un viaje de 4,2 km
  Entonces el total de un auto es $3 050
```

#### RF-08 · Desglose visible al cliente
Se muestra zona, tarifa, km, multiplicador y total antes de solicitar.

```gherkin
Escenario: ver el desglose de un viaje dentro de Santa Clara
  Dado un recorrido de 3,2 km con origen y destino en "Santa Clara"
  Cuando el cliente ve la pantalla de confirmación
  Entonces ve "Zona · Santa Clara (tarifa fija) $1 500"
  Y ve "Recorrido · 3,2 km incluido en la tarifa"
  Y ve "Auto ×1,0 $1 500"
  Y ve "Total a pagar $1 500"
  Y no ve ningún campo editable

Escenario: el botón lleva el importe
  Dado un total de $1 500
  Entonces el botón principal dice "Solicitar viaje a $1 500"

Escenario: precio por tipo de vehículo
  Dado un mismo trayecto
  Cuando el cliente compara los tipos de vehículo
  Entonces ve Moto $900, Auto $1 500 y Microbús $2 250
```

#### RF-09 (N) · Origen fuera de toda zona
Con D4, se cotiza con la tarifa general del municipio y se publica; no se bloquea.

```gherkin
Escenario: origen fuera de los polígonos
  Dado un origen que no cae en ninguna zona activa
  Y un fijo de municipio de 1 500
  Cuando el cliente ve el precio de un auto
  Entonces ve "Tarifa general $1 500"
  Y ve el aviso "Estás fuera de la zona de cobertura"
  Y puede solicitar el viaje con normalidad

Escenario: registrar la demanda fuera de zona
  Dado un viaje publicado con fuera_de_zona = true
  Entonces el viaje se contabiliza en el KPI de viajes con tarifa general
```

### Grupo C · Cliente

#### RF-10 · Confirmación sin edición de precio
La pantalla de confirmación muestra el precio y no permite modificarlo.

```gherkin
Escenario: no hay campo de oferta
  Dado un cliente en la pantalla de confirmación
  Entonces no existe campo "Tu Oferta" ni teclado numérico de importe
  Y el botón dice "Solicitar viaje a $<total>"
```

#### RF-11 · Publicación idempotente
Un doble toque publica un solo viaje.

```gherkin
Escenario: doble toque en solicitar
  Dado un cliente que toca "Solicitar viaje" dos veces en menos de 1 s
  Cuando se procesan las dos peticiones
  Entonces se crea una sola solicitud
  Y el cliente ve una sola pantalla de "Buscando conductor"
```

#### RF-12 · Pago efectivo o wallet con retención
Con wallet, el importe se retiene al publicar y se libera si el viaje no ocurre.

```gherkin
Escenario: saldo insuficiente
  Dado un cliente con $800 en wallet y un viaje de $1 500
  Cuando elige pagar con wallet
  Entonces ve "Saldo insuficiente. Tienes $800 y necesitas $1 500."
  Y se le ofrece recargar o pagar en efectivo

Escenario: retención liberada al expirar
  Dado un cliente que pagó con wallet y su viaje expiró sin conductor
  Entonces el importe retenido vuelve íntegro a su wallet
  Y no se registra ninguna comisión
```

#### RF-13 · Seguimiento y valoración
El cliente ve el estado del viaje y valora al terminar.

```gherkin
Escenario: recorrido completo del estado
  Dado un viaje asignado
  Cuando el conductor llega, inicia y completa
  Entonces el cliente ve en orden "Conductor asignado", "En camino", "En viaje" y "Viaje completado"
  Y al terminar puede valorar al conductor una sola vez
```

#### RF-14 · Cancelación del cliente
Reglas de gratuidad y cargo según estado y tiempo.

```gherkin
Escenario: cancelar mientras se busca conductor
  Dado un viaje en estado "publicada"
  Cuando el cliente cancela
  Entonces no se le cobra nada
  Y si pagó con wallet, la retención se libera

Escenario: cancelar después del margen
  Dado un viaje "en_camino" asignado hace 4 minutos y pagado con wallet
  Cuando el cliente cancela
  Entonces se le advierte el cargo de $300 antes de confirmar

Escenario: cancelar en efectivo
  Dado un viaje en efectivo asignado hace 4 minutos
  Cuando el cliente cancela
  Entonces no se le cobra nada
  Y se registra la cancelación en su historial
```

### Grupo D · Conductor

#### RF-15 · Tarjeta de viaje tomable
El conductor ve los siete datos obligatorios y su pago neto exacto con el %.

```gherkin
Escenario: tarjeta de viaje disponible
  Dado un conductor en línea dentro de la zona del origen con vehículo "Moto"
  Cuando recibe un viaje publicado de $900 con comisión 15 %
  Entonces la tarjeta muestra el tipo "Moto requerido"
  Y muestra la zona aplicada "Santa Clara · tarifa fija"
  Y muestra origen y destino
  Y muestra la distancia de la ruta
  Y muestra "Cliente paga $900"
  Y muestra "Te toca $765 (15%)"

Escenario: no se muestra el contacto del cliente
  Dado un viaje aún no tomado
  Entonces la tarjeta no muestra teléfono ni nombre completo del cliente
```

#### RF-16 · Tomar viaje (el primero gana)
Asignación atómica en servidor.

```gherkin
Escenario: dos conductores tocan a la vez
  Dado un viaje publicado
  Cuando dos conductores confirman "Tomar viaje" simultáneamente
  Entonces exactamente uno recibe el viaje
  Y el otro ve "Ese viaje ya lo tomó otro conductor"
  Y la lista de ese otro se actualiza sin el viaje

Escenario: conductor con viaje activo
  Dado un conductor con un viaje en curso
  Cuando intenta tomar otro
  Entonces ve "Ya tienes un viaje en curso. Termínalo antes de tomar otro."
```

#### RF-17 · Detalle y confirmación de toma
Un paso de confirmación evita asignaciones accidentales.

```gherkin
Escenario: confirmar antes de asignar
  Cuando el conductor toca "Tomar" en una tarjeta
  Entonces ve el resumen (recogida, destino, zona, precio al cliente, su pago)
  Y el viaje solo se asigna si confirma "Sí, tomar viaje"
```

#### RF-18 · Ciclo operativo del conductor
Llegada, inicio y completado, con geocerca y confirmaciones.

```gherkin
Escenario: marcar llegada por geocerca
  Dado un conductor a 40 m del punto de recogida
  Entonces el sistema marca el viaje como "en_origen" automáticamente

Escenario: completar lejos del destino
  Dado un conductor a 900 m del destino
  Cuando toca "Completar viaje"
  Entonces ve una confirmación adicional indicando la distancia restante
```

#### RF-19 (N) · Cliente ausente
Reporte de `no_show` con condiciones verificables.

```gherkin
Escenario: reportar ausencia
  Dado un conductor en "en_origen" hace 5 minutos con al menos una llamada registrada
  Cuando toca "El cliente no apareció"
  Entonces el viaje pasa a "no_show"
  Y el conductor queda libre de inmediato
  Y el cliente recibe una notificación

Escenario: reportar antes de tiempo
  Dado un conductor en "en_origen" hace 2 minutos
  Entonces el botón "El cliente no apareció" no está disponible
```

#### RF-20 (N) · Cancelación del conductor
Motivo obligatorio y republicación automática.

```gherkin
Escenario: cancelar después de tomar
  Dado un conductor con un viaje "asignada"
  Cuando cancela indicando el motivo "Problema con el vehículo"
  Entonces el viaje se republica con prioridad alta
  Y se incrementa el contador de intentos de asignación

Escenario: límite de republicaciones
  Dado un viaje republicado 2 veces por cancelaciones de conductores
  Cuando el tercer conductor cancela
  Entonces el viaje se cancela definitivamente
  Y se marca para revisión de soporte
```

#### RF-21 (N) · Modo "Aceptando viajes"
El conductor puede estar en línea sin recibir viajes nuevos.

```gherkin
Escenario: pausar la recepción
  Dado un conductor en línea con "Aceptando viajes" activo
  Cuando lo desactiva
  Entonces no recibe viajes nuevos
  Y su sesión y posición siguen activas
  Y los viajes que ya tiene asignados no se ven afectados
```

### Grupo E · Visibilidad

#### RF-22 (N) · Regla de elegibilidad
Solo ve el viaje quien cumple las 8 condiciones de §5.1.

```gherkin
Escenario: conductor fuera de la zona
  Dado un viaje publicado con origen dentro del polígono "Santa Clara"
  Y un conductor en línea fuera de ese polígono
  Entonces ese conductor no ve el viaje mientras no se escale la visibilidad

Escenario: conductor sin KYC
  Dado un conductor en línea con kyc = false
  Entonces no ve viajes publicados

Escenario: conductor con vehículo incompatible
  Dado un viaje publicado para "Moto"
  Y un conductor registrado con "Auto"
  Entonces ese conductor no ve el viaje

Escenario: conductor con deuda sobre el tope
  Dado un conductor con deuda de comisión de 600 y tope 500
  Entonces no ve viajes publicados
```

#### RF-23 (N) · Escalado y expiración
TTL en zona, escalado a zonas adyacentes y expiración sin cargo.

```gherkin
Escenario: escalar la visibilidad
  Dado un viaje publicado hace 91 segundos sin ser tomado
  Entonces se muestra también a los conductores de zonas adyacentes y de la ciudad
  Y el precio no cambia

Escenario: expirar sin conductor
  Dado un viaje publicado hace 181 segundos sin ser tomado
  Entonces pasa a "expirada"
  Y se libera cualquier retención de wallet
  Y el cliente ve "No encontramos conductor disponible"
```

### Grupo F · Dinero

#### RF-24 (N) · Comisión y liquidación
Comisión configurable (D5), liquidada según método de pago.

```gherkin
Escenario: viaje pagado en efectivo
  Dado un viaje de $1 500 en efectivo con comisión 15 %
  Cuando se completa
  Entonces el conductor recibe $1 500 en mano del cliente
  Y se le descuentan $225 de su wallet
  Y si su wallet no alcanza, se registra deuda de comisión de $225

Escenario: viaje pagado con wallet
  Dado un viaje de $1 500 pagado con wallet
  Cuando se completa
  Entonces se cobran $1 500 al cliente (ya retenidos)
  Y se acreditan $1 275 al conductor
  Y la comisión de $225 queda registrada

Escenario: viaje de moto
  Dado un viaje de $900 en efectivo con comisión 15 %
  Cuando se completa
  Entonces la comisión es $135 y el conductor recibe $765
```

#### RF-25 (N) · Deuda de comisión y tope (D6)
El conductor con wallet en 0 opera en efectivo hasta el tope.

```gherkin
Escenario: tomar viaje con wallet en cero
  Dado un conductor con saldo 0 y deuda 0
  Cuando toma un viaje en efectivo
  Entonces la toma se permite
  Y al completar se registra deuda de comisión

Escenario: bloqueo al superar el tope
  Dado un conductor con deuda de comisión de $600 y un tope de $500
  Cuando intenta ponerse en línea
  Entonces ve "Tienes una comisión pendiente de $600. Recarga tu wallet para volver a conectarte."
  Y se le ofrece recargar

Escenario: liquidación al recargar
  Dado un conductor con deuda de comisión de $500
  Cuando recarga $2 000
  Entonces la deuda se descuenta automáticamente
  Y su saldo disponible queda en $1 500
  Y puede volver a conectarse
```

#### RF-26 (N) · Reembolsos y disputas
Ventana de disputa y resolución con efecto en wallet.

```gherkin
Escenario: abrir una disputa
  Dado un viaje completado hace 2 horas
  Cuando el cliente reporta un cobro incorrecto
  Entonces el viaje pasa a "disputa"
  Y la liquidación de la comisión de ese viaje queda congelada

Escenario: resolver con reembolso
  Dado un viaje en disputa con pago por wallet
  Cuando soporte aprueba el reembolso total
  Entonces el cliente recibe el importe en su wallet
  Y el conductor no recibe pago ni se le cobra comisión por ese viaje
```

### Grupo G · Observabilidad

#### RF-27 (N) · Timestamps y métricas
Cada transición de estado registra su timestamp y actor; cada viaje guarda su snapshot de tarifa.

```gherkin
Escenario: medir el tiempo de asignación
  Dado un viaje publicado y luego asignado
  Cuando se consultan sus timestamps
  Entonces existen publicada_at y asignada_at
  Y la diferencia alimenta el KPI de tiempo a asignación

Escenario: medir viajes fuera de zona
  Dado un viaje publicado con fuera_de_zona = true
  Entonces el KPI de viajes con tarifa general lo incluye
```

#### RF-28 · Notificaciones del ciclo
Push en los hitos que el usuario no está mirando.

```gherkin
Escenario: aviso de asignación al cliente
  Dado un cliente con la app en segundo plano buscando conductor
  Cuando un conductor toma el viaje
  Entonces recibe una notificación con nombre, vehículo y ETA
```

---

## 10. Fuera de alcance

Se declara explícitamente para evitar falsas expectativas en el resto del plan:

1. **Negociación, subasta o propina.** No hay ninguna vía para que cliente o conductor alteren el importe. La propina queda fuera del MVP (ni botón ni campo).
2. **Precio dinámico por demanda (surge).** El precio no sube por lluvia, hora pico o falta de oferta. Solo cambia si el superadmin cambia la tarifa de la zona o el multiplicador del tipo.
3. **Cobro solo del tramo que sale de la zona.** El MVP cobra `km total × precio_km` cuando el viaje sale del polígono. Descontar el tramo interior exige intersección ruta∩polígono y queda para fase 2.
4. **Múltiples paradas con tarifa por parada.** El modelo `stop_model.dart` existe, pero el precio del MVP se calcula origen→destino. Las paradas, si se usan, no suman importe.
5. **Módulo de carga / fletes (`cargas`, carriers, dispatchers).** Tiene su propia negociación (`oferta_carga_service.dart`) y su propia economía. Este rediseño es solo taxi de pasajeros.
6. **Nuevos métodos de pago.** Solo efectivo y wallet. No se agrega transferencia, QR de pago ni tarjeta.
7. **Revisión del 11 % de recarga de wallet.** Es una fricción conocida y relevante para el taxi, pero es una decisión económica aparte (ver doc 03), no de este rediseño.
8. **Reparto automático / despacho manual desde superadmin.** No hay asignación forzada ni reasignación manual en el MVP; solo el registro para soporte.
9. **Incentivos, bonos, garantía de ingreso y planes de suscripción del conductor.** El modelo `planes` existe pero no se conecta a este flujo.
10. **Panel de disputas automatizado.** La resolución es manual por soporte desde el superadmin.
11. **Llamadas o chat dentro de la app.** Se mantiene `tel:` y WhatsApp, como hoy.
12. **Mapa offline / MBTiles para zonas.** No se toca la infraestructura de mapas.
13. **Facturación fiscal, IVA o reportes contables.** Fuera del alcance del módulo.
14. **Recargo por equipaje, mascotas, sillas infantiles o accesibilidad.** Sin cargos adicionales en el MVP.

---

## Supuestos

1. **Operación actual en Santa Clara.** El negocio opera hoy en un círculo de 2,53 km alrededor de 22.40689, -79.96450 (`AppConstants`); ese círculo se sustituye por el polígono municipal que dibuje el superadmin.
2. **Moneda única: CUP.** Todos los importes se muestran con `$` y se liquidan en CUP. No hay multimoneda en este módulo.
3. **El superadmin define las zonas.** Sin al menos un polígono activo, todo viaje cae en la tarifa general (`fijo_municipio`). La cobertura real depende de que alguien dibuje bien los polígonos.
4. **Los multiplicadores 0,6 / 1,0 / 1,5 son el punto de partida**, configurables por tipo de vehículo; el análisis económico (doc 03) puede ajustarlos.
5. **El tope de deuda 500 CUP es un valor de arranque.** Con tarifa 1 500 equivale a ~2 viajes de auto antes de bloquearse; se calibrará con datos del piloto.
6. **El conductor cobra en mano los viajes en efectivo** y la comisión se le descuenta del wallet. No hay pasarela que cobre al cliente por adelantado.
7. **Saldos de wallet bajos.** En Cuba el efectivo domina; el diseño asume que la mayoría de conductores no tendrá saldo suficiente para prepagar comisión, de ahí el modelo de deuda con tope (D6).
8. **Conectividad intermitente.** Publicar/tomar requieren red; el ciclo operativo tolera cortes.
9. **Privacidad del cliente.** El conductor no ve nombre ni teléfono hasta tomar el viaje.
10. **"Conductor" es el término de UI**, por consistencia con las pantallas existentes; no se renombra el vocabulario de la app.
11. **La tarifa se congela al publicar** (R2). Cualquier cambio de precio posterior es un ajuste manual de soporte, no un recálculo automático.
12. **El TTL total de 180 s** (90 + 90) es una propuesta inicial; se ajusta con datos del piloto.
13. **Punto-en-polígono sin PostGIS.** El plan de Supabase en uso no tiene PostGIS (ver el comentario en `driver_service.dart:287`), así que la pertenencia a zona se resuelve por algoritmo propio (ray casting) en servidor o cliente. Es una restricción técnica asumida, no una decisión de producto.
14. **Un viaje = un pasajero o grupo, un vehículo.** No hay pooling ni viajes compartidos.

---

## Riesgos

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| **1** | **La rama "sale de la zona" (km × precio_km) puede disparar el precio** de un viaje largo y expulsar demanda o generar rechazo del conductor si `precio_km` está mal calibrado | Alta | Alto | Instrumentar aceptación y conversión por tramo de km (KPI 24) y por modelo; `precio_km` es configurable sin release y se ajusta a los 14 días |
| **2** | **Fuga de conductores** que pierden la capacidad de negociar y perciben menos ingresos | Media-alta | Alto | Comunicar el neto exacto en cada tarjeta desde el primer día; piloto con garantía de ingreso; comparar ingreso/hora antes-después y publicarlo |
| **3** | **Deuda de comisión impagable** → bloqueo masivo de conductores y caída de oferta (el tope de 500 es bajo: 2 viajes de auto) | Alta | Alto | Calibrar el tope en el piloto (500 → 1 000 si el % de bloqueados supera el 25 %), bloqueo blando con CTA de recarga y liquidación automática al recargar |
| **4** | **Polígonos mal dibujados** (huecos en barrios, solapes sin prioridad) → viajes invisibles o precios absurdos | Media | Alto | Editor con validación geométrica, alerta de solape, vista "simular precio" por punto y KPI de % de viajes con tarifa general |
| **5** | **Caída de conversión** porque el cliente ya no puede ajustar el precio y la tarifa fija se percibe cara para trayectos cortos | Media | Alto | Medir conversión precio→solicitud; considerar subzona con base menor; comunicar la tarifa mínima como valor |
| **6** | **El multiplicador de microbús (1,5×) expulsa demanda** y deja el tipo sin uso | Media | Medio | Monitorear mix por tipo (KPI 12); recalibrar el multiplicador sin release |
| **7** | **Riesgo de crédito en efectivo** sin saldo bloqueante (cambio respecto a hoy) | Media | Medio | Tope bajo al inicio, revisión semanal y suspensión por deuda reincidente |
| **8** | **Cancelaciones por asignación a conductor lejano** | Media | Medio | Orden por ETA real, no por km en línea recta; medir desvío ETA prometido vs. real (KPI 9) |
| **9** | **Deuda técnica del modelo de datos actual** (`viajes.estado` es booleano, `solicitudes_transporte` no tiene `driver_id`, `vehicle_type.precio_espera_min` en SQL vs. `precio_espera_minuto` en Dart) | Alta | Medio | Resolver en el diseño técnico (doc 04); no arrastrar estos campos al nuevo flujo |
| **10** | **Disputas por cobro en efectivo** sin evidencia (el cliente dice que pagó, el conductor que no) | Media | Medio | Registrar GPS, timestamps y confirmación de ambas partes al completar; SLA 48 h |
| **11** | **Complejidad del editor de polígonos** en móvil/tablet para el superadmin | Media | Bajo-medio | Empezar con una zona municipal dibujada desde escritorio; subzonas después del piloto |

---

## Recomendación

**Ejecutar en tres fases, con el piloto antes de encender todo.**

### Fase 0 · Fundaciones (semana 1-2)
Editor de polígonos y tarifas en el superadmin, multiplicadores por tipo de vehículo, cálculo de precio en servidor, snapshot de tarifa por viaje, timestamps de estado y vista de KPIs. **Sin esto no hay nada que medir**, y es lo único que bloquea a las otras fases. Arranque con un polígono municipal, modelo `fijo` 1 500, `precio_km` 250 para las salidas, y los multiplicadores 0,6 / 1,0 / 1,5.

### Fase 1 · Piloto cerrado (semana 3-4)
- Un solo municipio, 20-40 conductores seleccionados.
- Flujo completo: precio fijo → lista de viajes → primer toque gana → ciclo operativo → liquidación con deuda.
- Se elimina la negociación **solo en este grupo**.
- Criterios de éxito para pasar de fase: tiempo a asignación p50 ≤ 60 s, tasa de expiración < 5 %, conversión precio→solicitud ≥ 65 %, aceptación en tramos > 10 km ≥ 60 %, % de conductores bloqueados por deuda < 25 %, sin incidentes de dinero abiertos.

### Fase 2 · Encendido y calibración (semana 5-8)
- Se abre a todos los conductores del municipio.
- Se activan subzonas con `fijo_mas_km` o `por_km` **solo si los datos lo piden** (tramos largos rechazados, barrios con tarifa inadecuada).
- Se calibran `precio_km`, multiplicadores y tope de deuda con datos reales.

### Lo que queda por calibrar (las decisiones de negocio ya están cerradas)

1. **`precio_km` de la zona municipal** (el que se cobra al salir de Santa Clara). Es el número con más impacto económico del modelo y debe salir del análisis del doc 03.
2. **Tope de deuda definitivo.** 500 CUP es el valor de arranque; con comisión de $225 por viaje de auto, bloquea al tercer viaje. Hay que decidir si eso es sano o si se sube a 1 000-1 500 con control semanal.
3. **Ajuste fino de multiplicadores** (moto 0,6 y microbús 1,5) tras dos semanas de datos por tipo de vehículo.

> Si hay que elegir una sola cosa para no fallar: **medir aceptación y conversión por tramo de km y por tipo de vehículo desde el primer día**. Es el dato que dice si la tarifa y los multiplicadores son viables, y sin él el debate se vuelve opinión.