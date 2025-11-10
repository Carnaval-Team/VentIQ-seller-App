-- =====================================================
-- TABLAS DE RATING PARA MARKETPLACE VENTIQ
-- =====================================================

-- Tabla de ratings de tiendas
CREATE TABLE IF NOT EXISTS public.app_dat_tienda_rating (
    id BIGSERIAL PRIMARY KEY,
    id_tienda BIGINT NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
    id_usuario UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    rating NUMERIC(2,1) NOT NULL CHECK (rating >= 1.0 AND rating <= 5.0),
    comentario TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraint para evitar múltiples ratings del mismo usuario a la misma tienda
    UNIQUE(id_tienda, id_usuario)
);

-- Índices para optimizar consultas
CREATE INDEX IF NOT EXISTS idx_tienda_rating_tienda ON public.app_dat_tienda_rating(id_tienda);
CREATE INDEX IF NOT EXISTS idx_tienda_rating_usuario ON public.app_dat_tienda_rating(id_usuario);
CREATE INDEX IF NOT EXISTS idx_tienda_rating_created ON public.app_dat_tienda_rating(created_at DESC);

-- Comentarios
COMMENT ON TABLE public.app_dat_tienda_rating IS 'Ratings y reseñas de tiendas por usuarios del marketplace';
COMMENT ON COLUMN public.app_dat_tienda_rating.rating IS 'Calificación de 1.0 a 5.0';
COMMENT ON COLUMN public.app_dat_tienda_rating.comentario IS 'Comentario opcional del usuario';

-- =====================================================

-- Tabla de ratings de productos
CREATE TABLE IF NOT EXISTS public.app_dat_producto_rating (
    id BIGSERIAL PRIMARY KEY,
    id_producto BIGINT NOT NULL REFERENCES public.app_dat_producto(id) ON DELETE CASCADE,
    id_usuario UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    rating NUMERIC(2,1) NOT NULL CHECK (rating >= 1.0 AND rating <= 5.0),
    comentario TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraint para evitar múltiples ratings del mismo usuario al mismo producto
    UNIQUE(id_producto, id_usuario)
);

-- Índices para optimizar consultas
CREATE INDEX IF NOT EXISTS idx_producto_rating_producto ON public.app_dat_producto_rating(id_producto);
CREATE INDEX IF NOT EXISTS idx_producto_rating_usuario ON public.app_dat_producto_rating(id_usuario);
CREATE INDEX IF NOT EXISTS idx_producto_rating_created ON public.app_dat_producto_rating(created_at DESC);

-- Comentarios
COMMENT ON TABLE public.app_dat_producto_rating IS 'Ratings y reseñas de productos por usuarios del marketplace';
COMMENT ON COLUMN public.app_dat_producto_rating.rating IS 'Calificación de 1.0 a 5.0';
COMMENT ON COLUMN public.app_dat_producto_rating.comentario IS 'Comentario opcional del usuario';

-- =====================================================
-- TRIGGERS PARA UPDATED_AT
-- =====================================================

-- Función para actualizar updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger para tienda_rating
DROP TRIGGER IF EXISTS update_tienda_rating_updated_at ON public.app_dat_tienda_rating;
CREATE TRIGGER update_tienda_rating_updated_at
    BEFORE UPDATE ON public.app_dat_tienda_rating
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger para producto_rating
DROP TRIGGER IF EXISTS update_producto_rating_updated_at ON public.app_dat_producto_rating;
CREATE TRIGGER update_producto_rating_updated_at
    BEFORE UPDATE ON public.app_dat_producto_rating
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- RLS POLICIES
-- =====================================================

-- Habilitar RLS
ALTER TABLE public.app_dat_tienda_rating ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_producto_rating ENABLE ROW LEVEL SECURITY;

-- Políticas para tienda_rating
DROP POLICY IF EXISTS "Usuarios pueden ver todos los ratings de tiendas" ON public.app_dat_tienda_rating;
CREATE POLICY "Usuarios pueden ver todos los ratings de tiendas"
    ON public.app_dat_tienda_rating FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Usuarios pueden crear sus propios ratings de tiendas" ON public.app_dat_tienda_rating;
CREATE POLICY "Usuarios pueden crear sus propios ratings de tiendas"
    ON public.app_dat_tienda_rating FOR INSERT
    WITH CHECK (auth.uid() = id_usuario);

DROP POLICY IF EXISTS "Usuarios pueden actualizar sus propios ratings de tiendas" ON public.app_dat_tienda_rating;
CREATE POLICY "Usuarios pueden actualizar sus propios ratings de tiendas"
    ON public.app_dat_tienda_rating FOR UPDATE
    USING (auth.uid() = id_usuario);

DROP POLICY IF EXISTS "Usuarios pueden eliminar sus propios ratings de tiendas" ON public.app_dat_tienda_rating;
CREATE POLICY "Usuarios pueden eliminar sus propios ratings de tiendas"
    ON public.app_dat_tienda_rating FOR DELETE
    USING (auth.uid() = id_usuario);

-- Políticas para producto_rating
DROP POLICY IF EXISTS "Usuarios pueden ver todos los ratings de productos" ON public.app_dat_producto_rating;
CREATE POLICY "Usuarios pueden ver todos los ratings de productos"
    ON public.app_dat_producto_rating FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Usuarios pueden crear sus propios ratings de productos" ON public.app_dat_producto_rating;
CREATE POLICY "Usuarios pueden crear sus propios ratings de productos"
    ON public.app_dat_producto_rating FOR INSERT
    WITH CHECK (auth.uid() = id_usuario);

DROP POLICY IF EXISTS "Usuarios pueden actualizar sus propios ratings de productos" ON public.app_dat_producto_rating;
CREATE POLICY "Usuarios pueden actualizar sus propios ratings de productos"
    ON public.app_dat_producto_rating FOR UPDATE
    USING (auth.uid() = id_usuario);

DROP POLICY IF EXISTS "Usuarios pueden eliminar sus propios ratings de productos" ON public.app_dat_producto_rating;
CREATE POLICY "Usuarios pueden eliminar sus propios ratings de productos"
    ON public.app_dat_producto_rating FOR DELETE
    USING (auth.uid() = id_usuario);
