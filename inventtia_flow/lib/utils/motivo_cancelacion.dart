/// Reglas del **motivo de cancelación** de una reserva (punto 2 del plan
/// `PLAN_PRECIOS_PAGOS_CALENDARIO.md`, §3.1).
///
/// Vive aparte de la UI a propósito: es lo único de la cancelación con motivo
/// que se puede probar sin Supabase ni widgets. La pantalla solo pinta el
/// resultado de estas funciones; las reglas (mínimo/máximo y textos) están aquí
/// y en `flow.staff_marcar_estado_agenda` / `flow.staff_cancelar_reserva`
/// (migración 61), que es quien manda de verdad.
library;

/// Longitud mínima del motivo (ya recortado con `trim`).
///
/// El servidor solo exige que **no** esté vacío, pero un «ok» o un «.» no le
/// sirven al cliente para entender por qué le quitaron la reserva. Tres
/// caracteres es el mínimo que deja escribir algo con sentido.
const int motivoCancelacionMinLength = 3;

/// Longitud máxima: coincide con el `maxLength` del campo del diálogo y con el
/// límite razonable de una columna `text` que se pinta en una tarjeta.
const int motivoCancelacionMaxLength = 500;

/// Valida el motivo y devuelve el **mensaje de error** para el campo, o `null`
/// si es válido.
///
/// Se usa tal cual como `errorText` del `TextField` del diálogo, así que el
/// texto tiene que ser lo que leería la persona que está cancelando.
String? validarMotivo(String? motivo) {
  final texto = (motivo ?? '').trim();
  if (texto.isEmpty) return 'Escribe el motivo de la cancelación.';
  if (texto.length < motivoCancelacionMinLength) {
    return 'El motivo debe tener al menos $motivoCancelacionMinLength caracteres.';
  }
  if (texto.length > motivoCancelacionMaxLength) {
    return 'El motivo no puede superar los $motivoCancelacionMaxLength caracteres.';
  }
  return null;
}

/// Traduce el fallo de cualquiera de los RPC de cancelación a algo que se
/// entienda en un `SnackBar`.
///
/// El servidor contesta en `español sin tildes` (migración 61) y, cuando la
/// migración **no** está aplicada, PostgREST contesta «Could not find the
/// function … (p_motivo)». Ese caso es el más importante: sin esta traducción
/// el usuario ve un error técnico y no sabe que falta un paso en la base de
/// datos. El resto de mensajes ya son legibles, así que solo se limpia el
/// prefijo `Exception: `.
String mensajeErrorCancelacion(Object error) {
  final texto = error.toString();

  // Migración 61 sin aplicar: el RPC existe pero sin `p_motivo`, así que
  // PostgREST no encuentra la sobrecarga.
  if (texto.contains('PGRST202') ||
      texto.contains('Could not find the function') ||
      texto.contains('schema cache')) {
    return 'Falta aplicar la migración 61 en Supabase: sin ella el servidor '
        'todavía no acepta el motivo de cancelación.';
  }

  // El servidor exige el motivo y no llegó (solo debería pasar por un fallo de
  // la app, pero el mensaje tiene que ser claro igualmente).
  if (texto.contains('Debes indicar el motivo')) {
    return 'Escribe el motivo de la cancelación antes de continuar.';
  }

  if (texto.contains('Solo se pueden cancelar reservas activas')) {
    return 'Solo se pueden cancelar las reservas activas: esta ya estaba '
        'cancelada o completada, o alguien la cambió mientras mirabas.';
  }

  if (texto.contains('No tiene permisos') ||
      texto.contains('No tienes permiso')) {
    return 'No tienes permisos para cancelar esta reserva.';
  }

  if (texto.contains('Reserva no encontrada')) {
    return 'La reserva ya no existe. Actualiza el listado.';
  }

  if (texto.contains('parametros obligatorios faltantes')) {
    return 'Faltan datos para cancelar la reserva. Actualiza el listado e '
        'inténtalo de nuevo.';
  }

  if (texto.contains('JWT') || texto.contains('No autenticado')) {
    return 'Tu sesión ha caducado. Vuelve a iniciar sesión.';
  }

  // Mensajes del servidor que ya están escritos para el usuario final
  // («Solo puedes cancelar hasta N horas antes de la reserva», etc.).
  return texto
      .replaceFirst('Exception: ', '')
      .replaceFirst('Exception(', '')
      .trim();
}

/// Texto del motivo tal y como se pinta en las tarjetas: recortado y **vacío**
/// cuando no hay motivo.
///
/// Devolver `''` (y no un texto tipo «Sin motivo») es intencionado: las
/// reservas canceladas antes de la migración 61 no tienen motivo y el plan pide
/// que, en ese caso, **no se pinte nada** en la tarjeta.
String textoMotivoCancelacion(String? motivo) => (motivo ?? '').trim();

/// Alias del nombre que fija el plan (§3.1) para el mismo texto.
String textoMotivo(String? motivo) => textoMotivoCancelacion(motivo);

/// ¿Hay un motivo que merezca pintarse? (no nulo y no vacío tras recortar).
bool hayMotivoCancelacion(String? motivo) =>
    textoMotivoCancelacion(motivo).isNotEmpty;

/// Rol que canceló (`cancelado_por_rol` de la BD) → etiqueta para la tarjeta.
///
/// El servidor usa `'cliente' | 'admin' | 'staff' | 'sistema'`; `'staff'` se
/// muestra como «vendedor» porque es el nombre que la app usa en el panel.
/// Cualquier otro valor desconocido se devuelve tal cual (recortado) y un valor
/// nulo devuelve `''`, que la tarjeta interpreta como «no pintar la línea».
String textoCanceladoPor(String? rol) {
  switch ((rol ?? '').trim().toLowerCase()) {
    case 'cliente':
      return 'cliente';
    case 'admin':
      return 'administración';
    case 'staff':
      return 'vendedor';
    case 'sistema':
      return 'sistema';
    default:
      return (rol ?? '').trim();
  }
}