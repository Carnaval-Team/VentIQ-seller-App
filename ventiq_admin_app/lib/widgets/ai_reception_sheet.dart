import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/ai_reception_models.dart';
import '../services/ai_reception_service.dart';

class AiReceptionSheet extends StatefulWidget {
  final VoidCallback? onProductsAdded;

  const AiReceptionSheet({super.key, this.onProductsAdded});

  @override
  State<AiReceptionSheet> createState() => _AiReceptionSheetState();
}

class _AiReceptionSheetState extends State<AiReceptionSheet> {
  final TextEditingController _promptController = TextEditingController();
  final AiReceptionService _service = AiReceptionService();

  // Contexts
  List<ProductAiContext> _contextProducts = [];
  List<MotivoAiContext> _contextMotives = [];
  List<UbicacionAiContext> _contextLocations = [];

  // Results
  List<AiReceptionDraft> _drafts = [];
  String? _inferredReason;
  String? _inferredLocation;
  String? _inferredCurrency;
  String? _inferredObservations;
  String? _inferredReceivedBy;
  String? _inferredDeliveredBy;

  // UI State
  bool _isLoadingContext = true;
  bool _isAnalyzing = false;
  String? _errorMessage;
  bool _hasResult = false;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    try {
      final ctx = await _service.loadFullContext();
      if (mounted) {
        setState(() {
          _contextProducts = ctx['products'] as List<ProductAiContext>;
          _contextMotives = ctx['motives'] as List<MotivoAiContext>;
          _contextLocations = ctx['locations'] as List<UbicacionAiContext>;
          _isLoadingContext = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Error cargando productos: $e');
      }
    }
  }

  Future<void> _analyze() async {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _drafts = [];
      _hasResult = false;
    });

    try {
      final result = await _service.parseReceptionText(
        prompt: text,
        contextProducts: _contextProducts,
        contextMotives: _contextMotives,
        contextLocations: _contextLocations,
      );
      if (mounted) {
        setState(() {
          _drafts = result.items;
          _inferredReason = result.reason;
          _inferredLocation = result.location;
          _inferredCurrency = result.currency;
          _inferredObservations = result.observations;
          _inferredReceivedBy = result.receivedBy;
          _inferredDeliveredBy = result.deliveredBy;
          _hasResult = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _removeDraft(String id) {
    setState(() {
      _drafts.removeWhere((d) => d.localId == id);
    });
  }

  void _updateDraft(AiReceptionDraft updated) {
    setState(() {
      final index = _drafts.indexWhere((d) => d.localId == updated.localId);
      if (index != -1) {
        _drafts[index] = updated;
      }
    });
  }

  void _confirm() {
    // Return full result object
    final result = AiReceptionResult(
      items: _drafts,
      reason: _inferredReason,
      location: _inferredLocation,
      currency: _inferredCurrency,
      observations: _inferredObservations,
      receivedBy: _inferredReceivedBy,
      deliveredBy: _inferredDeliveredBy,
    );
    Navigator.pop(context, result);
  }

  Widget _buildHeaderResultSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datos Generales Inferidos',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.category, 'Motivo', _inferredReason),
          _buildInfoRow(Icons.place, 'Ubicación', _inferredLocation),
          _buildInfoRow(
            Icons.person_outline,
            'Entregado por',
            _inferredDeliveredBy,
          ),
          _buildInfoRow(Icons.person, 'Recibido por', _inferredReceivedBy),
          _buildInfoRow(Icons.attach_money, 'Moneda', _inferredCurrency),
          _buildInfoRow(Icons.notes, 'Notas', _inferredObservations),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.blue[900],
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(AiReceptionDraft draft) async {
    final result = await showDialog<AiReceptionDraft>(
      context: context,
      builder:
          (ctx) => _AiDraftEditDialog(
            draft: draft,
            contextProducts: _contextProducts,
          ),
    );
    if (result != null) {
      _updateDraft(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asistente de Recepción',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Pega tu factura o dicta los productos',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingContext)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Input Section
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: TextField(
                    controller: _promptController,
                    maxLines: 3,
                    enabled: !_isAnalyzing,
                    decoration: const InputDecoration(
                      hintText:
                          'Ej: "Compra de 50 cajas de coca cola para el almacén principal. Nota: Vencimiento proximo."',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isAnalyzing || _isLoadingContext ? null : _analyze,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon:
                        _isAnalyzing
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                            : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isAnalyzing ? 'Analizando...' : 'Analizar Texto',
                    ),
                  ),
                ),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[100]!),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[800], fontSize: 13),
                      ),
                    ),
                  ),

                if (_hasResult) ...[
                  const SizedBox(height: 24),
                  _buildHeaderResultSection(),
                  const SizedBox(height: 16),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Resultados',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Spacer(),
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Colors.green,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Encontrado',
                          style: TextStyle(fontSize: 12, color: Colors.green),
                        ),
                        SizedBox(width: 12),
                        Icon(
                          Icons.help_outline,
                          size: 16,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Sin coincidencia',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),

                  ..._drafts
                      .map(
                        (draft) => _AiDraftCard(
                          draft: draft,
                          onDelete: () => _removeDraft(draft.localId),
                          onEdit: () => _showEditDialog(draft),
                        ),
                      )
                      .toList(),

                  const SizedBox(height: 20),

                  SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'Importar Todo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiDraftCard extends StatelessWidget {
  final AiReceptionDraft draft;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _AiDraftCard({
    required this.draft,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final color = draft.isMatched ? Colors.green : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color:
              draft.isMatched
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      draft.isMatched
                          ? Icons.inventory_2
                          : Icons.inventory_2_outlined,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          draft.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        if (!draft.isMatched)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Texto original: "${draft.originalTerm}"',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          children: [
                            _InfoBadge(
                              icon: Icons.numbers,
                              text: '${draft.quantity.toStringAsFixed(0)} un.',
                            ),
                            if (draft.price != null)
                              _InfoBadge(
                                icon: Icons.attach_money,
                                text: draft.price!.toStringAsFixed(2),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        color: Colors.grey[600],
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        color: Colors.red[300],
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoBadge({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiDraftEditDialog extends StatefulWidget {
  final AiReceptionDraft draft;
  final List<ProductAiContext> contextProducts;

  const _AiDraftEditDialog({
    required this.draft,
    required this.contextProducts,
  });

  @override
  State<_AiDraftEditDialog> createState() => _AiDraftEditDialogState();
}

class _AiDraftEditDialogState extends State<_AiDraftEditDialog> {
  late TextEditingController _qtyCtrl;
  late TextEditingController _priceCtrl;
  ProductAiContext? _selectedProduct;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.draft.quantity.toString());
    _priceCtrl = TextEditingController(
      text: widget.draft.price?.toString() ?? '',
    );

    if (widget.draft.productId != null) {
      try {
        _selectedProduct = widget.contextProducts.firstWhere(
          (p) => p.id == widget.draft.productId,
        );
      } catch (_) {}
    }
  }

  void _save() {
    final qty = double.tryParse(_qtyCtrl.text) ?? widget.draft.quantity;
    final price = double.tryParse(_priceCtrl.text);

    final updated = widget.draft.copyWith(
      quantity: qty,
      price: price,
      productId: _selectedProduct?.id,
      productName: _selectedProduct?.denominacion ?? widget.draft.productName,
      productSku: _selectedProduct?.sku,
      isMatched: _selectedProduct != null,
    );
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Producto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ProductAiContext>(
              value: _selectedProduct,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Producto (Catálogo)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text("Sin coincidencia (Manual)"),
                ),
                ...widget.contextProducts.map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text(
                      p.denominacion,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() => _selectedProduct = val);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Precio',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
