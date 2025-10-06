import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../widgets/connection_status_widget.dart';
import '../widgets/product_search_widget.dart';
import '../widgets/fluid_product_details_widget.dart';
import '../widgets/fluid_payment_methods_widget.dart';
import '../widgets/fluid_contact_form_widget.dart';

class FluidModeScreen extends StatefulWidget {
  const FluidModeScreen({Key? key}) : super(key: key);

  @override
  State<FluidModeScreen> createState() => _FluidModeScreenState();
}

class _FluidModeScreenState extends State<FluidModeScreen> {
  final OrderService _orderService = OrderService();

  // Estados del flujo
  FluidStep _currentStep = FluidStep.search;
  
  // Datos del flujo
  Product? _selectedProduct;
  List<OrderItem> _orderItems = [];
  Map<String, dynamic> _paymentData = {};
  Map<String, dynamic> _contactData = {};
  
  // Estados de carga
  bool _isLoading = false;
  bool _isProcessingOrder = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Cargar datos necesarios para el modo fluido
      await Future.delayed(const Duration(milliseconds: 500)); // Simular carga
    } catch (e) {
      print('Error cargando datos iniciales: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onProductSelected(Product product) {
    setState(() {
      _selectedProduct = product;
      _currentStep = FluidStep.productDetails;
    });
  }

  void _onProductDetailsCompleted(List<OrderItem> items) {
    setState(() {
      _orderItems = items;
      _currentStep = FluidStep.paymentMethods;
    });
  }

  void _onPaymentMethodsCompleted(Map<String, dynamic> paymentData) {
    setState(() {
      _paymentData = paymentData;
      _currentStep = FluidStep.contactForm;
    });
  }

  void _onContactFormCompleted(Map<String, dynamic> contactData) {
    setState(() {
      _contactData = contactData;
    });
    _processOrder();
  }

  Future<void> _processOrder() async {
    setState(() {
      _isProcessingOrder = true;
    });

    try {
      // Procesar la orden usando finalizeCurrentOrder
      _orderService.finalizeCurrentOrder(notas: _contactData['orderNotes']);
      
      _showSuccessDialog();
      _resetFlow();
    } catch (e) {
      print('Error procesando orden: $e');
      _showErrorDialog('Error inesperado: $e');
    } finally {
      setState(() {
        _isProcessingOrder = false;
      });
    }
  }


  void _resetFlow() {
    setState(() {
      _currentStep = FluidStep.search;
      _selectedProduct = null;
      _orderItems.clear();
      _paymentData.clear();
      _contactData.clear();
    });
  }

  void _goBack() {
    setState(() {
      switch (_currentStep) {
        case FluidStep.search:
          // No hay paso anterior
          break;
        case FluidStep.productDetails:
          _currentStep = FluidStep.search;
          _selectedProduct = null;
          break;
        case FluidStep.paymentMethods:
          _currentStep = FluidStep.productDetails;
          _orderItems.clear();
          break;
        case FluidStep.contactForm:
          _currentStep = FluidStep.paymentMethods;
          _paymentData.clear();
          break;
      }
    });
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('¡Orden Procesada!'),
        content: const Text('La orden ha sido procesada exitosamente.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error, color: Colors.red, size: 48),
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getStepTitle()),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          if (_currentStep != FluidStep.search)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _goBack,
              tooltip: 'Volver al paso anterior',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetFlow,
            tooltip: 'Reiniciar flujo',
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          const ConnectionStatusWidget(),
          _buildStepIndicator(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildCurrentStepWidget(),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 0: // Home (current)
              // Ya estamos en la pantalla principal
              break;
            case 1: // Preorden
              Navigator.pushNamed(context, '/preorder');
              break;
            case 2: // Órdenes
              Navigator.pushNamed(context, '/orders');
              break;
            case 3: // Configuración
              Navigator.pushNamed(context, '/settings');
              break;
          }
        },
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case FluidStep.search:
        return 'Buscar Producto';
      case FluidStep.productDetails:
        return 'Detalles del Producto';
      case FluidStep.paymentMethods:
        return 'Métodos de Pago';
      case FluidStep.contactForm:
        return 'Datos del Cliente';
    }
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStepIcon(FluidStep.search, Icons.search, 'Buscar'),
          _buildStepConnector(),
          _buildStepIcon(FluidStep.productDetails, Icons.inventory, 'Producto'),
          _buildStepConnector(),
          _buildStepIcon(FluidStep.paymentMethods, Icons.payment, 'Pago'),
          _buildStepConnector(),
          _buildStepIcon(FluidStep.contactForm, Icons.person, 'Cliente'),
        ],
      ),
    );
  }

  Widget _buildStepIcon(FluidStep step, IconData icon, String label) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep.index > step.index;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isCompleted
                ? Colors.green
                : isActive
                    ? Colors.purple
                    : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCompleted ? Icons.check : icon,
            color: isCompleted || isActive ? Colors.white : Colors.grey.shade600,
            size: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isCompleted || isActive ? Colors.purple : Colors.grey.shade600,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector() {
    return Expanded(
      child: Container(
        height: 2,
        color: Colors.grey.shade300,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildCurrentStepWidget() {
    if (_isProcessingOrder) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 16),
            Text(
              'Procesando orden...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    switch (_currentStep) {
      case FluidStep.search:
        return ProductSearchWidget(
          onProductSelected: _onProductSelected,
        );
      case FluidStep.productDetails:
        return FluidProductDetailsWidget(
          product: _selectedProduct!,
          onCompleted: _onProductDetailsCompleted,
        );
      case FluidStep.paymentMethods:
        return FluidPaymentMethodsWidget(
          orderItems: _orderItems,
          onCompleted: _onPaymentMethodsCompleted,
        );
      case FluidStep.contactForm:
        return FluidContactFormWidget(
          orderItems: _orderItems,
          paymentData: _paymentData,
          onCompleted: _onContactFormCompleted,
        );
    }
  }
}

enum FluidStep {
  search,
  productDetails,
  paymentMethods,
  contactForm,
}
