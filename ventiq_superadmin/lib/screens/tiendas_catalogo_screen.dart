import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../models/catalog_store.dart';
import '../services/catalog_store_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';

class TiendasCatalogoScreen extends StatefulWidget {
  const TiendasCatalogoScreen({super.key});

  @override
  State<TiendasCatalogoScreen> createState() => _TiendasCatalogoScreenState();
}

class _TiendasCatalogoScreenState extends State<TiendasCatalogoScreen> {
  List<CatalogStore> _stores = [];
  List<CatalogStore> _filteredStores = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final Set<int> _updatingStoreIds = <int>{};

  Future<int?> _askValidationDays(CatalogStore store) async {
    final controller = TextEditingController();

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Validar "${store.denominacion}"'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('¿Cuántos días estará validada en el catálogo?'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Días de validación',
                    hintText: 'Ej: 30',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final days = int.tryParse(controller.text.trim());
                Navigator.of(context).pop(days);
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() => _isLoading = true);

    try {
      final stores = await CatalogStoreService.getCatalogStores();

      if (!mounted) return;

      setState(() {
        _stores = stores;
        _filteredStores = stores;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar tiendas catálogo: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _applyFilters() {
    setState(() {
      final query = _searchQuery.trim().toLowerCase();
      if (query.isEmpty) {
        _filteredStores = _stores;
        return;
      }

      _filteredStores =
          _stores.where((store) {
            final haystack =
                <String?>[
                  store.denominacion,
                  store.direccion,
                  store.ubicacion,
                  store.nombrePais,
                  store.nombreEstado,
                  store.provincia,
                  store.phone,
                ].whereType<String>().join(' ').toLowerCase();

            return haystack.contains(query);
          }).toList();
    });
  }

  Future<void> _toggleValidada(CatalogStore store, bool value) async {
    if (_updatingStoreIds.contains(store.id)) return;

    if (!value) {
      await _updateStoreFlags(store, validada: false);
      return;
    }

    final days = await _askValidationDays(store);
    if (days == null) return;
    if (days <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Los días de validación deben ser mayores que 0.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _updatingStoreIds.add(store.id);
      _stores =
          _stores
              .map((s) => s.id == store.id ? s.copyWith(validada: true) : s)
              .toList();
    });
    _applyFilters();

    final subscriptionOk = await CatalogStoreService.renewCatalogSubscription(
      storeId: store.id,
      tiempoSuscripcionDias: days,
    );

    final storeOk =
        subscriptionOk
            ? await CatalogStoreService.updateCatalogStore(store.id, {
              'validada': true,
            })
            : false;

    if (!mounted) return;

    if (!subscriptionOk || !storeOk) {
      if (subscriptionOk && !storeOk) {
        final latestId =
            await CatalogStoreService.getLatestActiveCatalogSubscriptionId(
              store.id,
            );
        if (latestId != null) {
          await CatalogStoreService.expireCatalogSubscriptionById(latestId);
        }
      }

      setState(() {
        _stores =
            _stores
                .map(
                  (s) =>
                      s.id == store.id
                          ? s.copyWith(validada: store.validada)
                          : s,
                )
                .toList();
      });
      _applyFilters();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo validar la tienda. Intenta nuevamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    }

    setState(() {
      _updatingStoreIds.remove(store.id);
    });
  }

  Future<void> _toggleMostrarEnCatalogo(CatalogStore store, bool value) async {
    await _updateStoreFlags(store, mostrarEnCatalogo: value);
  }

  Future<void> _updateStoreFlags(
    CatalogStore store, {
    bool? validada,
    bool? mostrarEnCatalogo,
  }) async {
    if (_updatingStoreIds.contains(store.id)) return;

    setState(() {
      _updatingStoreIds.add(store.id);
      _stores =
          _stores
              .map(
                (s) =>
                    s.id == store.id
                        ? s.copyWith(
                          validada: validada,
                          mostrarEnCatalogo: mostrarEnCatalogo,
                        )
                        : s,
              )
              .toList();
    });
    _applyFilters();

    final updates = <String, dynamic>{};
    if (validada != null) updates['validada'] = validada;
    if (mostrarEnCatalogo != null)
      updates['mostrar_en_catalogo'] = mostrarEnCatalogo;

    final ok = await CatalogStoreService.updateCatalogStore(store.id, updates);

    if (!mounted) return;

    if (!ok) {
      setState(() {
        _stores =
            _stores
                .map(
                  (s) =>
                      s.id == store.id
                          ? s.copyWith(
                            validada: store.validada,
                            mostrarEnCatalogo: store.mostrarEnCatalogo,
                          )
                          : s,
                )
                .toList();
      });
      _applyFilters();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar la tienda. Intenta nuevamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    }

    setState(() {
      _updatingStoreIds.remove(store.id);
    });
  }

  Future<void> _openWhatsApp(CatalogStore store) async {
    final phoneRaw = (store.phone ?? '').trim();

    if (phoneRaw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta tienda no tiene teléfono registrado.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final digits = _phoneToWaDigits(phoneRaw);

    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teléfono inválido para WhatsApp.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final url = Uri.parse('https://wa.me/$digits');

    final can = await canLaunchUrl(url);
    if (!can) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp en este dispositivo.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  String _phoneToWaDigits(String phoneRaw) {
    var s = phoneRaw.trim();

    if (s.startsWith('00')) {
      s = s.substring(2);
    }

    s = s.replaceAll(RegExp(r'[^0-9]'), '');

    return s;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenWidth);

    final total = _stores.length;
    final validadas = _stores.where((s) => s.validada).length;
    final visibles = _stores.where((s) => s.mostrarEnCatalogo).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiendas Catálogo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStores,
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
                child: Column(
                  children: [
                    _buildHeaderStats(
                      total: total,
                      validadas: validadas,
                      visibles: visibles,
                    ),
                    const SizedBox(height: 12),
                    _buildSearch(),
                    const SizedBox(height: 16),
                    Expanded(
                      child:
                          _filteredStores.isEmpty
                              ? _buildEmptyState()
                              : isDesktop
                              ? _buildDesktopTable()
                              : _buildMobileList(),
                    ),
                  ],
                ),
              ),
      floatingActionButton:
          !isDesktop
              ? FloatingActionButton.extended(
                onPressed: _loadStores,
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar'),
              )
              : null,
    );
  }

  Widget _buildHeaderStats({
    required int total,
    required int validadas,
    required int visibles,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Total',
            value: total.toString(),
            icon: Icons.storefront,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            title: 'Validadas',
            value: validadas.toString(),
            icon: Icons.verified,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            title: 'En Catálogo',
            value: visibles.toString(),
            icon: Icons.public,
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Buscar por nombre, ubicación, teléfono...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            _searchQuery = value;
            _applyFilters();
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 40,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'No hay tiendas catálogo',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Solo se muestran las tiendas con only_catalogo = true',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTable() {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Tiendas en Catálogo (${_filteredStores.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: SingleChildScrollView(
                      child: DataTable(
                        showCheckboxColumn: false,
                        columnSpacing: 24,
                        horizontalMargin: 16,
                        headingRowHeight: 56,
                        dataRowHeight: 76,
                        columns: const [
                          DataColumn(
                            label: Text(
                              'Tienda',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Ubicación',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Validada',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Mostrar en catálogo',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Contacto',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                        rows:
                            _filteredStores.map((store) {
                              final isUpdating = _updatingStoreIds.contains(
                                store.id,
                              );

                              return DataRow(
                                cells: [
                                  DataCell(
                                    SizedBox(
                                      width: 340,
                                      child: Row(
                                        children: [
                                          _buildStoreAvatar(store),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  store.denominacion,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  store.phone?.isNotEmpty ==
                                                          true
                                                      ? store.phone!
                                                      : 'Sin teléfono',
                                                  style:
                                                      Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 520,
                                      child: Text(
                                        store.ubicacionCompleta,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child:
                                          isUpdating
                                              ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                              : Switch(
                                                value: store.validada,
                                                onChanged:
                                                    (v) => _toggleValidada(
                                                      store,
                                                      v,
                                                    ),
                                              ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child:
                                          isUpdating
                                              ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                              : Switch(
                                                value: store.mostrarEnCatalogo,
                                                onChanged:
                                                    (v) =>
                                                        _toggleMostrarEnCatalogo(
                                                          store,
                                                          v,
                                                        ),
                                              ),
                                    ),
                                  ),
                                  DataCell(
                                    Center(
                                      child: IconButton(
                                        tooltip: 'WhatsApp',
                                        onPressed:
                                            isUpdating
                                                ? null
                                                : () => _openWhatsApp(store),
                                        icon: const Icon(
                                          Icons.chat,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.builder(
      itemCount: _filteredStores.length,
      itemBuilder: (context, index) {
        final store = _filteredStores[index];
        final isUpdating = _updatingStoreIds.contains(store.id);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStoreAvatar(store),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            store.denominacion,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            store.ubicacionCompleta,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            store.phone?.isNotEmpty == true
                                ? store.phone!
                                : 'Sin teléfono',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'WhatsApp',
                      onPressed: isUpdating ? null : () => _openWhatsApp(store),
                      icon: const Icon(Icons.chat, color: AppColors.success),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.verified,
                            size: 18,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Validada')),
                          if (isUpdating)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Switch(
                              value: store.validada,
                              onChanged: (v) => _toggleValidada(store, v),
                            ),
                        ],
                      ),
                      const Divider(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.public,
                            size: 18,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Mostrar en catálogo')),
                          if (isUpdating)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Switch(
                              value: store.mostrarEnCatalogo,
                              onChanged:
                                  (v) => _toggleMostrarEnCatalogo(store, v),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStoreAvatar(CatalogStore store) {
    final img = (store.imagenUrl ?? '').trim();

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child:
            img.isEmpty
                ? Center(
                  child: Text(
                    store.denominacion.isNotEmpty
                        ? store.denominacion[0].toUpperCase()
                        : 'T',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
                : Image.network(
                  img,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Text(
                        store.denominacion.isNotEmpty
                            ? store.denominacion[0].toUpperCase()
                            : 'T',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}
