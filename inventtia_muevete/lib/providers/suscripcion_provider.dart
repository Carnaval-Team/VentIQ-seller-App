import 'package:flutter/foundation.dart';

import '../models/suscripcion_model.dart';
import '../models/plan_model.dart';
import '../models/solicitud_plan_model.dart';
import '../services/suscripcion_service.dart';
import '../services/plan_service.dart';

class SuscripcionProvider extends ChangeNotifier {
  final _suscripcionService = SuscripcionService();
  final _planService = PlanService();

  SuscripcionModel? _suscripcion;
  PlanModel? _planActual;
  List<PlanModel> _planesDisponibles = [];
  SolicitudPlanModel? _solicitudPendiente;

  bool _loading = false;
  bool _actionLoading = false;
  String? _error;

  SuscripcionModel? get suscripcion => _suscripcion;
  PlanModel? get planActual => _planActual;
  List<PlanModel> get planesDisponibles => _planesDisponibles;
  SolicitudPlanModel? get solicitudPendiente => _solicitudPendiente;
  bool get loading => _loading;
  bool get actionLoading => _actionLoading;
  String? get error => _error;

  bool get tienesSuscripcionActiva => _suscripcion?.estaActiva ?? false;
  bool get esPlanGratis => _suscripcion?.esGratis ?? true;
  bool get tieneSolicitudPendiente => _solicitudPendiente != null;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Cargar suscripción activa, plan y solicitud pendiente ─────────────────────

  Future<void> cargarSuscripcion(String userUuid, String tipoUsuario) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _suscripcionService.getSuscripcionActiva(userUuid),
        _planService.getPlanes(tipoUsuario),
        _suscripcionService.getSolicitudPendiente(userUuid),
      ]);

      _suscripcion = results[0] as SuscripcionModel?;
      _planesDisponibles = results[1] as List<PlanModel>;
      _solicitudPendiente = results[2] as SolicitudPlanModel?;

      if (_suscripcion != null) {
        _planActual =
            await _planService.getPlanPorCodigo(_suscripcion!.planCodigo);
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('[SuscripcionProvider] Error cargarSuscripcion: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Cambiar plan (directo — solo para planes gratuitos) ───────────────────────

  Future<bool> cambiarPlan(String userUuid, String nuevoPlanCodigo) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _suscripcionService.cambiarPlan(
        userUuid: userUuid,
        nuevoPlanCodigo: nuevoPlanCodigo,
      );
      if (ok) {
        _suscripcion =
            await _suscripcionService.getSuscripcionActiva(userUuid);
        if (_suscripcion != null) {
          _planActual =
              await _planService.getPlanPorCodigo(_suscripcion!.planCodigo);
        }
      }
      return ok;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  // ── Solicitar cambio de plan con evidencia de pago ────────────────────────────

  Future<bool> solicitarCambioPlan({
    required String userUuid,
    required String planCodigo,
    required String evidenciaUrl,
  }) async {
    _actionLoading = true;
    _error = null;
    notifyListeners();
    try {
      final solicitud = await _suscripcionService.solicitarCambioPlan(
        userUuid: userUuid,
        planCodigo: planCodigo,
        evidenciaUrl: evidenciaUrl,
      );
      if (solicitud != null) {
        _solicitudPendiente = solicitud;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _suscripcion = null;
    _planActual = null;
    _planesDisponibles = [];
    _solicitudPendiente = null;
    _error = null;
    notifyListeners();
  }
}
