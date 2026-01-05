import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/consignacion_envio_listado_service.dart';
import '../services/consignacion_envio_service.dart';
import 'consignacion_envio_detalles_screen.dart';
import 'asignar_productos_consignacion_screen.dart';
import '../config/app_colors.dart';
import '../utils/navigation_guard.dart';

class ConsignacionEnviosListadoScreen extends StatefulWidget {
  final int? idContrato;
  final int? estadoFiltro;
  final String? rol; // 'consignador' o 'consignatario'
  final Map<String, dynamic>? contrato;

  const ConsignacionEnviosListadoScreen({
    Key? key,
    this.idContrato,
    this.estadoFiltro,
    this.rol,
    this.contrato,
  }) : super(key: key);

  @override
  State<ConsignacionEnviosListadoScreen> createState() =>
      _ConsignacionEnviosListadoScreenState();
}

class _ConsignacionEnviosListadoScreenState
    extends State<ConsignacionEnviosListadoScreen> {
  late Future<List<Map<String, dynamic>>> _enviosFuture;
  int? _estadoSeleccionado;

  bool _canManageEnvios = false;

  @override
  void initState() {
    super.initState();
    _estadoSeleccionado = widget.estadoFiltro;
    _loadPermissions();
    _cargarEnvios();
  }

  Future<void> _loadPermissions() async {
    final canManage = await NavigationGuard.canPerformAction(
      'consignacion.edit',
    );
    if (!mounted) return;
    setState(() {
      _canManageEnvios = canManage;
    });
  }

  void _cargarEnvios() {
    setState(() {
      if (widget.idContrato != null) {
        _enviosFuture =
            ConsignacionEnvioListadoService.obtenerEnviosPorContrato(
              widget.idContrato!,
            );
      } else if (_estadoSeleccionado != null) {
        _enviosFuture = ConsignacionEnvioListadoService.obtenerEnviosPorEstado(
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
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
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
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
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

                return RefreshIndicator(
                  onRefresh: () async {
                    _cargarEnvios();
                    await _enviosFuture;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: envios.length,
                    itemBuilder: (context, index) {
                      return _buildEnvioCard(envios[index]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _canManageEnvios ? _buildFABMenu() : null,
    );
  }

  Widget _buildFABMenu() {
    final bool canCreate = widget.idContrato != null && widget.contrato != null;
    if (!canCreate || !_canManageEnvios) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.rol == 'consignador')
          FloatingActionButton.extended(
            heroTag: 'new_envio',
            onPressed: () async {
              if (!_canManageEnvios) {
                NavigationGuard.showActionDeniedMessage(context, 'Crear envío');
                return;
              }
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => AsignarProductosConsignacionScreen(
                        idContrato: widget.idContrato!,
                        contrato: widget.contrato!,
                      ),
                ),
              );
              if (result == true) _cargarEnvios();
            },
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add_box, color: Colors.white),
            label: const Text(
              'CREAR ENVÍO',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (widget.rol == 'consignatario')
          FloatingActionButton.extended(
            heroTag: 'new_devolucion',
            onPressed: () async {
              if (!_canManageEnvios) {
                NavigationGuard.showActionDeniedMessage(
                  context,
                  'Crear devolución',
                );
                return;
              }
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => AsignarProductosConsignacionScreen(
                        idContrato: widget.idContrato!,
                        contrato: widget.contrato!,
                        isDevolucion: true,
                      ),
                ),
              );
              if (result == true) _cargarEnvios();
            },
            backgroundColor: Colors.deepOrange,
            icon: const Icon(Icons.replay, color: Colors.white),
            label: const Text(
              'CREAR DEVOLUCIÓN',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
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
            _buildFiltroBoton('Todos', null, _estadoSeleccionado == null),
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
        side: BorderSide(color: isSelected ? Colors.blue : Colors.grey[300]!),
      ),
      child: Text(label),
    );
  }

  Widget _buildEnvioCard(Map<String, dynamic> envio) {
    final estado = (envio['estado_envio'] as num?)?.toInt() ?? 0;
    final estadoTexto =
        (envio['estado_envio_texto'] as String?) ??
        ConsignacionEnvioListadoService.obtenerTextoEstado(estado);
    final numeroEnvio = envio['numero_envio'] as String? ?? 'N/A';
    final tiendaConsignadora = envio['tienda_consignadora'] as String? ?? 'N/A';
    final tiendaConsignataria =
        envio['tienda_consignataria'] as String? ?? 'N/A';
    final cantidadProductos =
        (envio['cantidad_productos'] as num?)?.toInt() ?? 0;
    final cantidadTotal = (envio['cantidad_total_unidades'] as num?) ?? 0;
    final valorTotal = (envio['valor_total_costo'] as num?) ?? 0;
    final fechaPropuestaRaw = envio['fecha_propuesta'];
    final fechaPropuesta =
        fechaPropuestaRaw is String
            ? DateTime.parse(fechaPropuestaRaw)
            : (fechaPropuestaRaw is DateTime
                ? fechaPropuestaRaw
                : DateTime.now());
    final productosAceptados =
        (envio['productos_aceptados'] as num?)?.toInt() ?? 0;
    final productosRechazados =
        (envio['productos_rechazados'] as num?)?.toInt() ?? 0;
    final idEnvio = (envio['id_envio'] as num?)?.toInt() ?? 0;
    final tipoEnvio = (envio['tipo_envio'] as num?)?.toInt() ?? 1;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            numeroEnvio,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (tipoEnvio == 2) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'DEVOLUCIÓN',
                                style: TextStyle(
                                  color: Colors.deepOrange,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tipoEnvio == 2
                            ? '$tiendaConsignataria → $tiendaConsignadora'
                            : '$tiendaConsignadora → $tiendaConsignataria',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _buildBadgeEstado(estado, estadoTexto),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoItem('📦', '$cantidadProductos prod.'),
                _buildInfoItem('📊', '${cantidadTotal.toStringAsFixed(0)} u.'),
                _buildInfoItem('💵', '\$${valorTotal.toStringAsFixed(2)} USD'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(fechaPropuesta)}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            if (productosAceptados > 0 || productosRechazados > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (productosAceptados > 0)
                    _buildPill('✓ $productosAceptados', Colors.green),
                  if (productosRechazados > 0) ...[
                    const SizedBox(width: 8),
                    _buildPill('✗ $productosRechazados', Colors.red),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            _buildBotonesAccion(envio),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeEstado(int estado, String texto) {
    final color = _obtenerColorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBotonesAccion(Map<String, dynamic> envio) {
    final idEnvio = (envio['id_envio'] as num?)?.toInt() ?? 0;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _mostrarDetalles(idEnvio),
        icon: const Icon(Icons.info_outline, size: 18),
        label: const Text(
          'VER DETALLES',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildInfoItem(String icono, String texto) {
    return Column(
      children: [
        Text(icono, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 2),
        Text(
          texto,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Color _obtenerColorEstado(int estado) {
    switch (estado) {
      case 1:
        return Colors.orange;
      case 2:
        return Colors.blue;
      case 3:
        return Colors.amber.shade700;
      case 4:
        return Colors.green;
      case 5:
        return Colors.red;
      case 6:
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  void _mostrarDetalles(int idEnvio) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => ConsignacionEnvioDetallesScreen(
              idEnvio: idEnvio,
              rol: widget.rol,
            ),
      ),
    );
    if (result == true) _cargarEnvios();
  }
}
