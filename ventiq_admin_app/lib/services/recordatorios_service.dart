import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';
import 'local_notification_service.dart';
import 'recordatorios_calculo.dart';

/// Recordatorios de compras sin completar (Fase 9 del módulo Compras).
///
/// Junta las tres piezas con estado:
///  · el umbral de días guardado en `SharedPreferences`,
///  · el resumen del panel `fn_fdi_pendientes_panel`,
///  · la notificación local (`LocalNotificationService`) con control de
///    «una vez al día».
///
/// Los cálculos viven en `recordatorios_calculo.dart` (Dart puro, testeable).
/// Este servicio nunca lanza por un fallo de red: devuelve `null` y no
/// notifica, para que el inicio siga funcionando.
class RecordatoriosService {
  RecordatoriosService({SupabaseClient? supabase}) : _supabaseExplicito = supabase;

  /// Permite inyectar el cliente en pruebas; en la app se resuelve de forma
  /// perezosa con `Supabase.instance`.
  final SupabaseClient? _supabaseExplicito;

  SupabaseClient get _supabase =>
      _supabaseExplicito ?? Supabase.instance.client;

  /// Clave del umbral en `SharedPreferences`.
  static const String claveUmbralDias = 'compras_recordatorio_umbral_dias';

  /// Clave de la fecha (yyyy-MM-dd) del último aviso mostrado.
  static const String claveUltimoAviso = 'compras_recordatorio_ultimo_aviso';

  /// Id fijo de la notificación: reemplaza el aviso anterior en vez de apilar
  /// uno nuevo cada vez que se abre la app.
  static const int idNotificacionPendientes = 9101;

  /// Nombre de la RPC del panel de compras abiertas.
  static const String rpcPanelPendientes = 'fn_fdi_pendientes_panel';

  // -------------------------------------------------------------------------
  // Umbral
  // -------------------------------------------------------------------------

  /// Días del umbral configurado (15 por defecto, siempre dentro de rango).
  Future<int> umbralDias() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return normalizarUmbral(prefs.get(claveUmbralDias));
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el umbral de recordatorios: $e');
      return umbralDiasPorDefecto;
    }
  }

  /// Guarda el umbral ajustado al rango 1..365 (nunca escribe un valor
  /// inválido). Si no se puede escribir, lanza: el diálogo lo reporta.
  Future<void> guardarUmbral(int dias) async {
    final valor = acotarUmbral(dias);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(claveUmbralDias, valor);
  }

  // -------------------------------------------------------------------------
  // Resumen del panel
  // -------------------------------------------------------------------------

  /// Resumen de compras sin completar de la tienda.
  ///
  /// Devuelve `null` si la RPC falla (sin conexión, sin permisos, función
  /// ausente): el inicio no se rompe y simplemente no se muestra aviso.
  Future<ResumenPendientes?> resumen({required int idTienda}) async {
    final umbral = await umbralDias();
    try {
      final respuesta = await _supabase.rpc(
        rpcPanelPendientes,
        params: {'p_id_tienda': idTienda},
      );
      if (respuesta is! Map) {
        debugPrint(
          '⚠️ $rpcPanelPendientes devolvió ${respuesta.runtimeType}, no un objeto',
        );
        return null;
      }
      final panel = Map<String, dynamic>.from(respuesta);
      return ResumenPendientes.desdePanel(panel, umbralDias: umbral);
    } catch (e) {
      debugPrint('⚠️ No se pudo cargar el panel de pendientes: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Notificación local
  // -------------------------------------------------------------------------

  /// ¿Toca notificar hoy?
  ///
  /// Solo si hay algo que avisar y el último aviso guardado no es de hoy.
  /// Cuando devuelve `true` ya deja registrada la fecha del día, para que
  /// abrir la app otra vez el mismo día no repita el aviso.
  Future<bool> debeNotificar({
    required ResumenPendientes? resumen,
    DateTime? ahora,
  }) async {
    if (resumen == null || !resumen.hayAviso) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final hoy = fechaClave(ahora ?? DateTime.now());
      if (prefs.getString(claveUltimoAviso) == hoy) return false;
      await prefs.setString(claveUltimoAviso, hoy);
      return true;
    } catch (e) {
      // Sin `SharedPreferences` no hay control de repetición: mejor no avisar.
      debugPrint('⚠️ No se pudo comprobar el último aviso de compras: $e');
      return false;
    }
  }

  /// Muestra la notificación local del resumen, si corresponde.
  ///
  /// Silencioso ante fallos: la notificación es opcional y la tarjeta del
  /// inicio debe funcionar aunque el plugin no esté disponible (web, escritorio
  /// o permisos denegados).
  Future<void> notificarSiCorresponde({
    required ResumenPendientes? resumen,
    DateTime? ahora,
  }) async {
    if (kIsWeb) return;
    final toca = await debeNotificar(resumen: resumen, ahora: ahora);
    if (!toca || resumen == null) return;
    await mostrarNotificacion(resumen);
  }

  /// Publica el aviso con id fijo (no apila notificaciones).
  Future<void> mostrarNotificacion(ResumenPendientes resumen) async {
    if (kIsWeb) return;
    try {
      final servicio = LocalNotificationService();
      await servicio.initialize();
      final momento = DateTime.now();
      await servicio.showNotification(
        NotificationModel(
          id: idNotificacionPendientes,
          userId: '',
          tipo: NotificationType.alerta,
          titulo: tituloNotificacionPendientes,
          mensaje: resumen.mensajeNotificacion,
          prioridad: NotificationPriority.alta,
          leida: false,
          archivada: false,
          createdAt: momento,
          updatedAt: momento,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ No se pudo mostrar el recordatorio de compras: $e');
    }
  }

  /// Fecha `yyyy-MM-dd` usada como marca de «ya avisé hoy».
  static String fechaClave(DateTime momento) {
    final anio = momento.year.toString().padLeft(4, '0');
    final mes = momento.month.toString().padLeft(2, '0');
    final dia = momento.day.toString().padLeft(2, '0');
    return '$anio-$mes-$dia';
  }
}