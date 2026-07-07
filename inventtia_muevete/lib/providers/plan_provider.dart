import 'package:flutter/foundation.dart';

import '../models/plan_model.dart';
import '../services/plan_service.dart';

class PlanProvider extends ChangeNotifier {
  final _service = PlanService();

  List<PlanModel> _planes = [];
  bool _loading = false;
  String? _error;

  List<PlanModel> get planes => _planes;
  bool get loading => _loading;
  String? get error => _error;

  List<PlanModel> planesParaTipo(String tipoUsuario) =>
      _planes.where((p) => p.tipoUsuario == tipoUsuario).toList();

  // ────────────────────────────────────────────────────────────────────────────

  Future<void> cargarPlanes(String tipoUsuario) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.getPlanes(tipoUsuario);
      // Reemplaza solo los planes de ese tipo, conserva los del resto
      _planes = [
        ..._planes.where((p) => p.tipoUsuario != tipoUsuario),
        ...result,
      ];
    } catch (e) {
      _error = e.toString();
      debugPrint('[PlanProvider] Error cargarPlanes: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> cargarTodosLosPlanes() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _planes = await _service.getTodosLosPlanes();
    } catch (e) {
      _error = e.toString();
      debugPrint('[PlanProvider] Error cargarTodosLosPlanes: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
