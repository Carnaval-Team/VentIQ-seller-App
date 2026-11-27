import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/financial_service.dart';
import '../services/permissions_service.dart';
import '../services/user_preferences_service.dart';

/// Nomenclador global de tipos de costo adicional (Flete, Aduana, Importadora,
/// Seguro...). Diseño: `docs/design/compras-costos-adicionales.png`
/// (Stitch `d810b6b7ab4e46cfb22b28f2f4a01d6f`).
///
/// **Solo superadministrador.** La tabla es de solo lectura para el cliente y
/// la escritura va por `fn_cont_tipo_costo_guardar` /
/// `fn_cont_tipo_costo_eliminar`, que comprueban el rol en el servidor; esta
/// pantalla además oculta la edición si el usuario no es superadmin.
class CostTypesManagementScreen extends StatefulWidget {
  const CostTypesManagementScreen({Key? key}) : super(key: key);

  @override
  State<CostTypesManagementScreen> createState() =>
      _CostTypesManagementScreenState();
}

class _CostTypesManagementScreenState extends State<CostTypesManagementScreen> {
  final FinancialService _financialService = FinancialService();
  final PermissionsService _permissions = PermissionsService();

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();

  List<Map<String, dynamic>> _costTypes = [];
  Map<String, dynamic>? _seleccionado;
  bool _afectaMargen = true;
  bool _isLoading = true;
  bool _isSuperAdmin = false;
  bool _accessChecked = false;
  bool _guardando = false;

  /// Tienda del usuario e interruptor de ámbito para el alta.
  int? _idTienda;
  bool _crearGlobal = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final isSa = await _permissions.isSuperAdmin();
    int? tienda;
    try {
      tienda = await UserPreferencesService().getIdTienda();
    } catch (_) {
      tienda = null;
    }
    if (!mounted) return;
    setState(() {
      _isSuperAdmin = isSa;
      _idTienda = tienda;
      _accessChecked = true;
    });
    // Los conceptos son de lectura para cualquier autenticado; la escritura la
    // valida el servidor (dueño/gerente de la tienda o superadmin).
    await _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _isLoading = true);
    try {
      final tipos =
          await _financialService.getCostTypes(idTienda: _idTienda);
      if (!mounted) return;
      setState(() {
        _costTypes = tipos;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('Error cargando los conceptos: $e', error: true);
    }
  }

  void _snack(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  static String _texto(Object? v) => v?.toString().trim() ?? '';

  bool get _esImportadora {
    final actual = _seleccionado;
    return actual != null &&
        _texto(actual['denominacion']).toLowerCase() == 'importadora';
  }

  void _seleccionar(Map<String, dynamic>? tipo) {
    setState(() {
      _seleccionado = tipo;
      _nombreCtrl.text = _texto(tipo?['denominacion']);
      _descripcionCtrl.text = _texto(tipo?['descripcion']);
      _afectaMargen = tipo?['afecta_margen'] != false;
    });
  }

  void _nuevo() {
    _seleccionar(null);
    setState(() => _crearGlobal = false);
    _formKey.currentState?.reset();
  }

  void _cancelar() {
    if (_seleccionado == null) {
      _nombreCtrl.clear();
      _descripcionCtrl.clear();
      setState(() => _afectaMargen = true);
    } else {
      _seleccionar(_seleccionado);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final idTienda = _seleccionado != null
          ? (_seleccionado!['id_tienda'] as num?)?.toInt()
          : (_crearGlobal && _isSuperAdmin ? null : _idTienda);
      final res = await _financialService.saveCostType(
        id: (_seleccionado?['id'] as num?)?.toInt(),
        name: _nombreCtrl.text.trim(),
        description: _descripcionCtrl.text.trim(),
        afectaMargen: _afectaMargen,
        idTienda: idTienda,
      );
      final id = (res['id'] as num?)?.toInt();
      await _cargar();
      final guardado =
          _costTypes.where((t) => (t['id'] as num?)?.toInt() == id).toList();
      _seleccionar(guardado.isEmpty ? null : guardado.first);
      _snack(res['creado'] == true
          ? 'Concepto creado.'
          : 'Concepto actualizado.');
    } catch (e) {
      _snack('No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    final actual = _seleccionado;
    if (actual == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar concepto'),
        content: Text(
          'Se eliminará «${_texto(actual['denominacion'])}» del nomenclador. '
          'No se puede deshacer. Un concepto en uso no se elimina: el servidor '
          'lo rechaza y se dice cuántas referencias tiene.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _guardando = true);
    try {
      await _financialService.deleteCostType(
        (actual['id'] as num).toInt(),
      );
      _seleccionar(null);
      await _cargar();
      _snack('Concepto eliminado.');
    } catch (e) {
      _snack('No se pudo eliminar: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  static String _fecha(Object? valor) {
    final texto = _texto(valor);
    if (texto.isEmpty) return '—';
    final fecha = DateTime.tryParse(texto);
    if (fecha == null) return '—';
    final d = fecha.day.toString().padLeft(2, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    return '$d/$m/${fecha.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Costos adicionales',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: !_isLoading ? _cargar : null,
          ),
        ],
      ),
      body: !_accessChecked || _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (!_isSuperAdmin && _idTienda == null)
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Inicia sesión con una tienda para gestionar sus conceptos de '
                  'costo. Los globales los administra el superadmin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
              ),
            )
          : _cuerpo(),
    );
  }

  Widget _cuerpo() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth >= 900;
        final lista = _panelLista();
        final editor = _panelEditor();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _bannerSuperadmin(),
              const SizedBox(height: 12),
              Expanded(
                child: ancho
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: lista),
                          const SizedBox(width: 16),
                          SizedBox(width: 380, child: editor),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            lista,
                            const SizedBox(height: 16),
                            editor,
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bannerSuperadmin() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 18, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isSuperAdmin
                  ? 'Superadministrador · los conceptos globales los usa toda '
                      'la suite; los de tienda, solo su tienda.'
                  : 'Conceptos de tu tienda + los globales de la suite. '
                      'Puedes crear y editar los de tu tienda.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelLista() {
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Conceptos configurados',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${_costTypes.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _guardando ? null : _nuevo,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nuevo concepto'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_costTypes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay conceptos. Cree el primero con «Nuevo concepto».',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else if (ancho)
            for (final tipo in _costTypes)
              _filaTabla(tipo)
          else
            for (final tipo in _costTypes) _filaCompacta(tipo),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Text(
              'Un concepto en uso no se puede eliminar. «Importadora» es '
              'obligatorio: el aterrizaje lo resuelve por nombre.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaTabla(Map<String, dynamic> tipo) {
    final seleccionado =
        (_seleccionado?['id'] as num?)?.toInt() == (tipo['id'] as num?)?.toInt();
    final esImp = _texto(tipo['denominacion']).toLowerCase() == 'importadora';
    return InkWell(
      onTap: _guardando ? null : () => _seleccionar(tipo),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: seleccionado ? AppColors.primary.withValues(alpha: 0.06) : null,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _texto(tipo['denominacion']),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (esImp) ...[
                    const SizedBox(width: 6),
                    _chip('Obligatorio', AppColors.primary),
                  ],
                  const SizedBox(width: 6),
                  _chip(
                    tipo['id_tienda'] == null ? 'Global' : 'Tienda',
                    tipo['id_tienda'] == null
                        ? AppColors.textSecondary
                        : AppColors.secondary,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                _texto(tipo['descripcion']),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: Row(
                children: [
                  Icon(
                    tipo['afecta_margen'] == false
                        ? Icons.remove_circle_outline
                        : Icons.check_circle_outline,
                    size: 16,
                    color: tipo['afecta_margen'] == false
                        ? AppColors.textLight
                        : AppColors.success,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tipo['afecta_margen'] == false ? 'No' : 'Sí',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                _fecha(tipo['created_at']),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Widget _filaCompacta(Map<String, dynamic> tipo) {
    final seleccionado =
        (_seleccionado?['id'] as num?)?.toInt() == (tipo['id'] as num?)?.toInt();
    final esImp = _texto(tipo['denominacion']).toLowerCase() == 'importadora';
    return InkWell(
      onTap: _guardando ? null : () => _seleccionar(tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: seleccionado ? AppColors.primary.withValues(alpha: 0.06) : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _texto(tipo['denominacion']),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (esImp) ...[
                        const SizedBox(width: 6),
                        _chip('Obligatorio', AppColors.primary),
                      ],
                      const SizedBox(width: 6),
                      _chip(
                        tipo['id_tienda'] == null ? 'Global' : 'Tienda',
                        tipo['id_tienda'] == null
                            ? AppColors.textSecondary
                            : AppColors.secondary,
                      ),
                    ],
                  ),
                  if (_texto(tipo['descripcion']).isNotEmpty)
                    Text(
                      _texto(tipo['descripcion']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              tipo['afecta_margen'] == false ? 'No afecta' : 'Afecta',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tipo['afecta_margen'] == false
                    ? AppColors.textSecondary
                    : AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ámbito del concepto: global (toda la suite) o de la tienda actual.
  Widget _bloqueAlcance({required bool esNuevo, required bool esGlobal}) {
    if (!esNuevo && !_isSuperAdmin) {
      return Row(
        children: [
          _chip(
            esGlobal ? 'Global' : 'Tienda',
            esGlobal ? AppColors.textSecondary : AppColors.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              esGlobal
                  ? 'Global: solo el superadmin lo edita.'
                  : 'De la tienda ${_idTienda ?? ''}.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    if (esNuevo && !_isSuperAdmin) {
      return Text(
        'Se creará para la tienda ${_idTienda ?? ''}.',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }
    if (esNuevo && _isSuperAdmin) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _crearGlobal,
        onChanged: _guardando
            ? null
            : (v) => setState(() => _crearGlobal = v),
        title: const Text(
          'Concepto global',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _crearGlobal
              ? 'Lo verán todas las tiendas.'
              : 'Solo lo verá la tienda ${_idTienda ?? 'actual'}.',
          style: const TextStyle(fontSize: 11),
        ),
      );
    }
    return Row(
      children: [
        _chip(
          esGlobal ? 'Global' : 'Tienda',
          esGlobal ? AppColors.textSecondary : AppColors.secondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            esGlobal ? 'Global: toda la suite.' : 'De la tienda ${_idTienda ?? ''}.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _panelEditor() {
    final esNuevo = _seleccionado == null;
    final id = (_seleccionado?['id'] as num?)?.toInt();
    final esGlobal = _seleccionado?['id_tienda'] == null;
    final soloLectura = !esNuevo && esGlobal && !_isSuperAdmin;
    final editable = !_guardando && !soloLectura;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                esNuevo ? 'Nuevo concepto' : 'Editar concepto',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (!esNuevo)
                Text(
                  _texto(_seleccionado?['denominacion']),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 8),
              _bloqueAlcance(esNuevo: esNuevo, esGlobal: esGlobal),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombreCtrl,
                enabled: editable,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Requerido';
                  if (t.length > 80) return 'Máximo 80 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descripcionCtrl,
                enabled: editable,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Naturaleza',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: Row(
                  children: [
                    const Expanded(child: Text('Gasto')),
                    Icon(Icons.lock_outline,
                        size: 16, color: AppColors.textLight),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Todo costo adicional es un gasto; el ingreso no capitaliza.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _afectaMargen,
                onChanged: editable
                    ? (v) => setState(() => _afectaMargen = v)
                    : null,
                title: const Text(
                  'Afecta margen',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Si está activo, el costo capitaliza en el inventario y en el '
                  'precio promedio.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              if (!esNuevo) ...[
                const Divider(height: 16),
                Text(
                  'Creado ${_fecha(_seleccionado?['created_at'])} · id $id',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_guardando || soloLectura) ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Guardar cambios'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _guardando ? null : _cancelar,
                  child: const Text('Cancelar'),
                ),
              ),
              if (!esNuevo) ...[
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: Tooltip(
                    message: _esImportadora
                        ? 'Importadora es obligatorio: el aterrizaje lo resuelve por nombre'
                        : 'Un concepto en uso no se puede eliminar',
                    child: TextButton.icon(
                      onPressed: (_guardando || _esImportadora || soloLectura)
                          ? null
                          : _eliminar,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Eliminar concepto'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        backgroundColor: AppColors.error.withValues(alpha: 0.08),
                        minimumSize: const Size.fromHeight(38),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}