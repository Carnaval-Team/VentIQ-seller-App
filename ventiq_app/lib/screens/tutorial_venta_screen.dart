import 'package:flutter/material.dart';

import '../services/store_config_service.dart';
import '../theme/ventiq_home_theme.dart';

/// Un paso del tutorial de venta.
@immutable
class PasoTutorialVenta {
  const PasoTutorialVenta({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    this.ruta,
    this.etiquetaAccion,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;

  /// Ruta real que se abre con el botón «Ver en la app».
  final String? ruta;
  final String? etiquetaAccion;
}

/// Tutorial guiado de una venta, adaptado al modo del negocio.
///
/// Si la tienda está en modo **restaurante/cocina** explica el flujo de mesas y
/// comandas; si no, el flujo normal de mostrador (Home → producto → carrito →
/// orden → cobro). No ejecuta una venta real: muestra los pasos y, si el paso
/// tiene una pantalla asociada, la abre para que el cliente la vea en vivo.
class TutorialVentaScreen extends StatefulWidget {
  const TutorialVentaScreen({super.key, this.modoRestaurante});

  /// Inyectable para pruebas; `null` detecta el modo del negocio.
  final bool? modoRestaurante;

  /// Pasos del flujo normal (mostrador / tienda).
  static const List<PasoTutorialVenta> pasosNormal = <PasoTutorialVenta>[
    PasoTutorialVenta(
      icono: Icons.storefront_rounded,
      titulo: 'Empieza en el Home',
      descripcion:
          'Busca por nombre o toca una categoría. El buscador está siempre a la '
          'vista y puedes abrir el catálogo completo con la pleca lateral.',
      ruta: '/',
      etiquetaAccion: 'Ver el Home',
    ),
    PasoTutorialVenta(
      icono: Icons.add_shopping_cart_rounded,
      titulo: 'Añade el producto',
      descripcion:
          'Toca el «+» para elegir la cantidad sin entrar al detalle, o abre la '
          'ficha para ver presentaciones, ubicaciones y disponibilidad.',
    ),
    PasoTutorialVenta(
      icono: Icons.shopping_cart_rounded,
      titulo: 'Revisa el carrito',
      descripcion:
          'En Preorden ajustas cantidades, precios y cliente. Los productos con '
          'una sola presentación se añaden en segundos.',
      ruta: '/preorder',
      etiquetaAccion: 'Abrir Preorden',
    ),
    PasoTutorialVenta(
      icono: Icons.receipt_long_rounded,
      titulo: 'Confirma la venta',
      descripcion:
          'Crea la orden desde el carrito: se descuenta el stock y la venta queda '
          'registrada en Órdenes con su medio de pago.',
      ruta: '/orders',
      etiquetaAccion: 'Ver Órdenes',
    ),
    PasoTutorialVenta(
      icono: Icons.point_of_sale_rounded,
      titulo: 'Cobra y cierra el turno',
      descripcion:
          'Cobra en caja y, al terminar, revisa el resumen del turno: ventas por '
          'medio de pago, egresos y diferencias.',
      ruta: '/cierre',
      etiquetaAccion: 'Ir a cierre',
    ),
  ];

  /// Pasos del flujo de restaurante / cocina.
  static const List<PasoTutorialVenta> pasosRestaurante = <PasoTutorialVenta>[
    PasoTutorialVenta(
      icono: Icons.table_restaurant_rounded,
      titulo: 'Abre Mesas y Comensales',
      descripcion:
          'Ves la ocupación del salón de un vistazo: mesas libres, ocupadas y '
          'cuentas activas con sus colores.',
      ruta: '/mesas',
      etiquetaAccion: 'Ver Mesas',
    ),
    PasoTutorialVenta(
      icono: Icons.touch_app_rounded,
      titulo: 'Toca una mesa',
      descripcion:
          'Cada mesa es una o varias cuentas de comensales. Si solo tiene una '
          'cuenta abierta, se abre directo para atenderla.',
    ),
    PasoTutorialVenta(
      icono: Icons.restaurant_menu_rounded,
      titulo: 'Añade los productos',
      descripcion:
          'Desde la cuenta añade platos y bebidas. Los elaborados descuentan sus '
          'ingredientes y la cocina recibe la comanda.',
      ruta: '/mesas',
      etiquetaAccion: 'Volver a Mesas',
    ),
    PasoTutorialVenta(
      icono: Icons.price_check_rounded,
      titulo: 'Cobra y libera la mesa',
      descripcion:
          'Cobra la cuenta (completa o dividida) y la mesa vuelve a quedar libre '
          'para el siguiente cliente.',
    ),
    PasoTutorialVenta(
      icono: Icons.kitchen_rounded,
      titulo: 'Sigue la cocina',
      descripcion:
          'En KDS y Producción ves las comandas pendientes y en preparación, y '
          'marcas cada plato como listo.',
      ruta: '/kds',
      etiquetaAccion: 'Ver KDS',
    ),
  ];

  static List<PasoTutorialVenta> pasosPara({required bool restaurante}) =>
      restaurante ? pasosRestaurante : pasosNormal;

  @override
  State<TutorialVentaScreen> createState() => _TutorialVentaScreenState();
}

class _TutorialVentaScreenState extends State<TutorialVentaScreen> {
  late final bool _restaurante =
      widget.modoRestaurante ??
      (StoreConfigService.modoRestauranteSync ||
          StoreConfigService.cocinaActivaSync);
  late final List<PasoTutorialVenta> _pasos = TutorialVentaScreen.pasosPara(
    restaurante: _restaurante,
  );

  final PageController _page = PageController();
  int _indice = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _ir(int delta) {
    final int nuevo = (_indice + delta).clamp(0, _pasos.length - 1);
    if (nuevo == _indice) return;
    setState(() => _indice = nuevo);
    _page.animateToPage(
      nuevo,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _terminar() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final bool esUltimo = _indice == _pasos.length - 1;
    final PasoTutorialVenta paso = _pasos[_indice];

    return Scaffold(
      backgroundColor: VentiqHomeTheme.surface,
      appBar: AppBar(
        backgroundColor: VentiqHomeTheme.heroGradient.first,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _restaurante ? 'Tutorial · Restaurante' : 'Tutorial · Venta normal',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _terminar,
            child: const Text(
              'Saltar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: _page,
              onPageChanged: (int i) => setState(() => _indice = i),
              itemCount: _pasos.length,
              itemBuilder: (BuildContext context, int i) {
                return _buildPaso(_pasos[i], i);
              },
            ),
          ),
          _buildPie(esUltimo: esUltimo, paso: paso),
        ],
      ),
    );
  }

  Widget _buildPaso(PasoTutorialVenta paso, int i) {
    final bool esUltimo = i == _pasos.length - 1;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[
                      VentiqHomeTheme.primaryLight,
                      VentiqHomeTheme.primary,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(paso.icono, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                'PASO ${i + 1} DE ${_pasos.length}',
                style: VentiqHomeTheme.rotuloBloque.copyWith(
                  color: VentiqHomeTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            paso.titulo,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: VentiqHomeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            paso.descripcion,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.5,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          if (paso.ruta != null) ...<Widget>[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, paso.ruta!);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: Text(paso.etiquetaAccion ?? 'Ver en la app'),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: VentiqHomeTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: VentiqHomeTheme.border),
              boxShadow: VentiqHomeTheme.shadowCard,
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: VentiqHomeTheme.warning,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    esUltimo
                        ? 'Ya tienes el flujo completo. Vuelve a abrirlo desde el chip «Tutorial» del Home.'
                        : 'Puedes volver a este tutorial cuando quieras desde el chip «Tutorial» del Home.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPie({required bool esUltimo, required PasoTutorialVenta paso}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: VentiqHomeTheme.card,
        border: Border(top: BorderSide(color: VentiqHomeTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                for (int i = 0; i < _pasos.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _indice ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color:
                          i == _indice
                              ? VentiqHomeTheme.primary
                              : VentiqHomeTheme.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (_indice > 0)
                  TextButton(
                    onPressed: () => _ir(-1),
                    child: const Text('Atrás'),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: esUltimo ? _terminar : () => _ir(1),
                  icon: Icon(
                    esUltimo
                        ? Icons.check_rounded
                        : Icons.arrow_forward_rounded,
                    size: 18,
                  ),
                  label: Text(esUltimo ? 'Terminar' : 'Siguiente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
