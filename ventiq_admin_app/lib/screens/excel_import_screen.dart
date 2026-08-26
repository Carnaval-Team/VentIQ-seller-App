import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ventiq_admin_app/services/product_service.dart';
import '../config/app_colors.dart';
import '../services/excel_import_service.dart';
import '../widgets/admin_drawer.dart';
import '../services/user_preferences_service.dart';
import '../services/warehouse_service.dart';
import '../services/currency_service.dart';

class ExcelImportScreen extends StatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  int _currentStep = 0;
  ExcelFileWrapper? _selectedFile;
  ExcelAnalysisResult? _analysisResult;
  Map<String, String> _finalColumnMapping = {};
  Set<String> _discardedColumns = {}; // Columnas descartadas
  Map<String, dynamic> _defaultValues = {}; // Valores por defecto
  List<Map<String, dynamic>> _categories = []; // AGREGAR ESTA LÍNEA
  List<Map<String, dynamic>> _units = []; // AGREGAR ESTA LÍNEA
  Map<int, List<Map<String, dynamic>>> _subcategoriesCache = {};
  
  // Stock import configuration
  bool _importWithStock = false;
  int? _selectedLocationId;
  Map<String, String> _stockColumnMapping = {};
  List<Map<String, dynamic>> _locations = [];
  
  // Category selection tracking
  int? _selectedMainCategoryId; // Guardar la categoría principal seleccionada
  
  // Price currency configuration
  String _priceCurrency = 'USD'; // Moneda del precio_venta (USD o CUP)
  double? _exchangeRate; // Tasa de cambio si el precio está en CUP

  final _categoryController = TextEditingController();
  final _unitController = TextEditingController();

  @override
  void dispose() {
    _categoryController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUnits();
    _loadLocations();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ProductService.getCategorias();
      setState(() {
        _categories = categories;
      });
    } catch (e) {
      print('Error cargando categorías: $e');
    }
  }

  Future<void> _loadUnits() async {
    try {
      final units = await ProductService.getUnidadesMedida();
      setState(() {
        _units = units;
      });
    } catch (e) {
      print('Error cargando unidades: $e');
    }
  }

  Future<void> _loadLocations() async {
    try {
      print('🔍 Iniciando carga de ubicaciones...');
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final idTienda = userData['idTienda'] as int?;
      print('🏪 ID Tienda obtenido: $idTienda');
      
      if (idTienda != null) {
        // ✅ Usar el mismo servicio que las otras pantallas de inventario
        print('📦 Cargando almacenes y zonas con WarehouseService...');
        final warehouseService = WarehouseService();
        final warehouses = await warehouseService.listWarehouses(
          storeId: idTienda.toString(),
        );
        
        print('🏪 Almacenes obtenidos: ${warehouses.length}');
        
        // Extraer todas las zonas de todos los almacenes
        List<Map<String, dynamic>> allZones = [];
        for (final warehouse in warehouses) {
          print('📦 Almacén: ${warehouse.name} - Zonas: ${warehouse.zones.length}');
          for (final zone in warehouse.zones) {
            allZones.add({
              'id': int.parse(zone.id),
              'denominacion': '${warehouse.name} - ${zone.name}',
              'warehouse_id': int.parse(warehouse.id),
              'warehouse_name': warehouse.name,
              'zone_name': zone.name,
            });
          }
        }
        
        setState(() {
          _locations = allZones;
        });
        
        print('✅ Ubicaciones cargadas en estado: ${_locations.length}');
        if (_locations.isEmpty) {
          print('⚠️ No hay zonas disponibles. Verifica la configuración de almacenes.');
        } else {
          print('📍 Zonas disponibles:');
          for (final loc in _locations) {
            print('   - ID: ${loc['id']}, Nombre: ${loc['denominacion']}');
          }
        }
      } else {
        print('❌ idTienda es null - no se puede cargar ubicaciones');
      }
    } catch (e, stackTrace) {
      print('❌ Error cargando ubicaciones: $e');
      print('❌ StackTrace: $stackTrace');
    }
  }

  bool _isAnalyzing = false;
  bool _isImporting = false;
  ImportResult? _importResult;
  double _importProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Importar Productos desde Excel'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Atrás',
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
        ],
      ),
      endDrawer: const AdminDrawer(),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: Stepper(
          currentStep: _currentStep,
          onStepTapped: (step) {
            if (step <= _getMaxAllowedStep()) {
              setState(() => _currentStep = step);
            }
          },
          controlsBuilder: (context, details) => _buildStepControls(details),
          steps: [
            _buildSelectFileStep(),
            _buildAnalyzeFileStep(),
            _buildMapColumnsStep(),
            _buildPreviewStep(),
            _buildImportStep(),
          ],
        ),
      ),
    );
  }

  Step _buildSelectFileStep() {
    return Step(
      title: const Text('Seleccionar Archivo'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selecciona el archivo Excel (.xlsx o .xls) que contiene los productos a importar.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _selectFile,
                icon: const Icon(Icons.file_upload),
                label: const Text('Seleccionar Archivo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              /*
              ElevatedButton.icon(
                onPressed: _downloadTemplate,
                icon: const Icon(Icons.download),
                label: const Text('Descargar Template'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                ),
              ),
              */
            ],
          ),
          if (_selectedFile != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                border: Border.all(color: AppColors.success),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Archivo seleccionado: ${_selectedFile!.name}',
                      style: TextStyle(color: AppColors.success),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      isActive: _currentStep >= 0,
      state: _selectedFile != null ? StepState.complete : StepState.indexed,
    );
  }

  Step _buildAnalyzeFileStep() {
    return Step(
      title: const Text('Analizar Archivo'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isAnalyzing) ...[
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text(
                    'Analizando archivo Excel...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Detectando columnas y validando datos',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_analysisResult != null) ...[
            _buildAnalysisResults(),
          ] else ...[
            const Text(
              'El archivo se analizará automáticamente después de seleccionarlo.',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ],
      ),
      isActive: _currentStep >= 1,
      state: _analysisResult != null ? StepState.complete : StepState.indexed,
    );
  }

  Step _buildMapColumnsStep() {
    return Step(
      title: const Text('Mapear Columnas'),
      content:
          _analysisResult != null ? _buildColumnMapping() : const SizedBox(),
      isActive: _currentStep >= 2,
      state:
          _finalColumnMapping.isNotEmpty
              ? StepState.complete
              : StepState.indexed,
    );
  }

  Step _buildPreviewStep() {
    return Step(
      title: const Text('Vista Previa'),
      content: _analysisResult != null ? _buildPreviewData() : const SizedBox(),
      isActive: _currentStep >= 3,
      state: _currentStep > 3 ? StepState.complete : StepState.indexed,
    );
  }

  Step _buildImportStep() {
    return Step(
      title: const Text('Importar'),
      content: _buildImportSection(),
      isActive: _currentStep >= 4,
      state: _importResult != null ? StepState.complete : StepState.indexed,
    );
  }

  Widget _buildStepControls(ControlsDetails details) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (details.stepIndex > 0)
            TextButton(
              onPressed:
                  () => setState(() => _currentStep = details.stepIndex - 1),
              child: const Text('Anterior'),
            ),
          const SizedBox(width: 8),
          if (details.stepIndex < 4)
            ElevatedButton(
              onPressed:
                  _canProceedToNextStep(details.stepIndex)
                      ? () => _proceedToNextStep(details.stepIndex)
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(details.stepIndex == 1 ? 'Analizar' : 'Siguiente'),
            ),
          const Spacer(),
          if (_importResult != null && details.stepIndex == 4)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacementNamed('/products');
              },
              icon: const Icon(Icons.list_alt),
              label: const Text('Ver Productos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalysisResults() {
    final result = _analysisResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                result.isValid
                    ? AppColors.success.withOpacity(0.1)
                    : AppColors.warning.withOpacity(0.1),
            border: Border.all(
              color: result.isValid ? AppColors.success : AppColors.warning,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    result.isValid ? Icons.check_circle : Icons.warning,
                    color:
                        result.isValid ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    result.isValid
                        ? 'Archivo válido para importación'
                        : 'Archivo requiere ajustes',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          result.isValid
                              ? AppColors.success
                              : AppColors.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('📄 Archivo: ${result.fileName}'),
              Text('📊 Total de filas: ${result.totalRows}'),
              Text('📋 Columnas detectadas: ${result.headers.length}'),
              Text(
                '✅ Columnas mapeadas: ${result.columnAnalysis.mappedColumns.length}',
              ),
              if (result.missingRequiredFields.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '❌ Campos obligatorios faltantes: ${result.missingRequiredFields.join(', ')}',
                  style: TextStyle(color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColumnMapping() {
    final analysis = _analysisResult!.columnAnalysis;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Revisa y ajusta el mapeo de columnas:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Columnas mapeadas
        if (analysis.mappedColumns.isNotEmpty) ...[
          const Text(
            'Columnas mapeadas automáticamente:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          ...analysis.mappedColumns.entries.map(
            (entry) => _buildMappingRow(entry.key, entry.value, true),
          ),
          const SizedBox(height: 16),
        ],

        // Sugerencias
        if (analysis.suggestions.isNotEmpty) ...[
          const Text(
            'Sugerencias de mapeo:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          ...analysis.suggestions.entries.map(
            (entry) => _buildSuggestionRow(entry.key, entry.value),
          ),
          const SizedBox(height: 16),
        ],

        // Columnas no mapeadas
        if (analysis.unmappedColumns.isNotEmpty) ...[
          const Text(
            'Columnas sin mapear:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          ...analysis.unmappedColumns.map(
            (column) => _buildUnmappedColumnRow(column),
          ),
          const SizedBox(height: 16),
        ],

        // Sección de categoría/subcategoría OBLIGATORIA
        _buildMandatoryCategorySection(),
        
        // Valores por defecto
        const SizedBox(height: 16),
        _buildDefaultValuesSection(),
        
        // Sección de importación de stock
        const SizedBox(height: 24),
        _buildStockImportSection(),
      ],
    );
  }

  Widget _buildMappingRow(
    String excelColumn,
    String mappedField,
    bool isMapped,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              excelColumn,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const Icon(Icons.arrow_forward),
          Expanded(
            flex: 2,
            child: Text(
              mappedField,
              style: TextStyle(color: AppColors.primary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editMapping(excelColumn, mappedField),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionRow(String excelColumn, List<String> suggestions) {
    // Validar que la columna no esté vacía
    if (excelColumn.isEmpty) {
      return const SizedBox.shrink(); // No mostrar si está vacía
    }

    // Eliminar sugerencias duplicadas
    final uniqueSuggestions = suggestions.toSet().toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Columna no mapeada: "$excelColumn"',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Sugerencias:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children:
                uniqueSuggestions.map((suggestion) {
                  final isSelected =
                      _finalColumnMapping[excelColumn] == suggestion;
                  return InkWell(
                    onTap: () {
                      print('Mapeando $excelColumn -> $suggestion'); // Debug
                      setState(() {
                        _finalColumnMapping[excelColumn] = suggestion;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? Colors.green.withOpacity(0.2)
                                : Colors.blue.withOpacity(0.1),
                        border: Border.all(
                          color:
                              isSelected
                                  ? Colors.green.withOpacity(0.5)
                                  : Colors.blue.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) ...[
                            const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            suggestion,
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.green : Colors.blue,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewData() {
    final sampleData = _analysisResult!.sampleData;
    // Validar que hay mapeo de columnas
    if (_finalColumnMapping.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No hay columnas mapeadas para mostrar vista previa.',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 16),
          Text(
            'Regresa al paso anterior para mapear las columnas.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vista previa de los datos a importar:',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        // Mostrar información de categoría seleccionada
        if (_defaultValues.containsKey('id_categoria') && _defaultValues['id_categoria'] != null) ...
        [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✅ Categoría asignada: ${_getCategoryName(_defaultValues['id_categoria'] as int)}${_defaultValues.containsKey('id_subcategoria') ? ' > ${_getCategoryName(_defaultValues['id_subcategoria'] as int)}' : ''}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns:
                _finalColumnMapping.keys
                    .map((column) => DataColumn(label: Text(column)))
                    .toList(),
            rows:
                sampleData
                    .take(5)
                    .map(
                      (row) => DataRow(
                        cells:
                            _finalColumnMapping.keys
                                .map(
                                  (column) => DataCell(
                                    Text(row[column]?.toString() ?? ''),
                                  ),
                                )
                                .toList(),
                      ),
                    )
                    .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildImportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mostrar información de categoría seleccionada
        if (_defaultValues.containsKey('id_categoria') && _defaultValues['id_categoria'] != null) ...
        [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Todos los productos se importarán con: ${_getCategoryName(_defaultValues['id_categoria'] as int)}${_defaultValues.containsKey('id_subcategoria') ? ' > ${_getCategoryName(_defaultValues['id_subcategoria'] as int)}' : ''}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_isImporting) ...[
          const Text('Importando productos...', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _importProgress),
          const SizedBox(height: 8),
          Text('${(_importProgress * 100).toInt()}% completado'),
        ] else if (_importResult != null) ...[
          _buildImportResults(),
        ] else ...[
          const Text(
            'Todo listo para importar. Haz clic en "Importar" para comenzar.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _startImport,
            icon: const Icon(Icons.upload),
            label: const Text('Iniciar Importación'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ],
    );
  }

  int _warningsPage = 0;
  int _errorsPage = 0;
  static const int _itemsPerPage = 10;

  Widget _buildImportResults() {
    final result = _importResult!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            border: Border.all(color: AppColors.success),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Importación completada',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text('✅ Productos importados: ${result.successCount}'),
              Text('❌ Errores: ${result.errorCount}'),
              Text('⚠️ Advertencias: ${result.warnings.length}'),
              const SizedBox(height: 8),
              Text(
                '📊 Tasa de éxito: ${result.successRate.toStringAsFixed(1)}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        
        // Warnings (eventos alternativos)
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            '⚠️ Eventos alternativos encontrados:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _buildPaginatedList(
            items: result.warnings,
            currentPage: _warningsPage,
            onPageChanged: (page) => setState(() => _warningsPage = page),
            itemBuilder: (warning) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _getWarningIcon(warning.type),
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fila ${warning.row}: ${warning.message}',
                      style: TextStyle(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        
        // Errors
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            '❌ Errores encontrados:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _buildPaginatedList(
            items: result.errors,
            currentPage: _errorsPage,
            onPageChanged: (page) => setState(() => _errorsPage = page),
            itemBuilder: (error) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error,
                    size: 16,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fila ${error.row}: ${error.message}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
  
  IconData _getWarningIcon(String type) {
    switch (type) {
      case 'value_changed':
        return Icons.swap_horiz;
      case 'category_override':
        return Icons.category;
      case 'stock_skipped':
        return Icons.inventory_2;
      case 'product_reused':
        return Icons.recycling;
      case 'sku_generated':
        return Icons.qr_code_2;
      default:
        return Icons.warning;
    }
  }
  
  Widget _buildPaginatedList<T>({
    required List<T> items,
    required int currentPage,
    required Function(int) onPageChanged,
    required Widget Function(T) itemBuilder,
  }) {
    final totalPages = (items.length / _itemsPerPage).ceil();
    final startIndex = currentPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, items.length);
    final pageItems = items.sublist(startIndex, endIndex);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: pageItems.map(itemBuilder).toList(),
          ),
        ),
        if (totalPages > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: currentPage > 0
                    ? () => onPageChanged(currentPage - 1)
                    : null,
              ),
              Text(
                'Página ${currentPage + 1} de $totalPages',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: currentPage < totalPages - 1
                    ? () => onPageChanged(currentPage + 1)
                    : null,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _selectFile() async {
    try {
      final fileWrapper = await ExcelImportService.pickExcelFile();
      if (fileWrapper != null) {
        setState(() {
          _selectedFile = fileWrapper;
          _analysisResult = null;
          _finalColumnMapping.clear();
          _discardedColumns.clear();
          _defaultValues.clear();
          _subcategoriesCache.clear(); // AGREGAR ESTA LÍNEA
          _importResult = null;
        });
        
        // Analizar automáticamente el archivo después de seleccionarlo
        await _analyzeFile();
        
        // Si el análisis fue exitoso, avanzar automáticamente al siguiente paso
        if (_analysisResult != null && mounted) {
          setState(() {
            _currentStep = 1; // Avanzar al paso de mapeo de columnas
          });
        }
      }
    } catch (e) {
      _showError('Error al seleccionar archivo: $e');
    }
  }

  /*
  Future<void> _downloadTemplate() async {
    try {
      final bytes = await ExcelImportService.generateTemplate();
      final directory = await getDownloadsDirectory();
      final file = File('${directory!.path}/template_productos.xlsx');
      await file.writeAsBytes(bytes);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template descargado: ${file.path}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _showError('Error al descargar template: $e');
    }
  }
*/
  Future<void> _analyzeFile() async {
    if (_selectedFile == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final result = await ExcelImportService.analyzeExcelFile(_selectedFile!);
      final categories = await ProductService.getCategorias();
      final units = await ProductService.getUnidadesMedida();

      print('Categorías cargadas en análisis: ${categories.length}'); // Debug
      print('Unidades cargadas en análisis: ${units.length}'); // Debug

      setState(() {
        _analysisResult = result;
        _finalColumnMapping = Map.from(result.columnAnalysis.mappedColumns);
        _categories = categories;
        _units = units;
      });
      
      // Mostrar mensaje de éxito
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Archivo analizado exitosamente. ${result.totalRows} filas detectadas.',
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      _showError('Error al analizar archivo: $e');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _startImport() async {
    if (_selectedFile == null || _finalColumnMapping.isEmpty) return;
    
    // Validar que se haya seleccionado categoría/subcategoría (OBLIGATORIO)
    if (!_defaultValues.containsKey('id_categoria') || _defaultValues['id_categoria'] == null) {
      _showError('Debe seleccionar una Categoría y Subcategoría para todos los productos');
      return;
    }
    
    // Validar configuración de stock si está activada
    if (_importWithStock) {
      if (_selectedLocationId == null) {
        _showError('Debe seleccionar una ubicación para el stock');
        return;
      }
      
      // ✅ NUEVO: Validar cantidad
      if (!_stockColumnMapping.containsKey('cantidad')) {
        _showError('Debe mapear la columna de Cantidad');
        return;
      }
      
      // ✅ NUEVO: Validar precio_compra - buscar fallback en precio_costo
      bool tienePrecioCompra = _stockColumnMapping.containsKey('precio_compra');
      
      if (!tienePrecioCompra) {
        // Buscar si precio_costo o costo está mapeado en _finalColumnMapping
        final tienePrecioCosto = _finalColumnMapping.values.contains('precio_costo') ||
                                 _finalColumnMapping.values.contains('costo');
        
        if (!tienePrecioCosto) {
          _showError('Debe mapear las columnas de Cantidad y Precio de Compra (o Costo)');
          return;
        }
        
        // ✅ Si precio_costo está mapeado, usarlo como precio_compra automáticamente
        print('💡 Usando precio_costo como precio_compra para stock inicial');
        
        // Encontrar la columna que mapea a precio_costo
        String? columnaPrecioCosto;
        for (final entry in _finalColumnMapping.entries) {
          if (entry.value == 'precio_costo') {
            columnaPrecioCosto = entry.key;
            break;
          }
        }
        
        if (columnaPrecioCosto != null) {
          _stockColumnMapping['precio_compra'] = columnaPrecioCosto;
          print('✅ Mapeado automáticamente: $columnaPrecioCosto → precio_compra');
        }
      }
    }

    // ✅ NUEVO: Mostrar diálogo para seleccionar moneda del precio_venta
    if (_finalColumnMapping.containsValue('precio_venta')) {
      final currencySelected = await _showPriceCurrencyDialog();
      if (currencySelected == null) {
        return; // Usuario canceló
      }
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
    });

    try {
      print('🚨 PANTALLA - Valores antes de enviar al servicio:');
      print('   📝 _defaultValues completo: $_defaultValues');
      print('   🔑 categoria_id en _defaultValues: ${_defaultValues['categoria_id']}');
      print('   📊 _selectedMainCategoryId: $_selectedMainCategoryId');
      print('   💱 Moneda del precio: $_priceCurrency');
      print('   📊 Tasa de cambio: $_exchangeRate');
      
      final result = await ExcelImportService.importProducts(
        _selectedFile!,
        _finalColumnMapping,
        defaultValues: _defaultValues,
        importWithStock: _importWithStock,
        stockConfig: _importWithStock ? {
          'locationId': _selectedLocationId!,
          'columnMapping': _stockColumnMapping,
        } : null,
        priceCurrency: _priceCurrency,
        exchangeRate: _exchangeRate,
        onProgress: (current, total) {
          setState(() => _importProgress = current / total);
        },
      );

      setState(() => _importResult = result);
    } catch (e) {
      _showError('Error durante la importación: $e');
    } finally {
      setState(() => _isImporting = false);
    }
  }

  /// Mostrar diálogo para seleccionar la moneda del precio_venta con dropdown
  Future<bool?> _showPriceCurrencyDialog() async {
    String selectedCurrency = 'USD';
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.currency_exchange, color: Colors.blue),
                  SizedBox(width: 12),
                  Text('Moneda del Precio de Venta'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¿En qué moneda está el precio_venta en el archivo Excel?',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.05),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '⚠️ Importante: El sistema guarda los precios en USD. Si están en otra moneda, se convertirán automáticamente.',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.05),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '✅ Almacenamiento de Precios:\n'
                      '• Precio de Venta: Se guarda en CUP\n'
                      '• Precio Costo: Se guarda en USD\n'
                      '• Conversión: Se utiliza la tasa de cambio cargada anteriormente',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Dropdown para seleccionar moneda
                  DropdownButtonFormField<String>(
                    value: selectedCurrency,
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar Moneda',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.money),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'USD',
                        child: Text('USD - Dólar Estadounidense'),
                      ),
                      DropdownMenuItem(
                        value: 'CUP',
                        child: Text('CUP - Peso Cubano'),
                      ),
                      DropdownMenuItem(
                        value: 'EUR',
                        child: Text('EUR - Euro'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedCurrency = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Mostrar información de la tasa
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FutureBuilder<String>(
                      future: _getTasaInfo(selectedCurrency),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Text(
                            'Cargando tasa...',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          );
                        }
                        return Text(
                          snapshot.data ?? 'No se pudo cargar la tasa',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        );
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Actualizar la moneda seleccionada en el estado principal
                    _priceCurrency = selectedCurrency;
                    
                    // Si seleccionó CUP o EUR, obtener tasa de cambio
                    if (_priceCurrency != 'USD') {
                      try {
                        _exchangeRate = await _getExchangeRate(_priceCurrency);
                        print('💱 Tasa de cambio obtenida: $_exchangeRate');
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error obteniendo tasa de cambio: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        return;
                      }
                    }
                    if (mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Obtener información de la tasa para mostrar en el diálogo
  Future<String> _getTasaInfo(String currency) async {
    try {
      if (currency == 'USD') {
        return '💵 USD: Sin conversión, los precios se guardan tal cual.';
      }
      
      // Cargar tasas reales desde CurrencyService
      final rates = await CurrencyService.getCurrentRatesFromDatabase();
      
      // Buscar la tasa para la moneda seleccionada
      final rateData = rates.firstWhere(
        (rate) => rate['moneda_origen'] == currency,
        orElse: () => <String, dynamic>{},
      );
      
      if (rateData.isNotEmpty) {
        final tasa = (rateData['tasa'] as num?)?.toDouble() ?? 0;
        
        switch (currency) {
          case 'CUP':
            return '💱 CUP: 1 CUP = ${tasa.toStringAsFixed(6)} USD\nLos precios se convertirán multiplicando por $tasa.';
          case 'EUR':
            return '💶 EUR: 1 EUR = ${tasa.toStringAsFixed(2)} CUP\nLos precios se convertirán dividiendo entre $tasa.';
          default:
            return '💱 $currency: Tasa = $tasa';
        }
      } else {
        // Si no encuentra la tasa, buscar en formato inverso (USD→CUP)
        final inverseRate = rates.firstWhere(
          (rate) => rate['moneda_origen'] == 'USD',
          orElse: () => <String, dynamic>{},
        );
        
        if (inverseRate.isNotEmpty) {
          final tasaUsdACup = (inverseRate['tasa'] as num?)?.toDouble() ?? 0;
          final tasaCupAUsd = 1.0 / tasaUsdACup;
          return '💱 $currency: 1 USD = ${tasaUsdACup.toStringAsFixed(2)} CUP (1 CUP = ${tasaCupAUsd.toStringAsFixed(6)} USD)';
        }
        
        return '⚠️ No se encontró tasa para $currency en la base de datos.';
      }
    } catch (e) {
      return '❌ Error al cargar la tasa: $e';
    }
  }

  /// Obtener tasa de cambio usando CurrencyService
  Future<double> _getExchangeRate(String fromCurrency) async {
    try {
      print('📊 Obteniendo tasa de cambio de $fromCurrency a USD usando CurrencyService...');
      
      // Si es USD, retornar 1.0 (no hay conversión)
      if (fromCurrency == 'USD') {
        print('✅ Moneda es USD, no requiere conversión');
        return 1.0;
      }
      
      // Si es CUP, usar CurrencyService para obtener la tasa USD→CUP y luego invertir
      if (fromCurrency == 'CUP') {
        final usdToCupRate = await CurrencyService.getEffectiveUsdToCupRate();
        print('💱 Tasa USD→CUP obtenida de CurrencyService: $usdToCupRate');
        final cupToUsdRate = 1.0 / usdToCupRate;
        print('✅ Tasa de cambio CUP→USD: $cupToUsdRate');
        return cupToUsdRate;
      }
      
      // Para otras monedas, obtener de la tabla tasas_conversion usando CurrencyService
      print('🔍 Buscando tasa de conversión para $fromCurrency en BD...');
      final rates = await CurrencyService.getEffectiveRatesFromDatabase();
      
      // Buscar la tasa de fromCurrency a USD
      final rateData = rates.firstWhere(
        (rate) => rate['moneda_origen'] == fromCurrency && 
                  (rate['moneda_destino'] == 'USD' || rate['moneda_destino'] == null),
        orElse: () => <String, dynamic>{},
      );
      
      if (rateData.isEmpty) {
        print('⚠️ No se encontró tasa de conversión para $fromCurrency → USD');
        throw Exception('Moneda no soportada: $fromCurrency. Solo se soportan USD y CUP.');
      }
      
      final rate = (rateData['tasa'] as num?)?.toDouble() ?? 1.0;
      print('✅ Tasa de cambio (desde BD): 1 $fromCurrency = $rate USD');
      return rate;
      
    } catch (e) {
      print('❌ Error obteniendo tasa de cambio: $e');
      rethrow;
    }
  }

  void _editMapping(String excelColumn, String currentMapping) {
    // Implementar diálogo de edición de mapeo
  }

  bool _canProceedToNextStep(int currentStep) {
    switch (currentStep) {
      case 0:
        return _selectedFile != null;
      case 1:
        return _selectedFile != null; // Permitir análisis si hay archivo
      case 2:
        // Validar que haya mapeo de columnas Y que se haya seleccionado categoría/subcategoría
        final hasCategorySelected = _defaultValues.containsKey('id_categoria') && 
                                     _defaultValues['id_categoria'] != null;
        return (_finalColumnMapping.isNotEmpty || _defaultValues.isNotEmpty) && hasCategorySelected;
      case 3:
        return true;
      default:
        return false;
    }
  }

  void _proceedToNextStep(int currentStep) {
    // Validar categoría antes de avanzar desde el paso 2 (mapeo de columnas)
    if (currentStep == 2) {
      if (!_defaultValues.containsKey('id_categoria') || _defaultValues['id_categoria'] == null) {
        _showError('Debe seleccionar una Categoría y Subcategoría antes de continuar');
        return;
      }
    }
    // Ya no es necesario analizar aquí porque se hace automáticamente al seleccionar archivo
    setState(() => _currentStep = currentStep + 1);
  }

  int _getMaxAllowedStep() {
    if (_importResult != null) return 4;
    if (_finalColumnMapping.isNotEmpty) return 3;
    if (_analysisResult != null) return 2;
    if (_selectedFile != null) return 1;
    return 0;
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  Widget _buildUnmappedColumnRow(String excelColumn) {
    final isDiscarded = _discardedColumns.contains(excelColumn);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isDiscarded
                ? Colors.red.withOpacity(0.1)
                : Colors.grey.withOpacity(0.1),
        border: Border.all(
          color:
              isDiscarded
                  ? Colors.red.withOpacity(0.3)
                  : Colors.grey.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isDiscarded ? Icons.delete : Icons.help_outline,
            color: isDiscarded ? Colors.red : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              excelColumn,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDiscarded ? Colors.red : Colors.black,
                decoration: isDiscarded ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (!isDiscarded) ...[
            ElevatedButton.icon(
              onPressed: () => _showManualMappingDialog(excelColumn),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Mapear'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                if (isDiscarded) {
                  _discardedColumns.remove(excelColumn);
                } else {
                  _discardedColumns.add(excelColumn);
                  _finalColumnMapping.remove(excelColumn);
                }
              });
            },
            icon: Icon(isDiscarded ? Icons.restore : Icons.delete, size: 16),
            label: Text(isDiscarded ? 'Restaurar' : 'Descartar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDiscarded ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMandatoryCategorySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.05),
        border: Border.all(color: Colors.red.withOpacity(0.4), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.category, color: Colors.red.shade700, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Categoría y Subcategoría (OBLIGATORIO)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Todos los productos importados se asignarán a la categoría/subcategoría seleccionada',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCategorySelector('categoria_id'),
        ],
      ),
    );
  }

  Widget _buildDefaultValuesSection() {
    // Campos obligatorios que podrían necesitar valores por defecto
    // NOTA: categoria_id es obligatorio pero se maneja por separado con dropdowns
    final requiredFields = [
      'denominacion',
      'descripcion',
      'sku',
      'precio_venta',
    ];
    final mappedFields = _finalColumnMapping.values.toSet();
    final missingFields =
        requiredFields.where((field) => !mappedFields.contains(field)).toList();

    if (missingFields.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              const Icon(Icons.settings, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: const Text(
                  'Valores por defecto para campos faltantes:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...missingFields.map((field) => _buildDefaultValueRow(field)),
        ],
      ),
    );
  }

  Widget _buildDefaultValueRow(String field) {
    print('Construyendo campo: $field con valor: ${_defaultValues[field]}');
    
    // Saltar categoria_id porque se maneja en la sección obligatoria
    if (field == 'categoria_id') {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _buildDefaultTextField(field),
        ],
      ),
    );
  }

  String _getDefaultHint(String field) {
    switch (field) {
      case 'precio_venta':
        return '0.00';
      case 'categoria_id':
        return 'Seleccionar de la lista'; // CAMBIAR ESTE
      case 'denominacion':
        return 'Producto sin nombre';
      case 'descripcion':
        return 'Sin descripción';
      case 'sku':
        return 'AUTO-001';
      default:
        return 'Valor por defecto';
    }
  }

  Widget _buildStockImportSection() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle
          CheckboxListTile(
            value: _importWithStock,
            onChanged: (value) {
              setState(() {
                _importWithStock = value ?? false;
                if (!_importWithStock) {
                  _stockColumnMapping.clear();
                  _selectedLocationId = null;
                }
              });
            },
            title: const Text(
              '📦 Importar con Stock Inicial',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: const Text(
              'Se creará una operación de recepción con todos los productos',
              style: TextStyle(fontSize: 12),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          
          if (_importWithStock) ...[
            const Divider(height: 24),
            
            // Ubicación
            const Text(
              'Ubicación de Almacenamiento *',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _selectedLocationId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Seleccione la zona',
                prefixIcon: Icon(Icons.location_on),
              ),
              items: _locations.map((loc) {
                return DropdownMenuItem<int>(
                  value: loc['id'],
                  child: Text(loc['denominacion']),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedLocationId = value),
            ),
            const SizedBox(height: 16),
            
            // Mapeo de columnas
            const Text(
              'Mapeo de Columnas de Stock',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildStockColumnRow('cantidad', 'Cantidad/Stock *'),
            // _buildStockColumnRow('precio_compra', 'Precio de Compra *'),
          ],
        ],
      ),
    );
  }

  Widget _buildStockColumnRow(String field, String label) {
    // ✅ NUEVO: Filtrar columnas disponibles eliminando duplicados
    final allHeaders = _analysisResult?.headers ?? [];
    final availableColumns = <String>{};
    
    for (final h in allHeaders) {
      // Incluir si no está mapeada en _finalColumnMapping
      if (!_finalColumnMapping.containsKey(h)) {
        availableColumns.add(h);
      }
      // O si ya está seleccionada en el stock mapping actual
      else if (_stockColumnMapping[field] == h) {
        availableColumns.add(h);
      }
    }
    
    final availableColumnsList = availableColumns.toList();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward, size: 16),
          const SizedBox(width: 4),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: _stockColumnMapping[field],
              isExpanded: true, // Permite que el dropdown use todo el espacio disponible
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Seleccionar',
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    '(No mapear)',
                    style: TextStyle(color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...availableColumnsList.map((col) {
                  return DropdownMenuItem<String>(
                    value: col,
                    child: Text(
                      col,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  if (value == null) {
                    _stockColumnMapping.remove(field);
                  } else {
                    _stockColumnMapping[field] = value;
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showManualMappingDialog(String excelColumn) {
    final availableFields = [
      'denominacion',
      'descripcion',
      'categoria_id',
      'sku',
      'precio_venta',
      'denominacion_corta',
      'nombre_comercial',
      'codigo_barras',
      'unidad_medida',
      'es_refrigerado',
      'es_fragil',
      'es_peligroso',
      'es_vendible',
      'es_comprable',
      'stock_minimo',
      'stock_maximo',
      'es_oferta',
      'precio_oferta',
      'es_elaborado',
    ];

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Mapear columna: $excelColumn'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableFields.length,
                itemBuilder: (context, index) {
                  final field = availableFields[index];
                  return ListTile(
                    title: Text(field),
                    onTap: () {
                      setState(() {
                        _finalColumnMapping[excelColumn] = field;
                      });
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ],
          ),
    );
  }

  Widget _buildDefaultTextField(String field) {
    return TextFormField(
      initialValue: _defaultValues[field]?.toString() ?? '',
      decoration: InputDecoration(
        hintText: _getDefaultHint(field),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        filled: true,
        fillColor: Colors.grey.withOpacity(0.1),
      ),
      onChanged: (value) {
        setState(() {
          if (value.isEmpty) {
            _defaultValues.remove(field);
          } else {
            _defaultValues[field] = value;
          }
        });
      },
    );
  }

  Widget _buildCategorySelector(String field) {
    // Verificar si hay categorías cargadas
    if (_categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.hourglass_empty, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Text(
              'Cargando categorías...',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final availableCategories = _categories;
    
    // Usar _selectedMainCategoryId para el dropdown de categoría principal
    // Esto mantiene la selección incluso cuando se selecciona una subcategoría

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // DROPDOWN 1: CATEGORÍAS PRINCIPALES (OBLIGATORIO)
        DropdownButtonFormField<int>(
          value: _selectedMainCategoryId,
          decoration: const InputDecoration(
            labelText: 'Categoría Principal *',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          hint: const Text('Seleccionar categoría'),
          validator: (value) {
            if (value == null) {
              return 'Debe seleccionar una categoría';
            }
            return null;
          },
          items:
              availableCategories.map<DropdownMenuItem<int>>((category) {
                final categoryId = category['id'] as int?;
                final categoryName = category['denominacion'] as String?;

                return DropdownMenuItem<int>(
                  value: categoryId,
                  child: Text(
                    categoryName ?? 'Sin nombre',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
          onChanged: (int? newValue) {
            setState(() {
              if (newValue != null) {
                _selectedMainCategoryId = newValue; // Guardar categoría principal
                _defaultValues['id_categoria'] = newValue; // Guardar como id_categoria
                _defaultValues.remove('id_subcategoria'); // Limpiar subcategoría anterior
                // Limpiar caché de subcategorías para forzar recarga
                _subcategoriesCache.remove(newValue);
                print('🏷️ CATEGORÍA PRINCIPAL SELECCIONADA:');
                print('   ID: $newValue');
                print('   Nombre: ${_getCategoryName(newValue)}');
                print('   _defaultValues["id_categoria"]: ${_defaultValues['id_categoria']}');
                print('   _defaultValues["id_subcategoria"]: ${_defaultValues['id_subcategoria']}');
              } else {
                _selectedMainCategoryId = null;
                _defaultValues.remove('id_categoria');
                _defaultValues.remove('id_subcategoria');
                print('❌ CATEGORÍA PRINCIPAL DESELECCIONADA');
              }
            });
          },
        ),

        const SizedBox(height: 16),

        // DROPDOWN 2: SUBCATEGORÍAS (OBLIGATORIO si hay categoría seleccionada)
        if (_selectedMainCategoryId != null)
          _buildSubcategoryDropdown(field, _selectedMainCategoryId!),
      ],
    );
  }

  Widget _buildSubcategoryDropdown(String field, int categoryId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getSubcategories(categoryId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Error cargando subcategorías',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          );
        }

        final subcategories = snapshot.data ?? [];
        // Obtener el valor de id_subcategoria (no de field que es 'categoria_id')
        final currentSubcategoryValue = _defaultValues['id_subcategoria'] as int?;

        // Verificar si el valor actual es una subcategoría
        final selectedSubcategory = subcategories.firstWhere(
          (sub) => sub['id'] == currentSubcategoryValue,
          orElse: () => <String, dynamic>{},
        );

        final isSubcategorySelected = selectedSubcategory.isNotEmpty;

        if (subcategories.isEmpty) {
          // Si no hay subcategorías, usar la categoría padre automáticamente
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_defaultValues[field] != categoryId) {
              setState(() {
                _defaultValues[field] = categoryId;
              });
            }
          });

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Sin subcategorías - usando categoría principal',
              style: TextStyle(color: Colors.blue, fontSize: 12),
            ),
          );
        }

        return DropdownButtonFormField<int>(
          value: isSubcategorySelected ? currentSubcategoryValue : null,
          decoration: const InputDecoration(
            labelText: 'Subcategoría *',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          hint: const Text('Seleccionar subcategoría'),
          validator: (value) {
            if (value == null) {
              return 'Debe seleccionar una subcategoría';
            }
            return null;
          },
          items:
              subcategories.map<DropdownMenuItem<int>>((subcat) {
                final subcatId = subcat['id'] as int?;
                final subcatName = subcat['denominacion'] as String?;

                return DropdownMenuItem<int>(
                  value: subcatId,
                  child: Text(
                    subcatName ?? 'Sin nombre',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
          onChanged: (int? newValue) {
            setState(() {
              if (newValue != null) {
                // Guardar AMBOS: id_categoria (padre) e id_subcategoria
                _defaultValues['id_categoria'] = _selectedMainCategoryId!;
                _defaultValues['id_subcategoria'] = newValue;
                print('📂 SUBCATEGORÍA SELECCIONADA:');
                print('   ID Subcategoría: $newValue');
                print('   Nombre Subcategoría: ${_getCategoryName(newValue)}');
                print('   ID Categoría Padre: $_selectedMainCategoryId');
                print('   Nombre Categoría Padre: ${_getCategoryName(_selectedMainCategoryId!)}');
                print('   _defaultValues["id_categoria"]: ${_defaultValues['id_categoria']}');
                print('   _defaultValues["id_subcategoria"]: ${_defaultValues['id_subcategoria']}');
              }
            });
          },
        );
      },
    );
  }

  String _getCategoryName(int categoryId) {
    try {
      // Buscar primero en categorías principales
      try {
        final category = _categories.firstWhere((cat) => cat['id'] == categoryId);
        return category['denominacion'] as String? ?? 'Sin nombre';
      } catch (e) {
        // Si no se encuentra, buscar en subcategorías
        for (final subcatList in _subcategoriesCache.values) {
          try {
            final subcat = subcatList.firstWhere((sub) => sub['id'] == categoryId);
            return subcat['denominacion'] as String? ?? 'Sin nombre';
          } catch (e) {
            continue;
          }
        }
      }
      return 'Categoría no encontrada';
    } catch (e) {
      return 'Categoría no encontrada';
    }
  }

  Widget _buildSubcategorySelector(String field, int categoryId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getSubcategories(categoryId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Cargando subcategorías...',
                  style: TextStyle(color: Colors.blue, fontSize: 12),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Error cargando subcategorías: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final subcategories = snapshot.data ?? [];

        if (subcategories.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Esta categoría no tiene subcategorías',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _defaultValues[field] =
                          categoryId; // Usar categoría padre
                    });
                  },
                  icon: const Icon(Icons.folder, size: 16),
                  label: const Text('Usar solo categoría principal'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // SIEMPRE mostrar subcategorías disponibles
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Selecciona una subcategoría:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.green,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _defaultValues[field] =
                          categoryId; // Usar categoría padre
                    });
                  },
                  icon: const Icon(Icons.folder, size: 14),
                  label: const Text('Solo categoría'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.05),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Mostrar todas las subcategorías como lista seleccionable
                  ...subcategories.map((subcat) {
                    final subcatId = subcat['id'] as int?;
                    final isSelected = _defaultValues[field] == subcatId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _defaultValues[field] = subcatId;
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.white,
                            border: Border.all(
                              color:
                                  isSelected
                                      ? Colors.green
                                      : Colors.green.withOpacity(0.3),
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: isSelected ? Colors.green : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  subcat['denominacion'] as String? ??
                                      'Sin nombre',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        isSelected
                                            ? Colors.green.shade800
                                            : Colors.black87,
                                    fontWeight:
                                        isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected) ...[
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getSubcategories(int categoryId) async {
    // Usar caché si ya tenemos las subcategorías
    if (_subcategoriesCache.containsKey(categoryId)) {
      return _subcategoriesCache[categoryId]!;
    }

    try {
      final subcategories = await ProductService.getSubcategorias(categoryId);
      _subcategoriesCache[categoryId] = subcategories;
      return subcategories;
    } catch (e) {
      print('Error obteniendo subcategorías para categoría $categoryId: $e');
      return [];
    }
  }
}
