import 'package:flutter/material.dart';
import 'package:ventiq_admin_app/services/user_preferences_service.dart';
import 'package:ventiq_admin_app/services/permissions_service.dart';
import 'package:ventiq_admin_app/config/app_colors.dart';

/// Pantalla para seleccionar la tienda a la que acceder
class StoreSelectionScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;
  final int defaultStoreId;

  const StoreSelectionScreen({
    super.key,
    required this.stores,
    required this.defaultStoreId,
  });

  @override
  State<StoreSelectionScreen> createState() => _StoreSelectionScreenState();
}

class _StoreSelectionScreenState extends State<StoreSelectionScreen> {
  late int _selectedStoreId;
  final _userPreferencesService = UserPreferencesService();
  final _permissionsService = PermissionsService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedStoreId = widget.defaultStoreId;
  }

  Future<void> _selectStore() async {
    setState(() => _isLoading = true);

    try {
      // Actualizar la tienda seleccionada
      await _userPreferencesService.updateSelectedStore(_selectedStoreId);
      
      print('✅ Tienda seleccionada: $_selectedStoreId');

      if (mounted) {
        // Navegar al dashboard
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      print('❌ Error al seleccionar tienda: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar tienda: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar Tienda'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Text(
                'Selecciona la tienda a la que deseas acceder',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tienes acceso a ${widget.stores.length} tienda${widget.stores.length > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),

              // Lista de tiendas
              Expanded(
                child: ListView.builder(
                  itemCount: widget.stores.length,
                  itemBuilder: (context, index) {
                    final store = widget.stores[index];
                    final storeId = store['id_tienda'] as int;
                    final storeName = store['app_dat_tienda']?['denominacion'] ??
                        'Tienda ${store['id_tienda']}';
                    final isSelected = _selectedStoreId == storeId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _buildStoreCard(
                        storeId: storeId,
                        storeName: storeName,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() => _selectedStoreId = storeId);
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Botón de confirmación
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _selectStore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Continuar',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoreCard({
    required int storeId,
    required String storeName,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.white,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icono de tienda
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.store,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Información de la tienda
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    storeName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.primary : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: $storeId',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Radio button
            Radio<int>(
              value: storeId,
              groupValue: _selectedStoreId,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedStoreId = value);
                }
              },
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
