import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/suscripcion.dart';
import '../providers/entidad_provider.dart';
import '../providers/suscripcion_provider.dart';

/// Aviso permanente de suscripción.
///
/// Va montado en el shell de la app (encima del `IndexedStack`), no dentro de una
/// pantalla, porque el requisito es que el impago **se vea en todo momento**: si
/// viviera en "Mi suscripción", el aviso desaparecería al cambiar de pestaña.
///
/// Se pinta en tres tonos según la urgencia:
///   · rojo   → no puede operar (vencida, sin plan, suspendida, cancelada).
///   · ámbar  → en gracia: todavía funciona, pero se cae pronto.
///   · azul   → prueba o últimos días de un plan pagado (informativo).
/// Sin nada que decir no ocupa ni un píxel (`SizedBox.shrink`).
///
/// Además es quien **dispara la carga**: al ser un widget vivo en el árbol,
/// detecta cuándo cambia la entidad seleccionada y pide el estado de la nueva.
/// Así el cambio de entidad se resuelve en un solo sitio y no hay que tocar cada
/// pantalla que permita cambiarla.
class AvisoSuscripcion extends StatefulWidget {
  const AvisoSuscripcion({super.key, this.comprimido = false});

  /// En `true` solo pinta la barra de una línea (para pantallas con cabecera
  /// propia). El aviso sigue siendo visible; cambia la cantidad de detalle.
  final bool comprimido;

  @override
  State<AvisoSuscripcion> createState() => _AvisoSuscripcionState();
}

class _AvisoSuscripcionState extends State<AvisoSuscripcion> {
  int? _ultimaEntidadPedida;

  /// Pide el estado de la entidad seleccionada, una sola vez por cambio.
  ///
  /// Se hace en un `postFrameCallback` porque [cargar] llama a
  /// `notifyListeners()`, y notificar durante el build revienta el árbol.
  void _sincronizar() {
    final entidadProvider = context.read<EntidadProvider>();
    final id = entidadProvider.entidadSeleccionada?.id;
    if (id == _ultimaEntidadPedida) return;
    _ultimaEntidadPedida = id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SuscripcionProvider>().cargar(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    // `watch` a propósito: cuando el admin cambia de entidad hay que recalcular.
    context.watch<EntidadProvider>();
    _sincronizar();

    final sus = context.watch<SuscripcionProvider>();

    // Sin migración aplicada o sin estado: nada que avisar. Es lo que permite
    // publicar la app antes de que el usuario pegue el SQL.
    if (sus.esquemaPendiente || sus.estado == null) {
      return const SizedBox.shrink();
    }

    final estado = sus.estado!;

    final estilo = _estiloDe(estado);
    if (estilo == null) return const SizedBox.shrink();

    final texto = estado.mensaje?.trim();
    final detalle = (texto == null || texto.isEmpty) ? estilo.titulo : texto;

    return Material(
      color: estilo.color.withOpacity(0.10),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/mi-suscripcion'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: estilo.color.withOpacity(0.35)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(estilo.icono, color: estilo.color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      estilo.titulo,
                      style: TextStyle(
                        color: estilo.color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!widget.comprimido) ...[
                      const SizedBox(height: 2),
                      Text(
                        detalle,
                        style: TextStyle(
                          color: estilo.color.withOpacity(0.95),
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Con un pago ya reportado el botón cambia de texto: ofrecer
              // "Pagar" a quien acaba de reportar su pago invita a pagar dos
              // veces la misma suscripción.
              TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/mi-suscripcion'),
                style: TextButton.styleFrom(
                  foregroundColor: estilo.color,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  sus.esperandoVerificacion ? 'Ver estado' : 'Pagar',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Devuelve el estilo del aviso, o `null` si no hay nada que avisar.
  ///
  /// El silencio es deliberado en `activa` con tiempo de sobra: un aviso que
  /// siempre está encendido deja de leerse.
  _EstiloAviso? _estiloDe(EstadoSuscripcionEntidad e) {
    switch (e.estado) {
      case EstadoSuscripcion.vencida:
        return const _EstiloAviso(
          color: AppTheme.error,
          icono: Icons.error_outline,
          titulo: 'Suscripción vencida — no has pagado',
        );
      case EstadoSuscripcion.sinPlan:
      case EstadoSuscripcion.cancelada:
        return const _EstiloAviso(
          color: AppTheme.error,
          icono: Icons.error_outline,
          titulo: 'Sin plan activo — no has pagado',
        );
      case EstadoSuscripcion.suspendida:
        return const _EstiloAviso(
          color: AppTheme.error,
          icono: Icons.block,
          titulo: 'Entidad suspendida',
        );
      case EstadoSuscripcion.enGracia:
        return const _EstiloAviso(
          color: AppTheme.warning,
          icono: Icons.hourglass_bottom,
          titulo: 'Suscripción vencida — estás en el margen de gracia',
        );
      case EstadoSuscripcion.trial:
        // Solo avisa cuando quedan pocos días: si no, es ruido.
        if ((e.diasRestantes ?? 99) > 5) return null;
        return const _EstiloAviso(
          color: AppTheme.primary,
          icono: Icons.timelapse,
          titulo: 'Tu período de prueba termina pronto',
        );
      case EstadoSuscripcion.activa:
        if (e.diasRestantes == null || e.diasRestantes! > 7) return null;
        return const _EstiloAviso(
          color: AppTheme.primary,
          icono: Icons.event_available,
          titulo: 'Tu suscripción vence pronto',
        );
      case EstadoSuscripcion.sinSuscripcion:
        // Entidad anterior al módulo: sigue activa (grandfathering) y no es un
        // impago. Avisar aquí sería mentir.
        return null;
      case EstadoSuscripcion.desconocido:
        return null;
    }
  }
}

class _EstiloAviso {
  const _EstiloAviso({
    required this.color,
    required this.icono,
    required this.titulo,
  });

  final Color color;
  final IconData icono;
  final String titulo;
}
