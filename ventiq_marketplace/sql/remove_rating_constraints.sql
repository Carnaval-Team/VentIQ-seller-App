-- Eliminar constraint unique para rating de tienda
ALTER TABLE public.app_dat_tienda_rating 
DROP CONSTRAINT IF EXISTS app_dat_tienda_rating_id_tienda_id_usuario_key;

-- Eliminar constraint unique para rating de producto
ALTER TABLE public.app_dat_producto_rating 
DROP CONSTRAINT IF EXISTS app_dat_producto_rating_id_producto_id_usuario_key;
