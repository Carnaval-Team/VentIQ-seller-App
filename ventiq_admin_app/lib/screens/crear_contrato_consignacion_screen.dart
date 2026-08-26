import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/user_preferences_service.dart';
import '../services/subscription_service.dart';
import '../widgets/admin_drawer.dart';

class CrearContratoConsignacionScreen extends StatefulWidget {
  const CrearContratoConsignacionScreen({Key? key}) : super(key: key);

  @override
  State<CrearContratoConsignacionScreen> createState() => _CrearContratoConsignacionScreenState();
}

class _CrearContratoConsignacionScreenState extends State<CrearContratoConsignacionScreen> {
  final _formKey = GlobalKey<FormState>();
  
  int? _idTiendaActual;
  int? _idTiendaConsignataria;
  int? _idAlmacenDestino;
  double? _porcentajeComision;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  int? _plazoDias;
  String? _condiciones;
  
  List<Map<String, dynamic>> _tiendasDisponibles = [];
  List<Map<String, dynamic>> _almacenesDestino = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _tienePlanAvanzado = false;
  bool _cargandoAlmacenes = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final userPrefs = UserPreferencesService();
      final storeData = await userPrefs.getCurrentStoreInfo();
      _idTiendaActual = storeData?['id_tienda'] as int?;

      if (_idTiendaActual != null) {
        // Verificar si tiene plan Avanzado
        final subscriptionService = SubscriptionService();
        final tienePlan = await subscriptionService.hasFeatureEnabled(_idTiendaActual!, 'consignacion');
        
        final tiendas = await ConsignacionService.getTiendasDisponibles(_idTiendaActual!);
        setState(() {
          _tiendasDisponibles = tiendas;
          _tienePlanAvanzado = tienePlan;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ Error cargando datos: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _crearContrato() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idTiendaActual == null || _idTiendaConsignataria == null) return;

    setState(() => _isSaving = true);

    try {
      final contrato = await ConsignacionService.crearContrato(
        idTiendaConsignadora: _idTiendaActual!,
        idTiendaConsignataria: _idTiendaConsignataria!,
        porcentajeComision: _porcentajeComision!,
        idAlmacenDestino: null, // Se seleccionará al confirmar
        fechaInicio: _fechaInicio,
        fechaFin: _fechaFin,
        plazoDias: _plazoDias,
        condiciones: _condiciones,
      );

      if (!mounted) return;

      if (contrato != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Contrato creado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, contrato);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al crear el contrato'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Crear Contrato de Consignación',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    // Validación de plan
                    if (!_tienePlanAvanzado)
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline, color: Colors.red.shade700),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Plan Avanzado Requerido',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Solo puedes crear contratos de consignación con el plan Avanzado. Contáctanos para actualizar tu plan.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.red.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      // Información
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue.shade700),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Crea un contrato para enviar productos en consignación a otra tienda',
                                  style: TextStyle(color: Colors.blue.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Tienda consignataria
                    _buildWebCard(
                      title: 'Tienda Destino',
                      subtitle:
                          'Selecciona la tienda que recibirá los productos',
                      icon: Icons.store_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[400]!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: DropdownButton<int>(
                        value: _idTiendaConsignataria,
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('Seleccionar tienda *'),
                        ),
                        items: _tiendasDisponibles.map((tienda) {
                          return DropdownMenuItem<int>(
                            value: tienda['id'],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    tienda['denominacion'],
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (tienda['direccion'] != null)
                                    Text(
                                      tienda['direccion'],
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _idTiendaConsignataria = value);
                        },
                      ),
                    ),
                    if (_idTiendaConsignataria == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Debe seleccionar una tienda',
                          style: TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Nota: El almacén destino se seleccionará al confirmar la asignación de productos
                    if (_idTiendaConsignataria != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          border: Border.all(color: Colors.blue.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'El almacén destino será seleccionado por la tienda consignataria al confirmar la asignación de productos',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Porcentaje de comisión
                    _buildWebCard(
                      title: 'Comisión',
                      subtitle: 'Porcentaje que retiene la tienda destino',
                      icon: Icons.percent_outlined,
                      child: TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Porcentaje de comisión *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.percent),
                        suffixText: '%',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        _porcentajeComision = double.tryParse(value);
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'El porcentaje de comisión es obligatorio';
                        }
                        final porcentaje = double.tryParse(value);
                        if (porcentaje == null) {
                          return 'Ingrese un número válido';
                        }
                        if (porcentaje < 0 || porcentaje > 100) {
                          return 'El porcentaje debe estar entre 0 y 100';
                        }
                        return null;
                      },
                    ),
                    ),
                    const SizedBox(height: 20),

                    // Fechas
                    _buildWebCard(
                      title: 'Período del Contrato',
                      subtitle: 'Define la vigencia del contrato',
                      icon: Icons.date_range_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final fecha = await showDatePicker(
                                context: context,
                                initialDate: _fechaInicio ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (fecha != null) {
                                setState(() => _fechaInicio = fecha);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Fecha inicio',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                _fechaInicio != null
                                    ? '${_fechaInicio!.day}/${_fechaInicio!.month}/${_fechaInicio!.year}'
                                    : 'Hoy',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final fecha = await showDatePicker(
                                context: context,
                                initialDate: _fechaFin ?? DateTime.now().add(const Duration(days: 30)),
                                firstDate: _fechaInicio ?? DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 730)),
                              );
                              if (fecha != null) {
                                setState(() => _fechaFin = fecha);
                              }
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Fecha fin',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.event),
                                suffixIcon: _fechaFin != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 20),
                                        onPressed: () {
                                          setState(() => _fechaFin = null);
                                        },
                                      )
                                    : null,
                              ),
                              child: Text(
                                _fechaFin != null
                                    ? '${_fechaFin!.day}/${_fechaFin!.month}/${_fechaFin!.year}'
                                    : 'Opcional',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Plazo en días
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Plazo en días (opcional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.access_time),
                        suffixText: 'días',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        _plazoDias = int.tryParse(value);
                      },
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final plazo = int.tryParse(value);
                          if (plazo == null || plazo <= 0) {
                            return 'El plazo debe ser mayor a 0';
                          }
                        }
                        return null;
                      },
                    ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Condiciones
                    _buildWebCard(
                      title: 'Condiciones',
                      subtitle: 'Términos adicionales del acuerdo (opcional)',
                      icon: Icons.description_outlined,
                      child: TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Condiciones del contrato (opcional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                        hintText: 'Ej: Liquidación mensual, devolución permitida...',
                      ),
                      maxLines: 4,
                      onChanged: (value) {
                        _condiciones = value.isEmpty ? null : value;
                      },
                    ),
                    ),
                    const SizedBox(height: 24),

                    // Botón crear
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: (!_tienePlanAvanzado || _isSaving) ? null : _crearContrato,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          _isSaving
                              ? 'Creando...'
                              : _tienePlanAvanzado
                                  ? 'Crear Contrato'
                                  : 'Plan Avanzado Requerido',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _tienePlanAvanzado ? AppColors.primary : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                      ],
                    ),
                    ),
                    ),
                    ),
                    ),
    );
  }
  Widget _buildWebCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
    Color? iconColor,
    Widget? trailing,
  }) {
    final Color accentColor = iconColor ?? AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Container(height: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: child,
          ),
        ],
      ),
    );
  }

}
