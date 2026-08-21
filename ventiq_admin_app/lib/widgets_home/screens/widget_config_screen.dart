import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/store_selector_service.dart';
import '../../services/user_preferences_service.dart';
import '../data/widget_config_store.dart';
import '../home_widget_service.dart';
import '../models/widget_config.dart';
import '../widget_keys.dart';
import 'widget_product_picker_screen.dart';

/// Pantalla única de configuración de una instancia de widget.
///
/// Android la abre vía `android:configure` (MainActivity) cuando el usuario
/// suelta el widget en el escritorio; también se puede abrir desde el propio
/// widget para reconfigurarlo.
///
/// [finishOnSave] es true cuando venimos del flujo de configuración de Android:
/// al guardar hay que devolver RESULT_OK con el appWidgetId, o el lanzador
/// descarta el widget.
class WidgetConfigScreen extends StatefulWidget {
  const WidgetConfigScreen({
    super.key,
    required this.type,
    required this.appWidgetId,
    this.finishOnSave = false,
    this.onFinish,
  });

  final HomeWidgetType type;
  final int appWidgetId;
  final bool finishOnSave;

  /// Callback para cerrar el flujo nativo de configuración.
  final Future<void> Function()? onFinish;

  @override
  State<WidgetConfigScreen> createState() => _WidgetConfigScreenState();
}

class _WidgetConfigScreenState extends State<WidgetConfigScreen> {
  /// Mismos periodos que el selector del DashboardScreen.
  static const List<String> _periodos = [
    '3 años',
    '1 año',
    '6 meses',
    '3 meses',
    '1 mes',
    'Semana',
    'Día',
  ];

  final StoreSelectorService _storeSelector = StoreSelectorService();
  final UserPreferencesService _prefs = UserPreferencesService();

  bool _loading = true;
  bool _saving = false;

  List<Store> _stores = const [];
  int? _storeId;
  String? _storeName;

  String _periodo = '1 mes';
  String _modo = WidgetKeys.modoRealtime;
  DateTime? _desde;
  DateTime? _hasta;

  int? _productoId;
  String? _productoNombre;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Configuración previa (reconfiguración de un widget ya colocado).
    final existing = await WidgetConfigStore.load(
      widget.type,
      widget.appWidgetId,
    );

    await _storeSelector.initialize();
    var stores = _storeSelector.userStores;

    if (stores.isEmpty) {
      // Fallback: las tiendas guardadas en preferencias tras el login.
      final raw = await _prefs.getUserStores();
      stores = raw
          .map((json) {
            try {
              return Store.fromJson(json);
            } catch (_) {
              return null;
            }
          })
          .whereType<Store>()
          .toList();
    }

    final activeStoreId = await _prefs.getIdTienda();
    final initialStoreId = existing?.storeId ??
        _storeSelector.selectedStore?.id ??
        activeStoreId ??
        (stores.isNotEmpty ? stores.first.id : null);

    if (!mounted) return;
    setState(() {
      _stores = stores;
      _storeId = initialStoreId;
      _storeName = existing?.storeName ?? _nameForStore(stores, initialStoreId);
      _periodo = existing?.periodo ?? '1 mes';
      _modo = existing?.modo ?? WidgetKeys.modoRealtime;
      _desde = existing?.desde;
      _hasta = existing?.hasta;
      _productoId = existing?.productoId;
      _productoNombre = existing?.productoNombre;
      _loading = false;
    });
  }

  static String? _nameForStore(List<Store> stores, int? storeId) {
    if (storeId == null) return null;
    for (final store in stores) {
      if (store.id == storeId) return store.denominacion;
    }
    return null;
  }

  bool get _canSave {
    if (_storeId == null) return false;
    switch (widget.type) {
      case HomeWidgetType.miniDashboard:
        return true;
      case HomeWidgetType.sales:
        if (_modo == WidgetKeys.modoRange) {
          return _desde != null && _hasta != null;
        }
        return true;
      case HomeWidgetType.product:
        return _productoId != null;
    }
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);

    final config = WidgetConfig(
      type: widget.type,
      appWidgetId: widget.appWidgetId,
      storeId: _storeId,
      storeName: _storeName ?? _nameForStore(_stores, _storeId),
      periodo: widget.type == HomeWidgetType.miniDashboard ? _periodo : null,
      modo: widget.type == HomeWidgetType.sales ? _modo : null,
      desde: widget.type == HomeWidgetType.sales ? _desde : null,
      hasta: widget.type == HomeWidgetType.sales ? _hasta : null,
      productoId: widget.type == HomeWidgetType.product ? _productoId : null,
      productoNombre:
          widget.type == HomeWidgetType.product ? _productoNombre : null,
    );

    await HomeWidgetService.saveConfigAndRefresh(config);

    if (widget.finishOnSave && widget.onFinish != null) {
      await widget.onFinish!();
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Widget configurado')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('Configurar ${widget.type.label}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StoreSelector(
                  stores: _stores,
                  storeId: _storeId,
                  onChanged: (store) => setState(() {
                    _storeId = store.id;
                    _storeName = store.denominacion;
                    // Cambiar de tienda invalida el producto elegido.
                    if (widget.type == HomeWidgetType.product) {
                      _productoId = null;
                      _productoNombre = null;
                    }
                  }),
                ),
                const SizedBox(height: 16),
                ..._typeSpecificFields(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _canSave && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? 'Guardando…' : 'Guardar y activar'),
          ),
        ),
      ),
    );
  }

  List<Widget> _typeSpecificFields() {
    switch (widget.type) {
      case HomeWidgetType.miniDashboard:
        return [
          _SectionCard(
            title: 'Periodo',
            subtitle: 'El mismo selector que usa el Dashboard.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _periodos.map((periodo) {
                final selected = periodo == _periodo;
                return ChoiceChip(
                  label: Text(periodo),
                  selected: selected,
                  onSelected: (_) => setState(() => _periodo = periodo),
                );
              }).toList(),
            ),
          ),
        ];

      case HomeWidgetType.sales:
        return [
          _SectionCard(
            title: 'Modo',
            subtitle:
                'Tiempo Real muestra el día en curso y se refresca solo. '
                'Rango de fechas queda fijo en las fechas que elijas.',
            child: Column(
              children: [
                RadioListTile<String>(
                  value: WidgetKeys.modoRealtime,
                  groupValue: _modo,
                  title: const Text('Tiempo Real'),
                  secondary: const Icon(
                    Icons.bolt,
                    color: AppColors.success,
                  ),
                  onChanged: (value) => setState(() => _modo = value!),
                ),
                RadioListTile<String>(
                  value: WidgetKeys.modoRange,
                  groupValue: _modo,
                  title: const Text('Rango de fechas'),
                  secondary: const Icon(
                    Icons.date_range,
                    color: AppColors.info,
                  ),
                  onChanged: (value) => setState(() => _modo = value!),
                ),
              ],
            ),
          ),
          if (_modo == WidgetKeys.modoRange) ...[
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Fechas',
              child: Column(
                children: [
                  _DateTile(
                    label: 'Desde',
                    value: _desde,
                    onPick: (date) => setState(() => _desde = date),
                  ),
                  _DateTile(
                    label: 'Hasta',
                    value: _hasta,
                    onPick: (date) => setState(() => _hasta = date),
                  ),
                ],
              ),
            ),
          ],
        ];

      case HomeWidgetType.product:
        return [
          _SectionCard(
            title: 'Producto',
            subtitle: 'Se mostrarán su precio, costos, ventas e inventario.',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2, color: AppColors.primary),
              title: Text(_productoNombre ?? 'Seleccionar producto'),
              subtitle: _productoId == null
                  ? const Text('Ninguno seleccionado')
                  : Text('ID $_productoId'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _storeId == null ? null : _pickProduct,
            ),
          ),
        ];
    }
  }

  Future<void> _pickProduct() async {
    final storeId = _storeId;
    if (storeId == null) return;

    final result = await Navigator.of(context).push<({int id, String nombre})>(
      MaterialPageRoute(
        builder: (_) => WidgetProductPickerScreen(storeId: storeId),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _productoId = result.id;
      _productoNombre = result.nombre;
    });
  }
}

class _StoreSelector extends StatelessWidget {
  const _StoreSelector({
    required this.stores,
    required this.storeId,
    required this.onChanged,
  });

  final List<Store> stores;
  final int? storeId;
  final ValueChanged<Store> onChanged;

  @override
  Widget build(BuildContext context) {
    if (stores.isEmpty) {
      return const _SectionCard(
        title: 'Tienda',
        child: Text(
          'No hay tiendas disponibles. Inicia sesión en la app primero.',
        ),
      );
    }

    return _SectionCard(
      title: 'Tienda',
      subtitle: 'Cada widget puede seguir una tienda distinta.',
      child: Column(
        children: stores.map((store) {
          return RadioListTile<int>(
            value: store.id,
            groupValue: storeId,
            title: Text(store.denominacion),
            subtitle: store.direccion == null ? null : Text(store.direccion!),
            onChanged: (_) => onChanged(store),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.calendar_today, size: 20),
      title: Text(label),
      subtitle: Text(
        value == null
            ? 'Sin definir'
            : '${value!.day.toString().padLeft(2, '0')}/'
                '${value!.month.toString().padLeft(2, '0')}/${value!.year}',
      ),
      trailing: const Icon(Icons.edit, size: 18),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 1),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}
