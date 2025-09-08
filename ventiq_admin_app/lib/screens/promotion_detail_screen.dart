import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/promotion.dart';
import '../services/promotion_service.dart';
import 'promotion_form_screen.dart';

class PromotionDetailScreen extends StatefulWidget {
  final Promotion promotion;

  const PromotionDetailScreen({super.key, required this.promotion});

  @override
  State<PromotionDetailScreen> createState() => _PromotionDetailScreenState();
}

class _PromotionDetailScreenState extends State<PromotionDetailScreen> {
  final PromotionService _promotionService = PromotionService();
  late Promotion _promotion;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _promotion = widget.promotion;
  }

  Future<void> _refreshPromotion() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final updatedPromotion = await _promotionService.getPromotionById(
        _promotion.id,
      );
      setState(() {
        _promotion = updatedPromotion;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Error al actualizar promoción: $e');
    }
  }

  Future<void> _toggleStatus() async {
    try {
      await _promotionService.togglePromotionStatus(
        _promotion.id,
        !_promotion.estado,
      );
      setState(() {
        _promotion = _promotion.copyWith(estado: !_promotion.estado);
      });
      _showSuccessSnackBar(
        _promotion.estado
            ? 'Promoción activada exitosamente'
            : 'Promoción desactivada exitosamente',
      );
    } catch (e) {
      _showErrorSnackBar('Error al cambiar estado: $e');
    }
  }

  Future<void> _deletePromotion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Promoción'),
            content: Text('¿Está seguro de eliminar "${_promotion.nombre}"?'),
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
      try {
        await _promotionService.deletePromotion(_promotion.id);
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        _showErrorSnackBar('Error al eliminar promoción: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = _promotion.fechaFin?.isBefore(DateTime.now()) ?? false;
    final isActive = _promotion.estado && !isExpired;

    return Scaffold(
      appBar: AppBar(
        title: Text(_promotion.nombre),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _navigateToEdit(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'toggle':
                  _toggleStatus();
                  break;
                case 'delete':
                  _deletePromotion();
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          _promotion.estado ? Icons.pause : Icons.play_arrow,
                        ),
                        const SizedBox(width: 8),
                        Text(_promotion.estado ? 'Desactivar' : 'Activar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Eliminar', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _refreshPromotion,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusCard(isActive, isExpired),
                      const SizedBox(height: 16),
                      // Mostrar advertencia si es promoción con recargo
                      if (_promotion.isChargePromotion)
                        Card(
                          color: Colors.orange.withOpacity(0.1),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.orange,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.warning,
                                      color: Colors.orange,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'PROMOCIÓN CON RECARGO',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange[800],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _promotion.chargeWarningMessage,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.orange[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.info,
                                        color: Colors.orange,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Esta promoción aplicará un recargo adicional al precio base de los productos, resultando en un aumento del precio final de venta.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[600],
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_promotion.isChargePromotion)
                        const SizedBox(height: 16),
                      _buildBasicInfoCard(),
                      const SizedBox(height: 16),
                      _buildDiscountInfoCard(),
                      const SizedBox(height: 16),
                      _buildDateRangeCard(),
                      const SizedBox(height: 16),
                      _buildUsageCard(),
                      const SizedBox(height: 16),
                      if (_promotion.productos?.isNotEmpty == true)
                        _buildProductsCard(),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildStatusCard(bool isActive, bool isExpired) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isExpired) {
      statusColor = Colors.grey;
      statusText = 'Promoción Vencida';
      statusIcon = Icons.event_busy;
    } else if (isActive) {
      statusColor = Colors.green;
      statusText = 'Promoción Activa';
      statusIcon = Icons.check_circle;
    } else {
      statusColor = Colors.orange;
      statusText = 'Promoción Inactiva';
      statusIcon = Icons.pause_circle;
    }

    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: [
              statusColor.withOpacity(0.1),
              statusColor.withOpacity(0.05),
            ],
          ),
        ),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _promotion.codigoPromocion,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Información General',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Nombre', _promotion.nombre),
            _buildInfoRow(
              'Descripción',
              _promotion.descripcion ?? 'Sin descripción',
            ),
            _buildInfoRow(
              'Tipo',
              _promotion.tipoPromocion?.denominacion ?? 'No especificado',
            ),
            _buildInfoRow('Aplica a todo', _promotion.aplicaTodo ? 'Sí' : 'No'),
            if (_promotion.minCompra != null)
              _buildInfoRow(
                'Compra mínima',
                '\$${NumberFormat('#,###').format(_promotion.minCompra)}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_offer, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Información de Descuento',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    '${_promotion.valorDescuento}%',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const Text(
                    'de descuento',
                    style: TextStyle(fontSize: 16, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeCard() {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final now = DateTime.now();
    final daysRemaining = _promotion.fechaFin?.difference(now).inDays;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.date_range, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Período de Vigencia',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDateInfo(
              'Fecha de Inicio',
              _promotion.fechaInicio,
              dateFormat,
            ),
            const SizedBox(height: 8),
            _buildDateInfo('Fecha de Fin', _promotion.fechaFin, dateFormat),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    _promotion.fechaFin == null
                        ? Colors.blue.withOpacity(0.1)
                        : (daysRemaining != null && daysRemaining >= 0
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _promotion.fechaFin == null
                        ? Icons.all_inclusive
                        : (daysRemaining != null && daysRemaining >= 0
                            ? Icons.check_circle
                            : Icons.warning),
                    color:
                        _promotion.fechaFin == null
                            ? Colors.blue
                            : (daysRemaining != null && daysRemaining >= 0
                                ? Colors.green
                                : Colors.red),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _promotion.fechaFin == null
                          ? 'Esta promoción no tiene fecha de vencimiento'
                          : (daysRemaining != null && daysRemaining >= 0
                              ? 'Faltan $daysRemaining días para que expire'
                              : 'Esta promoción ha expirado hace ${daysRemaining?.abs()} días'),
                      style: TextStyle(
                        color:
                            _promotion.fechaFin == null
                                ? Colors.blue[700]
                                : (daysRemaining != null && daysRemaining >= 0
                                    ? Colors.green[700]
                                    : Colors.red[700]),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageCard() {
    final usagePercentage =
        _promotion.limiteUsos != null && _promotion.limiteUsos! > 0
            ? ((_promotion.usosActuales ?? 0) / _promotion.limiteUsos!) * 100
            : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Estadísticas de Uso',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildUsageStatCard(
                    'Usos Actuales',
                    _promotion.usosActuales.toString(),
                    Icons.shopping_cart,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildUsageStatCard(
                    'Límite de Usos',
                    _promotion.limiteUsos?.toString() ?? 'Ilimitado',
                    Icons.flag,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            if (_promotion.limiteUsos != null) ...[
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Progreso de uso'),
                      Text('${usagePercentage.toStringAsFixed(1)}%'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: usagePercentage / 100,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      usagePercentage > 80 ? Colors.red : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUsageStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProductsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Productos Incluidos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...(_promotion.productos ?? []).map(
              (product) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        product.producto?.denominacion ?? 'Producto sin nombre',
                      ),
                    ),
                  ],
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
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

  Widget _buildDateInfo(String label, DateTime? date, DateFormat dateFormat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              date != null ? dateFormat.format(date) : 'No especificado',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEdit() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PromotionFormScreen(
              promotion: _promotion,
              promotionTypes:
                  [
                    _promotion.tipoPromocion,
                  ].whereType<PromotionType>().toList(),
            ),
      ),
    ).then((result) {
      if (result == true) {
        _refreshPromotion();
      }
    });
  }
}
