-- ============================================================================
-- 044_taxi_documento_contacto_emergencia.sql
-- Documento legal para la DECLARACIÓN DE AUTORIZACIÓN del contacto de emergencia.
--
-- POR QUÉ
--   El alta de un contacto de emergencia usa el teléfono de un TERCERO. El anexo
--   08 exige que el usuario declare explícitamente que tiene autorización de esa
--   persona y que la declaración quede registrada en `consentimientos`.
--   La app ya llama a `fn_aceptar_consentimiento('contacto_emergencia', ...)`
--   al dar de alta el contacto, pero ese `codigo` NO existía en
--   `documentos_legales`, así que la RPC fallaba con `documento_no_existe` y la
--   pantalla degradaba en silencio (no bloqueaba el alta, pero no dejaba rastro).
--
-- DECISIÓN CLAVE: `es_obligatorio = FALSE`
--   El gate (`fn_usuario_habilitado`) exige TODOS los documentos con
--   `publicado AND es_obligatorio`. Si este documento fuera obligatorio, se
--   convertiría en un consentimiento previo al viaje para todo el mundo y
--   volvería a bloquear a todos los usuarios. No es eso: es una declaración que
--   se firma **en el momento de alta del contacto**, no una condición de uso.
--   Por eso se publica como NO obligatorio: la RPC lo acepta (sólo exige
--   `publicado` y vigente) y el gate lo ignora.
--
-- IDEMPOTENCIA
--   INSERT ... WHERE NOT EXISTS (codigo = 'contacto_emergencia').
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('muevete.documentos_legales') IS NULL THEN
    RAISE EXCEPTION 'falta la tabla muevete.documentos_legales (036)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'muevete' AND p.proname = 'fn_aceptar_consentimiento'
  ) THEN
    RAISE EXCEPTION 'falta muevete.fn_aceptar_consentimiento (036)';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Documento (no obligatorio: se firma al alta del contacto)
--    `hash_contenido` lo pone el trigger `trg_documentos_legales_hash`.
-- ----------------------------------------------------------------------------
INSERT INTO muevete.documentos_legales
  (codigo, version, titulo, resumen, contenido_md,
   es_obligatorio, publicado, vigente_desde, vigente_hasta)
SELECT
  'contacto_emergencia',
  '1.0.0',
  'Autorización del contacto de emergencia',
  'Declaras que tienes autorización de la persona cuyo teléfono registras como contacto de emergencia.',
  $md$# AUTORIZACIÓN DEL CONTACTO DE EMERGENCIA

## 1. Qué estás declarando
Al registrar un **contacto de emergencia** en Muévete estás indicando el nombre y
el teléfono de **otra persona**. Con esta declaración confirmas que:

- tienes **autorización de esa persona** para usar su número con este fin;
- esa persona sabe que, si activas una alerta durante un viaje, **recibirá un
  aviso** con tu ubicación, los datos del viaje y un pedido de ayuda;
- si esa persona te pide que la elimines de tu lista, lo harás, y nosotros
  eliminaremos el contacto de tu cuenta.

## 2. Para qué usamos ese número
**Solo** para avisarle si activas una emergencia durante un viaje. No lo usamos
para publicidad, no lo vendemos y no lo compartimos con el conductor ni con
terceros ajenos a la alerta.

## 3. Qué pasa con el número
Se guarda asociado a tu cuenta mientras lo mantengas registrado. Puedes
cambiarlo o eliminarlo cuando quieras desde **Perfil → Mi seguridad → Contactos
de emergencia**. Al eliminarlo, deja de ser usado de inmediato.

## 4. Límites del servicio
El aviso a tu contacto es **un apoyo**, no un servicio de emergencia: no
sustituye a llamar a la policía ni a los servicios de urgencia. Si estás en
peligro, llama primero a los números de emergencia.

## 5. Registro de esta declaración
Guardamos la fecha y hora, la versión de este texto, la versión de la aplicación
y el dispositivo desde el que aceptaste. No puedes modificar ese registro: es la
prueba de que diste tu autorización.
$md$,
  false,
  true,
  now(),
  NULL
WHERE NOT EXISTS (
  SELECT 1 FROM muevete.documentos_legales
   WHERE codigo = 'contacto_emergencia' AND version = '1.0.0'
);

-- ----------------------------------------------------------------------------
-- 2. Guarda: el documento debe quedar publicado, NO obligatorio y con hash
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_doc muevete.documentos_legales%ROWTYPE;
BEGIN
  SELECT * INTO v_doc FROM muevete.documentos_legales
   WHERE codigo = 'contacto_emergencia' AND version = '1.0.0';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no se insertó contacto_emergencia@1.0.0';
  END IF;
  IF NOT v_doc.publicado THEN
    RAISE EXCEPTION 'contacto_emergencia debe estar publicado';
  END IF;
  IF v_doc.es_obligatorio THEN
    RAISE EXCEPTION 'contacto_emergencia NO debe ser obligatorio: bloquearía el gate de todos los usuarios';
  END IF;
  IF v_doc.hash_contenido IS NULL OR length(v_doc.hash_contenido) <> 64 THEN
    RAISE EXCEPTION 'hash_contenido ausente o inválido (revisar trigger trg_documentos_legales_hash)';
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Documento:
--   SELECT codigo, version, publicado, es_obligatorio, vigente_hasta IS NULL AS vigente,
--          length(contenido_md) AS largo, left(contenido_md, 60) AS inicio,
--          length(hash_contenido) AS hash_largo
--     FROM muevete.documentos_legales WHERE codigo = 'contacto_emergencia';
--   -- esperado: publicado=true, es_obligatorio=false, vigente=true, hash 64
--
-- 2) El gate NO lo exige (no debe aparecer en faltantes):
--   SELECT muevete.fn_usuario_habilitado() -> 'consentimiento' AS consentimiento;
--
-- 3) La declaración SÍ se puede firmar (como usuario autenticado):
--   SELECT muevete.fn_aceptar_consentimiento('contacto_emergencia','1.0.0','app','test','test','{}'::jsonb);
--   -- esperado: success=true
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- DELETE FROM muevete.documentos_legales
--  WHERE codigo = 'contacto_emergencia' AND version = '1.0.0'
--    AND NOT EXISTS (SELECT 1 FROM muevete.consentimientos c
--                     WHERE c.documento_codigo = 'contacto_emergencia');
-- ============================================================================