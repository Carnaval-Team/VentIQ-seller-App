# Cambios en Supabase — Paradas durante el viaje y cobro por tiempo de espera

## 1. Nueva tabla: `muevete.paradas_viaje`

Registra cada parada que el chofer agrega durante un viaje activo.

```sql
CREATE TABLE muevete.paradas_viaje (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_viaje bigint NOT NULL,
  driver_id bigint NOT NULL,
  latitud double precision NOT NULL,
  longitud double precision NOT NULL,
  direccion text,                          -- dirección legible (opcional)
  tiempo_detenido integer DEFAULT 0,       -- segundos totales detenido (se actualiza al salir)
  created_at timestamp with time zone NOT NULL DEFAULT now(),  -- momento de llegada a la parada
  salida_at timestamp with time zone,      -- momento de salida (NULL mientras está detenido)
  CONSTRAINT paradas_viaje_pkey PRIMARY KEY (id),
  CONSTRAINT paradas_viaje_viaje_fkey FOREIGN KEY (id_viaje) REFERENCES muevete.viajes(id),
  CONSTRAINT paradas_viaje_driver_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id)
);
```

### Flujo:
1. Chofer llega a la parada → **INSERT** con `created_at = now()`, `salida_at = NULL`, `tiempo_detenido = 0`
2. Chofer sale de la parada → **UPDATE** `salida_at = now()`, `tiempo_detenido = EXTRACT(EPOCH FROM (now() - created_at))::integer`
3. Al completar el viaje se suman todos los `tiempo_detenido` de las paradas del viaje para calcular el cobro extra.

---

## 2. Nueva columna en `muevete.vehicle_type`

Precio por minuto de espera, configurable por tipo de vehículo.

```sql
ALTER TABLE muevete.vehicle_type
  ADD COLUMN precio_espera_minuto numeric DEFAULT 0;
```

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `precio_espera_minuto` | numeric | Precio a cobrar por cada minuto de espera en paradas |

> Este valor debe mostrarse al cliente en la pantalla de confirmación del viaje y en el resumen final, para evitar malentendidos.

---

## 3. Cálculo del cobro por espera al completar viaje

```
total_segundos_espera = SUM(tiempo_detenido) de todas las paradas del viaje
total_minutos_espera  = CEIL(total_segundos_espera / 60)
cobro_espera          = total_minutos_espera * vehicle_type.precio_espera_minuto
cobro_total           = cobro_viaje_base + cobro_espera
```

---

## 4. RLS (Row Level Security) sugerido

```sql
-- Los choferes solo pueden ver/crear/editar paradas de sus propios viajes
ALTER TABLE muevete.paradas_viaje ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_manage_own_stops" ON muevete.paradas_viaje
  FOR ALL
  USING (
    driver_id IN (SELECT id FROM muevete.drivers WHERE uuid = auth.uid())
  );

-- Los clientes pueden ver las paradas de sus viajes (solo lectura)
CREATE POLICY "user_view_trip_stops" ON muevete.paradas_viaje
  FOR SELECT
  USING (
    id_viaje IN (SELECT id FROM muevete.viajes WHERE "user" = auth.uid()::text)
  );
```

---

## 5. Resumen de cambios

| Acción | Objeto | Detalle |
|--------|--------|---------|
| **CREATE TABLE** | `muevete.paradas_viaje` | Tabla nueva para registrar paradas |
| **ALTER TABLE** | `muevete.vehicle_type` | Agregar columna `precio_espera_minuto` |
| **RLS** | `muevete.paradas_viaje` | Políticas para chofer y cliente |

---

## 6. Cambios en la app (Flutter)

- **Chofer (active_trip_screen):** Botón para agregar parada → inserta en `paradas_viaje`, inicia timer local, al salir hace UPDATE con `tiempo_detenido` y `salida_at`.
- **Cliente (ride_confirmed_screen):** Mostrar `precio_espera_minuto` del tipo de vehículo para transparencia.
- **Completar viaje:** Sumar todos los `tiempo_detenido` → calcular cobro extra → mostrar desglose al cliente (base + espera = total).
- **Modelo VehicleTypeModel:** Agregar campo `precioEsperaMinuto`.
