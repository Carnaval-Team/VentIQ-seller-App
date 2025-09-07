import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/promotion.dart';
import '../services/promotion_service.dart';

class PromotionFormScreen extends StatefulWidget {
  final Promotion? promotion;
  final List<PromotionType> promotionTypes;

  const PromotionFormScreen({
    super.key,
    this.promotion,
    required this.promotionTypes,
  });

  @override
  State<PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends State<PromotionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final PromotionService _promotionService = PromotionService();

  // Form controllers
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _codigoController = TextEditingController();
  final _valorDescuentoController = TextEditingController();
  final _minCompraController = TextEditingController();
  final _limiteUsosController = TextEditingController();

  // Form state
  String? _selectedTipoPromocion;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  bool _estado = true;
  bool _aplicaTodo = true;
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.promotion != null;
    if (_isEditing) {
      _populateForm();
    } else {
      _fechaInicio = DateTime.now();
      _fechaFin = DateTime.now().add(const Duration(days: 30));
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _codigoController.dispose();
    _valorDescuentoController.dispose();
    _minCompraController.dispose();
    _limiteUsosController.dispose();
    super.dispose();
  }

  void _populateForm() {
    final promotion = widget.promotion!;
    _nombreController.text = promotion.nombre;
    _descripcionController.text = promotion.descripcion ?? '';
    _codigoController.text = promotion.codigoPromocion;
    _valorDescuentoController.text = promotion.valorDescuento.toString();
    _minCompraController.text = promotion.minCompra?.toString() ?? '';
    _limiteUsosController.text = promotion.limiteUsos?.toString() ?? '';
    _selectedTipoPromocion = promotion.idTipoPromocion;
    _fechaInicio = promotion.fechaInicio;
    _fechaFin = promotion.fechaFin;
    _estado = promotion.estado;
    _aplicaTodo = promotion.aplicaTodo;
  }

  Future<void> _generateCode() async {
    try {
      final code = await _promotionService.generatePromotionCode(
        prefix:
            _nombreController.text.isNotEmpty
                ? _nombreController.text.substring(0, 3).toUpperCase()
                : null,
      );
      setState(() {
        _codigoController.text = code;
      });
    } catch (e) {
      _showErrorSnackBar('Error al generar código: $e');
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final initialDate =
        isStartDate
            ? _fechaInicio ?? DateTime.now()
            : _fechaFin ?? DateTime.now().add(const Duration(days: 30));

    final firstDate =
        isStartDate ? DateTime.now() : _fechaInicio ?? DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
      );

      if (time != null) {
        final dateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        );

        setState(() {
          if (isStartDate) {
            _fechaInicio = dateTime;
            // Asegurar que fecha fin sea después de fecha inicio
            if (_fechaFin != null && _fechaFin!.isBefore(dateTime)) {
              _fechaFin = dateTime.add(const Duration(days: 1));
            }
          } else {
            _fechaFin = dateTime;
          }
        });
      }
    }
  }

  Future<void> _savePromotion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_fechaInicio == null || _fechaFin == null) {
      _showErrorSnackBar('Debe seleccionar fechas de inicio y fin');
      return;
    }

    if (_fechaFin!.isBefore(_fechaInicio!)) {
      _showErrorSnackBar(
        'La fecha de fin debe ser posterior a la fecha de inicio',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final promotionData = {
        'nombre': _nombreController.text.trim(),
        'descripcion':
            _descripcionController.text.trim().isEmpty
                ? null
                : _descripcionController.text.trim(),
        'codigo_promocion': _codigoController.text.trim(),
        'id_tipo_promocion': int.parse(_selectedTipoPromocion!),
        'valor_descuento': double.parse(_valorDescuentoController.text),
        'min_compra':
            _minCompraController.text.isEmpty
                ? null
                : double.parse(_minCompraController.text),
        'fecha_inicio': _fechaInicio!.toIso8601String(),
        'fecha_fin': _fechaFin!.toIso8601String(),
        'estado': _estado,
        'aplica_todo': _aplicaTodo,
        'limite_usos':
            _limiteUsosController.text.isEmpty
                ? null
                : int.parse(_limiteUsosController.text),
      };

      if (_isEditing) {
        await _promotionService.updatePromotion(
          widget.promotion!.id,
          promotionData,
        );
        _showSuccessSnackBar('Promoción actualizada exitosamente');
      } else {
        await _promotionService.createPromotion(promotionData);
        _showSuccessSnackBar('Promoción creada exitosamente');
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showErrorSnackBar('Error al guardar promoción: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Promoción' : 'Nueva Promoción'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _savePromotion,
              child: const Text(
                'Guardar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBasicInfoSection(),
              const SizedBox(height: 24),
              _buildDiscountSection(),
              const SizedBox(height: 24),
              _buildDateSection(),
              const SizedBox(height: 24),
              _buildLimitsSection(),
              const SizedBox(height: 24),
              _buildStatusSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
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
                  'Información Básica',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la promoción *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.campaign),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El nombre es requerido';
                }
                if (value.trim().length < 3) {
                  return 'El nombre debe tener al menos 3 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descripcionController,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _codigoController,
                    decoration: const InputDecoration(
                      labelText: 'Código promocional *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El código es requerido';
                      }
                      if (value.trim().length < 4) {
                        return 'El código debe tener al menos 4 caracteres';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _generateCode,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedTipoPromocion,
              decoration: const InputDecoration(
                labelText: 'Tipo de promoción *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items:
                  widget.promotionTypes
                      .map(
                        (type) => DropdownMenuItem<String>(
                          value: type.id,
                          child: Text(type.denominacion),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedTipoPromocion = value;
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Debe seleccionar un tipo de promoción';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountSection() {
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
                  'Configuración de Descuento',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _valorDescuentoController,
              decoration: const InputDecoration(
                labelText: 'Valor del descuento (%) *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.percent),
                suffixText: '%',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El valor del descuento es requerido';
                }
                final double? discount = double.tryParse(value);
                if (discount == null) {
                  return 'Ingrese un valor válido';
                }
                if (discount <= 0 || discount > 100) {
                  return 'El descuento debe estar entre 1% y 100%';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _minCompraController,
              decoration: const InputDecoration(
                labelText: 'Compra mínima',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
                prefixText: '\$ ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final double? minPurchase = double.tryParse(value);
                  if (minPurchase == null || minPurchase < 0) {
                    return 'Ingrese un valor válido';
                  }
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSection() {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.date_range, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Vigencia',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha de inicio *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event),
                      ),
                      child: Text(
                        _fechaInicio != null
                            ? dateFormat.format(_fechaInicio!)
                            : 'Seleccionar fecha',
                        style: TextStyle(
                          color:
                              _fechaInicio != null
                                  ? Colors.black87
                                  : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha de fin *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event),
                      ),
                      child: Text(
                        _fechaFin != null
                            ? dateFormat.format(_fechaFin!)
                            : 'Seleccionar fecha',
                        style: TextStyle(
                          color:
                              _fechaFin != null
                                  ? Colors.black87
                                  : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_fechaInicio != null && _fechaFin != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Duración: ${_fechaFin!.difference(_fechaInicio!).inDays} días',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLimitsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Límites y Restricciones',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _limiteUsosController,
              decoration: const InputDecoration(
                labelText: 'Límite de usos',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.trending_up),
                helperText: 'Dejar vacío para usos ilimitados',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final int? limit = int.tryParse(value);
                  if (limit == null || limit <= 0) {
                    return 'Ingrese un número válido mayor a 0';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Aplica a todos los productos'),
              subtitle: const Text(
                'Si está desactivado, debe seleccionar productos específicos',
              ),
              value: _aplicaTodo,
              onChanged: (value) {
                setState(() {
                  _aplicaTodo = value;
                });
              },
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.toggle_on, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Estado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Promoción activa'),
              subtitle: Text(
                _estado
                    ? 'La promoción estará disponible para uso'
                    : 'La promoción estará desactivada',
              ),
              value: _estado,
              onChanged: (value) {
                setState(() {
                  _estado = value;
                });
              },
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
