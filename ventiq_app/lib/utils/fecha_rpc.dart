/// Instante para parámetros `timestamptz` de las RPC offline.
///
/// La cola guarda las fechas con `toIso8601String()` de un DateTime local,
/// sin offset. Postgres las leía en la zona de la sesión (UTC en newa,
/// America/Havana en main) y quedaban desplazadas: un cierre a las 11:07 de
/// Cuba se guardaba a las 11:07 UTC. Se reenvían como UTC con `Z`.
String? fechaUtcParaRpc(dynamic raw) {
  if (raw == null) return null;
  final dt = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
  return dt?.toUtc().toIso8601String();
}
