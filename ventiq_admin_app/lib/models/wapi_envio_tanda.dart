import 'wapi_envio_log.dart';

/// Estado agregado de una tanda de envío.
enum WapiTandaEstado {
  /// Hay mensajes pendientes y actividad reciente: se está enviando ahora.
  enCurso,

  /// Todos los mensajes se enviaron correctamente.
  completada,

  /// Terminó pero con algunos fallos.
  conFallos,

  /// Todos los mensajes fallaron.
  fallida,

  /// Quedaron pendientes pero sin actividad reciente. Ocurre cuando el worker
  /// de la edge function muere a mitad del envío y la cadena de chunks no
  /// continúa — los mensajes restantes nunca se despachan.
  interrumpida,
}

/// Agrupación de [WapiEnvioLog] que representa UN envío desde el punto de vista
/// del usuario ("la difusión de las 9:00").
///
/// El backend inserta los logs por chunks (ver `wapi-send-products`: procesa ~21
/// productos por invocación y re-invoca con el resto), así que un mismo envío
/// lógico genera varios grupos de filas con `created_at` distintos. Aquí los
/// reunimos en una sola tanda para que el historial se lea como una lista de
/// envíos, no como cientos de filas sueltas.
class WapiEnvioTanda {
  /// Ventana máxima entre dos lotes de logs para considerarlos el mismo envío.
  /// Cada chunk consume hasta ~250s de presupuesto, así que 20 min cubre varios
  /// chunks encadenados sin fusionar envíos de días distintos.
  static const Duration _ventanaAgrupacion = Duration(minutes: 20);

  /// Sin actividad por más de este tiempo, una tanda con pendientes se
  /// considera interrumpida en lugar de "en curso".
  static const Duration _umbralInactividad = Duration(minutes: 10);

  final String id;
  final String tipoEnvio;
  final int? idProgramacion;
  final DateTime inicio;
  final DateTime ultimaActividad;

  /// Logs de la tanda, ordenados ascendentemente por id (orden de despacho).
  final List<WapiEnvioLog> logs;

  WapiEnvioTanda({
    required this.id,
    required this.tipoEnvio,
    required this.idProgramacion,
    required this.inicio,
    required this.ultimaActividad,
    required this.logs,
  });

  int get total => logs.length;
  int get enviados =>
      logs.where((l) => l.estado == WapiEnvioEstado.enviado).length;
  int get fallidos =>
      logs.where((l) => l.estado == WapiEnvioEstado.fallido).length;
  int get pendientes =>
      logs.where((l) => l.estado == WapiEnvioEstado.pendiente).length;

  /// Mensajes ya resueltos (enviados + fallidos).
  int get procesados => enviados + fallidos;

  /// Fracción 0..1 de avance. Usa procesados para que los fallos también
  /// cuenten como progreso — si no, la barra se quedaría clavada.
  double get progreso => total == 0 ? 0 : procesados / total;

  /// Destinos únicos de la tanda.
  Set<String> get chats => logs.map((l) => l.chatId).toSet();

  /// Productos únicos de la tanda, en orden de despacho.
  List<int> get productos {
    final vistos = <int>{};
    final orden = <int>[];
    for (final l in logs) {
      final id = l.idProducto;
      if (id == null || vistos.contains(id)) continue;
      vistos.add(id);
      orden.add(id);
    }
    return orden;
  }

  /// Productos cuyos mensajes ya se resolvieron por completo.
  int get productosCompletados {
    final porProducto = <int, List<WapiEnvioLog>>{};
    for (final l in logs) {
      final id = l.idProducto;
      if (id == null) continue;
      porProducto.putIfAbsent(id, () => []).add(l);
    }
    return porProducto.values
        .where((ls) => ls.every((l) => l.estado != WapiEnvioEstado.pendiente))
        .length;
  }

  /// Producto que se está despachando ahora: el primero (en orden de envío)
  /// que todavía tiene mensajes pendientes.
  int? get productoActual {
    for (final l in logs) {
      if (l.estado == WapiEnvioEstado.pendiente) return l.idProducto;
    }
    return null;
  }

  /// Ids de log que todavía no llegaron a destino (pendientes + fallidos).
  /// Es exactamente lo que se manda al backend al pulsar "reanudar".
  List<int> get logIdsSinEnviar => logs
      .where((l) => l.estado != WapiEnvioEstado.enviado)
      .map((l) => l.id)
      .toList();

  /// Sesión con la que se despachó la tanda; necesaria para reanudarla.
  int? get idSesion {
    for (final l in logs) {
      if (l.idSesion != null) return l.idSesion;
    }
    return null;
  }

  /// ¿Se puede reanudar? Sólo tiene sentido si quedó algo sin entregar y
  /// sabemos por qué sesión mandarlo.
  bool puedeReanudarse(DateTime ahora) {
    final e = estadoPara(ahora);
    final reanudable = e == WapiTandaEstado.interrumpida ||
        e == WapiTandaEstado.conFallos ||
        e == WapiTandaEstado.fallida;
    return reanudable && idSesion != null && logIdsSinEnviar.isNotEmpty;
  }

  /// Error más frecuente de la tanda, para resumir los fallos sin llenar la UI.
  String? get errorPredominante {
    final conteo = <String, int>{};
    for (final l in logs) {
      if (l.estado != WapiEnvioEstado.fallido) continue;
      final k = l.errorMessage ?? l.errorCode ?? 'Error desconocido';
      conteo[k] = (conteo[k] ?? 0) + 1;
    }
    if (conteo.isEmpty) return null;
    final orden = conteo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return orden.first.key;
  }

  WapiTandaEstado estadoPara(DateTime ahora) {
    if (pendientes > 0) {
      final inactiva = ahora.difference(ultimaActividad) > _umbralInactividad;
      return inactiva ? WapiTandaEstado.interrumpida : WapiTandaEstado.enCurso;
    }
    if (fallidos == 0) return WapiTandaEstado.completada;
    if (enviados == 0) return WapiTandaEstado.fallida;
    return WapiTandaEstado.conFallos;
  }

  bool get esProgramado => tipoEnvio == 'programado';

  /// Agrupa logs planos (cualquier orden) en tandas, más reciente primero.
  ///
  /// Dos logs pertenecen a la misma tanda si comparten `tipo_envio` e
  /// `id_programacion` y sus `created_at` distan menos de [_ventanaAgrupacion].
  static List<WapiEnvioTanda> agrupar(List<WapiEnvioLog> logs) {
    if (logs.isEmpty) return [];

    // Orden cronológico ascendente: así el recorrido sigue el orden real de
    // despacho y `productoActual` devuelve el primero pendiente de verdad.
    final orden = [...logs]..sort((a, b) {
          final c = a.createdAt.compareTo(b.createdAt);
          return c != 0 ? c : a.id.compareTo(b.id);
        });

    final tandas = <WapiEnvioTanda>[];
    var buffer = <WapiEnvioLog>[orden.first];

    void cerrar() {
      final inicio = buffer.first.createdAt;
      // Última señal de vida: el sent_at más reciente, o el created_at del
      // último lote insertado si todavía no se envió nada.
      var ultima = inicio;
      for (final l in buffer) {
        if (l.createdAt.isAfter(ultima)) ultima = l.createdAt;
        final s = l.sentAt;
        if (s != null && s.isAfter(ultima)) ultima = s;
      }
      tandas.add(WapiEnvioTanda(
        id: '${buffer.first.id}_${inicio.millisecondsSinceEpoch}',
        tipoEnvio: buffer.first.tipoEnvio,
        idProgramacion: buffer.first.idProgramacion,
        inicio: inicio,
        ultimaActividad: ultima,
        logs: List.unmodifiable(buffer),
      ));
    }

    for (var i = 1; i < orden.length; i++) {
      final prev = orden[i - 1];
      final cur = orden[i];
      final mismaTanda = cur.tipoEnvio == prev.tipoEnvio &&
          cur.idProgramacion == prev.idProgramacion &&
          cur.createdAt.difference(prev.createdAt) <= _ventanaAgrupacion;
      if (mismaTanda) {
        buffer.add(cur);
      } else {
        cerrar();
        buffer = <WapiEnvioLog>[cur];
      }
    }
    cerrar();

    // Más reciente primero para la UI.
    return tandas.reversed.toList();
  }
}
