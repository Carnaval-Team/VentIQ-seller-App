import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../models/subscription.dart';
import '../models/subscription_history.dart';
import '../services/subscription_service.dart';
import '../services/user_preferences_service.dart';
import '../services/subscription_guard_service.dart';
import '../services/auth_service.dart';

class SubscriptionDetailScreen extends StatefulWidget {
  const SubscriptionDetailScreen({super.key});

  @override
  State<SubscriptionDetailScreen> createState() => _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen> {
  final _subscriptionService = SubscriptionService();
  final _userPreferencesService = UserPreferencesService();
  final _subscriptionGuard = SubscriptionGuardService();
  final _authService = AuthService();
  
  Subscription? _activeSubscription;
  List<Subscription> _subscriptionHistory = [];
  List<SubscriptionHistory> _changeHistory = [];
  bool _isLoading = true;
  int? _idTienda;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionData();
  }

  Future<void> _loadSubscriptionData() async {
    setState(() => _isLoading = true);
    
    try {
      _idTienda = await _userPreferencesService.getIdTienda();
      if (_idTienda == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      // Cargar suscripción activa
      _activeSubscription = await _subscriptionService.getActiveSubscription(_idTienda!);
      
      // Cargar historial de suscripciones
      _subscriptionHistory = await _subscriptionService.getSubscriptionHistory(_idTienda!);
      
      // Cargar historial de cambios si hay suscripción activa
      if (_activeSubscription != null) {
        _changeHistory = await _subscriptionService.getSubscriptionChangeHistory(_activeSubscription!.id);
      }
    } catch (e) {
      print('❌ Error cargando datos de suscripción: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando datos de suscripción: $e'),
            backgroundColor: AppColors.error,
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Detalles de Suscripción',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Mostrar botón de logout si no hay suscripción activa
          if (_activeSubscription == null || !_activeSubscription!.isActive)
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Colors.white),
              tooltip: 'Cerrar Sesión',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSubscriptionData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mostrar mensaje especial si no hay suscripción activa
                    if (_activeSubscription == null || !_activeSubscription!.isActive) ...[
                      _buildNoActiveSubscriptionCard(),
                      const SizedBox(height: 24),
                    ],
                    
                    if (_activeSubscription != null) ...[
                      _buildActiveSubscriptionCard(),
                      const SizedBox(height: 24),
                      _buildFeaturesCard(),
                      const SizedBox(height: 24),
                    ],
                    _buildSubscriptionHistoryCard(),
                    if (_changeHistory.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildChangeHistoryCard(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildActiveSubscriptionCard() {
    final subscription = _activeSubscription!;
    final isExpiringSoon = subscription.diasRestantes > 0 && subscription.diasRestantes <= 7;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user,
                  color: subscription.isActive ? AppColors.success : AppColors.warning,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suscripción Actual',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        subscription.planDenominacion ?? 'Plan desconocido',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: subscription.isActive ? AppColors.success : AppColors.warning,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    subscription.estadoText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (subscription.planDescripcion != null) ...[
              Text(
                subscription.planDescripcion!,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Layout responsivo para información de suscripción
            LayoutBuilder(
              builder: (context, constraints) {
                final isLargeScreen = constraints.maxWidth > 600;
                
                if (isLargeScreen && subscription.fechaFin != null) {
                  // Pantallas grandes: 3 elementos en una fila
                  return Row(
                    children: [
                      Expanded(
                        child: _buildInfoItem(
                          'Precio Mensual',
                          subscription.planPrecioMensual != null 
                              ? '\$${subscription.planPrecioMensual!.toStringAsFixed(2)}'
                              : 'N/A',
                          Icons.attach_money,
                        ),
                      ),
                      Expanded(
                        child: _buildInfoItem(
                          'Fecha Inicio',
                          DateFormat('dd/MM/yyyy').format(subscription.fechaInicio),
                          Icons.calendar_today,
                        ),
                      ),
                      Expanded(
                        child: _buildInfoItem(
                          'Fecha Vencimiento',
                          DateFormat('dd/MM/yyyy').format(subscription.fechaFin!),
                          Icons.event,
                          isExpiringSoon ? AppColors.warning : null,
                        ),
                      ),
                    ],
                  );
                } else {
                  // Pantallas pequeñas: layout original
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoItem(
                              'Precio Mensual',
                              subscription.planPrecioMensual != null 
                                  ? '\$${subscription.planPrecioMensual!.toStringAsFixed(2)}'
                                  : 'N/A',
                              Icons.attach_money,
                            ),
                          ),
                          Expanded(
                            child: _buildInfoItem(
                              'Fecha Inicio',
                              DateFormat('dd/MM/yyyy').format(subscription.fechaInicio),
                              Icons.calendar_today,
                            ),
                          ),
                        ],
                      ),
                      if (subscription.fechaFin != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoItem(
                                'Fecha Vencimiento',
                                DateFormat('dd/MM/yyyy').format(subscription.fechaFin!),
                                Icons.event,
                                isExpiringSoon ? AppColors.warning : null,
                              ),
                            ),
                            if (subscription.diasRestantes > 0)
                              Expanded(
                                child: _buildInfoItem(
                                  'Días Restantes',
                                  '${subscription.diasRestantes} días',
                                  Icons.hourglass_empty,
                                  isExpiringSoon ? AppColors.warning : AppColors.success,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                }
              },
            ),
            
            // Mostrar días restantes en pantallas grandes si es necesario
            if (subscription.diasRestantes > 0) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final isLargeScreen = constraints.maxWidth > 600;
                  if (isLargeScreen && subscription.fechaFin != null) {
                    // En pantallas grandes, mostrar días restantes por separado
                    return Column(
                      children: [
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoItem(
                                'Días Restantes',
                                '${subscription.diasRestantes} días',
                                Icons.hourglass_empty,
                                isExpiringSoon ? AppColors.warning : AppColors.success,
                              ),
                            ),
                            const Expanded(child: SizedBox()), // Espaciador
                            const Expanded(child: SizedBox()), // Espaciador
                          ],
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink(); // No mostrar nada en pantallas pequeñas (ya se muestra arriba)
                },
              ),
            ],

            if (isExpiringSoon) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: AppColors.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tu suscripción vence pronto. Contacta al administrador para renovar.',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesCard() {
    final subscription = _activeSubscription!;
    final funciones = subscription.planFuncionesHabilitadas;
    
    if (funciones == null || funciones.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.featured_play_list, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Funciones Habilitadas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: funciones.entries
                  .where((entry) => entry.value == true)
                  .map((entry) => _buildFeatureChip(entry.key))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureChip(String feature) {
    final featureName = _getFeatureName(feature);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            color: AppColors.primary,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            featureName,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionHistoryCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Historial de Suscripciones',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_subscriptionHistory.isEmpty)
              Center(
                child: Text(
                  'No hay historial de suscripciones',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _subscriptionHistory.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final subscription = _subscriptionHistory[index];
                  final isActive = subscription.id == _activeSubscription?.id;
                  
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.success : AppColors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isActive ? Icons.verified : Icons.history,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      subscription.planDenominacion ?? 'Plan desconocido',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estado: ${subscription.estadoText}',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        Text(
                          'Inicio: ${DateFormat('dd/MM/yyyy').format(subscription.fechaInicio)}',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        if (subscription.fechaFin != null)
                          Text(
                            'Fin: ${DateFormat('dd/MM/yyyy').format(subscription.fechaFin!)}',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                    trailing: isActive
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'ACTUAL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeHistoryCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.change_history, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Historial de Cambios',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _changeHistory.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final change = _changeHistory[index];
                
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    change.tipoOperacion,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (change.descripcionCambio.isNotEmpty)
                        Text(
                          change.descripcionCambio,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(change.fechaCambio),
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      if (change.motivo != null)
                        Text(
                          'Motivo: ${change.motivo}',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon, [Color? color]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _getFeatureName(String feature) {
    switch (feature) {
      case 'inventario':
        return 'Gestión de Inventario';
      case 'ventas':
        return 'Punto de Venta';
      case 'reportes':
        return 'Reportes Avanzados';
      case 'usuarios_ilimitados':
        return 'Usuarios Ilimitados';
      case 'tiendas_multiples':
        return 'Múltiples Tiendas';
      case 'integraciones':
        return 'Integraciones';
      case 'soporte_prioritario':
        return 'Soporte Prioritario';
      case 'backup_automatico':
        return 'Backup Automático';
      case 'analytics':
        return 'Analytics Avanzado';
      case 'api_access':
        return 'Acceso API';
      default:
        return feature.replaceAll('_', ' ').toUpperCase();
    }
  }

  Future<void> _logout() async {
    try {
      // Mostrar diálogo de confirmación
      final shouldLogout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cerrar Sesión'),
          content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Cerrar Sesión'),
            ),
          ],
        ),
      );

      if (shouldLogout == true) {
        // Cerrar sesión en Supabase y limpiar datos
        await _authService.signOut();
        await _userPreferencesService.clearUserData();
        _subscriptionGuard.clearCache();
        
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('❌ Error durante logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cerrar sesión: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _sendSupportEmail() async {
    try {
      final tiendaId = await _userPreferencesService.getIdTienda() ?? 'No disponible';
      final userEmail = await _userPreferencesService.getUserEmail() ?? 'No disponible';
      
      final subject = 'Solicitud de Activación de Suscripción - Inventtia';
      final body = '''Hola equipo de soporte,

Necesito ayuda con mi suscripción de Inventtia.

Detalles de mi cuenta:
- Tienda ID: $tiendaId
- Usuario: $userEmail

Problema:
Mi suscripción no está activa y no puedo acceder a las funcionalidades del sistema.

Por favor, ayúdenme a activar mi suscripción.

Gracias,''';

      // Mostrar directamente la información del correo
      if (mounted) {
        _showEmailContactDialog(
          email: 'soporteinventtia@gmail.com',
          subject: subject,
          body: body,
        );
      }
    } catch (e) {
      print('❌ Error mostrando información de soporte: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al mostrar información: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showEmailContactDialog({
    required String email,
    required String subject,
    required String body,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.email_outlined, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Información de Contacto',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Usa esta información para contactar al equipo de soporte:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                _buildCopyableField('Correo:', email),
                const SizedBox(height: 12),
                _buildCopyableField('Asunto:', subject),
                const SizedBox(height: 12),
                _buildCopyableField('Mensaje:', body),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCopyableField(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              IconButton(
                onPressed: () => _copyToClipboard(value),
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copiar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado al portapapeles'),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.success,
      ),
    );
  }


  Widget _buildNoActiveSubscriptionCard() {
    final message = _subscriptionGuard.getSubscriptionStatusMessage();
    final color = _subscriptionGuard.getSubscriptionStatusColor();
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: color,
            ),
            const SizedBox(height: 16),
            Text(
              'Suscripción No Activa',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Acceso Limitado',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mientras tu suscripción no esté activa, solo puedes acceder a esta pantalla. Contacta al administrador del sistema para activar tu suscripción.',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _sendSupportEmail,
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text('Contactar Soporte'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _loadSubscriptionData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar Sesión'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
