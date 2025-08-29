import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/barcode_service.dart';
import 'product_details_screen.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({Key? key}) : super(key: key);

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController controller = MobileScannerController();
  bool isFlashOn = false;
  bool isFrontCamera = false;
  String? lastScannedCode;
  final BarcodeService _barcodeService = BarcodeService();
  bool isSearching = false;
  DateTime? lastScanTime;
  static const Duration scanCooldown = Duration(seconds: 3); // 3 segundos entre escaneos

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Escáner de Códigos',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              isFrontCamera ? Icons.camera_front : Icons.camera_rear,
              color: Colors.white,
              size: 28,
            ),
            onPressed: _switchCamera,
            tooltip: 'Cambiar cámara',
          ),
          IconButton(
            icon: Icon(
              isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
              size: 28,
            ),
            onPressed: _toggleFlash,
            tooltip: 'Flash',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                MobileScanner(
                  controller: controller,
                  onDetect: _onBarcodeDetect,
                ),
                // Instrucciones en la parte superior
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Apunta la cámara hacia el código de barras',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                // Mostrar último código escaneado o estado de búsqueda
                if (lastScannedCode != null || isSearching)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSearching) ...[
                            const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Buscando producto...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ] else if (lastScannedCode != null) ...[
                            const Text(
                              'Último código escaneado:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lastScannedCode!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Botón de finalizar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.black,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: const Text(
                'Finalizar Escaneo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onBarcodeDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty && !isSearching) {
        // Verificar si ha pasado suficiente tiempo desde el último escaneo
        final now = DateTime.now();
        if (lastScanTime != null && now.difference(lastScanTime!) < scanCooldown) {
          print('Escaneo ignorado - cooldown activo. Tiempo restante: ${scanCooldown.inSeconds - now.difference(lastScanTime!).inSeconds}s');
          return;
        }
        
        lastScanTime = now;
        _searchProduct(barcode.rawValue!);
      }
    }
  }

  void _searchProduct(String barcode) async {
    if (isSearching) return; // Evitar búsquedas múltiples simultáneas
    
    setState(() {
      isSearching = true;
      lastScannedCode = barcode;
    });

    // Debug print del código escaneado
    print('Código de barras escaneado: $barcode');

    try {
      final product = await _barcodeService.searchProductByBarcode(barcode);
      
      setState(() {
        isSearching = false;
      });

      if (product != null) {
        // Producto encontrado - navegar a detalles
        print('Producto encontrado: ${product.denominacion}');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsScreen(
              product: product,
              categoryColor: const Color(0xFF4A90E2),
            ),
          ),
        );
      } else {
        // Producto no encontrado - mostrar mensaje
        _showProductNotFoundDialog(barcode);
      }
    } catch (e) {
      setState(() {
        isSearching = false;
      });
      print('Error al buscar producto: $e');
      _showErrorDialog('Error al buscar el producto. Inténtalo de nuevo.');
    }
  }

  void _showProductNotFoundDialog(String barcode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Producto no encontrado'),
        content: Text('No se encontró ningún producto con el código de barras:\n$barcode'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
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
        title: const Text('Error'),
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

  void _toggleFlash() async {
    await controller.toggleTorch();
    setState(() {
      isFlashOn = !isFlashOn;
    });
  }

  void _switchCamera() async {
    await controller.switchCamera();
    setState(() {
      isFrontCamera = !isFrontCamera;
      // Reset flash state when switching cameras (front camera usually doesn't have flash)
      if (isFrontCamera) {
        isFlashOn = false;
      }
    });
  }
}
