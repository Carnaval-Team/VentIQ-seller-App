-- =====================================================
-- TRIGGER PARA NOTIFICAR NUEVA VERSIÓN DE APP
-- =====================================================
-- Este trigger se ejecuta cuando se inserta una nueva versión en app_versiones
-- y envía notificaciones a todos los usuarios de la app correspondiente

-- =====================================================
-- FUNCIÓN DEL TRIGGER
-- =====================================================

CREATE OR REPLACE FUNCTION fn_notificar_nueva_version()
RETURNS TRIGGER AS $$
DECLARE
  v_user_record RECORD;
  v_mensaje TEXT;
  v_titulo TEXT;
  v_data JSONB;
  v_tipo_notificacion VARCHAR;
  v_prioridad VARCHAR;
  v_color VARCHAR;
  v_icono VARCHAR;
  v_count INTEGER := 0;
BEGIN
  -- Construir el título de la notificación
  v_titulo := '🎉 Nueva Versión Disponible';
  
  -- Construir el mensaje personalizado
  v_mensaje := format(
    'Una nueva versión de %s está disponible! 📱

📦 Versión: %s
🔢 Build: %s
📅 Lanzamiento: %s

%s

💡 Puedes actualizar desde Ajustes > Buscar Actualizaciones o dejar que tu dispositivo la descargue automáticamente.

ℹ️ Versión mínima requerida: %s',
    CASE 
      WHEN NEW.app_name = 'ventiq_app' THEN 'Inventtia'
      WHEN NEW.app_name = 'ventiq_admin' THEN 'Vendedor Admin'
      ELSE NEW.app_name
    END,
    NEW.version_actual,
    NEW.build_number,
    to_char(NEW.fecha_lanzamiento, 'DD/MM/YYYY'),
    CASE 
      WHEN NEW.actualizacion_obligatoria THEN '⚠️ ACTUALIZACIÓN OBLIGATORIA - Es necesario actualizar para continuar usando la aplicación.'
      ELSE '✨ Actualización recomendada para disfrutar de las últimas mejoras y correcciones.'
    END,
    NEW.version_minima
  );
  
  -- Configurar tipo de notificación según si es obligatoria
  IF NEW.actualizacion_obligatoria THEN
    v_tipo_notificacion := 'warning';
    v_prioridad := 'urgente';
    v_color := '#FF6B6B';
    v_icono := 'warning';
  ELSE
    v_tipo_notificacion := 'sistema';
    v_prioridad := 'alta';
    v_color := '#4CAF50';
    v_icono := 'system_update';
  END IF;
  
  -- Construir data JSON con información de la versión
  v_data := jsonb_build_object(
    'app_name', NEW.app_name,
    'version_actual', NEW.version_actual,
    'version_minima', NEW.version_minima,
    'build_number', NEW.build_number,
    'actualizacion_obligatoria', NEW.actualizacion_obligatoria,
    'fecha_lanzamiento', NEW.fecha_lanzamiento,
    'accion', 'actualizar_app'
  );
  
  -- Determinar a qué usuarios notificar según la app
  IF NEW.app_name = 'ventiq_app' THEN
    -- Notificar a todos los vendedores
    FOR v_user_record IN 
      SELECT DISTINCT v.uuid
      FROM public.app_dat_vendedor v
      WHERE v.uuid IS NOT NULL
    LOOP
      -- Crear notificación para cada vendedor
      PERFORM fn_crear_notificacion(
        p_user_id := v_user_record.uuid,
        p_tipo := v_tipo_notificacion,
        p_titulo := v_titulo,
        p_mensaje := v_mensaje,
        p_data := v_data,
        p_prioridad := v_prioridad,
        p_accion := 'ir_a_ajustes',
        p_icono := v_icono,
        p_color := v_color,
        p_fecha_expiracion := NULL
      );
      
      v_count := v_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Notificaciones enviadas a % vendedores para %', v_count, NEW.app_name;
    
  ELSIF NEW.app_name = 'ventiq_admin' THEN
    -- Notificar a todos los gerentes
    FOR v_user_record IN 
      SELECT DISTINCT g.uuid
      FROM public.app_dat_gerente g
      WHERE g.uuid IS NOT NULL
    LOOP
      -- Crear notificación para cada gerente
      PERFORM fn_crear_notificacion(
        p_user_id := v_user_record.uuid,
        p_tipo := v_tipo_notificacion,
        p_titulo := v_titulo,
        p_mensaje := v_mensaje,
        p_data := v_data,
        p_prioridad := v_prioridad,
        p_accion := 'ir_a_ajustes',
        p_icono := v_icono,
        p_color := v_color,
        p_fecha_expiracion := NULL
      );
      
      v_count := v_count + 1;
    END LOOP;
    
    RAISE NOTICE 'Notificaciones enviadas a % gerentes para %', v_count, NEW.app_name;
    
  ELSE
    RAISE NOTICE 'App desconocida: %. No se enviaron notificaciones.', NEW.app_name;
  END IF;
  
  RETURN NEW;
  
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Error al enviar notificaciones de nueva versión: %', SQLERRM;
  RETURN NEW; -- Continuar con la inserción aunque falle la notificación
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- CREAR EL TRIGGER
-- =====================================================

DROP TRIGGER IF EXISTS trigger_notificar_nueva_version ON public.app_versiones;

CREATE TRIGGER trigger_notificar_nueva_version
  AFTER INSERT ON public.app_versiones
  FOR EACH ROW
  WHEN (NEW.activa = true) -- Solo notificar si la versión está activa
  EXECUTE FUNCTION fn_notificar_nueva_version();

-- =====================================================
-- COMENTARIOS
-- =====================================================

COMMENT ON FUNCTION fn_notificar_nueva_version() IS 
'Función trigger que envía notificaciones a usuarios cuando se registra una nueva versión de la app.
- Para ventiq_app: notifica a todos los vendedores (app_dat_vendedor)
- Para ventiq_admin: notifica a todos los gerentes (app_dat_gerente)
- Diferencia entre actualizaciones obligatorias y opcionales
- Incluye información completa de la versión en el mensaje';

COMMENT ON TRIGGER trigger_notificar_nueva_version ON public.app_versiones IS
'Trigger que se ejecuta después de insertar una nueva versión activa en app_versiones.
Envía notificaciones automáticas a todos los usuarios de la aplicación correspondiente.';

-- =====================================================
-- EJEMPLO DE USO
-- =====================================================

-- Insertar una nueva versión de ventiq_app (notificará a todos los vendedores)
/*
INSERT INTO public.app_versiones (
  app_name,
  version_actual,
  version_minima,
  build_number,
  actualizacion_obligatoria,
  fecha_lanzamiento,
  activa
) VALUES (
  'ventiq_app',
  '1.4.2',
  '1.4.0',
  402,
  false,
  NOW(),
  true
);
*/

-- Insertar una nueva versión de ventiq_admin (notificará a todos los gerentes)
/*
INSERT INTO public.app_versiones (
  app_name,
  version_actual,
  version_minima,
  build_number,
  actualizacion_obligatoria,
  fecha_lanzamiento,
  activa
) VALUES (
  'ventiq_admin',
  '2.1.0',
  '2.0.0',
  210,
  true,
  NOW(),
  true
);
*/
