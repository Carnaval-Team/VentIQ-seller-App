import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../services/identidad_service.dart';

/// Resultado de evaluar el gate antes de operar.
class ResultadoGate {
  final bool permitido;
  final PasoSeguridad paso;
  final String motivo;

  /// El servidor no tiene las RPC del gate: se deja pasar para no romper la
  /// app y se avisa en el informe. Nunca se inventa un bloqueo local.
  final bool servidorSinGate;

  const ResultadoGate({
    required this.permitido,
    required this.paso,
    this.motivo = '',
    this.servidorSinGate = false,
  });

  static const ResultadoGate permitir = ResultadoGate(
    permitido: true,
    paso: PasoSeguridad.listo,
  );
}

/// Gate de habilitación en el flujo: identidad → consentimiento → contactos.
///
/// La fuente de verdad es el servidor (`fn_usuario_habilitado` y
/// `fn_gate_seguridad`); esto sólo decide a qué pantalla mandar al usuario y
/// con qué motivo. Las RPC de precio y de viaje vuelven a validar.
class GateSeguridad {
  static final IdentidadService _identidad = IdentidadService();

  // ── Evaluación ──────────────────────────────────────────────────────────

  /// Consulta el gate completo. Nunca lanza: ante error devuelve un resultado
  /// con el motivo para que la UI decida.
  static Future<ResultadoGate> evaluar({int? driverId, String? rol}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return ResultadoGate.permitir;

    EstadoIdentidad estado;
    try {
      estado = await _identidad.estado(rol: rol);
    } on IdentidadException catch (e) {
      if (e.clave == 'funcion_no_disponible') {
        return const ResultadoGate(
          permitido: true,
          paso: PasoSeguridad.listo,
          servidorSinGate: true,
        );
      }
      return ResultadoGate(
        permitido: false,
        paso: PasoSeguridad.identidad,
        motivo: e.mensaje,
      );
    } catch (_) {
      // Sin red no se puede comprobar el gate; la operación de todos modos
      // requiere red y el servidor volverá a validar.
      return const ResultadoGate(
        permitido: true,
        paso: PasoSeguridad.listo,
        servidorSinGate: true,
      );
    }

    if (estado.motivos.contains('bloqueado')) {
      return const ResultadoGate(
        permitido: false,
        paso: PasoSeguridad.bloqueado,
        motivo: 'Tu cuenta tiene reportes de seguridad confirmados',
      );
    }

    if (!estado.perfil.ok) {
      final faltan = estado.perfil.faltantes
          .map(IdentidadService.etiquetaMotivo)
          .toList();
      return ResultadoGate(
        permitido: false,
        paso: PasoSeguridad.identidad,
        motivo: faltan.isEmpty
            ? 'Completa tu perfil para continuar'
            : 'Falta: ${faltan.join(', ')}',
      );
    }

    if (!estado.consentimiento.ok) {
      return const ResultadoGate(
        permitido: false,
        paso: PasoSeguridad.consentimiento,
        motivo: 'Acepta la privacidad y los términos para continuar',
      );
    }

    try {
      final gate = await _identidad.gateSeguridad(
        userUuid: uid,
        driverId: driverId,
      );
      if (!gate.ok) {
        if (gate.motivos.contains('bloqueado')) {
          return ResultadoGate(
            permitido: false,
            paso: PasoSeguridad.bloqueado,
            motivo:
                gate.motivoBloqueoPublico ??
                'Tu cuenta no puede operar en este momento',
          );
        }
        return const ResultadoGate(
          permitido: false,
          paso: PasoSeguridad.contactos,
          motivo: 'Necesitas un contacto de emergencia para viajar',
        );
      }
    } on IdentidadException catch (e) {
      if (e.clave == 'funcion_no_disponible') {
        return ResultadoGate(
          permitido: estado.operarPermitido,
          paso: PasoSeguridad.listo,
          servidorSinGate: true,
        );
      }
      return ResultadoGate(
        permitido: false,
        paso: PasoSeguridad.contactos,
        motivo: e.mensaje,
      );
    } catch (_) {
      return ResultadoGate(
        permitido: estado.operarPermitido,
        paso: PasoSeguridad.listo,
        servidorSinGate: true,
      );
    }

    return ResultadoGate.permitir;
  }

  // ── Navegación ──────────────────────────────────────────────────────────

  /// Evalúa el gate y, si falta algo, abre la pantalla que toca.
  ///
  /// Devuelve `true` sólo cuando el usuario puede seguir con la acción.
  static Future<bool> asegurar(
    BuildContext context, {
    int? driverId,
    String? rol,
    bool mostrarAviso = true,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final resultado = await evaluar(driverId: driverId, rol: rol);

    if (resultado.permitido) return true;

    switch (resultado.paso) {
      case PasoSeguridad.identidad:
        navigator.pushNamed(
          '/identidad/onboarding',
          arguments: {'motivo': resultado.motivo, 'rol': rol},
        );
        break;
      case PasoSeguridad.consentimiento:
        navigator.pushNamed(
          '/identidad/consentimiento',
          arguments: {'motivo': resultado.motivo},
        );
        break;
      case PasoSeguridad.contactos:
        navigator.pushNamed(
          '/seguridad/contactos',
          arguments: {'motivo': resultado.motivo},
        );
        break;
      case PasoSeguridad.bloqueado:
      case PasoSeguridad.listo:
        if (mostrarAviso) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                resultado.motivo,
                style: GoogleFonts.plusJakartaSans(),
              ),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        break;
    }
    return false;
  }

  /// Traduce un error de RPC (`P0050`, `P0053`, `P0110`) a la pantalla que
  /// corresponde. Devuelve `true` si la app ya abrió algo.
  static Future<bool> desdeCodigoError(
    BuildContext context,
    String? clave, {
    String? motivo,
  }) async {
    if (clave == null) return false;
    final navigator = Navigator.of(context);

    switch (clave) {
      case 'perfil_incompleto':
        navigator.pushNamed(
          '/identidad/onboarding',
          arguments: {'motivo': motivo ?? 'Completa tu perfil para continuar'},
        );
        return true;
      case 'consentimiento_pendiente':
        navigator.pushNamed(
          '/identidad/consentimiento',
          arguments: {
            'motivo':
                motivo ?? 'Acepta la privacidad y los términos para continuar',
          },
        );
        return true;
      case 'sin_contacto_emergencia':
      case 'bloqueado':
        navigator.pushNamed(
          '/seguridad/contactos',
          arguments: {
            'motivo':
                motivo ?? 'Necesitas un contacto de emergencia para viajar',
          },
        );
        return true;
      default:
        return false;
    }
  }

  /// Aviso corto para el snackbar cuando el gate no deja operar.
  static String mensajeCorto(ResultadoGate resultado) {
    switch (resultado.paso) {
      case PasoSeguridad.identidad:
        return 'Completa tu perfil para continuar';
      case PasoSeguridad.consentimiento:
        return 'Acepta los documentos legales para continuar';
      case PasoSeguridad.contactos:
        return 'Agrega tu contacto de emergencia para viajar';
      case PasoSeguridad.bloqueado:
        return resultado.motivo.isEmpty
            ? 'Tu cuenta no puede operar en este momento'
            : resultado.motivo;
      case PasoSeguridad.listo:
        return '';
    }
  }
}
