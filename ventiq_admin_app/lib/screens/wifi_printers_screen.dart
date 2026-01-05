import 'package:flutter/material.dart';
import '../services/wifi_printer_service.dart';
import '../utils/navigation_guard.dart';

class WiFiPrintersScreen extends StatefulWidget {
  const WiFiPrintersScreen({Key? key}) : super(key: key);

  @override
  State<WiFiPrintersScreen> createState() => _WiFiPrintersScreenState();
}

class _WiFiPrintersScreenState extends State<WiFiPrintersScreen> {
  final WiFiPrinterService _wifiService = WiFiPrinterService();

  List<Map<String, dynamic>> _savedPrinters = [];
  List<Map<String, dynamic>> _discoveredPrinters = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String? _statusMessage;

  bool _canEditPrinters = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadSavedPrinters();
  }

  Future<void> _loadPermissions() async {
    final canEdit = await NavigationGuard.canPerformAction('printers.edit');
    if (!mounted) return;
    setState(() {
      _canEditPrinters = canEdit;
    });
  }

  Future<void> _loadSavedPrinters() async {
    setState(() => _isLoading = true);

    try {
      final printers = await _wifiService.getSavedPrinters();
      setState(() {
        _savedPrinters = printers;
        _isLoading = false;
      });
      debugPrint('✅ ${printers.length} impresoras guardadas cargadas');
    } catch (e) {
      debugPrint('❌ Error cargando impresoras: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchPrinters() async {
    if (!_canEditPrinters) {
      NavigationGuard.showActionDeniedMessage(context, 'Configurar impresoras');
      return;
    }
    setState(() {
      _isScanning = true;
      _statusMessage = '🔍 Buscando impresoras...';
      _discoveredPrinters.clear();
    });

    try {
      debugPrint('🔍 Iniciando búsqueda de impresoras...');
      final printers = await _wifiService.discoverPrinters();

      // Guardar impresoras encontradas
      for (final printer in printers) {
        await _wifiService.savePrinter(printer);
      }

      setState(() {
        _discoveredPrinters = printers;
        _isScanning = false;

        if (printers.isEmpty) {
          _statusMessage = '❌ No se encontraron impresoras';
        } else {
          final networkCount =
              printers.where((p) => p['type'] == 'network').length;
          final apCount =
              printers.where((p) => p['type'] == 'access_point').length;
          _statusMessage =
              '✅ Se encontraron ${printers.length} impresora(s) (Red: $networkCount, AP: $apCount)';
        }
      });

      // Recargar guardadas
      await _loadSavedPrinters();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_statusMessage ?? 'Búsqueda completada'),
            backgroundColor: printers.isEmpty ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error en búsqueda: $e');
      setState(() {
        _statusMessage = '❌ Error: $e';
        _isScanning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deletePrinter(String ip) async {
    if (!_canEditPrinters) {
      NavigationGuard.showActionDeniedMessage(context, 'Eliminar impresora');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Impresora'),
            content: Text('¿Deseas eliminar la impresora $ip?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _wifiService.removeSavedPrinter(ip);
      await _loadSavedPrinters();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Impresora eliminada'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _testPrinter(Map<String, dynamic> printer) async {
    if (!_canEditPrinters) {
      NavigationGuard.showActionDeniedMessage(context, 'Probar impresora');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Probar Impresora'),
            content: Text(
              '¿Deseas probar la conexión con ${printer['ip']}:${printer['port']}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Probar'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔌 Probando conexión...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      try {
        await _wifiService.connectToPrinter(
          printer['ip'],
          port: printer['port'] ?? 9100,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Conexión exitosa'),
              backgroundColor: Colors.green,
            ),
          );
        }

        await _wifiService.disconnect();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error de conexión: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Impresoras WiFi',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // Botón de búsqueda
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                (!_canEditPrinters || _isScanning)
                                    ? null
                                    : _searchPrinters,
                            icon:
                                _isScanning
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : const Icon(Icons.search),
                            label: Text(
                              _isScanning ? 'Buscando...' : 'Buscar Impresoras',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        if (_statusMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  _statusMessage!.startsWith('✅')
                                      ? Colors.green.shade50
                                      : _statusMessage!.startsWith('❌')
                                      ? Colors.red.shade50
                                      : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    _statusMessage!.startsWith('✅')
                                        ? Colors.green.shade200
                                        : _statusMessage!.startsWith('❌')
                                        ? Colors.red.shade200
                                        : Colors.blue.shade200,
                              ),
                            ),
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[800],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Lista de impresoras
                  Expanded(
                    child:
                        _savedPrinters.isEmpty
                            ? _buildEmptyState()
                            : _buildPrintersList(),
                  ),
                ],
              ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.print_disabled, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              'No hay impresoras guardadas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Presiona "Buscar Impresoras" para encontrar impresoras en tu red',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrintersList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _savedPrinters.length,
      itemBuilder: (context, index) {
        final printer = _savedPrinters[index];
        final isAP = printer['type'] == 'access_point';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isAP ? Colors.orange.shade300 : Colors.green.shade300,
              width: 1.5,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: isAP ? Colors.orange.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      isAP
                          ? Colors.orange.shade100
                          : const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isAP ? Icons.router : Icons.print,
                  color: isAP ? Colors.orange : const Color(0xFF10B981),
                  size: 24,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      printer['name'] ?? 'Impresora',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (isAP)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'AP',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${printer['ip']}:${printer['port'] ?? 9100}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),
              trailing:
                  !_canEditPrinters
                      ? null
                      : PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: Colors.grey[600]),
                        onSelected: (value) {
                          switch (value) {
                            case 'test':
                              _testPrinter(printer);
                              break;
                            case 'delete':
                              _deletePrinter(printer['ip']);
                              break;
                          }
                        },
                        itemBuilder:
                            (context) => [
                              const PopupMenuItem(
                                value: 'test',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.cable,
                                      size: 20,
                                      color: Color(0xFF4A90E2),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Probar conexión'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 12),
                                    Text('Eliminar'),
                                  ],
                                ),
                              ),
                            ],
                      ),
            ),
          ),
        );
      },
    );
  }
}
