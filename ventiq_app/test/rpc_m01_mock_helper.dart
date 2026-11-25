import 'dart:convert';

import 'package:http/http.dart' as http;

/// Simula un proyecto donde las RPC `*_m01` todavía no están desplegadas.
///
/// El cliente prueba `<base>_m01` primero y cae al nombre antiguo solo con
/// PGRST202. Los tests de contrato que fijan la cadena antigua responden esto
/// a cada intento `_m01` y lo excluyen de su registro de peticiones, de modo
/// que siguen verificando la cadena de respaldo sin cambios.
http.Response? m01NoDesplegada(http.Request request) {
  final fn = request.url.path.split('/').last;
  if (!fn.endsWith('_m01')) return null;
  return http.Response(
    jsonEncode({
      'code': 'PGRST202',
      'message':
          'Could not find the function public.$fn in the schema cache',
    }),
    404,
    headers: {'content-type': 'application/json'},
    request: request,
  );
}
