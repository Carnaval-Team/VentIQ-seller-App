import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/campo_adicional.dart';

/// Formulario dinámico que construye inputs a partir de una lista de
/// [CampoAdicional] (texto / número / seleccionable / sí-no). Validación incluida.
///
/// Soporta:
///  - valores por defecto por campo (fijos o condicionales según otro campo),
///  - recálculo automático de los defaults dependientes cuando cambia el campo
///    del que dependen (sin pisar lo que el usuario ya editó a mano).
///
/// Uso:
///   final key = GlobalKey`<DatosAdicionalesFormState>`();
///   DatosAdicionalesForm(key: key, campos: servicio.camposAdicionales)
///   ...
///   if (key.currentState!.validar()) {
///     final valores = key.currentState!.valores;
///   }
class DatosAdicionalesForm extends StatefulWidget {
  final List<CampoAdicional> campos;
  final ValueChanged<Map<String, dynamic>>? onChanged;
  final Map<String, dynamic>? initialValues;
  const DatosAdicionalesForm({super.key, required this.campos, this.onChanged, this.initialValues});

  @override
  State<DatosAdicionalesForm> createState() => DatosAdicionalesFormState();
}

class DatosAdicionalesFormState extends State<DatosAdicionalesForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String?> _selects = {};
  final Map<String, bool> _bools = {};

  /// Claves que el usuario ha editado manualmente: no se sobreescriben al
  /// recalcular los defaults condicionales.
  final Set<String> _editadosPorUsuario = {};

  @override
  void initState() {
    super.initState();
    // 1. Sembrar cada campo con el valor inicial (si viene) o vacío.
    for (final c in widget.campos) {
      final initVal = widget.initialValues?[c.clave];
      final tieneInit = initVal != null && initVal.toString().isNotEmpty;
      if (tieneInit) _editadosPorUsuario.add(c.clave);
      if (c.tipo == TipoCampo.select) {
        final s = initVal?.toString();
        _selects[c.clave] = (s != null && c.opciones.contains(s)) ? s : null;
      } else if (c.tipo == TipoCampo.booleano) {
        _bools[c.clave] = _asBool(initVal);
      } else {
        final ctrl = TextEditingController(text: initVal?.toString() ?? '');
        ctrl.addListener(() => _onTextChanged(c.clave));
        _ctrls[c.clave] = ctrl;
      }
    }
    // 2. Aplicar defaults (fijos y condicionales) a los campos sin valor inicial.
    for (final c in widget.campos) {
      if (_editadosPorUsuario.contains(c.clave)) continue;
      _aplicarDefault(c);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  static bool _asBool(Object? v) {
    if (v is bool) return v;
    final s = v?.toString().toLowerCase().trim();
    return s == 'true' || s == 'sí' || s == 'si' || s == '1';
  }

  /// Aplica el default (resuelto según el estado actual) al control del campo,
  /// sin marcarlo como editado por el usuario.
  void _aplicarDefault(CampoAdicional c) {
    final def = c.defaultPara(_snapshot());
    if (def == null) return;
    switch (c.tipo) {
      case TipoCampo.booleano:
        _bools[c.clave] = _asBool(def);
        break;
      case TipoCampo.select:
        final s = def.toString();
        _selects[c.clave] = c.opciones.contains(s) ? s : _selects[c.clave];
        break;
      default:
        final ctrl = _ctrls[c.clave];
        if (ctrl != null) ctrl.text = def.toString();
    }
  }

  /// Estado actual de todos los campos (incluye vacíos), para evaluar reglas.
  Map<String, dynamic> _snapshot() {
    final out = <String, dynamic>{};
    for (final c in widget.campos) {
      switch (c.tipo) {
        case TipoCampo.select:
          out[c.clave] = _selects[c.clave];
          break;
        case TipoCampo.booleano:
          out[c.clave] = _bools[c.clave] ?? false;
          break;
        default:
          out[c.clave] = _ctrls[c.clave]?.text.trim();
      }
    }
    return out;
  }

  void _onTextChanged(String clave) {
    _editadosPorUsuario.add(clave);
    _recalcularDependientes(clave);
    _notifyChange();
  }

  /// Recalcula el default de los campos cuyas reglas dependen de [claveCambiada]
  /// y que el usuario no haya editado manualmente.
  void _recalcularDependientes(String claveCambiada) {
    var cambio = false;
    for (final c in widget.campos) {
      if (_editadosPorUsuario.contains(c.clave)) continue;
      final depende = c.reglas.any((r) => r.siClave == claveCambiada);
      if (!depende) continue;
      _aplicarDefault(c);
      cambio = true;
    }
    if (cambio && mounted) setState(() {});
  }

  void _notifyChange() {
    widget.onChanged?.call(valores);
  }

  /// Valida todos los campos. Devuelve true si son válidos.
  bool validar() => _formKey.currentState?.validate() ?? true;

  /// Valores actuales { clave: valor }. Para número devuelve int si es entero;
  /// para booleano devuelve bool.
  Map<String, dynamic> get valores {
    final out = <String, dynamic>{};
    for (final c in widget.campos) {
      if (c.tipo == TipoCampo.select) {
        if (_selects[c.clave] != null) out[c.clave] = _selects[c.clave];
      } else if (c.tipo == TipoCampo.booleano) {
        out[c.clave] = _bools[c.clave] ?? false;
      } else {
        final txt = _ctrls[c.clave]!.text.trim();
        if (txt.isEmpty) continue;
        if (c.tipo == TipoCampo.numero) {
          out[c.clave] = int.tryParse(txt) ?? txt;
        } else {
          out[c.clave] = txt;
        }
      }
    }
    return out;
  }

  String? _validarCampo(CampoAdicional c, String? v) {
    final txt = (v ?? '').trim();
    if (c.requerido && txt.isEmpty) return 'Requerido';
    if (txt.isEmpty) return null;
    if (c.tipo == TipoCampo.numero) {
      final n = int.tryParse(txt);
      if (n == null) return 'Debe ser un número';
      if (c.min != null && txt.length < c.min!) {
        return 'Mínimo ${c.min} dígitos';
      }
      if (c.max != null && txt.length > c.max!) {
        return 'Máximo ${c.max} dígitos';
      }
    } else {
      if (c.min != null && txt.length < c.min!) {
        return 'Mínimo ${c.min} caracteres';
      }
      if (c.max != null && txt.length > c.max!) {
        return 'Máximo ${c.max} caracteres';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.campos.isEmpty) return const SizedBox.shrink();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in widget.campos) ...[
            _buildCampo(c),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildCampo(CampoAdicional c) {
    final label = c.requerido ? '${c.etiqueta} *' : c.etiqueta;
    if (c.tipo == TipoCampo.booleano) {
      return InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Switch(
              value: _bools[c.clave] ?? false,
              onChanged: (v) {
                setState(() => _bools[c.clave] = v);
                _editadosPorUsuario.add(c.clave);
                _recalcularDependientes(c.clave);
                _notifyChange();
              },
            ),
          ],
        ),
      );
    }
    if (c.tipo == TipoCampo.select) {
      return DropdownButtonFormField<String>(
        value: _selects[c.clave],
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.arrow_drop_down_circle_outlined),
          border: const OutlineInputBorder(),
        ),
        items: c.opciones
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) {
          setState(() => _selects[c.clave] = v);
          _editadosPorUsuario.add(c.clave);
          _recalcularDependientes(c.clave);
          _notifyChange();
        },
        validator: (v) =>
            (c.requerido && (v == null || v.isEmpty)) ? 'Requerido' : null,
      );
    }
    final esNumero = c.tipo == TipoCampo.numero;
    return TextFormField(
      controller: _ctrls[c.clave],
      keyboardType: esNumero ? TextInputType.number : TextInputType.text,
      inputFormatters:
          esNumero ? [FilteringTextInputFormatter.digitsOnly] : null,
      maxLength: esNumero ? c.max : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(esNumero ? Icons.numbers : Icons.short_text),
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: (v) => _validarCampo(c, v),
    );
  }
}

/// Helper: ¿la lista de campos exige al menos un dato? (para decidir si mostrar el form)
bool requiereDatos(List<CampoAdicional> campos) => campos.isNotEmpty;
