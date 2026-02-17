import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/store_ai_models.dart';
import '../services/store_ai_assistant_service.dart';
import '../services/warehouse_service.dart';

class AiStoreGeneratorSheet extends StatefulWidget {
  const AiStoreGeneratorSheet({super.key});

  @override
  State<AiStoreGeneratorSheet> createState() => _AiStoreGeneratorSheetState();
}

class _AiStoreGeneratorSheetState extends State<AiStoreGeneratorSheet> {
  final TextEditingController _inputController = TextEditingController();
  final StoreAiAssistantService _assistantService = StoreAiAssistantService();
  final WarehouseService _warehouseService = WarehouseService();

  final List<Map<String, String>> _conversation = [];

  StoreAiPlan _plan = StoreAiPlan.empty();
  bool _loadingContext = true;
  bool _isSending = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _layoutTypes = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loadingContext = true;
      _errorMessage = null;
    });

    try {
      final types = await _warehouseService.getTiposLayout();
      if (!mounted) return;
      setState(() {
        _layoutTypes = List<Map<String, dynamic>>.from(types);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _layoutTypes = [
          {'id': 1, 'denominacion': 'Zona'},
        ];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingContext = false;
      });
    }

    if (_conversation.isEmpty) {
      _addAssistantMessage(
        'Describe tu tienda (nombre, dirección, país/estado/ciudad) y la configuración mínima (almacenes, zonas y tpvs). Yo te iré preguntando lo que falte.',
      );
    }
  }

  void _addUserMessage(String message) {
    _conversation.add({'role': 'user', 'content': message});
  }

  void _addAssistantMessage(String message) {
    _conversation.add({'role': 'assistant', 'content': message});
  }

  bool get _isPlanComplete =>
      _assistantService.validatePlanCompleteness(_plan).isEmpty;

  Future<void> _sendMessage() async {
    FocusScope.of(context).unfocus();

    final message = _inputController.text.trim();
    final validationError = _assistantService.validatePrompt(message);
    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
      });
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    _addUserMessage(message);
    _inputController.clear();

    try {
      final response = await _assistantService.sendMessage(
        conversation: List<Map<String, String>>.from(_conversation),
        userMessage: message,
        currentPlan: _plan,
        layoutTypes: _layoutTypes,
      );

      if (!mounted) return;

      setState(() {
        _plan = response.plan;
        _addAssistantMessage(response.assistantMessage);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _addAssistantMessage(
          'No pude procesar ese mensaje. Intenta responder de forma más directa (por ejemplo: "Almacén Principal" / "TPV Caja 1" / "Zona: Estantería A").',
        );
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
    }
  }

  void _generate() {
    if (!_isPlanComplete) {
      setState(() {
        _errorMessage =
            'Aún faltan datos. Responde las preguntas hasta completar el plan.';
      });
      return;
    }

    Navigator.pop(context, _plan);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.auto_awesome, color: AppColors.primary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Crear tienda asistida (IA)',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'La IA solo te preguntará lo necesario para crear la tienda completa (usuario, tienda, ubicación, almacenes, zonas y TPVs).',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    if (_loadingContext) ...[
                      Row(
                        children: const [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cargando tipos de layout...',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_errorMessage != null) ...[
                      _buildErrorBanner(_errorMessage!),
                      const SizedBox(height: 12),
                    ],
                    _buildChat(),
                    const SizedBox(height: 12),
                    _buildPlanPreview(),
                    const SizedBox(height: 12),
                    _buildInputBar(),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSending ? null : _generate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _isPlanComplete ? AppColors.success : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check_circle),
                        label: Text(
                          _isPlanComplete
                              ? 'Generar (usar este plan)'
                              : 'Completa los datos para generar',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChat() {
    if (_conversation.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chat',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        ..._conversation.map((m) {
          final role = m['role'] ?? '';
          final content = m['content'] ?? '';
          final isUser = role == 'user';

          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 520),
              decoration: BoxDecoration(
                color:
                    isUser
                        ? AppColors.primary.withOpacity(0.1)
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      isUser
                          ? AppColors.primary.withOpacity(0.25)
                          : Colors.grey.shade300,
                ),
              ),
              child: Text(
                content,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildPlanPreview() {
    final missing = _assistantService.validatePlanCompleteness(_plan);
    final missingFriendly = _humanizeMissing(missing);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isPlanComplete ? AppColors.success : Colors.orange.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isPlanComplete ? Icons.verified : Icons.info_outline,
                color: _isPlanComplete ? AppColors.success : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Vista previa del plan',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildKeyValue(
            'Usuario',
            (_plan.user.fullName ?? '').trim().isEmpty
                ? 'Pendiente'
                : _plan.user.fullName!,
          ),
          _buildKeyValue(
            'Email',
            (_plan.user.email ?? '').trim().isEmpty
                ? 'Pendiente'
                : _plan.user.email!,
          ),
          _buildKeyValue(
            'Teléfono',
            (_plan.user.phone ?? '').trim().isEmpty
                ? 'Pendiente'
                : _plan.user.phone!,
          ),
          const SizedBox(height: 6),
          _buildKeyValue(
            'Tienda',
            (_plan.storeName ?? '').trim().isEmpty
                ? 'Pendiente'
                : _plan.storeName!,
          ),
          _buildKeyValue(
            'Dirección',
            (_plan.storeAddress ?? '').trim().isEmpty
                ? 'Pendiente'
                : _plan.storeAddress!,
          ),
          _buildKeyValue(
            'Ubicación',
            '${_plan.location.city ?? '¿?'} / ${_plan.location.stateName ?? _plan.location.stateCode ?? '¿?'} / ${_plan.location.countryName ?? _plan.location.countryCode ?? '¿?'}',
          ),
          const SizedBox(height: 6),
          _buildKeyValue('Almacenes', '${_plan.warehousesCount}'),
          _buildKeyValue('Zonas', '${_plan.layoutsCount}'),
          _buildKeyValue('TPVs', '${_plan.tpvsCount}'),
          if (missingFriendly.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Faltan: ${missingFriendly.join(' · ')}',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _humanizeMissing(List<String> missing) {
    final mapped = <String>[];

    for (final key in missing) {
      final label = _missingLabel(key);
      if (label != null && label.trim().isNotEmpty) {
        mapped.add(label);
      }
    }

    final unique = mapped.toSet().toList();
    unique.sort();
    return unique;
  }

  String? _missingLabel(String key) {
    switch (key) {
      case 'user.full_name':
        return 'Nombre del usuario';
      case 'user.phone':
        return 'Teléfono del usuario';
      case 'user.email':
        return 'Email del usuario';
      case 'user.password':
        return 'Contraseña del usuario';
      case 'store.store_name':
        return 'Nombre de la tienda';
      case 'store.store_address':
        return 'Dirección de la tienda';
      case 'location.country':
        return 'País';
      case 'location.country_code':
        return 'País (siglas)';
      case 'location.country_name':
        return 'País (nombre)';
      case 'location.state':
        return 'Estado/Provincia';
      case 'location.state_code':
        return 'Estado/Provincia (código)';
      case 'location.state_name':
        return 'Estado/Provincia (nombre)';
      case 'location.city':
        return 'Ciudad';
      case 'config.warehouses[>=1]':
        return 'Al menos 1 almacén';
      case 'config.layouts[>=1]':
        return 'Al menos 1 zona';
      case 'config.tpvs[>=1]':
        return 'Al menos 1 TPV';
      case 'warehouse.name':
        return 'Nombre del almacén';
      case 'layout.name':
        return 'Nombre de la zona';
      case 'layout.code':
        return 'Código de la zona';
      case 'layout.warehouse_name':
        return 'Almacén asignado a la zona';
      case 'layout.tipo_layout_id':
        return 'Tipo de zona';
      case 'tpv.name':
        return 'Nombre del TPV';
      case 'tpv.warehouse_name':
        return 'Almacén asignado al TPV';
      default:
        if (key.startsWith('config.layouts[warehouse=')) {
          final start = key.indexOf('warehouse=') + 'warehouse='.length;
          final end = key.lastIndexOf(']');
          if (start > 0 && end > start) {
            final warehouse = key.substring(start, end);
            return 'Zona requerida en "$warehouse"';
          }
          return 'Zona requerida por almacén';
        }

        return null;
    }
  }

  Widget _buildKeyValue(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              key,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Escribe aquí...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isSending || _loadingContext ? null : _sendMessage,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child:
                _isSending
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.send),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
