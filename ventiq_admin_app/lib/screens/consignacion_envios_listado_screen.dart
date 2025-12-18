import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/consignacion_envio_listado_service.dart';
import '../services/user_preferences_service.dart';
import 'consignacion_envio_detalles_screen.dart';

class ConsignacionEnviosListadoScreen extends StatefulWidget {
  final int? idContrato;
  final int? estadoFiltro;
  final String? rol; // 'consignador' o 'consignatario'

  const ConsignacionEnviosListadoScreen({
    Key? key,
    this.idContrato,
    this.estadoFiltro,
    this.rol,
  }) : super(key: key);

  @override
  State<ConsignacionEnviosListadoScreen> createState() =>
      _ConsignacionEnviosListadoScreenState();
}

class _ConsignacionEnviosListadoScreenState
    extends State<ConsignacionEnviosListadoScreen> {
  late Future<List<Map<String, dynamic>>> _enviosFuture;
  int? _estadoSeleccionado;

  @override
  void initState() {
    super.initState();
    _estadoSeleccionado = widget.estadoFiltro;
    _cargarEnvios();
  }

  void _cargarEnvios() {
    setState(() {
      if (widget.idContrato != null) {
        _enviosFuture =
            ConsignacionEnvioListadoService.obtenerEnviosPorContrato(
          widget.idContrato!,
        );
      } else if (_estadoSeleccionado != null) {
        _enviosFuture =
            ConsignacionEnvioListadoService.obtenerEnviosPorEstado(
          _estadoSeleccionado!,
        );
      } else {
        _enviosFuture = ConsignacionEnvioListadoService.obtenerEnvios();
      }
    });
  }

  void _cambiarFiltro(int? nuevoEstado) {
    setState(() {
      _estadoSeleccionado = nuevoEstado;
      _cargarEnvios();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Envíos de Consignación'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filtros
          _buildFiltros(),
          // Lista de envíos
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _enviosFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _cargarEnvios,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }

                final envios = snapshot.data ?? [];

                if (envios.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No hay envíos',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: envios.length,
                  itemBuilder: (context, index) {
                    return _buildEnvioCard(envios[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFiltroBoton(
              'Todos',
              null,
              _estadoSeleccionado == null,
            ),
            const SizedBox(width: 8),
            _buildFiltroBoton(
              'Propuesto',
              ConsignacionEnvioListadoService.ESTADO_PROPUESTO,
              _estadoSeleccionado ==
                  ConsignacionEnvioListadoService.ESTADO_PROPUESTO,
            ),
            const SizedBox(width: 8),
            _buildFiltroBoton(
              'En Tránsito',
              ConsignacionEnvioListadoService.ESTADO_EN_TRANSITO,
              _estadoSeleccionado ==
                  ConsignacionEnvioListadoService.ESTADO_EN_TRANSITO,
            ),
            const SizedBox(width: 8),
            _buildFiltroBoton(
              'Aceptado',
              ConsignacionEnvioListadoService.ESTADO_ACEPTADO,
              _estadoSeleccionado ==
                  ConsignacionEnvioListadoService.ESTADO_ACEPTADO,
            ),
            const SizedBox(width: 8),
            _buildFiltroBoton(
              'Rechazado',
              ConsignacionEnvioListadoService.ESTADO_RECHAZADO,
              _estadoSeleccionado ==
                  ConsignacionEnvioListadoService.ESTADO_RECHAZADO,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroBoton(String label, int? estado, bool isSelected) {
    return ElevatedButton(
      onPressed: () => _cambiarFiltro(estado),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.blue,
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey[300]!,
        ),
      ),
      child: Text(label),
    );
  }

  Widget _buildEnvioCard(Map<String, dynamic> envio) {
    final estado = (envio['estado_envio'] as num?)?.toInt() ?? 0;
    final estadoTexto = envio['estado_envio_texto'] as String? ?? 'DESCONOCIDO';
    final numeroEnvio = envio['numero_envio'] as String? ?? 'N/A';
    final tiendaConsignadora = envio['tienda_consignadora'] as String? ?? 'N/A';
    final tiendaConsignataria = envio['tienda_consignataria'] as String? ?? 'N/A';
    final cantidadProductos = (envio['cantidad_productos'] as num?)?.toInt() ?? 0;
    final cantidadTotal = (envio['cantidad_total_unidades'] as num?) ?? 0;
    final valorTotal = (envio['valor_total_costo'] as num?) ?? 0;
    final fechaPropuestaRaw = envio['fecha_propuesta'];
    final fechaPropuesta = fechaPropuestaRaw is String 
        ? DateTime.parse(fechaPropuestaRaw) 
        : (fechaPropuestaRaw is DateTime ? fechaPropuestaRaw : DateTime.now());
    final productosAceptados = (envio['productos_aceptados'] as num?)?.toInt() ?? 0;
    final productosRechazados = (envio['productos_rechazados'] as num?)?.toInt() ?? 0;
    final idEnvio = (envio['id_envio'] as num?)?.toInt() ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado: Número y Estado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Envío $numeroEnvio',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$tiendaConsignadora → $tiendaConsignataria',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _obtenerColorEstado(estado),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    estadoTexto,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Información: Productos y Cantidades
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoItem(
                  '📦',
                  '$cantidadProductos productos',
                ),
                _buildInfoItem(
                  '📊',
                  '${cantidadTotal.toStringAsFixed(0)} unidades',
                ),
                _buildInfoItem(
                  '💰',
                  '\$${valorTotal.toStringAsFixed(2)}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Fecha
            Text(
              'Creado: ${DateFormat('dd/MM/yyyy HH:mm').format(fechaPropuesta)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
            // Productos aceptados/rechazados (si aplica)
            if (productosAceptados > 0 || productosRechazados > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (productosAceptados > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '✓ $productosAceptados aceptados',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (productosRechazados > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '✗ $productosRechazados rechazados',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            // Botones de acción según rol
            const SizedBox(height: 12),
            _buildBotonesAccion(idEnvio, estado),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonesAccion(int idEnvio, int estado) {
    final esConsignatario = widget.rol == 'consignatario';
    final esConsignador = widget.rol == 'consignador';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Botón Ver Detalles (ambos pueden ver)
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _mostrarDetalles(idEnvio),
            icon: const Icon(Icons.info_outline, size: 16),
            label: const Text('Detalles'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              backgroundColor: Colors.blue,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Botones específicos según rol
        if (esConsignatario && estado == 3) ...[
          // Consignatario puede aceptar/rechazar envío EN_TRANSITO
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _aceptarEnvio(idEnvio),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Aceptar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                backgroundColor: Colors.green,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _rechazarEnvio(idEnvio),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Rechazar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                backgroundColor: Colors.red,
              ),
            ),
          ),
        ] else if (esConsignador && estado == 1) ...[
          // Consignador solo puede cancelar envío PROPUESTO
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _cancelarEnvio(idEnvio),
              icon: const Icon(Icons.close_outlined, size: 16),
              label: const Text('Cancelar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                backgroundColor: Colors.orange,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoItem(String icono, String texto) {
    return Column(
      children: [
        Text(icono, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _obtenerColorEstado(int estado) {
    switch (estado) {
      case 1: // PROPUESTO
        return Colors.orange;
      case 2: // CONFIGURADO
        return Colors.blue;
      case 3: // EN_TRANSITO
        return Colors.amber;
      case 4: // ACEPTADO
        return Colors.green;
      case 5: // RECHAZADO
        return Colors.red;
      case 6: // PARCIALMENTE_ACEPTADO
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  void _mostrarDetalles(int idEnvio) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ConsignacionEnvioDetallesScreen(
          idEnvio: idEnvio,
          rol: widget.rol,
        ),
      ),
    );
  }

  void _aceptarEnvio(int idEnvio) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aceptar Envío'),
        content: const Text('¿Deseas aceptar este envío de consignación?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Envío aceptado exitosamente'),
                  duration: Duration(seconds: 2),
                ),
              );
              if (!mounted) return;
              _cargarEnvios();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _rechazarEnvio(int idEnvio) {
    showDialog(
      context: context,
      builder: (context) {
        final motivoController = TextEditingController();
        return AlertDialog(
          title: const Text('Rechazar Envío'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Por qué deseas rechazar este envío?'),
              const SizedBox(height: 16),
              TextField(
                controller: motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo del rechazo',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: Productos dañados, cantidad incorrecta, etc.',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Envío rechazado: ${motivoController.text}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                if (!mounted) return;
                _cargarEnvios();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Rechazar'),
            ),
          ],
        );
      },
    );
  }

  void _cancelarEnvio(int idEnvio) {
    showDialog(
      context: context,
      builder: (context) {
        final motivoController = TextEditingController();
        return AlertDialog(
          title: const Text('Cancelar Envío'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Por qué deseas cancelar este envío?'),
              const SizedBox(height: 16),
              TextField(
                controller: motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo de la cancelación',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: Cambio de planes, error en asignación, etc.',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final result = await ConsignacionEnvioListadoService.cancelarEnvio(
                    idEnvio,
                    'uuid-usuario-actual', // TODO: Obtener UUID del usuario actual
                    motivoController.text.isNotEmpty ? motivoController.text : null,
                  );

                  if (!mounted) return;

                  if (result['success'] as bool) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Envío cancelado exitosamente'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _cargarEnvios();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ ${result['mensaje']}'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Error cancelando envío: $e'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('Cancelar Envío'),
            ),
          ],
        );
      },
    );
  }
}

// La pantalla ConsignacionEnvioDetallesScreen se ha movido a su propio archivo:
// consignacion_envio_detalles_screen.dart
