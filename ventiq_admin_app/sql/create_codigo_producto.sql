CREATE TABLE IF NOT EXISTS public.codigo_producto (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_producto bigint NOT NULL REFERENCES public.app_dat_producto(id) ON DELETE CASCADE,

  -- Código completo y tipo
  codigo_barras varchar NOT NULL,
  tipo_codigo varchar NOT NULL,           -- 'EAN-13', 'EAN-8', 'UPC-A', 'UPC-E', 'Code-128', 'QR Code', etc.

  -- Dígitos desglosados (parseados del código de barras)
  prefijo_pais varchar,                   -- EAN-13: primeros 3 dígitos (ej: '779' = Argentina)
  codigo_fabricante varchar,              -- EAN-13: dígitos 4-7 | UPC-A: dígitos 2-6
  codigo_producto varchar,               -- EAN-13: dígitos 8-12 | UPC-A: dígitos 7-11
  digito_control varchar,                -- Último dígito de verificación
  numero_sistema varchar,                -- UPC-A: primer dígito (tipo de producto)

  -- Datos interpretados
  pais_origen varchar,                   -- Nombre del país según prefijo (ej: 'Argentina')
  fabricante varchar,                    -- Nombre del fabricante (si se conoce)
  descripcion varchar,

  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

CREATE INDEX idx_codigo_producto_barras ON public.codigo_producto(codigo_barras);
CREATE INDEX idx_codigo_producto_producto ON public.codigo_producto(id_producto);
CREATE INDEX idx_codigo_producto_fabricante ON public.codigo_producto(codigo_fabricante);
CREATE INDEX idx_codigo_producto_prefijo_pais ON public.codigo_producto(prefijo_pais);
