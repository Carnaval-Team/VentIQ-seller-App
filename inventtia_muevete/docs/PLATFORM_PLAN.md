# MUEVETE – PLAN MAESTRO DE TRANSFORMACIÓN
## "Plataforma de carga: Shippers ↔ Transportistas"

---

## 1. CONTEXTO: ESTADO ACTUAL vs. ESTADO OBJETIVO

### Lo que existe hoy (ride-hailing urbano)
| Componente | Estado actual |
|---|---|
| `users` | Clientes de taxi urbano |
| `drivers` | Choferes urbanos, 1 vehículo ligero |
| `solicitudes_transporte` | Viajes cortos punto a punto |
| `ofertas_chofer` | Negociación de precio por viaje |
| `viajes` | Viaje activo sin detalles de carga |
| `valoraciones_viaje` | Rating único por viaje (1 dimensión) |
| `suscription_plan/user` | Wallet de recarga, sin planes reales |
| `transacciones_wallet` | Pagos de viaje + recargas |
| Escrow | **No existe** |
| Matching automático | **No existe** |
| Carga (FTL/LTL) | **No existe** |
| Verificación MC/DOT | **No existe** |
| GPS/ELD tracking | Manual (estado en DB), sin ELD |
| Multi-usuario | **No existe** |
| Reputación multidimensional | **No existe** (solo 1 rating) |
| Chat interno | **No existe** |
| Dashboard analítico | **No existe** |
| Antifraude / KYC avanzado | Básico (foto documento) |

---

## 2. ARQUITECTURA DE LA PLATAFORMA OBJETIVO

### 2.1 Taxonomía completa de tipos de usuario

La plataforma tiene **5 tipos de usuario** distintos, todos comparten la misma tabla `auth.users` pero se diferencian por el campo `tipo_usuario` y la tabla de perfil donde se almacenan:

```
auth.users
  │
  ├── muevete.users   (tipo_usuario = 'cliente_pasajero')
  │     └── Cliente de taxi/viajes urbanos — flujo EXISTENTE, sin cambios
  │
  ├── muevete.users   (tipo_usuario = 'shipper')
  │     └── Cliente de envíos de carga (empresa, cooperativa, importador)
  │         → Vista completamente nueva
  │
  ├── muevete.drivers (tipo_usuario = 'conductor_pasajeros')
  │     └── Chofer urbano que se gestiona solo, tiene su propio vehículo ligero
  │         → Flujo EXISTENTE, sin cambios
  │
  ├── muevete.drivers (tipo_usuario = 'carrier_carga')
  │     └── Transportista de carga, se gestiona solo, tiene su propio camión
  │         → Vista completamente nueva
  │
  └── muevete.drivers (tipo_usuario = 'dispatcher')
        └── Gestor/despachador que administra N transportistas de carga
            → Vista completamente nueva, maneja sub-usuarios (choferes)
```

**Regla de aislamiento de demanda (crítica):**
- Un `conductor_pasajeros` SOLO ve solicitudes con `tipo_solicitud = 'viaje'`
- Un `carrier_carga` SOLO ve cargas con `tipo_solicitud IN ('carga_ftl','carga_ltl')`
- Un `dispatcher` gestiona cargas en nombre de sus transportistas registrados
- Un `cliente_pasajero` SOLO puede solicitar viajes urbanos
- Un `shipper` SOLO puede publicar/ver cargas de envío

Este aislamiento se implementa a nivel de:
1. **RLS (Row Level Security)** en Supabase — filtro por `tipo_usuario` del JWT
2. **Queries del servicio** — siempre incluir filtro `tipo_solicitud`
3. **Navegación** — cada tipo tiene su propio árbol de rutas

### 2.2 Conceptos centrales nuevos
- **Carga (load)**: lo que el shipper publica (FTL o LTL)
- **Oferta de carrier**: respuesta al load publicado
- **Matching score**: algoritmo de compatibilidad carga↔carrier
- **Escrow**: custodia de pago hasta entrega confirmada
- **Liquidación**: liberación de fondos del escrow al carrier
- **Suscripción real**: plan con límites funcionales según tipo de usuario
- **Reputación multidimensional**: 4 categorías × 5 estrellas por lado
- **Dispatcher**: gestor de flota que opera cargas para múltiples choferes registrados

---

## 2B. FLUJOS DE REGISTRO — DETALLE POR TIPO DE USUARIO

> **Principio base**: Los datos que se solicitan HOY en el registro (nombre, email, contraseña, país, provincia, ciudad, teléfono, tipo de documento, foto frente, foto dorso) se mantienen **exactamente igual** para todos los tipos. Lo que varía son las **secciones adicionales** que aparecen según el tipo seleccionado.

### Paso 0 — Datos comunes (TODOS los tipos)
Idénticos al formulario actual en `register_screen.dart`:
- Nombre completo
- Correo electrónico
- Contraseña (mín. 6 caracteres)
- País (dropdown con código de área)
- Provincia / Estado
- Ciudad / Municipio
- Teléfono (con código de país)
- Tipo de documento (Carnet de Identidad / Pasaporte / Licencia de Conducir)
- Foto frente del documento (obligatoria)
- Foto dorso del documento (obligatoria)

### Paso 1 — Selección de tipo de cuenta

El selector de tipo de cuenta actual tiene 2 opciones (`Cliente` / `Conductor`). Se **expande a 4 opciones** con descripción clara:

| Opción | Icono | Subtítulo |
|---|---|---|
| **Cliente de viajes** | `person_outline` | "Solicitar viajes urbanos" |
| **Shipper de carga** | `inventory_2_outlined` | "Publicar y gestionar envíos de carga" |
| **Transportista** | `local_shipping_outlined` | "Ofrecer servicios de transporte" |
| **Dispatcher** | `dashboard_outlined` | "Gestionar flota y choferes" |

Al seleccionar **Transportista**, aparece un sub-selector adicional:
- `conductor_pasajeros` → "Transporte de pasajeros / viajes urbanos"
- `carrier_carga` → "Transporte de carga y encomiendas"

### Paso 2A — Campos extra para `cliente_pasajero`
**Sin campos adicionales.** Idéntico al flujo actual. Al registrarse va directo a `/client/home`.

### Paso 2B — Campos extra para `shipper`
Sección adicional: **"Información de Empresa / Carga"**
- Tipo de cuenta: `Individual` / `Empresa` / `Cooperativa` (dropdown)
- Si es `Empresa` o `Cooperativa`:
  - Nombre de la empresa (text field, obligatorio)
  - RUT / EIN / Número fiscal (text field, obligatorio)
  - Dirección de la empresa (text field)
- Mercancías que maneja habitualmente (chips multiselección, opcional):
  - General, Refrigerada, Peligrosa, Sobredimensionada, Vehículos, Electrónica, Otros
- Al registrarse va a `/shipper/home` → vista completamente nueva

### Paso 2C — Campos extra para `conductor_pasajeros`
**Sin cambios respecto al flujo actual** (ya existe). Sección: **"Datos del Vehículo"**
- Tipo de vehículo (dropdown desde `vehicle_type`)
- Marca, Modelo, Año
- Matrícula / Chapa
- Color
- Foto del vehículo (opcional)
- Al registrarse va a `/driver/home` → flujo existente sin cambios

### Paso 2D — Campos extra para `carrier_carga`
Sección adicional: **"Datos del Vehículo de Carga"**
- Tipo de carrocería (dropdown): Furgón seco, Flatbed, Reefer/Refrigerado, Tanque, Curtainsider, Volcadora
- Marca del camión
- Modelo
- Año
- Matrícula / Chapa
- Capacidad (toneladas)
- Longitud de plataforma (metros)
- Seguro vigente: sí/no + fecha de vencimiento
- (Opcional) MC Number / DOT Number

Sección adicional: **"Verificación Profesional"** (opcional en registro, requerida para operar escrow)
- Número MC (Motor Carrier) — texto libre, se verificará vía FMCSA
- Número DOT — texto libre
- Certificado de seguro de carga (foto/PDF) — upload opcional

Al registrarse va a `/carrier/home` → vista completamente nueva

### Paso 2E — Campos extra para `dispatcher`
Sección: **"Datos de la Empresa Despachadora"**
- Nombre de la empresa despachadora (obligatorio)
- RUT / EIN / Número fiscal (obligatorio)
- Dirección de la empresa

Sección: **"Transportistas que Gestionarás"** (mínimo 1 obligatorio)
> Esta sección es un formulario repetible (tipo lista dinámica: `+` para agregar, `×` para eliminar).  
> **Se debe registrar al menos un transportista para poder completar el registro.**

Por cada transportista:
- Nombre completo (obligatorio)
- Teléfono (obligatorio)
- Email (obligatorio — se usará para crear su cuenta vinculada)
- Tipo de carrocería del vehículo
- Marca / Modelo / Matrícula
- Capacidad (toneladas)
- MC Number (opcional)
- DOT Number (opcional)

**Lógica de backend al registrar un dispatcher:**
1. Se crea el perfil del dispatcher en `muevete.drivers` con `tipo_usuario = 'dispatcher'`
2. Por cada transportista ingresado, se crea un registro en `muevete.drivers` con `tipo_usuario = 'carrier_carga'` y `estado = false` (pendiente de activar)
3. Se crea un registro en `muevete.sub_usuarios` vinculando dispatcher ↔ cada transportista
4. Se envía email/notificación a cada transportista para que active su cuenta y suba sus documentos
5. El dispatcher puede seguir agregando transportistas desde su perfil después del registro

Al registrarse va a `/dispatcher/home` → vista completamente nueva (sub-set de `/carrier/home` con panel de flota)

---

## 2C. AISLAMIENTO DE DEMANDA — IMPLEMENTACIÓN

### Columna discriminadora en `solicitudes_transporte` y `cargas`

```sql
-- En solicitudes_transporte (viajes de taxi — existente):
tipo_solicitud = 'viaje'

-- En cargas (nueva tabla):
tipo_carga IN ('carga_ftl', 'carga_ltl')
```

### RLS Policies (Supabase Row Level Security)

```sql
-- CONDUCTORES DE PASAJEROS: solo ven viajes
CREATE POLICY "conductor_pasajeros_solo_viajes" ON muevete.solicitudes_transporte
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM muevete.drivers d
      WHERE d.uuid = auth.uid()
      AND d.tipo_usuario = 'conductor_pasajeros'
    )
    AND tipo_solicitud = 'viaje'
  );

-- CARRIERS DE CARGA: solo ven cargas
CREATE POLICY "carrier_carga_solo_cargas" ON muevete.cargas
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM muevete.drivers d
      WHERE d.uuid = auth.uid()
      AND d.tipo_usuario IN ('carrier_carga', 'dispatcher')
    )
  );

-- CLIENTES PASAJEROS: solo ven sus viajes
CREATE POLICY "cliente_pasajero_sus_viajes" ON muevete.solicitudes_transporte
  FOR SELECT USING (
    user_id = auth.uid()
    AND tipo_solicitud = 'viaje'
  );

-- SHIPPERS: solo ven sus cargas
CREATE POLICY "shipper_sus_cargas" ON muevete.cargas
  FOR SELECT USING (
    shipper_id = auth.uid()
  );
```

### Navegación por tipo de usuario (routes en Flutter)

```dart
// En AuthProvider._loadProfile() — determinar ruta de home
switch (tipoUsuario) {
  case 'cliente_pasajero':   → '/client/home'        // EXISTENTE
  case 'conductor_pasajeros': → '/driver/home'        // EXISTENTE
  case 'shipper':             → '/shipper/home'       // NUEVO
  case 'carrier_carga':       → '/carrier/home'       // NUEVO
  case 'dispatcher':          → '/dispatcher/home'    // NUEVO
}
```

---

## 2D. VISTA DE SUSCRIPCIONES — DISEÑO POR TIPO DE USUARIO

La pantalla `PlanesScreen` se renderiza de forma **completamente diferente** según el `tipo_usuario`. No es una pantalla genérica — muestra solo los planes relevantes para ese tipo y destaca las características que importan a ese perfil.

### Para `cliente_pasajero` — NO aplica
Los clientes de taxi no tienen planes. Acceden directamente con su wallet. Esta pantalla no se muestra para este tipo.

### Para `shipper` — Planes de publicación de carga
| | Básico | Profesional | Empresarial |
|---|---|---|---|
| **Precio/mes** | Gratis | $49/mes | $149/mes |
| **Cargas/mes** | 5 | 30 | Ilimitadas |
| **Contactos/mes** | 10 | Ilimitados | Ilimitados |
| **Matching automático** | No | Sí (5/día) | Sí (ilimitado) |
| **Escrow incluido** | No (comisión 3%) | Sí (comisión 2%) | Sí (comisión 1.5%) |
| **Ventana exclusiva** | No | 2h antes | 6h antes |
| **Cargas destacadas** | No | 2/mes | 10/mes |
| **Dashboard analítico** | No | Básico | Avanzado |
| **Sub-usuarios** | 1 | 3 | 10 |
| **Soporte** | Email | Chat | Teléfono (SLA 4h) |

### Para `carrier_carga` — Planes de transporte de carga
| | Básico | Profesional | |
|---|---|---|---|
| **Precio/mes** | Gratis | $39/mes | |
| **Ofertas/mes** | 10 | Ilimitadas | |
| **Matching recibido** | Aleatorio | Priorizado | |
| **Verificación MC/DOT** | No | Incluida | |
| **Escrow disponible** | No | Sí | |
| **GPS tracking avanzado** | No | Sí | |
| **Dashboard ingresos** | Básico | Avanzado | |
| **Alertas de carga** | 1 alerta | Ilimitadas | |

### Para `dispatcher` — Planes de flota
| | Starter | Pro | |
|---|---|---|---|
| **Precio/mes** | $79/mes | $199/mes | |
| **Transportistas** | Hasta 5 | Hasta 20 | |
| **Cargas activas** | Ilimitadas | Ilimitadas | |
| **Panel de flota** | Básico | Avanzado + ELD | |
| **Sub-usuarios operadores** | 2 | 5 | |
| **Factoraje de fletes** | No | Sí | |
| **API acceso** | No | Sí | |

### Para `conductor_pasajeros` — NO aplica nuevos planes
Los conductores de taxi operan sin suscripción (comisión por viaje). Esta pantalla no se muestra para este tipo.

### Componentes de `PlanesScreen` que varían

```dart
// La pantalla recibe el tipo de usuario y renderiza la tabla correcta
class PlanesScreen extends StatelessWidget {
  // 1. Header contextual:
  //    - shipper: "Elige tu plan para publicar cargas"
  //    - carrier:  "Elige tu plan para recibir cargas"
  //    - dispatcher: "Elige tu plan de gestión de flota"
  
  // 2. Tabla de características: distinta por tipo (ver arriba)
  
  // 3. CTA principal:
  //    - Plan actual marcado con badge "Tu plan actual"
  //    - Plan recomendado marcado con badge "Más popular"
  //    - Botón "Seleccionar" en planes superiores
  //    - Botón "Gestionar" en plan actual
  
  // 4. Preguntas frecuentes: distintas por tipo
  //    - shipper: "¿Qué es el escrow?", "¿Puedo cancelar en cualquier momento?"
  //    - carrier:  "¿Cómo funciona la verificación MC/DOT?"
  //    - dispatcher: "¿Cómo invito a mis choferes?"
}
```

---

## 3. CAMBIOS EN EL ESQUEMA SQL (`muevete_schema.sql`)

### 3.1 Tablas a MODIFICAR

#### `muevete.users` — agregar campos de shipper y tipo de usuario
```sql
ALTER TABLE muevete.users ADD COLUMN IF NOT EXISTS
  -- DISCRIMINADOR: diferencia cliente_pasajero vs shipper
  tipo_usuario      text DEFAULT 'cliente_pasajero',
  -- 'cliente_pasajero' → flujo taxi existente (sin cambios)
  -- 'shipper'          → flujo de carga nuevo

  -- Campos shipper (solo aplican cuando tipo_usuario = 'shipper')
  tipo_cuenta       text DEFAULT 'individual',  -- 'individual', 'empresa', 'cooperativa'
  empresa_nombre    text,
  empresa_rut       text,
  empresa_direccion text,
  mercaderias_habituales jsonb DEFAULT '[]',   -- ['general','refrigerada','peligrosa',...]

  -- Campos comunes shipper + cliente
  kyc_estado        text DEFAULT 'pendiente',   -- 'pendiente','verificado','rechazado'
  kyc_fecha         timestamptz,
  plan_id           bigint REFERENCES muevete.planes(id),
  plan_activo_hasta timestamptz,
  cargas_mes_count  integer DEFAULT 0,
  mfa_habilitado    boolean DEFAULT false,
  risk_score        numeric DEFAULT 0,
  bloqueado         boolean DEFAULT false,
  motivo_bloqueo    text;
```

#### `muevete.drivers` — agregar discriminador y campos carrier/dispatcher
```sql
ALTER TABLE muevete.drivers ADD COLUMN IF NOT EXISTS
  -- DISCRIMINADOR: diferencia conductor_pasajeros / carrier_carga / dispatcher
  tipo_usuario      text DEFAULT 'conductor_pasajeros',
  -- 'conductor_pasajeros' → flujo taxi existente (sin cambios)
  -- 'carrier_carga'       → transportista de carga (se gestiona solo)
  -- 'dispatcher'          → gestor de flota (gestiona N transportistas)

  -- Identificador de dispatcher propietario (para carriers registrados por un dispatcher)
  dispatcher_id     bigint REFERENCES muevete.drivers(id),

  -- Campos carrier/dispatcher (solo aplican cuando tipo_usuario != 'conductor_pasajeros')
  mc_number         text,
  dot_number        text,
  mc_dot_verificado boolean DEFAULT false,
  seguro_verificado boolean DEFAULT false,
  seguro_vence      date,
  autoridad_activa  boolean DEFAULT false,
  autoridad_fecha   date,           -- fecha de activación MC (para filtro 30 días)
  plan_id           bigint REFERENCES muevete.planes(id),
  plan_activo_hasta timestamptz,
  cargas_mes_count  integer DEFAULT 0,
  ontime_pct        numeric DEFAULT 0,    -- % entregas a tiempo
  response_time_avg numeric DEFAULT 0,   -- minutos promedio para aceptar
  matching_score    numeric DEFAULT 0,   -- score acumulado del algoritmo
  kyc_estado        text DEFAULT 'pendiente',
  mfa_habilitado    boolean DEFAULT false,
  risk_score        numeric DEFAULT 0,
  bloqueado         boolean DEFAULT false,
  eld_provider      text,                -- 'samsara','keeptruckin','none'
  eld_vehicle_id    text;
```

#### `muevete.vehiculos` — agregar campos de camión de carga
```sql
ALTER TABLE muevete.vehiculos ADD COLUMN IF NOT EXISTS
  tipo_carroceria   text,    -- 'flatbed','van','reefer','tanker','dryvan','curtain'
  capacidad_ton     numeric,
  capacidad_m3      numeric,
  año               integer,
  num_ejes          integer,
  longitud_m        numeric,
  ancho_m           numeric,
  alto_m            numeric,
  tiene_gps         boolean DEFAULT false,
  tiene_eld         boolean DEFAULT false,
  seguro_vigente    boolean DEFAULT false,
  seguro_vence      date,
  inspeccion_vence  date;
```

#### `muevete.solicitudes_transporte` — renombrar semánticamente (mantener compatibilidad)
> Esta tabla se EXTIENDE para soportar cargas. Las solicitudes de taxi siguen funcionando con los campos existentes.

```sql
ALTER TABLE muevete.solicitudes_transporte ADD COLUMN IF NOT EXISTS
  tipo_solicitud       text DEFAULT 'viaje',    -- 'viaje', 'carga_ftl', 'carga_ltl'
  -- Campos de carga
  descripcion_carga    text,
  tipo_mercancia       text,
  peso_kg              numeric,
  volumen_m3           numeric,
  valor_declarado      numeric,
  requiere_refrigeracion boolean DEFAULT false,
  requiere_seguro      boolean DEFAULT false,
  instrucciones_carga  text,
  fecha_recogida       date,
  fecha_entrega        date,
  -- Ventanas de tiempo
  ventana_recogida_desde time,
  ventana_recogida_hasta time,
  ventana_entrega_desde  time,
  ventana_entrega_hasta  time,
  -- Escrow
  escrow_id            bigint REFERENCES muevete.escrow_transacciones(id),
  -- Visibilidad (ventana exclusiva plan Profesional/Dispatcher)
  exclusiva_hasta      timestamptz,
  -- LTL
  es_consolidada       boolean DEFAULT false,
  consolidacion_id     bigint REFERENCES muevete.consolidaciones_ltl(id),
  -- Recurrencia
  es_recurrente        boolean DEFAULT false,
  recurrencia_patron   jsonb,    -- {'frecuencia':'semanal','dias':[1,3,5]}
  contrato_id          bigint REFERENCES muevete.contratos_carga(id),
  -- Matching
  matching_score_max   numeric;  -- mejor score recibido hasta ahora
```

#### `muevete.ofertas_chofer` — extender para carga
```sql
ALTER TABLE muevete.ofertas_chofer ADD COLUMN IF NOT EXISTS
  matching_score       numeric,   -- score calculado al momento de la oferta
  vehiculo_id          bigint REFERENCES muevete.vehiculos(id),
  notas                text,
  fecha_recogida_prop  date,
  fecha_entrega_prop   date,
  incluye_seguro       boolean DEFAULT false,
  tarifa_por_milla     numeric;
```

#### `muevete.valoraciones_viaje` — reemplazar por sistema multidimensional
> Mantener la tabla actual para compatibilidad con viajes de taxi; agregar nueva tabla para cargas.

#### `muevete.suscription_plan` → reemplazar semánticamente por `muevete.planes`
> Se crea tabla nueva `planes` con toda la metadata del plan; se mantiene la tabla vieja por compatibilidad.

#### `muevete.transacciones_wallet` — ampliar tipos
```sql
-- Agregar nuevos tipos al CHECK constraint:
-- 'escrow_deposito', 'escrow_liberacion', 'escrow_devolucion',
-- 'escrow_comision', 'factoraje_adelanto', 'factoraje_devolucion',
-- 'suscripcion', 'seguro_prima', 'carga_destacada'
```

### 3.2 Tablas NUEVAS a crear

#### `muevete.planes`
```sql
CREATE TABLE muevete.planes (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo          text UNIQUE NOT NULL,  -- 'shipper_basico','carrier_profesional', etc.
  tipo_usuario    text NOT NULL,         -- 'shipper','carrier'
  nombre          text NOT NULL,
  precio_mensual  numeric NOT NULL,
  cargas_mes_max  integer,               -- NULL = ilimitado
  contactos_mes_max integer,             -- NULL = ilimitado
  matching_auto   boolean DEFAULT false,
  matching_diario_max integer,           -- NULL = ilimitado
  escrow_comision numeric,               -- porcentaje
  escrow_incluido boolean DEFAULT false,
  verificacion_mc boolean DEFAULT false,
  alertas_push    boolean DEFAULT false,
  ventana_exclusiva_horas integer,       -- horas de acceso anticipado a cargas
  gps_basico      boolean DEFAULT false,
  gps_avanzado    boolean DEFAULT false,
  eld_integrado   boolean DEFAULT false,
  multi_usuarios  integer DEFAULT 1,     -- cantidad máxima de sub-usuarios
  api_acceso      boolean DEFAULT false,
  factoraje       boolean DEFAULT false,
  dashboard_nivel text DEFAULT 'ninguno', -- 'ninguno','basico','avanzado'
  soporte_nivel   text DEFAULT 'email',   -- 'email','chat','telefono'
  soporte_sla_h   integer,               -- horas para respuesta
  activo          boolean DEFAULT true,
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.suscripciones_usuario`
```sql
CREATE TABLE muevete.suscripciones_usuario (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid       uuid REFERENCES auth.users(id),
  plan_id         bigint REFERENCES muevete.planes(id),
  estado          text DEFAULT 'activa', -- 'activa','vencida','cancelada','trial'
  inicio          timestamptz DEFAULT now(),
  fin             timestamptz,
  auto_renovar    boolean DEFAULT true,
  metodo_pago     text,
  ultima_factura  bigint,
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.cargas` (tabla principal de carga, pivot de toda la plataforma)
```sql
CREATE TABLE muevete.cargas (
  id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  shipper_id            uuid NOT NULL REFERENCES auth.users(id),
  tipo                  text NOT NULL DEFAULT 'ftl', -- 'ftl','ltl'
  estado                text NOT NULL DEFAULT 'publicada',
  -- 'publicada','en_matching','ofertada','aceptada','en_transito',
  -- 'entregada','completada','cancelada','disputa'
  
  -- Origen
  dir_origen            text NOT NULL,
  lat_origen            double precision NOT NULL,
  lon_origen            double precision NOT NULL,
  ciudad_origen         text,
  estado_origen         text,
  pais_origen           text DEFAULT 'US',
  
  -- Destino
  dir_destino           text NOT NULL,
  lat_destino           double precision NOT NULL,
  lon_destino           double precision NOT NULL,
  ciudad_destino        text,
  estado_destino        text,
  pais_destino          text DEFAULT 'US',
  
  -- Dimensiones y mercancía
  descripcion           text,
  tipo_mercancia        text,
  peso_kg               numeric,
  volumen_m3            numeric,
  longitud_m            numeric,
  ancho_m               numeric,
  alto_m                numeric,
  valor_declarado       numeric,
  requiere_refrigeracion boolean DEFAULT false,
  temperatura_min       numeric,
  temperatura_max       numeric,
  requiere_seguro       boolean DEFAULT false,
  instrucciones         text,
  
  -- Tipo de equipo requerido
  tipo_equipo           text, -- 'flatbed','van','reefer','dryvan','tanker'
  id_tipo_vehiculo      bigint REFERENCES muevete.vehicle_type(id),
  
  -- Fechas
  fecha_recogida        date,
  fecha_entrega         date,
  ventana_recogida_desde time,
  ventana_recogida_hasta time,
  ventana_entrega_desde  time,
  ventana_entrega_hasta  time,
  
  -- Precio
  precio_ofertado       numeric,          -- lo que el shipper ofrece
  precio_final          numeric,          -- acordado con carrier
  moneda                text DEFAULT 'USD',
  
  -- Visibilidad por plan
  exclusiva_hasta       timestamptz,      -- hasta cuándo es exclusiva para plan Profesional+
  destacada             boolean DEFAULT false,
  destacada_hasta       timestamptz,
  
  -- Distancia calculada
  distancia_km          double precision,
  distancia_millas      double precision,
  
  -- LTL
  es_ltl                boolean DEFAULT false,
  consolidacion_id      bigint,           -- FK a muevete.consolidaciones_ltl
  ltl_espacio_ocupado   numeric,          -- % del camión que ocupa
  
  -- Recurrencia y contratos
  es_recurrente         boolean DEFAULT false,
  recurrencia_patron    jsonb,
  contrato_id           bigint,           -- FK a muevete.contratos_carga
  
  -- Escrow
  escrow_id             bigint,           -- FK a muevete.escrow_transacciones
  
  -- Matching
  matching_score_max    numeric DEFAULT 0,
  matching_ejecutado_at timestamptz,
  
  -- Carrier asignado
  carrier_driver_id     bigint REFERENCES muevete.drivers(id),
  oferta_aceptada_id    bigint,           -- FK a muevete.ofertas_carga
  
  -- Tracking
  ultima_lat            double precision,
  ultima_lon            double precision,
  ultima_ubicacion_at   timestamptz,
  
  -- Metadata
  created_at            timestamptz DEFAULT now(),
  updated_at            timestamptz DEFAULT now(),
  expires_at            timestamptz
);
```

#### `muevete.ofertas_carga`
```sql
CREATE TABLE muevete.ofertas_carga (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  carga_id            bigint NOT NULL REFERENCES muevete.cargas(id),
  driver_id           bigint NOT NULL REFERENCES muevete.drivers(id),
  precio              numeric NOT NULL,
  tarifa_por_milla    numeric,
  tiempo_estimado_dias integer,
  fecha_recogida_prop  date,
  fecha_entrega_prop   date,
  vehiculo_id         bigint REFERENCES muevete.vehiculos(id),
  incluye_seguro      boolean DEFAULT false,
  notas               text,
  estado              text DEFAULT 'pendiente',
  -- 'pendiente','aceptada','rechazada','retirada','expirada'
  matching_score      numeric,           -- score al momento de la oferta
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now(),
  CONSTRAINT uq_oferta_carga_driver UNIQUE (carga_id, driver_id)
);
```

#### `muevete.escrow_transacciones`
```sql
CREATE TABLE muevete.escrow_transacciones (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  carga_id            bigint NOT NULL,   -- FK cargas
  shipper_uuid        uuid NOT NULL REFERENCES auth.users(id),
  carrier_driver_id   bigint NOT NULL REFERENCES muevete.drivers(id),
  monto_total         numeric NOT NULL,
  comision_plataforma numeric NOT NULL,
  monto_carrier       numeric NOT NULL,  -- monto_total - comision_plataforma
  moneda              text DEFAULT 'USD',
  estado              text DEFAULT 'pendiente',
  -- 'pendiente','depositado','liberado','devuelto','disputa','congelado'
  
  -- Depósito
  depositado_at       timestamptz,
  metodo_pago         text,
  referencia_pago     text,
  
  -- Confirmación de entrega
  geocerca_confirmada  boolean DEFAULT false,
  geocerca_confirmada_at timestamptz,
  pod_url              text,             -- Proof of Delivery (imagen/PDF)
  qr_token             text,             -- token para escaneo QR
  entrega_confirmada_at timestamptz,
  shipper_confirmo     boolean DEFAULT false,
  shipper_confirmo_at  timestamptz,
  
  -- Liberación automática
  liberar_auto_at      timestamptz,     -- si shipper no confirma en 48-72h
  liberado_at          timestamptz,
  
  -- Disputa
  disputa_abierta      boolean DEFAULT false,
  disputa_motivo       text,
  disputa_evidencias   jsonb DEFAULT '[]',
  disputa_resolucion   text,
  disputa_resuelta_at  timestamptz,
  
  created_at           timestamptz DEFAULT now()
);
```

#### `muevete.tracking_carga`
```sql
CREATE TABLE muevete.tracking_carga (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  carga_id        bigint NOT NULL REFERENCES muevete.cargas(id),
  driver_id       bigint NOT NULL REFERENCES muevete.drivers(id),
  latitude        double precision NOT NULL,
  longitude       double precision NOT NULL,
  velocidad_kmh   numeric,
  rumbo           numeric,              -- heading en grados
  estado_evento   text,
  -- 'en_ruta','parada','recogida_iniciada','recogida_completada',
  -- 'entrega_iniciada','entrega_completada','fuera_de_ruta'
  fuente          text DEFAULT 'app',  -- 'app','eld','manual'
  eld_data        jsonb,               -- datos brutos del ELD
  created_at      timestamptz DEFAULT now()
);
CREATE INDEX idx_tracking_carga_carga_id ON muevete.tracking_carga(carga_id);
CREATE INDEX idx_tracking_carga_created ON muevete.tracking_carga(created_at DESC);
```

#### `muevete.geocercas`
```sql
CREATE TABLE muevete.geocercas (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  carga_id        bigint NOT NULL REFERENCES muevete.cargas(id),
  tipo            text NOT NULL,       -- 'origen','destino'
  lat_centro      double precision NOT NULL,
  lon_centro      double precision NOT NULL,
  radio_millas    numeric DEFAULT 0.5,
  activada        boolean DEFAULT true,
  disparada_at    timestamptz,         -- cuando el GPS entró al radio
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.valoraciones_carga` (sistema multidimensional)
```sql
CREATE TABLE muevete.valoraciones_carga (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  carga_id        bigint NOT NULL REFERENCES muevete.cargas(id),
  evaluador_uuid  uuid NOT NULL REFERENCES auth.users(id),
  evaluado_uuid   uuid,                -- NULL si evaluado es driver
  evaluado_driver_id bigint REFERENCES muevete.drivers(id),
  tipo_evaluador  text NOT NULL,       -- 'shipper','carrier'
  
  -- Dimensiones para CARRIER (calificado por shipper)
  puntualidad           smallint CHECK (puntualidad BETWEEN 1 AND 5),
  comunicacion          smallint CHECK (comunicacion BETWEEN 1 AND 5),
  documentacion         smallint CHECK (documentacion BETWEEN 1 AND 5),
  estado_carga          smallint CHECK (estado_carga BETWEEN 1 AND 5),
  
  -- Dimensiones para SHIPPER (calificado por carrier)
  puntualidad_pago      smallint CHECK (puntualidad_pago BETWEEN 1 AND 5),
  precision_carga       smallint CHECK (precision_carga BETWEEN 1 AND 5),
  tiempo_carga_descarga smallint CHECK (tiempo_carga_descarga BETWEEN 1 AND 5),
  comunicacion_shipper  smallint CHECK (comunicacion_shipper BETWEEN 1 AND 5),
  
  comentario      text,
  respuesta       text,                -- el evaluado puede responder
  calificacion_neutral boolean DEFAULT false,  -- asignada automáticamente a los 7 días
  created_at      timestamptz DEFAULT now(),
  CONSTRAINT uq_valoracion_carga UNIQUE (carga_id, evaluador_uuid)
);
```

#### `muevete.chat_conversaciones`
```sql
CREATE TABLE muevete.chat_conversaciones (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  carga_id        bigint REFERENCES muevete.cargas(id),
  shipper_uuid    uuid NOT NULL REFERENCES auth.users(id),
  carrier_uuid    uuid NOT NULL REFERENCES auth.users(id),  -- UUID del driver
  ultimo_mensaje  text,
  ultimo_mensaje_at timestamptz,
  shipper_no_leidos integer DEFAULT 0,
  carrier_no_leidos integer DEFAULT 0,
  activa          boolean DEFAULT true,
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.chat_mensajes`
```sql
CREATE TABLE muevete.chat_mensajes (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  conversacion_id bigint NOT NULL REFERENCES muevete.chat_conversaciones(id),
  remitente_uuid  uuid NOT NULL REFERENCES auth.users(id),
  tipo            text DEFAULT 'texto',  -- 'texto','imagen','documento','ubicacion'
  contenido       text NOT NULL,
  archivo_url     text,
  leido           boolean DEFAULT false,
  leido_at        timestamptz,
  created_at      timestamptz DEFAULT now()
);
CREATE INDEX idx_chat_mensajes_conv ON muevete.chat_mensajes(conversacion_id, created_at);
```

#### `muevete.matching_scores`
```sql
CREATE TABLE muevete.matching_scores (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  carga_id        bigint NOT NULL REFERENCES muevete.cargas(id),
  driver_id       bigint NOT NULL REFERENCES muevete.drivers(id),
  score_total     numeric NOT NULL,      -- 0-100
  
  -- Componentes del score (pesos según spec)
  score_proximidad        numeric,       -- 25%
  score_historial_ruta    numeric,       -- 20%
  score_rating            numeric,       -- 15%
  score_precio            numeric,       -- 15%
  score_tiempo_respuesta  numeric,       -- 10%
  score_fiabilidad        numeric,       -- 10%
  score_preferencias      numeric,       -- 5%
  
  sugerido_al_carrier     boolean DEFAULT false,
  sugerido_al_shipper     boolean DEFAULT false,
  sugerido_at             timestamptz,
  created_at              timestamptz DEFAULT now(),
  CONSTRAINT uq_matching UNIQUE (carga_id, driver_id)
);
```

#### `muevete.consolidaciones_ltl`
```sql
CREATE TABLE muevete.consolidaciones_ltl (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  driver_id       bigint REFERENCES muevete.drivers(id),
  vehiculo_id     bigint REFERENCES muevete.vehiculos(id),
  estado          text DEFAULT 'abierta',  -- 'abierta','cerrada','en_transito','entregada'
  zona_origen     text,                    -- ej: "Miami-30mi"
  fecha_objetivo  date,
  capacidad_total_m3 numeric,
  capacidad_usada_m3 numeric DEFAULT 0,
  ruta_optimizada jsonb,                   -- puntos de recogida y entrega en orden
  cargas_count    integer DEFAULT 0,
  valor_total     numeric DEFAULT 0,
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.contratos_carga`
```sql
CREATE TABLE muevete.contratos_carga (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  shipper_uuid    uuid NOT NULL REFERENCES auth.users(id),
  carrier_uuid    uuid NOT NULL,          -- UUID del driver
  descripcion     text,
  tarifa_acordada numeric,
  tipo_tarifa     text,                   -- 'por_carga','por_milla','mensual'
  inicio          date,
  fin             date,
  cargas_min_mes  integer,
  estado          text DEFAULT 'activo',  -- 'activo','vencido','cancelado'
  condiciones     text,
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.alertas_usuario`
```sql
CREATE TABLE muevete.alertas_usuario (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid       uuid NOT NULL REFERENCES auth.users(id),
  tipo_usuario    text NOT NULL,          -- 'shipper','carrier'
  nombre          text NOT NULL,
  
  -- Criterios (carrier buscando cargas)
  origen_ciudad   text,
  origen_radio_km numeric,
  destino_ciudad  text,
  tipo_equipo     text,
  peso_max_kg     numeric,
  precio_min      numeric,
  precio_max      numeric,
  
  -- Criterios (shipper buscando carriers)
  rating_min      numeric,
  mc_verificado   boolean,
  
  activa          boolean DEFAULT true,
  canal           text DEFAULT 'push',    -- 'push','email','ambos'
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.kyc_documentos`
```sql
CREATE TABLE muevete.kyc_documentos (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid       uuid NOT NULL REFERENCES auth.users(id),
  tipo_usuario    text NOT NULL,          -- 'shipper','carrier'
  tipo_doc        text NOT NULL,
  -- 'identidad_frente','identidad_dorso','selfie','seguro','mc_certificate',
  -- 'dot_certificate','empresa_rut','licencia_comercial'
  url             text NOT NULL,
  estado          text DEFAULT 'pendiente',  -- 'pendiente','aprobado','rechazado'
  revisor_nota    text,
  revisado_at     timestamptz,
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.antifraude_eventos`
```sql
CREATE TABLE muevete.antifraude_eventos (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid       uuid REFERENCES auth.users(id),
  tipo_evento     text NOT NULL,
  -- 'ip_sospechosa','multiples_cuentas','cambio_email','cambio_telefono',
  -- 'mfa_fallido','patron_fraude'
  ip_address      text,
  device_id       text,
  detalles        jsonb DEFAULT '{}',
  accion_tomada   text,                   -- 'ninguna','alerta','bloqueo'
  created_at      timestamptz DEFAULT now()
);
```

#### `muevete.sub_usuarios`
```sql
CREATE TABLE muevete.sub_usuarios (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  -- Propietario: puede ser un shipper (empresarial) o un dispatcher
  propietario_uuid    uuid NOT NULL REFERENCES auth.users(id),
  tipo_propietario    text NOT NULL,       -- 'shipper','dispatcher'

  -- Sub-usuario: para shippers es un operador; para dispatchers es un carrier_carga
  sub_uuid            uuid NOT NULL REFERENCES auth.users(id),
  sub_driver_id       bigint REFERENCES muevete.drivers(id), -- solo para dispatcher→carrier
  rol                 text DEFAULT 'operador',
  -- shipper: 'operador','admin'
  -- dispatcher: 'conductor' (el carrier_carga gestionado)

  -- Estado de la invitación / activación
  invitacion_estado   text DEFAULT 'pendiente',
  -- 'pendiente' → email enviado, el transportista no ha activado aún
  -- 'activo'    → el transportista activó su cuenta
  -- 'revocado'  → dispatcher revocó el acceso
  invitacion_email    text,               -- email usado para invitar (antes de que active)
  invitacion_token    text,               -- token único del email de invitación

  activo              boolean DEFAULT false, -- true solo cuando el sub activó su cuenta
  created_at          timestamptz DEFAULT now(),
  CONSTRAINT uq_sub_usuario UNIQUE (propietario_uuid, sub_uuid)
);
```

#### `muevete.facturas_plataforma`
```sql
CREATE TABLE muevete.facturas_plataforma (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid       uuid NOT NULL REFERENCES auth.users(id),
  tipo            text NOT NULL,   -- 'suscripcion','escrow_comision','carga_destacada','seguro'
  monto           numeric NOT NULL,
  moneda          text DEFAULT 'USD',
  estado          text DEFAULT 'pendiente', -- 'pendiente','pagada','vencida'
  descripcion     text,
  periodo_inicio  date,
  periodo_fin     date,
  referencia_id   bigint,          -- id de suscripcion/escrow/etc.
  created_at      timestamptz DEFAULT now(),
  pagada_at       timestamptz
);
```

---

## 4. CAMBIOS EN MODELOS DART

### 4.1 Modelos a MODIFICAR

#### `user_model.dart`
- Agregar: `tipoDocumento`, `docFrenteUrl`, `docDorsoUrl` (ya están en DB, faltan en modelo)
- Agregar: `tipoCuenta`, `empresaNombre`, `empresaRut`, `kycEstado`, `planId`, `planActivoHasta`, `bloqueado`
- Agregar: `photoUrl` (ya en DB, puede faltar en modelo)

#### `driver_model.dart`
- Agregar: `tipoCarrier`, `mcNumber`, `dotNumber`, `mcDotVerificado`, `seguroVerificado`
- Agregar: `planId`, `planActivoHasta`, `ontimePct`, `responseTimeAvg`, `kycEstado`
- Agregar: `eldProvider`, `eldVehicleId`, `tipoDocumento`, `docFrenteUrl`, `docDorsoUrl`

#### `vehicle_model.dart`
- Agregar: `tipoCarroceria`, `capacidadTon`, `capacidadM3`, `año`, `numEjes`
- Agregar: `tieneGps`, `tieneEld`, `seguroVigente`, `seguroVence`

#### `transport_request_model.dart`
- Este modelo representa viajes de taxi. Para cargas se crea nuevo `CargaModel`.
- Agregar: `tipoSolicitud` para diferenciar 'viaje' vs 'carga_ftl' vs 'carga_ltl'

#### `wallet_transaction_model.dart`
- Agregar nuevos tipos al enum `TipoTransaccion`:
  `escrowDeposito`, `escrowLiberacion`, `escrowDevolucion`, `escrowComision`,
  `factoraje`, `suscripcion`, `cargaDestacada`

### 4.2 Modelos NUEVOS a crear

| Archivo | Descripción |
|---|---|
| `models/carga_model.dart` | Carga FTL/LTL completa |
| `models/oferta_carga_model.dart` | Oferta de carrier para una carga |
| `models/escrow_model.dart` | Transacción de escrow |
| `models/tracking_carga_model.dart` | Punto de rastreo GPS/ELD |
| `models/valoracion_carga_model.dart` | Valoración multidimensional |
| `models/chat_conversacion_model.dart` | Conversación de chat |
| `models/chat_mensaje_model.dart` | Mensaje individual del chat |
| `models/matching_score_model.dart` | Score de compatibilidad |
| `models/consolidacion_ltl_model.dart` | Consolidación LTL |
| `models/contrato_carga_model.dart` | Contrato recurrente |
| `models/plan_model.dart` | Plan de suscripción |
| `models/suscripcion_model.dart` | Suscripción activa del usuario |
| `models/alerta_usuario_model.dart` | Alerta personalizada |
| `models/kyc_documento_model.dart` | Documento KYC |
| `models/sub_usuario_model.dart` | Sub-usuario (chofer/operador) |
| `models/factura_plataforma_model.dart` | Factura de la plataforma |

---

## 5. CAMBIOS EN SERVICIOS DART

### 5.1 Servicios a MODIFICAR

#### `transport_request_service.dart`
- `createRequest()`: verificar límite de cargas según plan
- `getNearbyDrivers()`: filtrar por tipo de equipo y verificación MC/DOT
- `_enrichOfferData()`: agregar campos de matching_score, mc_dot_verificado

#### `driver_service.dart`
- `fetchNearbyPendingRequests()`: incluir cargas FTL/LTL además de viajes
- `makeOffer()`: verificar si driver tiene plan que permite escrow
- `getDriverAverageRating()`: calcular promedio multidimensional desde `valoraciones_carga`

#### `wallet_service.dart`
- Agregar soporte para nuevos tipos de transacción
- `holdClientFunds()`: usar para depósito en escrow también
- Agregar: `depositarEscrow()`, `liberarEscrow()`, `devolverEscrow()`

#### `auth_service.dart`
- `isDriver()`: mantener lógica
- Agregar: verificación de plan activo

### 5.2 Servicios NUEVOS a crear

| Archivo | Descripción | Métodos clave |
|---|---|---|
| `services/carga_service.dart` | CRUD de cargas | `publicarCarga()`, `getCargasShipper()`, `getCargasDisponibles()`, `actualizarEstado()`, `buscarCarriers()`, `destacarCarga()` |
| `services/oferta_carga_service.dart` | Ofertas de carga | `hacerOferta()`, `aceptarOferta()`, `rechazarOferta()`, `getOfertasCarga()`, `getOfertasCarrier()` |
| `services/escrow_service.dart` | Escrow completo | `crearEscrow()`, `depositarFondos()`, `confirmarEntrega()`, `liberarFondos()`, `abrirDisputa()`, `resolverDisputa()`, `programarLiberacionAuto()` |
| `services/tracking_service.dart` | Rastreo GPS/ELD | `enviarUbicacion()`, `getHistorialTracking()`, `verificarGeocerca()`, `getUltimaUbicacion()`, `conectarELD()` |
| `services/matching_service.dart` | Motor de matching | `calcularScore()`, `getSugerenciasCarrier()`, `getSugerenciasShipper()`, `ejecutarMatchingBatch()` |
| `services/chat_service.dart` | Chat interno | `crearConversacion()`, `enviarMensaje()`, `getConversaciones()`, `getMensajes()`, `marcarLeido()`, `suscribirMensajes()` |
| `services/valoracion_carga_service.dart` | Reputación multidimensional | `calificarCarrier()`, `calificarShipper()`, `getValoracionesCarrier()`, `getValoracionesShipper()`, `getRatingPromedio()`, `asignarNeutralSiVencio()` |
| `services/plan_service.dart` | Planes y suscripciones | `getPlanes()`, `suscribirse()`, `verificarLimites()`, `cancelarSuscripcion()`, `renovarSuscripcion()` |
| `services/alerta_service.dart` | Alertas personalizadas | `crearAlerta()`, `getAlertas()`, `evaluarAlertas()`, `eliminarAlerta()` |
| `services/kyc_service.dart` | KYC/verificación | `subirDocumento()`, `getEstadoKyc()`, `verificarMcDot()` |
| `services/consolidacion_ltl_service.dart` | Cargas parciales LTL | `crearConsolidacion()`, `agregarCarga()`, `optimizarRuta()`, `cerrarConsolidacion()` |
| `services/contrato_carga_service.dart` | Contratos recurrentes | `crearContrato()`, `getContratos()`, `generarCargaRecurrente()` |
| `services/antifraude_service.dart` | Antifraude | `registrarEvento()`, `calcularRiskScore()`, `verificarPatrones()`, `bloquearUsuario()` |
| `services/sub_usuario_service.dart` | Multi-usuario | `crearSubUsuario()`, `getSubUsuarios()`, `revocarAcceso()` |

---

## 6. CAMBIOS EN PROVIDERS DART

### 6.1 Providers a MODIFICAR

#### `auth_provider.dart`
- Agregar campo `plan` con el plan activo del usuario
- `signUp()`: agregar parámetro `tipoCuenta` (shipper/carrier)
- Agregar: `refreshPlan()`, `verificarLimiteCargas()`

#### `transport_provider.dart`
- Este provider maneja viajes de taxi → mantener
- Agregar: referencia al `CargaProvider` para el flujo de carga
- `sendRequest()`: verificar plan antes de publicar

#### `wallet_provider.dart`
- Agregar soporte para nuevos tipos de transacción
- Agregar: `getEscrowActivo()`, `getSaldo()`

### 6.2 Providers NUEVOS a crear

| Archivo | Descripción |
|---|---|
| `providers/carga_provider.dart` | Estado global de publicación y búsqueda de cargas, ofertas activas, filtros |
| `providers/escrow_provider.dart` | Estado del escrow activo, flujo de confirmación |
| `providers/tracking_provider.dart` | Estado del tracking en tiempo real, suscripción a canales Realtime |
| `providers/chat_provider.dart` | Lista de conversaciones, mensajes no leídos, suscripción Realtime |
| `providers/plan_provider.dart` | Plan activo, límites disponibles, verificación de features |
| `providers/matching_provider.dart` | Sugerencias de matching cargadas, estado del algoritmo |

---

## 7. CAMBIOS EN PANTALLAS (SCREENS)

### 7.1 Pantallas a MODIFICAR

#### `screens/login_screen.dart`
- **Sin cambios en el formulario** (email + contraseña + recordarme sigue igual)
- Cambio único: tras login exitoso, el router lee `tipo_usuario` del perfil y redirige a la ruta correcta (5 rutas posibles en vez de 2)

#### `screens/register_screen.dart` — REFACTORING MAYOR
El formulario actual se convierte en un formulario **multi-paso adaptativo**:

**Datos que se CONSERVAN igual (Paso 0 — común a todos):**
- Nombre completo, Email, Contraseña, País, Provincia, Ciudad, Teléfono
- Tipo de documento, Foto frente, Foto dorso

**Cambios en la sección "Tipo de Cuenta" (Paso 1):**
- De 2 opciones (`Cliente` / `Conductor`) a **4 opciones**:
  1. Cliente de viajes → `tipo_usuario = 'cliente_pasajero'` → sin campos extra
  2. Shipper de carga → `tipo_usuario = 'shipper'` → muestra Paso 2B
  3. Transportista → sub-selector → `conductor_pasajeros` o `carrier_carga`
  4. Dispatcher → `tipo_usuario = 'dispatcher'` → muestra Paso 2E

**Nuevas secciones condicionales (aparecen/desaparecen con AnimatedCrossFade):**
- `_buildShipperFields()` — empresa, RUT, mercancías habituales (chips)
- `_buildCarrierFields()` — tipo carrocería, marca, modelo, matrícula, capacidad, seguro, MC/DOT opcional
- `_buildDispatcherFields()` — empresa + lista dinámica de transportistas

**Cambios en `_handleRegister()`:**
- Según tipo, llama `createUserProfile()` (cliente/shipper) o `createDriverProfile()` (conductor/carrier/dispatcher)
- Dispatcher: además llama `DispatcherService().registrarTransportistas(lista)` que crea perfiles `carrier_carga` vinculados y envía emails de invitación
- Redirige a la ruta correcta según `tipo_usuario`

**Nuevo widget para dispatcher — lista dinámica de transportistas:**
- `List<Map<String,dynamic>> _transportistas` (mínimo 1 requerido para poder enviar el form)
- Widget `_TransportistaFormItem` reutilizable: nombre, email, teléfono, tipo carrocería, marca, modelo, matrícula, capacidad, MC/DOT opcional
- Botón `+ Agregar transportista` y botón `×` para eliminar (deshabilitado si solo queda 1)
- Validación al enviar: al menos 1 transportista con nombre + email + teléfono completos

#### `screens/client/profile_screen.dart`
- Agregar: sección de suscripción activa y cambio de plan
- Agregar: sección KYC con estado y documentos
- Agregar: gestión de sub-usuarios (plan Empresarial)
- Agregar: preferencias de alertas

#### `screens/driver/driver_profile_screen.dart`
- Agregar: MC Number, DOT Number con estado de verificación
- Agregar: información de seguro (vigencia)
- Agregar: plan activo y límites
- Agregar: gestión de choferes (dispatcher)
- Agregar: ELD conectado

#### `screens/driver/driver_home_screen.dart`
- Agregar: tab/sección para ver cargas disponibles (además de viajes)
- Agregar: indicador de sugerencias de matching
- Agregar: contador de alertas activas

#### `screens/client/home_map_screen.dart`
- Agregar: acceso a publicar carga (botón/FAB)
- Mantener flujo de taxi existente

#### `screens/driver/incoming_requests_screen.dart`
- Extender para mostrar tanto solicitudes de viaje como cargas disponibles
- Agregar filtros: tipo de equipo, distancia, precio

#### `screens/client/request_history_screen.dart`
- Extender para mostrar historial de cargas además de viajes
- Agregar: estado detallado de escrow por carga

### 7.2 Pantallas NUEVAS a crear

#### Pantallas de CARGA (Shipper)
| Archivo | Descripción |
|---|---|
| `screens/shipper/publicar_carga_screen.dart` | Formulario completo publicación FTL/LTL |
| `screens/shipper/mis_cargas_screen.dart` | Lista de cargas del shipper con estados |
| `screens/shipper/detalle_carga_screen.dart` | Detalle de carga + ofertas recibidas + tracking |
| `screens/shipper/buscar_carriers_screen.dart` | Buscar y filtrar carriers disponibles |
| `screens/shipper/perfil_carrier_screen.dart` | Perfil público del carrier (reputación, historial) |
| `screens/shipper/dashboard_analitico_screen.dart` | Estadísticas: cargas, costos, carriers, tiempos |
| `screens/shipper/cargas_recurrentes_screen.dart` | Gestión de contratos y cargas recurrentes (Empresarial) |

#### Pantallas de CARGA (Carrier/Driver)
| Archivo | Descripción |
|---|---|
| `screens/carrier/cargas_disponibles_screen.dart` | Mapa + lista de cargas disponibles con scores — solo para `carrier_carga` |
| `screens/carrier/detalle_carga_carrier_screen.dart` | Detalle de carga y formulario de oferta |
| `screens/carrier/mis_ofertas_screen.dart` | Ofertas enviadas y su estado |
| `screens/carrier/carga_activa_screen.dart` | Pantalla de carga en tránsito + tracking + QR entrega |
| `screens/carrier/dashboard_carrier_screen.dart` | Estadísticas: ingresos, millas, calificaciones |
| `screens/carrier/perfil_shipper_screen.dart` | Perfil público del shipper (reputación) |

#### Pantallas de DISPATCHER (nuevo árbol de navegación)
| Archivo | Descripción |
|---|---|
| `screens/dispatcher/dispatcher_home_screen.dart` | Panel principal: resumen de flota + cargas activas + alertas |
| `screens/dispatcher/gestionar_choferes_screen.dart` | Lista de transportistas gestionados + estado + ubicación |
| `screens/dispatcher/agregar_transportista_screen.dart` | Formulario para agregar nuevos transportistas al sistema |
| `screens/dispatcher/detalle_transportista_screen.dart` | Perfil, viajes activos y estadísticas de un transportista específico |
| `screens/dispatcher/asignar_carga_screen.dart` | Asignar una carga disponible a un transportista de la flota |
| `screens/dispatcher/mis_cargas_dispatcher_screen.dart` | Todas las cargas gestionadas por el dispatcher + estado |
| `screens/dispatcher/flota_mapa_screen.dart` | Mapa en tiempo real con todas las ubicaciones de los transportistas |

#### Pantallas COMUNES (shipper + carrier + dispatcher)
| Archivo | Descripción |
|---|---|
| `screens/common/chat_screen.dart` | Chat interno por carga |
| `screens/common/chat_lista_screen.dart` | Lista de todas las conversaciones |
| `screens/common/escrow_detalle_screen.dart` | Estado del escrow: depósito, entrega, liberación |
| `screens/common/tracking_mapa_screen.dart` | Mapa en tiempo real de la carga |
| `screens/common/valorar_carga_screen.dart` | Formulario de valoración multidimensional (4 dimensiones × tipo de evaluador) |
| `screens/common/planes_screen.dart` | Comparativo de planes — renderizado distinto según `tipo_usuario` (shipper/carrier/dispatcher) |
| `screens/common/mis_alertas_screen.dart` | Crear/editar/eliminar alertas personalizadas |
| `screens/common/kyc_flow_screen.dart` | Flujo guiado de verificación de identidad |
| `screens/common/disputa_screen.dart` | Abrir y seguir disputas de escrow |

---

## 8. DATOS FALTANTES EN VISTAS/SERVICIOS EXISTENTES

### 8.1 Datos faltantes en `home_map_screen.dart` (cliente)
- No muestra precio por km ni estimado de costo antes de seleccionar vehículo
- No diferencia entre modo "taxi" y modo "carga"
- No muestra el plan activo del usuario ni cargas restantes del mes

### 8.2 Datos faltantes en `driver_home_screen.dart`
- No muestra ganancias del día/semana
- No muestra rating promedio del driver visible en pantalla principal
- No hay indicación de cargas disponibles vs viajes disponibles
- No muestra verificación MC/DOT

### 8.3 Datos faltantes en `incoming_requests_screen.dart`
- No hay filtros por tipo de equipo requerido
- No hay score de matching visible al ver una solicitud de carga
- No hay información sobre el shipper (solo usuario anónimo)
- `precio_oferta` se muestra pero no el desglose (base + espera)

### 8.4 Datos faltantes en `driver_profile_screen.dart`
- MC/DOT no se muestra (campos existen en DB pero no en modelo ni pantalla)
- El rating se calcula con `valoraciones_viaje` (sólo 1 dimensión); la multidimensional no existe
- Plan de suscripción no se muestra
- Historial de cargas completadas no existe (sólo viajes)

### 8.5 Datos faltantes en `profile_screen.dart` (cliente/shipper)
- Sin sección de plan de suscripción
- Sin historial de cargas (solo viajes)
- Sin documentos KYC visibles
- Sin gestión de sub-usuarios

### 8.6 Datos faltantes en `wallet_screen.dart` / `driver_wallet_screen.dart`
- El "balance" actual mezcla wallet de recarga con escrow; debería separarse
- No hay historial filtrado por tipo (escrow vs. suscripción vs. comisión)
- No hay saldo de escrow retenido visible

### 8.7 Datos faltantes en `driver_offers_screen.dart`
- No muestra score de matching para cada oferta
- No indica si el driver tiene MC/DOT verificado
- No muestra dimensiones/peso de la carga

### 8.8 Datos faltantes en `ride_confirmed_screen.dart`
- Para viajes de taxi está bien
- Para cargas: falta tracking mapa, estado del escrow, POD upload

### 8.9 `valoraciones_viaje` (tabla existente)
- Solo tiene 1 campo `rating` (1-5). Para la plataforma de carga necesita las 4 dimensiones
- La nueva tabla `valoraciones_carga` es la correcta; la vieja se mantiene para taxis

---

## 9. PRIORIZACIÓN POR FASES (Roadmap)

> **Leyenda**: ✅ Implementado | ⚠️ Parcial / pendiente completar | ❌ No implementado

### FASE 1 – MVP de Carga (≈ 6 semanas) — 🟡 EN PROGRESO
**Objetivo**: Publicar cargas FTL y recibir ofertas. Sin escrow ni matching.

**Schema**: 
- ✅ `planes` — migración SQL creada (`docs/migrations/013_planes.sql`) con seed de 7 planes + RLS
- ✅ `cargas` — **confirmado en Supabase** (`muevete.cargas`)
  - ✅ Campos Truckstop agregados (`docs/migrations/014_cargas_truckstop_fields.sql`): `nombre_ubicacion_origen/destino`, `cp_origen/destino`, `contacto_origen/destino_nombre/tel`, `commodity_id`, `opciones_equipo[]`, `numeros_referencia[]`, `es_privada`, `horas_anticipacion_publica`
  - 🚫 **Paradas intermedias (`carga_paradas`) — fuera de scope**. Solo se soportan origen + destino en Fase 1 y 2. Paradas múltiples diferidas a integración con Truckstop API (Fase 3+).
- ✅ `ofertas_carga` — **confirmado en Supabase** (`muevete.ofertas_carga`)
- ✅ `app_nom_estado` + `app_dat_estado_carga` — **nuevo sistema de estados auditado** (`docs/migrations/015_estados_carga_nomenclador.sql`)
  - ✅ Catálogo de estados con `codigo`, `nombre`, `orden`, `activo`
  - ✅ Bitácora de cambios: quién (`usuario_uuid`, `driver_id`), cuándo, motivo, metadata
  - ✅ Vista `v_cargas_estado_actual` — estado vigente por carga
  - ✅ Función RPC `fn_cambiar_estado_carga` — toda transición pasa por aquí y sincroniza `cargas.estado`
  - ✅ RLS: lectura para participantes (shipper + carrier asignado por `drivers.uuid`), escritura solo `service_role`
- ❌ `valoraciones_carga` — diferida a Fase 2
- ❌ `kyc_documentos` — diferida a Fase 2

**Modelos**: 
- ✅ `CargaModel` → `lib/models/carga_model.dart` — incluye campos Truckstop: contactos, CP, `commodityId`, `opcionesEquipo`, `numerosReferencia`, `esPrivada`, `horasAnticipacionPublica`; lee campo `estado` sincronizado por RPC
- ✅ `OfertaCargaModel` → `lib/models/oferta_carga_model.dart`
- ✅ `PlanModel` → `lib/models/plan_model.dart`
- ✅ `EstadoCargaModel` + `NomEstadoModel` → `lib/models/estado_carga_model.dart` — fila de bitácora y entrada del nomenclador
- 🔜 `ValoracionCargaModel` — diferido a Fase 2

**Servicios**: 
- ✅ `CargaService` → `lib/services/carga_service.dart`
  - ✅ `publicarCarga()`, `getCargasShipper()`, `getCargasDisponibles()`, `getCargaById()`
  - ✅ `cancelarCarga()`, `actualizarEstado()`, `confirmarRecogida()`, `confirmarEntrega()`, `asignarCargaACarrier()` — todos vía RPC `fn_cambiar_estado_carga`
  - ✅ `getHistorialEstados()` — bitácora completa con JOIN a nomenclador
  - ✅ `getNomEstados()` — catálogo de estados activos
- ✅ `OfertaCargaService` → `lib/services/oferta_carga_service.dart`
  - ✅ `hacerOferta()` — cambia estado a `ofertada` vía RPC
  - ✅ `aceptarOferta()` — asigna carrier y cambia estado a `aceptada` vía RPC
  - ✅ `rechazarOferta()`, `retirarOferta()`, `getOfertasCarga()`, `getOfertasCarrier()`
- ❌ `ValoracionCargaService` — diferido a Fase 2
- ✅ `PlanService` → `lib/services/plan_service.dart` (`getPlanes`, `getTodosLosPlanes`, `getPlanPorCodigo`)

**Providers**: 
- ✅ `CargaProvider` → `lib/providers/carga_provider.dart`
  - ✅ `loadHistorialEstados()`, getters `historialEstados`, `nomEstados`, `loadingHistorial`
  - ✅ `cancelarCarga(usuarioUuid)`, `confirmarRecogida(driverId)`, `confirmarEntrega(driverId)`, `asignarCargaACarrier(usuarioUuid)` — propagan contexto del actor al RPC
- ✅ `PlanProvider` → `lib/providers/plan_provider.dart`

**Pantallas**: 
- ✅ `PublicarCargaScreen` → tab `_PublicarCargaTab` dentro de `shipper_home_screen.dart` — incluye campos Truckstop
- ✅ `MisCargasScreen` → tab `_MisCargasTab` dentro de `shipper_home_screen.dart` — tabla responsiva con todos los campos
- ✅ `DetalleCargaScreen` → `_DetalleCargaScreen` dentro de `shipper_home_screen.dart` — mapa OSRM, campos Truckstop, gestión de ofertas (aceptar/rechazar/cancelar)
- ✅ `CargasDisponiblesScreen` → `lib/screens/carrier/carrier_home_screen.dart` — tabla responsiva con filtros avanzados
- ✅ `DetalleCargaCarrierScreen` → `_DetalleCargaCarrierScreen` dentro de `carrier_home_screen.dart` — mapa OSRM, campos Truckstop, envío de oferta
- ✅ `PlanesScreen` → `lib/screens/common/planes_screen.dart`
- ✅ `RegisterScreen` modificado → `lib/screens/register_screen.dart`
- ⚠️ `ProfileScreen` básico → existe pero sin plan/KYC
- ⚠️ `DriverProfileScreen` básico → existe pero sin MC/DOT ni plan

**Extras FASE 1 ya implementados (por delante del plan):**
- ✅ `DispatcherService` → `lib/services/dispatcher_service.dart`
- ✅ `DispatcherHomeScreen` → `lib/screens/dispatcher/dispatcher_home_screen.dart`
- ✅ `CarrierDirectoryScreen` → `lib/screens/shipper/carrier_directory_screen.dart`
- ✅ `CargoLocationPickerScreen` → `lib/screens/shipper/cargo_location_picker_screen.dart`
- ✅ `RouteMapWidget` → `lib/widgets/route_map_widget.dart` — mapa de ruta OSRM reutilizable
- ✅ `AuthProvider` con 5 tipos de usuario y rutas diferenciadas
- ✅ `LoginScreen` redirige a ruta correcta según `tipo_usuario`
- ✅ `LandingScreen` redirige a `homeRoute` si el usuario ya está autenticado
- ✅ Modelos `UserModel` y `DriverModel` extendidos con `tipoUsuario`, campos shipper/carrier/dispatcher

**Pendiente para CERRAR FASE 1:**
- ⚠️ **Ejecutar en Supabase**: `014_cargas_truckstop_fields.sql` y `015_estados_carga_nomenclador.sql`
- ⚠️ Actualizar `VehicleModel` con campos de camión de carga (`tipoCarroceria`, `capacidadTon`, `tieneGps`, etc.)
- ⚠️ Mostrar historial de estados en `DetalleCargaScreen` (shipper) y `DetalleCargaCarrierScreen` (carrier) usando `CargaProvider.loadHistorialEstados()`
- ⚠️ Verificar flujo completo E2E: shipper publica → carrier ve carga → carrier oferta → shipper acepta oferta → carrier confirma recogida → carrier confirma entrega

**Diferido a Fase 2 (fuera de scope Fase 1):**
- 🔜 `ValoracionCargaModel` + `ValoracionCargaService`
- 🔜 `kyc_documentos` — tabla y flujo KYC
- 🔜 `WalletTransactionModel` — nuevos tipos de transacción (no aplica sin escrow)
- 🔜 Verificación de límites de plan en `publicarCarga()`

**Fuera de scope permanente (decisión de diseño):**
- 🚫 **Paradas intermedias (`carga_paradas`)** — el sistema solo soporta origen + destino. La gestión de rutas multi-parada es responsabilidad de la integración con Truckstop/broker externo (Fase 3+) y no será implementada en la app.

---

### FASE 2 – Gestión de Ofertas + Escrow + Matching básico (≈ 6 semanas) — ❌ NO INICIADA
**Objetivo**: Cerrar el ciclo oferta→aceptación→pago seguro y sugerencias automáticas.

> **Incorporado desde Fase 1:** gestión completa de ofertas (aceptar, rechazar, negociar), valoraciones de carga, KYC.

**Schema**: 
- ❌ `escrow_transacciones`
- ❌ `matching_scores`
- ❌ `suscripciones_usuario`
- ❌ `alertas_usuario`
- ❌ `valoraciones_carga` — movida desde Fase 1
- ❌ `kyc_documentos` — movida desde Fase 1

**Modelos**: 
- ❌ `EscrowModel`
- ❌ `MatchingScoreModel`
- ❌ `SuscripcionModel`
- ❌ `AlertaUsuarioModel`
- ❌ `ValoracionCargaModel` — movido desde Fase 1
- ❌ `KycDocumentoModel` — movido desde Fase 1

**Servicios**: 
- ❌ `EscrowService`
- ❌ `MatchingService`
- ❌ `AlertaService`
- ❌ `ValoracionCargaService` — movido desde Fase 1
- ❌ `KycService` — movido desde Fase 1
- ❌ Completar `OfertaCargaService` con `aceptarOferta()`, `rechazarOferta()`, `negociarPrecio()`

**Providers**: 
- ❌ `EscrowProvider`
- ❌ `MatchingProvider`

**Pantallas**: 
- ❌ `EscrowDetalleScreen`
- ❌ `DisputaScreen`
- ❌ `MisAlertasScreen`
- ❌ `KycFlowScreen`
- ❌ `ValorarCargaScreen`
- ❌ Modificar `DetalleCargaScreen` para incluir gestión de ofertas y escrow

---

### FASE 3 – Tracking GPS + Chat + LTL (≈ 6 semanas) — ❌ NO INICIADA
**Objetivo**: Rastreo en tiempo real, comunicación interna y consolidación de cargas.

**Schema**: 
- ❌ `tracking_carga`
- ❌ `geocercas`
- ❌ `chat_conversaciones`
- ❌ `chat_mensajes`
- ❌ `consolidaciones_ltl`

**Modelos**: 
- ❌ `TrackingCargaModel`
- ❌ `ChatConversacionModel`
- ❌ `ChatMensajeModel`
- ❌ `ConsolidacionLtlModel`

**Servicios**: 
- ❌ `TrackingService`
- ❌ `ChatService`
- ❌ `ConsolidacionLtlService`

**Providers**: 
- ❌ `TrackingProvider`
- ❌ `ChatProvider`

**Pantallas**: 
- ❌ `TrackingMapaScreen`
- ❌ `ChatScreen`
- ❌ `ChatListaScreen`
- ❌ `CargaActivaScreen` (carrier)
- ❌ Modificar `DetalleCargaScreen` para incluir tracking

---

### FASE 4 – Multi-usuario + Contratos + Antifraude (≈ 6 semanas) — 🟡 PARCIALMENTE ADELANTADA
**Objetivo**: Dispatcher con múltiples choferes, contratos recurrentes, seguridad avanzada.

**Schema**: 
- ❌ `sub_usuarios`
- ❌ `contratos_carga`
- ❌ `antifraude_eventos`
- ❌ `facturas_plataforma`

**Modelos**: 
- ❌ `SubUsuarioModel`
- ❌ `ContratoCargaModel`
- ❌ `AntiFraudeEventoModel`
- ❌ `FacturaPlatformaModel`

**Servicios**: 
- ✅ `DispatcherService` → `lib/services/dispatcher_service.dart` (adelantado desde Fase 1)
- ❌ `SubUsuarioService`
- ❌ `ContratoCargaService`
- ❌ `AntiFraudeService`

**Pantallas**: 
- ✅ `DispatcherHomeScreen` → `lib/screens/dispatcher/dispatcher_home_screen.dart` (adelantado)
- ❌ `GestionarChoferesScreen`
- ❌ `CargasRecurrentesScreen`
- ❌ `DashboardCarrierScreen`
- ❌ `DashboardAnaliticoScreen` (shipper)
- ✅ `BuscarCarriersScreen` → `lib/screens/shipper/carrier_directory_screen.dart` (adelantado)
- ❌ `PerfilCarrierScreen`
- ❌ `PerfilShipperScreen`

---

## 10. CONSIDERACIONES TÉCNICAS IMPORTANTES

### 10.1 Retrocompatibilidad
- La tabla `solicitudes_transporte` y el flujo de taxi **NO se toca**. Toda la lógica nueva va en `cargas`.
- La tabla `valoraciones_viaje` se mantiene para taxis; `valoraciones_carga` es la nueva.
- Los servicios existentes (`DriverService`, `TransportRequestService`) **no se eliminan**.

### 10.2 Supabase Realtime
- `cargas`: suscribir a cambios de `estado` para notificaciones en tiempo real
- `tracking_carga`: INSERT stream para mapa en tiempo real (shipper ve al carrier)
- `chat_mensajes`: INSERT stream por `conversacion_id`
- `escrow_transacciones`: UPDATE stream para notificar liberación/disputa
- `ofertas_carga`: INSERT stream por `carga_id` (shipper ve ofertas entrantes)

### 10.3 Límites por plan (verificación en servicio)
```dart
// En CargaService.publicarCarga()
final plan = await PlanService().getPlanActivo(userId);
if (plan.cargasMesMax != null) {
  final count = await getCargasMesActual(userId);
  if (count >= plan.cargasMesMax!) throw PlanLimitException();
}
```

### 10.4 Escrow - Flujo de fondos
```
Shipper deposita → escrow.estado='depositado'
  ↓
Carrier confirma recogida → tracking INSERT
  ↓
GPS entra en geocerca destino → geocerca.disparada_at SET
  ↓
Carrier confirma entrega (QR/manual) → escrow.qr_token verificado
  ↓
Shipper tiene 1h para objetar → timer programado
  ↓
Sin objeción → escrow.liberado_at SET, fondos → wallet_drivers
  ↓
Si disputa → escrow.estado='disputa', fondos congelados
```

### 10.5 Matching Score - Implementación simplificada (servidor)
> El cálculo del score se hace en un Edge Function de Supabase (o RPC PostgreSQL) para evitar exponer lógica en el cliente y garantizar consistencia.

```sql
-- RPC: calcular_matching_score(p_carga_id, p_driver_id)
-- Retorna score 0-100 con todos los componentes
```

### 10.6 Verificación MC/DOT
- Integración con FMCSA SAFER Web API (requiere Edge Function con HTTP call)
- Almacenar resultado en `drivers.mc_dot_verificado` + `drivers.autoridad_fecha`
- Filtro de antigüedad: `autoridad_fecha >= now() - interval '30 days'`

---

## 11. RESUMEN DE ARCHIVOS A CREAR/MODIFICAR

### Archivos SQL (migraciones) — estado real
```
docs/migrations/
  013_planes.sql                        ✅ creado — planes con seed
  014_cargas_truckstop_fields.sql       ✅ creado — campos Truckstop en cargas
  015_estados_carga_nomenclador.sql     ✅ creado — app_nom_estado + app_dat_estado_carga + RPC
  016_escrow.sql                        ❌ pendiente Fase 2
  017_tracking_geocercas.sql            ❌ pendiente Fase 3
  018_chat.sql                          ❌ pendiente Fase 3
  019_valoraciones_carga.sql            ❌ pendiente Fase 2
  020_matching_scores.sql               ❌ pendiente Fase 2
  021_consolidacion_ltl.sql             ❌ pendiente Fase 3
  022_contratos_alertas.sql             ❌ pendiente Fase 4
  023_kyc_antifraude.sql                ❌ pendiente Fase 2
  024_sub_usuarios_facturas.sql         ❌ pendiente Fase 4
  025_alter_users_drivers_vehicles.sql  ❌ pendiente (campos extras drivers/vehicles)
```

### Modelos — estado real
```
lib/models/
  carga_model.dart              ✅ completo + campos Truckstop
  oferta_carga_model.dart       ✅ completo
  plan_model.dart               ✅ completo
  estado_carga_model.dart       ✅ nuevo — EstadoCargaModel + NomEstadoModel
  escrow_model.dart             ❌ pendiente Fase 2
  tracking_carga_model.dart     ❌ pendiente Fase 3
  valoracion_carga_model.dart   ❌ pendiente Fase 2
  chat_conversacion_model.dart  ❌ pendiente Fase 3
  chat_mensaje_model.dart       ❌ pendiente Fase 3
  matching_score_model.dart     ❌ pendiente Fase 2
  consolidacion_ltl_model.dart  ❌ pendiente Fase 3
  contrato_carga_model.dart     ❌ pendiente Fase 4
  suscripcion_model.dart        ❌ pendiente Fase 2
  alerta_usuario_model.dart     ❌ pendiente Fase 2
  kyc_documento_model.dart      ❌ pendiente Fase 2
```

### Servicios — estado real
```
lib/services/
  carga_service.dart              ✅ completo — CRUD + cambios de estado vía RPC + historial
  oferta_carga_service.dart       ✅ completo — hacer/aceptar/rechazar/retirar ofertas
  plan_service.dart               ✅ completo — getPlanes, getTodosLosPlanes, getPlanPorCodigo
  dispatcher_service.dart         ✅ completo (adelantado desde Fase 4)
  escrow_service.dart             ❌ pendiente Fase 2
  tracking_service.dart           ❌ pendiente Fase 3
  matching_service.dart           ❌ pendiente Fase 2
  chat_service.dart               ❌ pendiente Fase 3
  valoracion_carga_service.dart   ❌ pendiente Fase 2
  alerta_service.dart             ❌ pendiente Fase 2
  kyc_service.dart                ❌ pendiente Fase 2
  consolidacion_ltl_service.dart  ❌ pendiente Fase 3
  contrato_carga_service.dart     ❌ pendiente Fase 4
  antifraude_service.dart         ❌ pendiente Fase 4
```

### Providers — estado real
```
lib/providers/
  carga_provider.dart     ✅ completo — misCargas, cargasDisponibles, historialEstados, nomEstados
  plan_provider.dart      ✅ completo
  escrow_provider.dart    ❌ pendiente Fase 2
  tracking_provider.dart  ❌ pendiente Fase 3
  chat_provider.dart      ❌ pendiente Fase 3
  matching_provider.dart  ❌ pendiente Fase 2
```

### Pantallas — estado real
```
lib/screens/
  shipper/
    shipper_home_screen.dart            ✅ completo — tabs: publicar, mis cargas (tabla), detalle+ofertas
    cargo_location_picker_screen.dart   ✅ completo — mapa OSRM para selección de ruta
    carrier_directory_screen.dart       ✅ completo (adelantado)
    perfil_carrier_screen.dart          ❌ pendiente Fase 4
    dashboard_analitico_screen.dart     ❌ pendiente Fase 4
    cargas_recurrentes_screen.dart      ❌ pendiente Fase 4
  carrier/
    carrier_home_screen.dart            ✅ completo — tabla responsiva + filtros + detalle + oferta
    mis_ofertas_screen.dart             ❌ pendiente Fase 1 (post-cierre)
    carga_activa_screen.dart            ❌ pendiente Fase 3
    dashboard_carrier_screen.dart       ❌ pendiente Fase 4
    perfil_shipper_screen.dart          ❌ pendiente Fase 4
  dispatcher/
    dispatcher_home_screen.dart         ✅ completo (adelantado desde Fase 4)
    gestionar_choferes_screen.dart      ❌ pendiente Fase 4
    asignar_carga_screen.dart           ❌ pendiente Fase 4
    flota_mapa_screen.dart              ❌ pendiente Fase 4
  common/
    planes_screen.dart                  ✅ completo
    chat_screen.dart                    ❌ pendiente Fase 3
    chat_lista_screen.dart              ❌ pendiente Fase 3
    escrow_detalle_screen.dart          ❌ pendiente Fase 2
    tracking_mapa_screen.dart           ❌ pendiente Fase 3
    valorar_carga_screen.dart           ❌ pendiente Fase 2
    mis_alertas_screen.dart             ❌ pendiente Fase 2
    kyc_flow_screen.dart                ❌ pendiente Fase 2
    disputa_screen.dart                 ❌ pendiente Fase 2
  widgets/
    route_map_widget.dart               ✅ nuevo — mapa OSRM reutilizable (carrier + shipper)
```

### Archivos modificados
```
lib/models/
  user_model.dart                ← agregar tipo_usuario, campos shipper
  driver_model.dart              ← agregar tipo_usuario, dispatcher_id, campos carrier
  vehicle_model.dart             ← agregar campos camión de carga
  transport_request_model.dart   ← agregar tipo_solicitud (discriminador viaje/carga)
  wallet_transaction_model.dart  ← agregar nuevos tipos de transacción

lib/services/
  transport_request_service.dart  ← filtrar por tipo_solicitud='viaje' siempre
  driver_service.dart             ← fetchNearbyPendingRequests filtra por tipo_usuario
  wallet_service.dart             ← nuevos tipos de transacción
  auth_service.dart               ← isDriver() ahora también distingue conductor vs carrier vs dispatcher
                                    createDriverProfile() acepta tipo_usuario
                                    createUserProfile() acepta tipo_usuario

lib/services/ (NUEVO)
  dispatcher_service.dart         ← registrarTransportistas(), getTransportistas(), asignarCarga()

lib/providers/
  auth_provider.dart              ← _loadProfile() determina 5 tipos de ruta
                                    signUp() acepta tipoUsuario + datos condicionales
                                    getter tipoUsuario, isShipper, isCarrierCarga, isDispatcher
  wallet_provider.dart            ← escrow balance separado del balance libre

lib/screens/
  login_screen.dart               ← solo cambia la redirección post-login (5 rutas)
  register_screen.dart            ← refactoring mayor (ver sección 7.1)
  client/profile_screen.dart      ← suscripción, KYC (solo para cliente_pasajero)
  client/home_map_screen.dart     ← sin cambios (solo para cliente_pasajero)
  client/request_history_screen.dart ← sin cambios (solo para cliente_pasajero)
  driver/driver_profile_screen.dart  ← MC/DOT, plan (solo para conductor_pasajeros)
  driver/driver_home_screen.dart     ← sin cambios (solo para conductor_pasajeros)
  driver/incoming_requests_screen.dart ← sin cambios (solo para conductor_pasajeros)
```

### Nueva ruta de navegación en `main.dart` / `app_router.dart`
```dart
// Nuevas rutas a agregar:
'/shipper/home'              → ShipperHomeScreen
'/shipper/publicar-carga'   → PublicarCargaScreen
'/shipper/mis-cargas'       → MisCargasScreen
'/carrier/home'             → CarrierHomeScreen   (cargas_disponibles)
'/dispatcher/home'          → DispatcherHomeScreen
'/dispatcher/choferes'      → GestionarChoferesScreen
'/planes'                   → PlanesScreen  (recibe tipo_usuario como argumento)
```

### Nuevo servicio necesario para el registro de dispatcher
```dart
// lib/services/dispatcher_service.dart
class DispatcherService {
  // Crea los perfiles carrier_carga en muevete.drivers,
  // los vincula en sub_usuarios con estado 'pendiente',
  // y dispara email de activación para cada uno.
  Future<void> registrarTransportistas(
    String dispatcherUuid,
    int dispatcherDriverId,
    List<Map<String, dynamic>> transportistas,
  ) async { ... }

  // Invita a un nuevo transportista post-registro
  Future<void> invitarTransportista(
    int dispatcherDriverId,
    Map<String, dynamic> datosTransportista,
  ) async { ... }

  Future<List<Map<String,dynamic>>> getTransportistas(int dispatcherDriverId) async { ... }
  Future<void> revocarTransportista(int subUsuarioId) async { ... }
}
```

---

*Documento generado para la planificación completa de la transformación de Muevete de ride-hailing urbano a plataforma de carga freight.*
