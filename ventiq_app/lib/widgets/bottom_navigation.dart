import 'package:flutter/material.dart';
import '../services/mesa_cuenta_service.dart';
import '../services/order_service.dart';
import '../services/store_config_service.dart';

class AppBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const AppBottomNavigation({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final orderService = OrderService();

    // En modo restaurante el carrito NO es la preorden local: es la cuenta
    // abierta de la mesa, que vive en BD. El botón lleva allí (ver
    // NavigationHelper.goCarrito), así que la etiqueta y el contador también
    // tienen que hablar de la mesa o el vendedor no entiende a dónde va.
    final modoRestaurante = StoreConfigService.modoRestauranteSync;
    final cuentaService = MesaCuentaService();
    final cuentaActiva = modoRestaurante ? cuentaService.activeCuentaId : null;

    // El contador de la preorden local no aplica en restaurante: los items de
    // la cuenta están en BD y contarlos aquí obligaría a una consulta en cada
    // rebuild de la barra. Se usa el punto de "hay cuenta abierta" en su lugar.
    final currentOrderItemCount =
        modoRestaurante ? 0 : orderService.currentOrderItemCount;

    final etiqueta = modoRestaurante
        ? (cuentaActiva != null
            ? (cuentaService.activeMesaNumero ?? 'Cuenta')
            : 'Mesas')
        : 'Preorden';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF4A90E2),
        unselectedItemColor: Colors.grey[600],
        selectedFontSize: 12,
        unselectedFontSize: 11,
        iconSize: 24,
        elevation: 0,
        items: [
          // Home (Categorías, o Mesas en modo restaurante)
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          // Carrito: preorden local, o cuenta de mesa en modo restaurante
          BottomNavigationBarItem(
            icon: _iconoCarrito(
              lleno: false,
              modoRestaurante: modoRestaurante,
              cuentaAbierta: cuentaActiva != null,
              itemCount: currentOrderItemCount,
            ),
            activeIcon: _iconoCarrito(
              lleno: true,
              modoRestaurante: modoRestaurante,
              cuentaAbierta: cuentaActiva != null,
              itemCount: currentOrderItemCount,
            ),
            label: etiqueta,
          ),
          // Listado de órdenes
          const BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            activeIcon: Icon(Icons.list_alt),
            label: 'Órdenes',
          ),
          // Configuración
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Config',
          ),
        ],
      ),
    );
  }

  /// Icono del botón de carrito con su indicador.
  ///
  /// En modo normal: globo rojo con el número de items de la preorden.
  /// En modo restaurante: punto verde si hay una cuenta abierta a la que volver.
  /// El número no se usa allí porque los items están en BD y contarlos en cada
  /// rebuild costaría una consulta.
  Widget _iconoCarrito({
    required bool lleno,
    required bool modoRestaurante,
    required bool cuentaAbierta,
    required int itemCount,
  }) {
    final icono = modoRestaurante
        ? Icon(lleno ? Icons.receipt_long : Icons.receipt_long_outlined)
        : Icon(lleno ? Icons.shopping_cart : Icons.shopping_cart_outlined);

    if (modoRestaurante) {
      if (!cuentaAbierta) return icono;
      return Stack(
        children: [
          icono,
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      );
    }

    if (itemCount <= 0) return icono;

    return Stack(
      children: [
        icono,
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              '$itemCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
