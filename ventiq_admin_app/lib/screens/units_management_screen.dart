import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/restaurant_service.dart';
import '../models/restaurant_models.dart';

class UnitsManagementScreen extends StatefulWidget {
  const UnitsManagementScreen({Key? key}) : super(key: key);

  @override
  State<UnitsManagementScreen> createState() => _UnitsManagementScreenState();
}

class _UnitsManagementScreenState extends State<UnitsManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Estado para unidades de medida
  List<UnidadMedida> _unidades = [];
  List<ConversionUnidad> _conversiones = [];
  bool _isLoading = true;
  
  // Filtros
  int? _filtroTipoUnidad;
  String _filtroTexto = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final unidades = await RestaurantService.getUnidadesMedida();
      final conversiones = await RestaurantService.getConversiones();
      
      setState(() {
        _unidades = unidades;
        _conversiones = conversiones;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error cargando datos: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<UnidadMedida> get _unidadesFiltradas {
    var filtradas = _unidades.where((unidad) {
      final matchTexto = _filtroTexto.isEmpty ||
          unidad.denominacion.toLowerCase().contains(_filtroTexto.toLowerCase()) ||
          unidad.abreviatura.toLowerCase().contains(_filtroTexto.toLowerCase());
      
      final matchTipo = _filtroTipoUnidad == null || 
          unidad.tipoUnidad == _filtroTipoUnidad;
      
      return matchTexto && matchTipo;
    }).toList();
    
    // Ordenar por tipo y luego por nombre
    filtradas.sort((a, b) {
      final tipoComparison = a.tipoUnidad.compareTo(b.tipoUnidad);
      if (tipoComparison != 0) return tipoComparison;
      return a.denominacion.compareTo(b.denominacion);
    });
    
    return filtradas;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Unidades de Medida'),
        backgroundColor: Colors.orange[800],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.straighten),
              text: 'Unidades',
            ),
            Tab(
              icon: Icon(Icons.swap_horiz),
              text: 'Conversiones',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUnidadesTab(),
          _buildConversionesTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _showUnidadDialog();
          } else {
            _showConversionDialog();
          }
        },
        backgroundColor: Colors.orange[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildUnidadesTab() {
    return Column(
      children: [
        // Filtros
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar unidad',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _filtroTexto = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                decoration: const InputDecoration(
                  labelText: 'Tipo de unidad',
                  border: OutlineInputBorder(),
                ),
                value: _filtroTipoUnidad,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  const DropdownMenuItem(value: 1, child: Text('Peso')),
                  const DropdownMenuItem(value: 2, child: Text('Volumen')),
                  const DropdownMenuItem(value: 3, child: Text('Longitud')),
                  const DropdownMenuItem(value: 4, child: Text('Unidad')),
                ],
                onChanged: (value) => setState(() => _filtroTipoUnidad = value),
              ),
            ],
          ),
        ),
        // Lista de unidades
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _unidadesFiltradas.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.straighten, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No hay unidades de medida',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _unidadesFiltradas.length,
                      itemBuilder: (context, index) {
                        final unidad = _unidadesFiltradas[index];
                        return _buildUnidadCard(unidad);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildUnidadCard(UnidadMedida unidad) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getTipoColor(unidad.tipoUnidad),
          child: Text(
            unidad.abreviatura,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          unidad.denominacion,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipo: ${unidad.tipoUnidadTexto}'),
            if (unidad.esBase)
              const Text(
                'Unidad base',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (unidad.factorBase != null)
              Text('Factor base: ${unidad.factorBase}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showUnidadDialog(unidad: unidad),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDeleteUnidad(unidad),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversionesTab() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _conversiones.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swap_horiz, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No hay conversiones configuradas',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _conversiones.length,
                itemBuilder: (context, index) {
                  final conversion = _conversiones[index];
                  return _buildConversionCard(conversion);
                },
              );
  }

  Widget _buildConversionCard(ConversionUnidad conversion) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.swap_horiz, color: Colors.orange),
        title: Text(
          '${conversion.unidadOrigen?.denominacion ?? 'N/A'} → ${conversion.unidadDestino?.denominacion ?? 'N/A'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Factor: ${conversion.factorConversion}'),
            if (conversion.esAproximada)
              const Text(
                'Conversión aproximada',
                style: TextStyle(
                  color: Colors.orange,
                  fontStyle: FontStyle.italic,
                ),
              ),
            if (conversion.observaciones != null)
              Text('Obs: ${conversion.observaciones}'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showConversionDialog(conversion: conversion),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmDeleteConversion(conversion),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTipoColor(int tipo) {
    switch (tipo) {
      case 1: return Colors.brown; // Peso
      case 2: return Colors.blue;  // Volumen
      case 3: return Colors.green; // Longitud
      case 4: return Colors.purple; // Unidad
      default: return Colors.grey;
    }
  }

  void _showUnidadDialog({UnidadMedida? unidad}) {
    final isEditing = unidad != null;
    final denominacionController = TextEditingController(
      text: unidad?.denominacion ?? '',
    );
    final abreviaturaController = TextEditingController(
      text: unidad?.abreviatura ?? '',
    );
    final descripcionController = TextEditingController(
      text: unidad?.descripcion ?? '',
    );
    final factorBaseController = TextEditingController(
      text: unidad?.factorBase?.toString() ?? '',
    );
    
    int tipoUnidad = unidad?.tipoUnidad ?? 1;
    bool esBase = unidad?.esBase ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar Unidad' : 'Nueva Unidad'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: denominacionController,
                  decoration: const InputDecoration(
                    labelText: 'Denominación *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: abreviaturaController,
                  decoration: const InputDecoration(
                    labelText: 'Abreviatura *',
                    border: OutlineInputBorder(),
                  ),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(10),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Tipo de unidad *',
                    border: OutlineInputBorder(),
                  ),
                  value: tipoUnidad,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Peso')),
                    DropdownMenuItem(value: 2, child: Text('Volumen')),
                    DropdownMenuItem(value: 3, child: Text('Longitud')),
                    DropdownMenuItem(value: 4, child: Text('Unidad')),
                  ],
                  onChanged: (value) => setDialogState(() => tipoUnidad = value!),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Es unidad base'),
                  subtitle: const Text('Unidad de referencia para conversiones'),
                  value: esBase,
                  onChanged: (value) => setDialogState(() => esBase = value!),
                ),
                if (!esBase) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: factorBaseController,
                    decoration: const InputDecoration(
                      labelText: 'Factor base',
                      helperText: 'Factor de conversión a la unidad base',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => _saveUnidad(
                isEditing: isEditing,
                unidadId: unidad?.id,
                denominacion: denominacionController.text,
                abreviatura: abreviaturaController.text,
                tipoUnidad: tipoUnidad,
                esBase: esBase,
                factorBase: factorBaseController.text.isNotEmpty 
                    ? double.tryParse(factorBaseController.text)
                    : null,
                descripcion: descripcionController.text.isNotEmpty 
                    ? descripcionController.text 
                    : null,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800],
                foregroundColor: Colors.white,
              ),
              child: Text(isEditing ? 'Actualizar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _showConversionDialog({ConversionUnidad? conversion}) {
    final isEditing = conversion != null;
    final factorController = TextEditingController(
      text: conversion?.factorConversion.toString() ?? '',
    );
    final observacionesController = TextEditingController(
      text: conversion?.observaciones ?? '',
    );
    
    UnidadMedida? unidadOrigen = conversion?.unidadOrigen;
    UnidadMedida? unidadDestino = conversion?.unidadDestino;
    bool esAproximada = conversion?.esAproximada ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar Conversión' : 'Nueva Conversión'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<UnidadMedida?>(
                  decoration: const InputDecoration(
                    labelText: 'Unidad origen *',
                    border: OutlineInputBorder(),
                  ),
                  value: unidadOrigen,
                  items: _unidades.map((unidad) => DropdownMenuItem(
                    value: unidad,
                    child: Text('${unidad.denominacion} (${unidad.abreviatura})'),
                  )).toList(),
                  onChanged: (value) => setDialogState(() => unidadOrigen = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UnidadMedida?>(
                  decoration: const InputDecoration(
                    labelText: 'Unidad destino *',
                    border: OutlineInputBorder(),
                  ),
                  value: unidadDestino,
                  items: _unidades.map((unidad) => DropdownMenuItem(
                    value: unidad,
                    child: Text('${unidad.denominacion} (${unidad.abreviatura})'),
                  )).toList(),
                  onChanged: (value) => setDialogState(() => unidadDestino = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: factorController,
                  decoration: const InputDecoration(
                    labelText: 'Factor de conversión *',
                    helperText: '1 unidad origen = X unidades destino',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Conversión aproximada'),
                  subtitle: const Text('Marcar si la conversión no es exacta'),
                  value: esAproximada,
                  onChanged: (value) => setDialogState(() => esAproximada = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacionesController,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => _saveConversion(
                isEditing: isEditing,
                conversionId: conversion?.id,
                unidadOrigen: unidadOrigen,
                unidadDestino: unidadDestino,
                factor: double.tryParse(factorController.text),
                esAproximada: esAproximada,
                observaciones: observacionesController.text.isNotEmpty 
                    ? observacionesController.text 
                    : null,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[800],
                foregroundColor: Colors.white,
              ),
              child: Text(isEditing ? 'Actualizar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveUnidad({
    required bool isEditing,
    int? unidadId,
    required String denominacion,
    required String abreviatura,
    required int tipoUnidad,
    required bool esBase,
    double? factorBase,
    String? descripcion,
  }) async {
    if (denominacion.isEmpty || abreviatura.isEmpty) {
      _showErrorSnackBar('Denominación y abreviatura son obligatorios');
      return;
    }

    try {
      // Aquí iría la lógica para guardar en la base de datos
      // Por ahora simulamos el éxito
      Navigator.pop(context);
      _showSuccessSnackBar(
        isEditing ? 'Unidad actualizada correctamente' : 'Unidad creada correctamente'
      );
      _loadData();
    } catch (e) {
      _showErrorSnackBar('Error al guardar: $e');
    }
  }

  void _saveConversion({
    required bool isEditing,
    int? conversionId,
    UnidadMedida? unidadOrigen,
    UnidadMedida? unidadDestino,
    double? factor,
    required bool esAproximada,
    String? observaciones,
  }) async {
    if (unidadOrigen == null || unidadDestino == null || factor == null) {
      _showErrorSnackBar('Todos los campos obligatorios deben completarse');
      return;
    }

    if (unidadOrigen.id == unidadDestino.id) {
      _showErrorSnackBar('Las unidades origen y destino deben ser diferentes');
      return;
    }

    if (factor <= 0) {
      _showErrorSnackBar('El factor de conversión debe ser mayor a 0');
      return;
    }

    try {
      // Aquí iría la lógica para guardar en la base de datos
      Navigator.pop(context);
      _showSuccessSnackBar(
        isEditing ? 'Conversión actualizada correctamente' : 'Conversión creada correctamente'
      );
      _loadData();
    } catch (e) {
      _showErrorSnackBar('Error al guardar: $e');
    }
  }

  void _confirmDeleteUnidad(UnidadMedida unidad) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Está seguro de eliminar la unidad "${unidad.denominacion}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteUnidad(unidad);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteConversion(ConversionUnidad conversion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: const Text('¿Está seguro de eliminar esta conversión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteConversion(conversion);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteUnidad(UnidadMedida unidad) async {
    try {
      // Aquí iría la lógica para eliminar de la base de datos
      _showSuccessSnackBar('Unidad eliminada correctamente');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('Error al eliminar: $e');
    }
  }

  void _deleteConversion(ConversionUnidad conversion) async {
    try {
      // Aquí iría la lógica para eliminar de la base de datos
      _showSuccessSnackBar('Conversión eliminada correctamente');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('Error al eliminar: $e');
    }
  }
}
