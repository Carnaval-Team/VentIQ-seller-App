import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/store_registration_service.dart';

class StoreRegistrationScreen extends StatefulWidget {
  const StoreRegistrationScreen({super.key});

  @override
  State<StoreRegistrationScreen> createState() => _StoreRegistrationScreenState();
}

class _StoreRegistrationScreenState extends State<StoreRegistrationScreen> {
  final PageController _pageController = PageController();
  final StoreRegistrationService _registrationService = StoreRegistrationService();
  
  int _currentStep = 0;
  bool _isLoading = false;
  
  // Formulario controllers
  final _userFormKey = GlobalKey<FormState>();
  final _storeFormKey = GlobalKey<FormState>();
  
  // Datos del usuario
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  
  // Datos de la tienda
  final _storeNameController = TextEditingController();
  final _storeAddressController = TextEditingController();
  final _storeLocationController = TextEditingController();
  
  // Datos obligatorios
  List<Map<String, dynamic>> _tpvData = [];
  List<Map<String, dynamic>> _almacenesData = [];
  List<Map<String, dynamic>> _personalData = [];
  
  // Los roles y layout types se manejan directamente en los métodos

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _storeNameController.dispose();
    _storeAddressController.dispose();
    _storeLocationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Registrar Nueva Tienda',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Header con gradiente
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary,
                  AppColors.primary.withOpacity(0.8),
                ],
              ),
            ),
            child: Column(
              children: [
                // Progress indicator mejorado
                _buildModernProgressIndicator(),
                const SizedBox(height: 16),
              ],
            ),
          ),
          
          // Content con mejor diseño
          Expanded(
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 600), // Limitar ancho en pantallas grandes
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildUserRegistrationStep(),
                  _buildStoreInfoStep(),
                  _buildOptionalDataStep(),
                  _buildConfirmationStep(),
                ],
              ),
            ),
          ),
          
          // Navigation buttons mejorados
          _buildModernNavigationButtons(),
        ],
      ),
    );
  }

  Widget _buildModernProgressIndicator() {
    final steps = [
      {'title': 'Usuario', 'icon': Icons.person},
      {'title': 'Tienda', 'icon': Icons.store},
      {'title': 'Configuración', 'icon': Icons.settings},
      {'title': 'Confirmación', 'icon': Icons.check_circle},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          // Título del paso actual
          // Text(
          //   'Paso ${_currentStep + 1} de ${steps.length}',
          //   style: const TextStyle(
          //     color: Colors.white70,
          //     fontSize: 14,
          //     fontWeight: FontWeight.w500,
          //   ),
          // ),
          // const SizedBox(height: 8),
          // Text(
          //   steps[_currentStep]['title'] as String,
          //   style: const TextStyle(
          //     color: Colors.white,
          //     fontSize: 20,
          //     fontWeight: FontWeight.bold,
          //   ),
          // ),
          // const SizedBox(height: 20),
          
          // Indicador de progreso centrado
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(steps.length, (index) {
                  final isActive = index <= _currentStep;
                  final isCompleted = index < _currentStep;
                  final isCurrent = index == _currentStep;
                  
                  return Expanded(
                    child: Row(
                      children: [
                        // Círculo del paso
                        Container(
                          width: isCurrent ? 48 : 40,
                          height: isCurrent ? 48 : 40,
                          decoration: BoxDecoration(
                            color: isCompleted 
                                ? Colors.green 
                                : isActive 
                                    ? Colors.white 
                                    : Colors.white.withOpacity(0.3),
                            shape: BoxShape.circle,
                            border: isCurrent ? Border.all(
                              color: Colors.white,
                              width: 3,
                            ) : null,
                            boxShadow: isCurrent ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ] : null,
                          ),
                          child: Icon(
                            isCompleted 
                                ? Icons.check 
                                : steps[index]['icon'] as IconData,
                            color: isCompleted 
                                ? Colors.white 
                                : isActive 
                                    ? AppColors.primary 
                                    : Colors.white.withOpacity(0.6),
                            size: isCurrent ? 24 : 20,
                          ),
                        ),
                        
                        // Línea conectora
                        if (index < steps.length - 1)
                          Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: index < _currentStep 
                                    ? Colors.green 
                                    : Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRegistrationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Form(
            key: _userFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header del paso
                Center(
                  child: Column(
                    children: [
                      // Container(
                      //   width: 80,
                      //   height: 80,
                      //   decoration: BoxDecoration(
                      //     gradient: AppColors.primaryGradient,
                      //     borderRadius: BorderRadius.circular(20),
                      //     boxShadow: [
                      //       BoxShadow(
                      //         color: AppColors.primary.withOpacity(0.3),
                      //         blurRadius: 15,
                      //         offset: const Offset(0, 5),
                      //       ),
                      //     ],
                      //   ),
                      //   // child: const Icon(
                      //   //   Icons.person_add,
                      //   //   size: 40,
                      //   //   color: Colors.white,
                      //   // ),
                      // ),
                      const SizedBox(height: 20),
                      const Text(
                        'Registro de Usuario',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Crea la cuenta del administrador de la tienda',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
            
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Nombre Completo',
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa el nombre completo';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa un email';
                }
                if (!value.contains('@')) {
                  return 'Ingresa un email válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: Icon(Icons.lock),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingresa una contraseña';
                }
                if (value.length < 6) {
                  return 'La contraseña debe tener al menos 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar Contraseña',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) {
                if (value != _passwordController.text) {
                  return 'Las contraseñas no coinciden';
                }
                return null;
              },
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Form(
            key: _storeFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header del paso
                Center(
                  child: Column(
                    children: [
                      // Container(
                      //   width: 80,
                      //   height: 80,
                      //   decoration: BoxDecoration(
                      //     gradient: AppColors.primaryGradient,
                      //     borderRadius: BorderRadius.circular(20),
                      //     boxShadow: [
                      //       BoxShadow(
                      //         color: AppColors.primary.withOpacity(0.3),
                      //         blurRadius: 15,
                      //         offset: const Offset(0, 5),
                      //       ),
                      //     ],
                      //   ),
                      //   child: const Icon(
                      //     Icons.store,
                      //     size: 40,
                      //     color: Colors.white,
                      //   ),
                      // ),
                      const SizedBox(height: 20),
                      const Text(
                        'Información de la Tienda',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Configura los datos básicos de tu tienda',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
            
            TextFormField(
              controller: _storeNameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la Tienda',
                prefixIcon: Icon(Icons.store),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa el nombre de la tienda';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _storeAddressController,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                prefixIcon: Icon(Icons.location_on),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa la dirección';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _storeLocationController,
              decoration: const InputDecoration(
                labelText: 'Ubicación (Ciudad, País)',
                prefixIcon: Icon(Icons.place),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa la ubicación';
                }
                return null;
              },
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionalDataStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header del paso
              Center(
                child: Column(
                  children: [
                    // Container(
                    //   width: 80,
                    //   height: 80,
                    //   decoration: BoxDecoration(
                    //     gradient: AppColors.primaryGradient,
                    //     borderRadius: BorderRadius.circular(20),
                    //     boxShadow: [
                    //       BoxShadow(
                    //         color: AppColors.primary.withOpacity(0.3),
                    //         blurRadius: 15,
                    //         offset: const Offset(0, 5),
                    //       ),
                    //     ],
                    //   ),
                    //   child: const Icon(
                    //     Icons.settings,
                    //     size: 40,
                    //     color: Colors.white,
                    //   ),
                    // ),
                    const SizedBox(height: 20),
                    const Text(
                      'Configuración Adicional',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Configura TPVs, almacenes y personal (opcional)',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Almacenes Section
              _buildSectionCard(
                title: 'Almacenes',
                icon: Icons.warehouse,
                count: _almacenesData.length,
                items: _almacenesData,
                onAdd: _showAddAlmacenDialog,
                onEdit: (index) => _showEditAlmacenDialog(index),
                onDelete: (index) => _deleteAlmacen(index),
                required: true,
              ),
              const SizedBox(height: 16),

          // TPVs Section
          _buildSectionCard(
            title: 'TPVs',
            icon: Icons.point_of_sale,
            count: _tpvData.length,
            items: _tpvData,
            onAdd: _showAddTPVDialog,
            onEdit: (index) => _showEditTPVDialog(index),
            onDelete: (index) => _deleteTPV(index),
            required: true,
          ),
          const SizedBox(height: 16),
          

          
          // Personal Section
          _buildSectionCard(
            title: 'Personal',
            icon: Icons.people,
            count: _personalData.length,
            items: _personalData,
            onAdd: _showAddPersonalDialog,
            onEdit: (index) => _showEditPersonalDialog(index),
            onDelete: (index) => _deletePersonal(index),
            required: true,
          ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required int count,
    required List<Map<String, dynamic>> items,
    required VoidCallback onAdd,
    required Function(int) onEdit,
    required Function(int) onDelete,
    required bool required,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (required && count == 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'REQUERIDO',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: onAdd,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      elevation: 2,
                    ),
                    child: const Icon(Icons.add, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: Text(
                  'No hay ${title.toLowerCase()} configurados',
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['denominacion'] ?? '${item['nombres']} ${item['apellidos']}' ?? 'Sin nombre',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: item['is_main_user'] == true 
                                          ? Colors.green.shade700 
                                          : Colors.black,
                                    ),
                                  ),
                                ),
                                if (item['is_main_user'] == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'PROPIETARIO',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (item['direccion'] != null)
                              Text(
                                item['direccion'],
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            if (item['tipo_rol'] != null)
                              Text(
                                'Rol: ${item['tipo_rol']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: item['is_main_user'] == true 
                                      ? Colors.green.shade600 
                                      : Colors.grey,
                                  fontWeight: item['is_main_user'] == true 
                                      ? FontWeight.w500 
                                      : FontWeight.normal,
                                ),
                              ),
                            if (item['almacen_asignado'] != null && item['tipo_rol'] == 'almacenero')
                              Text(
                                'Almacén: ${item['almacen_asignado']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                            if (item['tpv_asignado'] != null && item['tipo_rol'] == 'vendedor')
                              Text(
                                'TPV: ${item['tpv_asignado']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Solo mostrar botones de editar/eliminar si no es el usuario principal
                      if (items[index]['is_main_user'] != true) ...[
                        IconButton(
                          onPressed: () => onEdit(index),
                          icon: const Icon(Icons.edit, size: 20),
                          color: Colors.blue,
                        ),
                        IconButton(
                          onPressed: () => onDelete(index),
                          icon: const Icon(Icons.delete, size: 20),
                          color: Colors.red,
                        ),
                      ] else ...[
                        // Mostrar indicador de usuario principal
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.admin_panel_settings, size: 16, color: Colors.green),
                              SizedBox(width: 4),
                              Text(
                                'ADMIN',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header del paso
              Center(
                child: Column(
                  children: [
                    // Container(
                    //   width: 80,
                    //   height: 80,
                    //   decoration: BoxDecoration(
                    //     gradient: AppColors.primaryGradient,
                    //     borderRadius: BorderRadius.circular(20),
                    //     boxShadow: [
                    //       BoxShadow(
                    //         color: AppColors.primary.withOpacity(0.3),
                    //         blurRadius: 15,
                    //         offset: const Offset(0, 5),
                    //       ),
                    //     ],
                    //   ),
                    //   child: const Icon(
                    //     Icons.check_circle,
                    //     size: 40,
                    //     color: Colors.white,
                    //   ),
                    // ),
                    const SizedBox(height: 20),
                    const Text(
                      'Confirmación',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Revisa la información antes de crear la tienda',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Información del Usuario',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Nombre: ${_fullNameController.text}'),
                  Text('Email: ${_emailController.text}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Información de la Tienda',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Nombre: ${_storeNameController.text}'),
                  Text('Dirección: ${_storeAddressController.text}'),
                  Text('Ubicación: ${_storeLocationController.text}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configuración Inicial',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // TPVs
                  Text(
                    'TPVs (${_tpvData.length}):',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  ..._tpvData.map((tpv) => Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('• ${tpv['denominacion']} (Almacén: ${tpv['almacen_asignado'] ?? 'No asignado'})'),
                  )).toList(),
                  const SizedBox(height: 8),
                  
                  // Almacenes
                  Text(
                    'Almacenes (${_almacenesData.length}):',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  ..._almacenesData.map((almacen) => Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('• ${almacen['denominacion']} - ${almacen['direccion']}'),
                  )).toList(),
                  const SizedBox(height: 8),
                  
                  // Personal
                  Text(
                    'Personal (${_personalData.length}):',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  ..._personalData.map((personal) {
                    String asignacion = '';
                    if (personal['almacen_asignado'] != null) {
                      asignacion = ' (Almacén: ${personal['almacen_asignado']})';
                    } else if (personal['tpv_asignado'] != null) {
                      asignacion = ' (TPV: ${personal['tpv_asignado']})';
                    }
                    return Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4),
                      child: Text('• ${personal['nombres']} ${personal['apellidos']} - ${personal['tipo_rol']}$asignacion'),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
          
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Creando tienda...'),
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Row(
              children: [
                // Botón Anterior
                if (_currentStep > 0)
                  Expanded(
                    child: Container(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _previousStep,
                        icon: const Icon(Icons.arrow_back, size: 20),
                        label: const Text(
                          'Anterior',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                
                if (_currentStep > 0) const SizedBox(width: 16),
                
                // Botón Siguiente/Crear
                Expanded(
                  flex: _currentStep == 0 ? 1 : 1,
                  child: Container(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _nextStep,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _currentStep == 3 
                                  ? Icons.check_circle 
                                  : Icons.arrow_forward,
                              size: 20,
                            ),
                      label: Text(
                        _isLoading 
                            ? 'Procesando...'
                            : _currentStep == 3 
                                ? 'Crear Tienda' 
                                : 'Siguiente',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: AppColors.primary.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextStep() {
    if (_currentStep < 3) {
      if (_validateCurrentStep()) {
        setState(() {
          _currentStep++;
        });
        
        // Si navegamos al paso 3 (configuración), agregar automáticamente al usuario principal
        if (_currentStep == 2) {
          _addMainUserToPersonal();
        }
        
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else {
      _createStore();
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _userFormKey.currentState?.validate() ?? false;
      case 1:
        return _storeFormKey.currentState?.validate() ?? false;
      case 2:
        // Validar que hay al menos uno de cada
        if (_tpvData.isEmpty) {
          _showErrorDialog('Debes configurar al menos un TPV (Punto de Venta)');
          return false;
        }
        if (_almacenesData.isEmpty) {
          _showErrorDialog('Debes configurar al menos un almacén');
          return false;
        }
        if (_personalData.isEmpty) {
          _showErrorDialog('Debes configurar al menos un miembro del personal');
          return false;
        }
        return true;
      case 3:
        return true; // Confirmación
      default:
        return false;
    }
  }

  Future<void> _createStore() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _registrationService.registerUserAndCreateStore(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        denominacionTienda: _storeNameController.text.trim(),
        direccionTienda: _storeAddressController.text.trim(),
        ubicacionTienda: _storeLocationController.text.trim(),
        tpvData: _tpvData.isEmpty ? null : _tpvData,
        almacenesData: _almacenesData.isEmpty ? null : _almacenesData,
        personalData: _personalData.isEmpty ? null : _personalData,
      );

      if (result['success']) {
        _showSuccessDialog();
      } else {
        _showErrorDialog(result['message'] ?? 'Error desconocido');
      }
    } catch (e) {
      _showErrorDialog('Error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('¡Éxito!'),
          ],
        ),
        content: const Text(
          'La tienda ha sido creada exitosamente. El usuario administrador puede iniciar sesión ahora.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Cerrar diálogo
              Navigator.of(context).pop(); // Volver al login
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ===== MÉTODOS PARA TPVs =====
  void _showAddTPVDialog() {
    final nameController = TextEditingController();
    String? selectedAlmacen;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar TPV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del TPV',
                  hintText: 'Ej: TPV Principal, Caja 1',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedAlmacen,
                decoration: const InputDecoration(
                  labelText: 'Almacén Asignado',
                ),
                items: _almacenesData.map((almacen) {
                  return DropdownMenuItem<String>(
                    value: almacen['denominacion'],
                    child: Text(almacen['denominacion']),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedAlmacen = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Selecciona un almacén';
                  }
                  return null;
                },
              ),
              if (_almacenesData.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Debes crear al menos un almacén primero',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty && 
                    selectedAlmacen != null && 
                    _almacenesData.isNotEmpty) {
                  setState(() {
                    _tpvData.add({
                      'denominacion': nameController.text.trim(),
                      'almacen_asignado': selectedAlmacen,
                    });
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTPVDialog(int index) {
    final tpv = _tpvData[index];
    final nameController = TextEditingController(text: tpv['denominacion']);
    String? selectedAlmacen = tpv['almacen_asignado'];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar TPV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del TPV',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedAlmacen,
                decoration: const InputDecoration(
                  labelText: 'Almacén Asignado',
                ),
                items: _almacenesData.map((almacen) {
                  return DropdownMenuItem<String>(
                    value: almacen['denominacion'],
                    child: Text(almacen['denominacion']),
                  );
                }).toList(),
                onChanged: (value) {
                  setDialogState(() {
                    selectedAlmacen = value;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty && selectedAlmacen != null) {
                  setState(() {
                    _tpvData[index]['denominacion'] = nameController.text.trim();
                    _tpvData[index]['almacen_asignado'] = selectedAlmacen;
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTPV(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar TPV'),
        content: Text('¿Estás seguro de eliminar "${_tpvData[index]['denominacion']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _tpvData.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // ===== MÉTODOS PARA ALMACENES =====
  void _showAddAlmacenDialog() {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final locationController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Almacén'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre del Almacén',
                hintText: 'Ej: Almacén Principal',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                hintText: 'Dirección del almacén',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Ubicación',
                hintText: 'Ciudad, País',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                setState(() {
                  _almacenesData.add({
                    'denominacion': nameController.text.trim(),
                    'direccion': addressController.text.trim(),
                    'ubicacion': locationController.text.trim(),
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _showEditAlmacenDialog(int index) {
    final almacen = _almacenesData[index];
    final nameController = TextEditingController(text: almacen['denominacion']);
    final addressController = TextEditingController(text: almacen['direccion']);
    final locationController = TextEditingController(text: almacen['ubicacion']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Almacén'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre del Almacén',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: 'Dirección',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Ubicación',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                setState(() {
                  _almacenesData[index]['denominacion'] = nameController.text.trim();
                  _almacenesData[index]['direccion'] = addressController.text.trim();
                  _almacenesData[index]['ubicacion'] = locationController.text.trim();
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _deleteAlmacen(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Almacén'),
        content: Text('¿Estás seguro de eliminar "${_almacenesData[index]['denominacion']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _almacenesData.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  // ===== MÉTODOS PARA PERSONAL =====
  void _showAddPersonalDialog() {
    final nombresController = TextEditingController();
    final apellidosController = TextEditingController();
    String? selectedRole;
    String? selectedAlmacen;
    String? selectedTPV;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar Personal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombresController,
                  decoration: const InputDecoration(
                    labelText: 'Nombres',
                    hintText: 'Nombres del empleado',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: apellidosController,
                  decoration: const InputDecoration(
                    labelText: 'Apellidos',
                    hintText: 'Apellidos del empleado',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Rol',
                  ),
                  items: [
                    const DropdownMenuItem(value: 'gerente', child: Text('Gerente')),
                    const DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                    const DropdownMenuItem(value: 'almacenero', child: Text('Almacenero')),
                    const DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedRole = value;
                      // Reset assignments when role changes
                      selectedAlmacen = null;
                      selectedTPV = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // Mostrar dropdown de almacén para almaceneros
                if (selectedRole == 'almacenero')
                  DropdownButtonFormField<String>(
                    value: selectedAlmacen,
                    decoration: const InputDecoration(
                      labelText: 'Almacén Asignado',
                    ),
                    items: _almacenesData.map((almacen) {
                      return DropdownMenuItem<String>(
                        value: almacen['denominacion'],
                        child: Text(almacen['denominacion']),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedAlmacen = value;
                      });
                    },
                  ),
                
                // Mostrar dropdown de TPV para vendedores
                if (selectedRole == 'vendedor')
                  DropdownButtonFormField<String>(
                    value: selectedTPV,
                    decoration: const InputDecoration(
                      labelText: 'TPV Asignado',
                    ),
                    items: _tpvData.map((tpv) {
                      return DropdownMenuItem<String>(
                        value: tpv['denominacion'],
                        child: Text(tpv['denominacion']),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedTPV = value;
                      });
                    },
                  ),
                
                // Mostrar advertencias si no hay almacenes o TPVs
                if (selectedRole == 'almacenero' && _almacenesData.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Debes crear al menos un almacén primero',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                
                if (selectedRole == 'vendedor' && _tpvData.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Debes crear al menos un TPV primero',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                bool canAdd = nombresController.text.trim().isNotEmpty &&
                    apellidosController.text.trim().isNotEmpty &&
                    selectedRole != null;
                
                // Validaciones específicas por rol
                if (selectedRole == 'almacenero') {
                  canAdd = canAdd && selectedAlmacen != null && _almacenesData.isNotEmpty;
                } else if (selectedRole == 'vendedor') {
                  canAdd = canAdd && selectedTPV != null && _tpvData.isNotEmpty;
                }
                
                if (canAdd) {
                  setState(() {
                    final personalItem = {
                      'nombres': nombresController.text.trim(),
                      'apellidos': apellidosController.text.trim(),
                      'tipo_rol': selectedRole,
                      'id_roll': _getRoleId(selectedRole!),
                      'uuid': 'PLACEHOLDER_USER_UUID', // Se reemplazará con el UUID real
                    };
                    
                    // Agregar asignaciones específicas
                    if (selectedRole == 'almacenero' && selectedAlmacen != null) {
                      personalItem['almacen_asignado'] = selectedAlmacen;
                    } else if (selectedRole == 'vendedor' && selectedTPV != null) {
                      personalItem['tpv_asignado'] = selectedTPV;
                    }
                    
                    _personalData.add(personalItem);
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPersonalDialog(int index) {
    final personal = _personalData[index];
    final nombresController = TextEditingController(text: personal['nombres']);
    final apellidosController = TextEditingController(text: personal['apellidos']);
    String? selectedRole = personal['tipo_rol'];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Personal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombresController,
                decoration: const InputDecoration(
                  labelText: 'Nombres',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: apellidosController,
                decoration: const InputDecoration(
                  labelText: 'Apellidos',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                ),
                items: [
                  const DropdownMenuItem(value: 'gerente', child: Text('Gerente')),
                  const DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                  const DropdownMenuItem(value: 'almacenero', child: Text('Almacenero')),
                  const DropdownMenuItem(value: 'vendedor', child: Text('Vendedor')),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    selectedRole = value;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nombresController.text.trim().isNotEmpty &&
                    apellidosController.text.trim().isNotEmpty &&
                    selectedRole != null) {
                  setState(() {
                    _personalData[index]['nombres'] = nombresController.text.trim();
                    _personalData[index]['apellidos'] = apellidosController.text.trim();
                    _personalData[index]['tipo_rol'] = selectedRole;
                    _personalData[index]['id_roll'] = _getRoleId(selectedRole!);
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _deletePersonal(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Personal'),
        content: Text('¿Estás seguro de eliminar a "${_personalData[index]['nombres']} ${_personalData[index]['apellidos']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _personalData.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  int _getRoleId(String roleType) {
    switch (roleType) {
      case 'gerente':
        return 1;
      case 'supervisor':
        return 2;
      case 'almacenero':
        return 3;
      case 'vendedor':
        return 4;
      default:
        return 4; // Default to vendedor
    }
  }

  // Agregar automáticamente al usuario principal con roles de gerente y supervisor
  void _addMainUserToPersonal() {
    final fullName = _fullNameController.text.trim();
    if (fullName.isEmpty) return;
    
    // Separar nombres y apellidos (simple split por espacio)
    final nameParts = fullName.split(' ');
    final nombres = nameParts.isNotEmpty ? nameParts.first : 'Usuario';
    final apellidos = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : 'Principal';
    
    // Verificar si ya existe el usuario principal para evitar duplicados
    final existingMainUser = _personalData.where((p) => p['is_main_user'] == true).toList();
    if (existingMainUser.isNotEmpty) {
      return; // Ya existe, no agregar duplicados
    }
    
    // Agregar como Gerente
    final gerenteItem = {
      'nombres': nombres,
      'apellidos': apellidos,
      'tipo_rol': 'gerente',
      'id_roll': 1,
      'uuid': 'MAIN_USER_UUID', // Se reemplazará con el UUID real del usuario creado
      'is_main_user': true, // Marca especial para identificar al usuario principal
      'is_editable': false, // No se puede editar
    };
    
    // Agregar como Supervisor
    final supervisorItem = {
      'nombres': nombres,
      'apellidos': apellidos,
      'tipo_rol': 'supervisor',
      'id_roll': 2,
      'uuid': 'MAIN_USER_UUID', // Se reemplazará con el UUID real del usuario creado
      'is_main_user': true, // Marca especial para identificar al usuario principal
      'is_editable': false, // No se puede editar
    };
    
    setState(() {
      _personalData.insert(0, gerenteItem); // Insertar al inicio
      _personalData.insert(1, supervisorItem); // Insertar después del gerente
    });
    
    print('✅ Usuario principal agregado automáticamente como Gerente y Supervisor');
    print('   - Nombres: $nombres');
    print('   - Apellidos: $apellidos');
  }
}
