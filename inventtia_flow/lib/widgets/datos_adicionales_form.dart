import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/campo_adicional.dart';

/// Formulario dinámico que construye inputs a partir de una lista de
/// [CampoAdicional] (texto / número / seleccionable). Validación incluida.
///
/// Uso:
///   final key = GlobalKey<DatosAdicionalesFormState>();
///   DatosAdicionalesForm(key: key, campos: servicio.camposAdicionales)
///   ...
///   if (key.currentState!.validar()) {
///     final valores = key.currentState!.valores;
///   }
class DatosAdicionalesForm extends StatefulWidget {
  final List<CampoAdicional> campos;
  const DatosAdicionalesForm({super.key, required this.campos});

  @override
  State<DatosAdicionalesForm> createState() => DatosAdicionalesFormState();
}

class DatosAdicionalesFormState extends State<DatosAdicionalesForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String?> _selects = {};

  @override
  void initState() {
    super.initState();
    for (final c in widget.campos) {
      if (c.tipo == TipoCampo.select) {
        _selects[c.clave] = null;
      } else {
        _ctrls[c.clave] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Valida todos los campos. Devuelve true si son válidos.
  bool validar() => _formKey.currentState?.validate() ?? true;

  /// Valores actuales { clave: valor }. Para número, devuelve int si es entero.
  Map<String, dynamic> get valores {
    final out = <String, dynamic>{};
    for (final c in widget.campos) {
      if (c.tipo == TipoCampo.select) {
        if (_selects[c.clave] != null) out[c.clave] = _selects[c.clave];
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
        onChanged: (v) => setState(() => _selects[c.clave] = v),
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
