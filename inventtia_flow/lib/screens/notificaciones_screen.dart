import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/notificacion.dart';
import '../providers/notificacion_provider.dart';
import '../utils/notificacion_orden.dart';
import '../utils/shell_navegacion.dart';

/// ¿Tocar este aviso debe llevar a la pestaña «Reservas»?
///
/// El circuito del **pago por adelantado** (migración 62) avisa al cliente con
/// `tipo = 'pago'`: «Pago verificado» («Tu reserva está confirmada»), «Pago
/// rechazado», «Pago caducado»… El dato que el cliente quiere ver —el chip de
/// `flow.agenda.pago_estado` en su reserva— solo existe en la lista de reservas,
/// así que un aviso que únicamente se marcara como leído dejaba al usuario sin el
/// destino que el propio aviso anuncia.
///
/// Las cancelaciones (migración 61) también dejan la reserva en un estado que se
/// consulta ahí, incluida la cancelación automática por pago no verificado.
bool _llevaAReservas(Notificacion n) => n.tipo == 'pago' || n.esCancelacion;

/// Marca el aviso como leído y, si toca, lleva al usuario a «Reservas».
///
/// El marcado va **primero** y no se espera para navegar: la navegación cierra
/// esta ruta (`popUntil` de [ShellNavegacion]) y el `Future` del provider sigue
/// vivo porque no depende del `context`.
Future<void> _alTocarAviso(
  BuildContext context,
  NotificacionProvider prov,
  Notificacion notif,
) async {
  final marcado = prov.marcarLeida(notif.id);
  // Sin shell detrás (test o vista previa montada sola) no hay a dónde ir.
  if (_llevaAReservas(notif) && ShellNavegacion.disponible) {
    // Índices del shell del cliente; `HomeShell` los traduce a la pestaña de
    // Reservas de la vista que toque (vendedor/admin) y recarga la lista.
    ShellNavegacion.irAPestana(context, ShellNavegacion.reservas);
  }
  await marcado;
}

class NotificacionesScreen extends StatelessWidget {
  const NotificacionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Consumer<NotificacionProvider>(
        builder: (_, prov, __) {
          final items = prov.items;
          // Agrupación por día (F1): una cabecera discreta delante de cada
          // jornada. El orden se reafirma aquí con el helper puro — es
          // idempotente y así las cabeceras nunca se repiten aunque la lista
          // llegue desordenada por cualquier camino.
          final filas = _filasPorDia(ordenarPorFecha(items));
          return Column(
            children: [
              _Hero(
                total: items.length,
                noLeidas: prov.unreadCount,
                hayNoLeidas: prov.hayNoLeidas,
                onMarcarTodas: prov.marcarTodasLeidas,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: prov.recargar,
                  color: AppTheme.primary,
                  child: items.isEmpty
                      ? _EmptyState()
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: filas.length,
                          itemBuilder: (_, i) {
                            final fila = filas[i];
                            if (fila is _CabeceraDia) {
                              return _CabeceraDiaTile(etiqueta: fila.etiqueta);
                            }
                            final notif = (fila as _FilaNotificacion).notif;
                            return _NotificacionCard(
                              notif: notif,
                              onTap: () => _alTocarAviso(context, prov, notif),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Cabecera "hero" alineada con Mis Listas y Mis Reservas: degradado de marca,
// botón de atrás, eyebrow, título grande, contador de no leídas y la acción
// "marcar todas leídas".
class _Hero extends StatelessWidget {
  final int total;
  final int noLeidas;
  final bool hayNoLeidas;
  final VoidCallback onMarcarTodas;

  const _Hero({
    required this.total,
    required this.noLeidas,
    required this.hayNoLeidas,
    required this.onMarcarTodas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33405F90),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 20, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroIconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TUS AVISOS',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Notificaciones',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        total == 0
                            ? 'No tienes notificaciones'
                            : noLeidas == 0
                                ? 'Estás al día'
                                : noLeidas == 1
                                    ? 'Tienes 1 sin leer'
                                    : 'Tienes $noLeidas sin leer',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hayNoLeidas)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _HeroIconButton(
                    icon: Icons.done_all_rounded,
                    onTap: onMarcarTodas,
                    tooltip: 'Marcar todas leídas',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Botón circular translúcido para acciones dentro del hero.
class _HeroIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _HeroIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

// ── Agrupación por día (F1) ──────────────────────────────────────────────────
//
// El feed se aplana a una lista de filas: o una cabecera de jornada o una
// tarjeta. Se hace con dos clases y no con `List<Widget>` para no construir los
// ~100 widgets de golpe y poder seguir usando `ListView.builder`.

sealed class _FilaFeed {
  const _FilaFeed();
}

class _CabeceraDia extends _FilaFeed {
  final String etiqueta;
  const _CabeceraDia(this.etiqueta);
}

class _FilaNotificacion extends _FilaFeed {
  final Notificacion notif;
  const _FilaNotificacion(this.notif);
}

/// Intercala una cabecera la primera vez que aparece cada día.
///
/// Como la lista viene ordenada de más reciente a más antigua, los avisos de un
/// mismo día son consecutivos; basta comparar con la etiqueta anterior. Las
/// etiquetas (`Hoy`, `Ayer`, `dd/MM/yyyy`) identifican un día de calendario
/// único, así que no hay dos jornadas distintas con el mismo texto.
List<_FilaFeed> _filasPorDia(List<Notificacion> items) {
  final filas = <_FilaFeed>[];
  String? etiquetaActual;
  for (final n in items) {
    final etiqueta = etiquetaDiaNotificacion(n.createdAt);
    if (etiqueta != etiquetaActual) {
      etiquetaActual = etiqueta;
      filas.add(_CabeceraDia(etiqueta));
    }
    filas.add(_FilaNotificacion(n));
  }
  return filas;
}

/// Cabecera de día discreta: texto en `textSecondary` con una línea fina que
/// rellena el ancho. Sin fondo ni tarjeta, para que no compita con las tarjetas.
class _CabeceraDiaTile extends StatelessWidget {
  final String etiqueta;

  const _CabeceraDiaTile({required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 6, bottom: 10),
      child: Row(
        children: [
          Text(
            etiqueta,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: AppTheme.border)),
        ],
      ),
    );
  }
}

class _NotificacionCard extends StatelessWidget {
  final Notificacion notif;
  final VoidCallback onTap;

  const _NotificacionCard({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final noLeida = !notif.leida;
    final color = notif.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Franja de acento vertical, teñida según el tipo de aviso.
                Container(width: 5, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ícono del tipo de notificación.
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(notif.icono, color: color, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    notif.titulo,
                                    style: TextStyle(
                                      fontWeight: noLeida
                                          ? FontWeight.w800
                                          : FontWeight.w700,
                                      fontSize: 15.5,
                                      color: AppTheme.textPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    notif.mensaje,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (noLeida) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(height: 1, color: AppTheme.border),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 14, color: color.withValues(alpha: 0.9)),
                            const SizedBox(width: 6),
                            Text(
                              _fechaRelativa(notif.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            // Chip del tipo de aviso.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: color.withValues(alpha: 0.30)),
                              ),
                              child: Text(
                                _etiquetaTipo(notif.tipo),
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _etiquetaTipo(String tipo) {
    switch (tipo) {
      case 'sala_espera':
        return 'Cola';
      case 'reserva':
        return 'Reserva';
      case 'promo':
        return 'Promo';
      // Pagos reportados y planes acreditados de la entidad.
      case 'suscripcion':
        return 'Suscripción';
      // Cancelación de reserva con motivo (migración 61).
      case 'cancelacion':
        return 'Cancelación';
      // Circuito de pago por adelantado del servicio (migración 62).
      case 'pago':
        return 'Pago';
      case 'sistema':
      default:
        return 'Aviso';
    }
  }

  String _fechaRelativa(DateTime fecha) {
    final ahora = DateTime.now();
    final diff = ahora.difference(fecha);
    if (diff.inSeconds < 60) return 'Hace un momento';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return DateFormat('dd/MM/yyyy').format(fecha);
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.12),
        Center(
          child: Column(
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.10),
                      AppTheme.accent.withValues(alpha: 0.10),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.notifications_none,
                    size: 46, color: AppTheme.primary.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 18),
              const Text('Sin notificaciones',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Aquí verás tus avisos de colas y reservaciones',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
