import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../models/wapi_session.dart';
import '../utils/wapi_errores.dart';

typedef WapiSessionAction = void Function(String action);

/// Card visual de una sesión/bot WhatsApp.
///
/// QUÉ CAMBIÓ (UX para el cliente final)
///   1. **El estado se explica, no solo se pinta**: bajo el nombre va una frase
///      («Falta vincular el teléfono: sin eso no se envía nada.») para que nadie
///      tenga que interpretar un punto de color.
///   2. **Botón principal = la acción que resuelve el problema**: «Mostrar QR
///      para vincular» o «Reconectar ahora». Antes había que adivinar entre las
///      opciones del menú de tres puntos.
///   3. **Aviso de estado viejo**: si la app lleva >10 min sin poder refrescar,
///      lo dice en vez de afirmar que el bot está bien.
///   4. **Último problema, traducido**: `wapi_errores.dart` convierte el código
///      crudo en algo comprensible.
///   5. El enlace de Documentación apuntaba al repo equivocado (wa-automate);
///      ahora va al gateway que realmente usamos (OpenWA).
///   6. Se respeta «reducir movimiento» del sistema.
class WapiSessionCard extends StatelessWidget {
  final WapiSession session;
  final WapiSessionAction onAction;
  final bool compact;

  /// Cuántos mensajes hay esperando en la cola de esta tienda. Se usa para
  /// cuantificar el daño mientras el bot está caído ("hay 24 mensajes que no
  /// van a salir hasta que reconectes").
  final int mensajesEnEspera;

  const WapiSessionCard({
    super.key,
    required this.session,
    required this.onAction,
    this.compact = false,
    this.mensajesEnEspera = 0,
  });

  static const _docsUrl = 'https://github.com/rmyndharis/OpenWA';

  @override
  Widget build(BuildContext context) {
    final st = session.status;
    final viejo = session.esEstadoViejo(DateTime.now());
    final accion = st.accionSugerida;
    final diagnostico = (session.lastErrorCode != null ||
            session.lastErrorMessage != null)
        ? diagnosticarError(
            codigo: session.lastErrorCode,
            mensaje: session.lastErrorMessage,
          )
        : null;

    // Sólo mostramos el "último problema" cuando sigue habiendo problema: si el
    // bot está conectado, un error viejo solo mete ruido.
    final problema =
        (st != WapiStatus.connected) ? diagnostico : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _IconoEstado(status: st, viejo: viejo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.phoneNumber ?? 'Sin teléfono vinculado',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: st),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                onSelected: (v) async {
                  if (v == 'docs') {
                    final ok = await launchUrl(
                      Uri.parse(_docsUrl),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!ok) onAction('docs');
                  } else {
                    onAction(v);
                  }
                },
                itemBuilder: (ctx) => [
                  if (st == WapiStatus.scanQr)
                    const PopupMenuItem(
                      value: 'qr',
                      child: ListTile(
                        leading: Icon(Icons.qr_code_2),
                        title: Text('Mostrar QR'),
                        dense: true,
                      ),
                    ),
                  if (st != WapiStatus.connected)
                    const PopupMenuItem(
                      value: 'restart',
                      child: ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('Reconectar bot'),
                        dense: true,
                      ),
                    ),
                  if (st == WapiStatus.connected)
                    const PopupMenuItem(
                      value: 'restart',
                      child: ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('Reiniciar conexión'),
                        dense: true,
                      ),
                    ),
                  if (st == WapiStatus.connected)
                    const PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.power_off),
                        title: Text('Desconectar'),
                        dense: true,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'details',
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Detalles'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'health',
                    child: ListTile(
                      leading: Icon(Icons.monitor_heart_outlined),
                      title: Text('Estado del servidor'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'docs',
                    child: ListTile(
                      leading: Icon(Icons.menu_book_outlined),
                      title: Text('Ayuda'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Eliminar',
                          style: TextStyle(color: Colors.red)),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Explicación del estado (una frase, sin tecnicismos) ───────
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: st.color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: st.color.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(st.icon, size: 15, color: st.color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _textoEstado(st, viejo),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Último problema detectado (traducido) ─────────────────────
          if (problema != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(problema.icono, size: 14, color: problema.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Último problema: ${problema.titulo.toLowerCase()}.'
                    '${problema.queHacer != null ? ' ${problema.queHacer}' : ''}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (!compact) ...[
            const SizedBox(height: 10),
            // Wrap: si no caben en una línea bajan a la siguiente en vez de
            // recortarse (el session-id puede ser largo).
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _ChipMini(
                  icon: Icons.fingerprint,
                  label: session.wapiSessionId,
                ),
                _ChipMini(
                  icon: viejo ? Icons.history_toggle_off : Icons.schedule,
                  label: 'Actualizado ${_relative(session.lastStatusAt)}',
                ),
                if (!session.watchdogEnabled)
                  const _ChipMini(
                    icon: Icons.visibility_off_outlined,
                    label: 'Vigilancia automática desactivada',
                  ),
                if (session.recoveryAttempts > 0)
                  _ChipMini(
                    icon: Icons.healing_outlined,
                    label:
                        'Reconexiones automáticas: ${session.recoveryAttempts}',
                  ),
              ],
            ),
          ],

          // ── Acción principal: la que resuelve el estado ──────────────
          if (!compact && accion != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => onAction(accion),
                icon: Icon(
                  accion == 'qr' ? Icons.qr_code_2 : Icons.refresh,
                  size: 19,
                ),
                label: Text(accion == 'qr'
                    ? 'Mostrar QR para vincular'
                    : 'Reconectar ahora'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Frase que explica el estado y, si hay mensajes esperando, lo cuantifica.
  String _textoEstado(WapiStatus st, bool viejo) {
    final base = st.detalle;
    if (viejo && st != WapiStatus.connected) {
      return '$base (No pudimos consultar el bot '
          '${_relative(session.lastStatusAt)}; pulsa «Actualizar».)';
    }
    if (st.bloqueaEnvios && mensajesEnEspera > 0) {
      final cuantos = mensajesEnEspera == 1
          ? '1 mensaje en cola no saldrá'
          : '$mensajesEnEspera mensajes en cola no saldrán';
      return '$base $cuantos hasta que se reconecte.';
    }
    return base;
  }

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }
}

class _IconoEstado extends StatelessWidget {
  final WapiStatus status;
  final bool viejo;
  const _IconoEstado({required this.status, required this.viejo});

  @override
  Widget build(BuildContext context) {
    final color = viejo ? AppColors.textLight : status.color;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(status.icon, color: color),
          if (viejo)
            const Positioned(
              right: 2,
              bottom: 2,
              child: Icon(Icons.help_outline,
                  size: 13, color: AppColors.textLight),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final WapiStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChipMini extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipMini({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      // maxWidth acotado: el chip vive dentro de un Wrap (ancho no acotado),
      // así el Flexible interno tiene un límite contra el que hacer ellipsis.
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}