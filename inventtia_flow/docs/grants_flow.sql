-- Grants mínimos para que el cliente Flutter (con anon key) pueda acceder
-- al esquema flow. El usuario anonimo necesita USAGE para poder iniciar sesión
-- y ejecutar funciones auth. El usuario autenticado (rol authenticated) es el
-- que realmente consulta las tablas y ejecuta las RPCs.

-- 1. Permiso para usar el schema
GRANT USAGE ON SCHEMA flow TO anon;
GRANT USAGE ON SCHEMA flow TO authenticated;

-- 2. Permisos sobre las tablas (lectura/escritura según corresponda a las RLS)
-- Nota: las RLS policies deben controlar qué filas puede ver/modificar cada usuario.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA flow TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA flow TO anon;

-- 3. Permisos sobre las secuencias (para inserts con IDs autoincrementales)
GRANT USAGE ON ALL SEQUENCES IN SCHEMA flow TO authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA flow TO anon;

-- 4. Permisos para ejecutar funciones/RPCs del schema
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA flow TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA flow TO anon;

-- 5. Permisos para tablas futuras (aplica a objetos creados después de ejecutar este script)
ALTER DEFAULT PRIVILEGES IN SCHEMA flow
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA flow
GRANT USAGE ON SEQUENCES TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA flow
GRANT EXECUTE ON FUNCTIONS TO authenticated;
