import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../models/subscription.dart';
import '../services/subscription_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/app_snackbar.dart';
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
      _activeSubscription = await _subscriptionService.getCurrentSubscription(_idTienda!);
      
      // Cargar historial de suscripciones
      _subscriptionHistory = await _subscriptionService.getSubscriptionHistory(_idTienda!);
      
    } catch (e) {
      print('❌ Error cargando datos de suscripción: $e');
      if (mounted) {
        AppSnackBar.showPersistent(
          context,
          message: 'Error cargando datos de suscripción: $e',
          backgroundColor: Colors.red,
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Detalles de Suscripción',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Mostrar botón de categorías si hay suscripción activa
          if (_activeSubscription != null && _activeSubscription!.isActive)
            IconButton(
              onPressed: _navigateToCategories,
              icon: const Icon(Icons.category, color: Colors.white),
              tooltip: 'Ir al Catálogo',
            ),
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
                  _buildCurrentSubscriptionCard(),
                  const SizedBox(height: 20),
                  _buildContactCard(),
                  const SizedBox(height: 20),
                  if (_subscriptionHistory.isNotEmpty) ...[
                    _buildHistoryCard(),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildCurrentSubscriptionCard() {
    final subscription = _activeSubscription;
    
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
                  subscription?.isActive == true ? Icons.check_circle : Icons.error,
                  color: subscription?.isActive == true ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    subscription?.isActive == true ? 'Suscripción Activa' : 'Suscripción Inactiva',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (subscription != null) ...[
              _buildInfoRow('Plan', subscription.planDenominacion ?? 'No especificado'),
              _buildInfoRow('Estado', subscription.estadoText),
              _buildInfoRow('Fecha de inicio', DateFormat('dd/MM/yyyy').format(subscription.fechaInicio)),
              if (subscription.fechaFin != null)
                _buildInfoRow('Fecha de fin', DateFormat('dd/MM/yyyy').format(subscription.fechaFin!)),
              if (subscription.diasRestantes > 0)
                _buildInfoRow('Días restantes', '${subscription.diasRestantes} días'),
              
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _getStatusColor().withOpacity(0.3)),
                ),
                child: Text(
                  _getStatusMessage(),
                  style: TextStyle(
                    color: _getStatusColor(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ] else ...[
              const Text(
                'No se encontró información de suscripción para esta tienda.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.support_agent, color: Color(0xFF4A90E2), size: 28),
                SizedBox(width: 12),
                Text(
                  'Soporte y Contacto',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Para activar, renovar o cambiar tu suscripción, contacta al administrador:',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            _buildContactButton(
              icon: Icons.phone,
              label: 'WhatsApp: 53765120',
              onTap: () => _launchWhatsApp('53765120'),
            ),
            const SizedBox(height: 12),
            _buildContactButton(
              icon: Icons.email,
              label: 'Email: supportinventtia@gmail.com',
              onTap: () => _launchEmail('supportinventtia@gmail.com'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history, color: Color(0xFF4A90E2), size: 28),
                SizedBox(width: 12),
                Text(
                  'Historial de Suscripciones',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            ..._subscriptionHistory.take(3).map((subscription) => 
              _buildHistoryItem(subscription)
            ).toList(),
            
            if (_subscriptionHistory.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Y ${_subscriptionHistory.length - 3} más...',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF4A90E2)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.launch, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Subscription subscription) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            subscription.isActive ? Icons.check_circle : Icons.cancel,
            color: subscription.isActive ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subscription.planDenominacion ?? 'Plan desconocido',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '${DateFormat('dd/MM/yyyy').format(subscription.fechaInicio)} - ${subscription.estadoText}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (_activeSubscription == null || !_activeSubscription!.isActive || _activeSubscription!.isExpired) {
      return Colors.red;
    }

    if (_activeSubscription!.diasRestantes > 0 && _activeSubscription!.diasRestantes <= 30) {
      return Colors.orange;
    }

    return Colors.green;
  }

  String _getStatusMessage() {
    if (_activeSubscription == null) {
      return 'No se encontró información de suscripción para esta tienda.';
    }

    if (_activeSubscription!.isExpired) {
      return 'Tu suscripción ha vencido el ${_activeSubscription!.fechaFin?.toString().split(' ')[0]}. Contacta al administrador para renovarla.';
    }

    if (!_activeSubscription!.isActive) {
      return 'Tu suscripción está ${_activeSubscription!.estadoText.toLowerCase()}. Contacta al administrador para activarla.';
    }

    if (_activeSubscription!.diasRestantes > 0 && _activeSubscription!.diasRestantes <= 30) {
      return 'Tu suscripción vence en ${_activeSubscription!.diasRestantes} días. Contacta al administrador para renovarla.';
    }

    return 'Tu suscripción está activa y funcionando correctamente.';
  }

  void _navigateToCategories() {
    Navigator.pushReplacementNamed(context, '/categories');
  }

  Future<void> _logout() async {
    try {
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
    } catch (e) {
      print('❌ Error durante logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cerrando sesión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _launchWhatsApp(String phoneNumber) async {
    final url = 'https://wa.me/$phoneNumber?text=Hola, necesito ayuda con mi suscripción de VentIQ';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        // Fallback: copiar número al portapapeles
        await Clipboard.setData(ClipboardData(text: phoneNumber));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Número copiado al portapapeles'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error abriendo WhatsApp: $e');
      // Fallback: copiar número al portapapeles
      await Clipboard.setData(ClipboardData(text: phoneNumber));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Número copiado al portapapeles'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _launchEmail(String email) async {
    final url = 'mailto:$email?subject=Soporte VentIQ - Suscripción';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        // Fallback: copiar email al portapapeles
        await Clipboard.setData(ClipboardData(text: email));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email copiado al portapapeles'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error abriendo email: $e');
      // Fallback: copiar email al portapapeles
      await Clipboard.setData(ClipboardData(text: email));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email copiado al portapapeles'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}
