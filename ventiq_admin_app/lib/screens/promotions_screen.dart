import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/promotion.dart';
import '../services/promotion_service.dart';
import 'promotion_detail_screen.dart';
import 'promotion_form_screen.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  final PromotionService _promotionService = PromotionService();
  final TextEditingController _searchController = TextEditingController();

  List<Promotion> _promotions = [];
  List<PromotionType> _promotionTypes = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _selectedType;
  bool? _selectedStatus;
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _hasMoreData = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final futures = await Future.wait([
        _promotionService.listPromotions(page: 1, limit: _pageSize),
        _promotionService.getPromotionTypes(),
        _promotionService.getPromotionStats(),
      ]);

      setState(() {
        _promotions = futures[0] as List<Promotion>;
        _promotionTypes = futures[1] as List<PromotionType>;
        _stats = futures[2] as Map<String, dynamic>;
        _currentPage = 1;
        _hasMoreData = _promotions.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Error al cargar promociones: $e');
    }
  }

  Future<void> _loadMorePromotions() async {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final newPromotions = await _promotionService.listPromotions(
        search: _searchController.text.isEmpty ? null : _searchController.text,
        estado: _selectedStatus,
        tipoPromocion: _selectedType,
        page: _currentPage + 1,
        limit: _pageSize,
      );

      setState(() {
        if (newPromotions.isNotEmpty) {
          _promotions.addAll(newPromotions);
          _currentPage++;
          _hasMoreData = newPromotions.length >= _pageSize;
        } else {
          _hasMoreData = false;
        }
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
      _showErrorSnackBar('Error al cargar más promociones: $e');
    }
  }

  Future<void> _refreshPromotions() async {
    try {
      final newPromotions = await _promotionService.listPromotions(
        search: _searchController.text.isEmpty ? null : _searchController.text,
        estado: _selectedStatus,
        tipoPromocion: _selectedType,
        page: 1,
        limit: _pageSize,
      );

      setState(() {
        _promotions = newPromotions;
        _currentPage = 1;
        _hasMoreData = newPromotions.length >= _pageSize;
      });
    } catch (e) {
      _showErrorSnackBar('Error al actualizar promociones: $e');
    }
  }

  void _onSearchChanged() {
    // Implementar debounce si es necesario
    _refreshPromotions();
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

  Future<void> _togglePromotionStatus(Promotion promotion) async {
    try {
      await _promotionService.togglePromotionStatus(
        promotion.id,
        !promotion.estado,
      );

      setState(() {
        final index = _promotions.indexWhere((p) => p.id == promotion.id);
        if (index != -1) {
          _promotions[index] = promotion.copyWith(estado: !promotion.estado);
        }
      });

      _showSuccessSnackBar(
        promotion.estado
            ? 'Promoción desactivada exitosamente'
            : 'Promoción activada exitosamente',
      );
    } catch (e) {
      _showErrorSnackBar('Error al cambiar estado: $e');
    }
  }

  Future<void> _deletePromotion(Promotion promotion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Promoción'),
            content: Text('¿Está seguro de eliminar "${promotion.nombre}"?'),
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
        await _promotionService.deletePromotion(promotion.id);
        setState(() {
          _promotions.removeWhere((p) => p.id == promotion.id);
        });
        _showSuccessSnackBar('Promoción eliminada exitosamente');
      } catch (e) {
        _showErrorSnackBar('Error al eliminar promoción: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promociones y Marketing'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () => _showStatsDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsCards(),
          _buildFilters(),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildPromotionsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToPromotionForm(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatsCards() {
    if (_stats.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total',
              _stats['total_promociones']?.toString() ?? '0',
              Icons.campaign,
              AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Activas',
              _stats['promociones_activas']?.toString() ?? '0',
              Icons.check_circle,
              Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Usos',
              _stats['total_usos']?.toString() ?? '0',
              Icons.trending_up,
              Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar promociones...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Todos los tipos'),
                    ),
                    ..._promotionTypes.map(
                      (type) => DropdownMenuItem<String>(
                        value: type.id,
                        child: Text(type.denominacion),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedType = value;
                    });
                    _refreshPromotions();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<bool>(
                  value: _selectedStatus,
                  decoration: InputDecoration(
                    labelText: 'Estado',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem<bool>(value: null, child: Text('Todos')),
                    DropdownMenuItem<bool>(value: true, child: Text('Activas')),
                    DropdownMenuItem<bool>(
                      value: false,
                      child: Text('Inactivas'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value;
                    });
                    _refreshPromotions();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromotionsList() {
    if (_promotions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No hay promociones disponibles',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshPromotions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _promotions.length + (_hasMoreData ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _promotions.length) {
            return _buildLoadMoreButton();
          }

          final promotion = _promotions[index];
          return _buildPromotionCard(promotion);
        },
      ),
    );
  }

  Widget _buildPromotionCard(Promotion promotion) {
    final isExpired = promotion.fechaFin.isBefore(DateTime.now());
    final isActive = promotion.estado && !isExpired;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _navigateToPromotionDetail(promotion),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promotion.nombre,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          promotion.codigoPromocion,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(isActive, isExpired),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _navigateToPromotionForm(promotion: promotion);
                          break;
                        case 'toggle':
                          _togglePromotionStatus(promotion);
                          break;
                        case 'delete':
                          _deletePromotion(promotion);
                          break;
                      }
                    },
                    itemBuilder:
                        (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Row(
                              children: [
                                Icon(
                                  promotion.estado
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  promotion.estado ? 'Desactivar' : 'Activar',
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Eliminar',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                promotion.descripcion ?? '',
                style: TextStyle(color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoChip(
                    Icons.local_offer,
                    '${promotion.valorDescuento}%',
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.calendar_today,
                    DateFormat('dd/MM/yyyy').format(promotion.fechaFin),
                  ),
                  const SizedBox(width: 8),
                  if (promotion.limiteUsos != null)
                    _buildInfoChip(
                      Icons.trending_up,
                      '${promotion.usosActuales}/${promotion.limiteUsos}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isActive, bool isExpired) {
    Color color;
    String text;

    if (isExpired) {
      color = Colors.grey;
      text = 'Vencida';
    } else if (isActive) {
      color = Colors.green;
      text = 'Activa';
    } else {
      color = Colors.orange;
      text = 'Inactiva';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child:
            _isLoadingMore
                ? const CircularProgressIndicator()
                : ElevatedButton(
                  onPressed: _loadMorePromotions,
                  child: const Text('Cargar más'),
                ),
      ),
    );
  }

  void _showStatsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Estadísticas de Promociones'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatRow(
                    'Total promociones',
                    _stats['total_promociones']?.toString() ?? '0',
                  ),
                  _buildStatRow(
                    'Promociones activas',
                    _stats['promociones_activas']?.toString() ?? '0',
                  ),
                  _buildStatRow(
                    'Promociones vencidas',
                    _stats['promociones_vencidas']?.toString() ?? '0',
                  ),
                  _buildStatRow(
                    'Total usos',
                    _stats['total_usos']?.toString() ?? '0',
                  ),
                  _buildStatRow(
                    'Descuento aplicado',
                    '\$${NumberFormat('#,###').format(_stats['descuento_total_aplicado'] ?? 0)}',
                  ),
                  _buildStatRow(
                    'ROI',
                    '${_stats['roi_promociones']?.toString() ?? '0'}x',
                  ),
                  _buildStatRow(
                    'Tasa conversión',
                    '${_stats['conversion_rate']?.toString() ?? '0'}%',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _navigateToPromotionDetail(Promotion promotion) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PromotionDetailScreen(promotion: promotion),
      ),
    ).then((_) => _refreshPromotions());
  }

  void _navigateToPromotionForm({Promotion? promotion}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PromotionFormScreen(
              promotion: promotion,
              promotionTypes: _promotionTypes,
            ),
      ),
    ).then((_) => _refreshPromotions());
  }
}
