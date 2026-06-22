import 'package:flutter/material.dart';
import '../models/entidad.dart';
import '../services/entidad_service.dart';

class EntidadProvider extends ChangeNotifier {
  List<Entidad> _misEntidades = [];
  Entidad? _entidadSeleccionada;
  bool _isLoading = false;
  String? _error;

  List<Entidad> get misEntidades => _misEntidades;
  Entidad? get entidadSeleccionada => _entidadSeleccionada;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAdmin => _misEntidades.isNotEmpty;

  void seleccionarEntidad(Entidad entidad) {
    _entidadSeleccionada = entidad;
    notifyListeners();
  }

  Future<void> cargarMisEntidades(String uuidUsuario) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _misEntidades = await EntidadService.getMisEntidades(uuidUsuario);
      print('[flow] EntidadProvider → ${_misEntidades.length} entidades cargadas');
      // Autoseleccionar la primera si no hay ninguna seleccionada o la seleccionada ya no existe
      if (_misEntidades.isNotEmpty) {
        final stillExists = _entidadSeleccionada != null &&
            _misEntidades.any((e) => e.id == _entidadSeleccionada!.id);
        if (!stillExists) {
          _entidadSeleccionada = _misEntidades.first;
        } else {
          // Refrescar datos de la seleccionada
          _entidadSeleccionada = _misEntidades
              .firstWhere((e) => e.id == _entidadSeleccionada!.id);
        }
      } else {
        _entidadSeleccionada = null;
      }
    } catch (e) {
      print('[flow] EntidadProvider ERROR: $e');
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Entidad?> crearEntidad({
    required String denominacion,
    String? direccion,
    String? telefono,
    required String ownerUuid,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final entidad = await EntidadService.createEntidad(
        denominacion: denominacion,
        direccion: direccion,
        telefono: telefono,
        ownerUuid: ownerUuid,
      );
      _misEntidades.add(entidad);
      _misEntidades.sort((a, b) => a.denominacion.compareTo(b.denominacion));
      print('[flow] EntidadProvider → entidad creada id: ${entidad.id}');
      _isLoading = false;
      notifyListeners();
      return entidad;
    } catch (e) {
      print('[flow] EntidadProvider crearEntidad ERROR: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> actualizarEntidad({
    required int id,
    required String denominacion,
    String? direccion,
    String? telefono,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await EntidadService.updateEntidad(
        id: id,
        denominacion: denominacion,
        direccion: direccion,
        telefono: telefono,
      );
      final idx = _misEntidades.indexWhere((e) => e.id == id);
      if (idx != -1) _misEntidades[idx] = updated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('[flow] EntidadProvider actualizarEntidad ERROR: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void limpiar() {
    _misEntidades = [];
    _entidadSeleccionada = null;
    _error = null;
    notifyListeners();
  }

  Future<void> recargarSiEsNecesario(String uuidUsuario) async {
    if (_misEntidades.isEmpty && !_isLoading) {
      await cargarMisEntidades(uuidUsuario);
    }
  }
}
