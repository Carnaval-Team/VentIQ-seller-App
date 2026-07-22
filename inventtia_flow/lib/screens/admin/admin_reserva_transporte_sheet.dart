import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_theme.dart';
import '../../models/config_precio.dart';
import '../../models/servicio.dart';
import '../../models/transporte.dart';
import '../../services/agenda_admin_service.dart';
import '../../services/transporte_service.dart';
import '../../utils/precio_reserva.dart';
import '../../widgets/datos_adicionales_form.dart';

class AdminReservaTransporteSheet extends StatefulWidget {
  final LocalServicio localServicio;
  final DateTime diaInicial;
  final VoidCallback onCreated;

  const AdminReservaTransporteSheet({
    super.key,
    required this.localServicio,
    required this.diaInicial,
    required this.onCreated,
  });

  @override
  State<AdminReservaTransporteSheet> createState() =>
      _AdminReservaTransporteSheetState();
}

class _AdminReservaTransporteSheetState
    extends State<AdminReservaTransporteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _ciCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();

  String _tipoViaje = 'ida';
  DateTime? _fechaIda;
  DateTime? _fechaVuelta;
  TransporteTurnoDisponible? _turnoIda;
  TransporteTurnoDisponible? _turnoVuelta;
  List<TransporteTurnoDisponible> _turnosIda = const [];
  List<TransporteTurnoDisponible> _turnosVuelta = const [];
  int _cantidad = 1;
  bool _loadingIda = false;
  bool _loadingVuelta = false;
  bool _saving = false;
  final _datosKey = GlobalKey<DatosAdicionalesFormState>();
  Map<String, dynamic> _datosAdicionales = {};

  bool get _requiereIda => _tipoViaje != 'vuelta';

  bool get _requiereVuelta => _tipoViaje != 'ida';

  ConfigPrecio get _configPrecio =>
      widget.localServicio.servicio?.configPrecio ?? ConfigPrecio();

  bool get _mismaFecha {
    final ida = _fechaIda;
    final vuelta = _fechaVuelta;
    if (ida == null || vuelta == null) return false;
    return ida.year == vuelta.year &&
        ida.month == vuelta.month &&
        ida.day == vuelta.day;
  }

  bool get _usarPrecioCombinado =>
      _tipoViaje == 'ida_vuelta' &&
      (_mismaFecha || _configPrecio.aplicaPrecioIdaVueltaTodos);

  bool get _usarTurnoCombinadoCapacidad =>
      _tipoViaje == 'ida_vuelta' && _mismaFecha;

  ResultadoPrecioReserva get _precio {
    final cant = _cantidad < 1 ? 1 : _cantidad;
    final moneda = _monedaPrecio;

    if (_tipoViaje == 'ida') {
      final unitario = _unitarioTurnoOBase(_turnoIda, 'ida', moneda);
      return ResultadoPrecioReserva(
        total: unitario * cant,
        unitario: unitario,
        moneda: moneda,
        origen: _origenPrecio(_turnoIda),
      );
    }
    if (_tipoViaje == 'vuelta') {
      final unitario = _unitarioTurnoOBase(_turnoVuelta, 'vuelta', moneda);
      return ResultadoPrecioReserva(
        total: unitario * cant,
        unitario: unitario,
        moneda: moneda,
        origen: _origenPrecio(_turnoVuelta),
      );
    }

    if (_usarPrecioCombinado) {
      final paquete = _turnoPrecioPaquete;
      final unitario = _unitarioTurnoOBase(paquete, 'ida_vuelta', moneda);
      return ResultadoPrecioReserva(
        total: unitario * cant,
        unitario: unitario,
        moneda: moneda,
        origen: _origenPrecio(paquete),
      );
    }

    final unitarioIda = _unitarioTurnoOBase(_turnoIda, 'ida', moneda);
    final unitarioVuelta = _unitarioTurnoOBase(_turnoVuelta, 'vuelta', moneda);
    final unitario = unitarioIda + unitarioVuelta;
    return ResultadoPrecioReserva(
      total: unitario * cant,
      unitario: unitario,
      moneda: moneda,
      origen: 'turno',
    );
  }

  TransporteTurnoDisponible? get _turnoPrecioPaquete {
    if (_turnoIda != null &&
        _turnoVuelta != null &&
        _turnoIda!.idTurno == _turnoVuelta!.idTurno &&
        _turnoIda!.esPaquete) {
      return _turnoIda;
    }
    for (final t in [..._turnosIda, ..._turnosVuelta]) {
      if (t.esPaquete && t.precios.isNotEmpty) return t;
    }
    for (final t in [..._turnosIda, ..._turnosVuelta]) {
      if (t.esPaquete) return t;
    }
    return _turnoIda ?? _turnoVuelta;
  }

  String get _monedaPrecio {
    final config = _configPrecio;
    final monedas = config.monedas.isEmpty ? ['USD'] : config.monedas;
    var mon = config.monedaDefault;
    if (!monedas.contains(mon)) mon = monedas.first;
    return mon;
  }

  String _origenPrecio(TransporteTurnoDisponible? turno) =>
      turno != null && turno.precios.isNotEmpty ? 'turno' : 'base';

  double _unitarioTurnoOBase(
    TransporteTurnoDisponible? turno,
    String tipoViaje,
    String moneda,
  ) {
    final config = _configPrecio;
    final base = PrecioReserva.calcular(
      config: config,
      datosAdicionales: {..._datosAdicionales, 'tipo_viaje': tipoViaje},
      cantidad: 1,
      moneda: moneda,
    );
    if (turno == null || turno.precios.isEmpty) return base.unitario;
    return turno.precios[moneda] ??
        turno.precios[config.monedaDefault] ??
        turno.precios.values.first;
  }

  DateTime get _diaInicialNormalizado => DateTime(
        widget.diaInicial.year,
        widget.diaInicial.month,
        widget.diaInicial.day,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFechaInicial());
  }

  @override
  void dispose() {
    _ciCtrl.dispose();
    _nombreCtrl.dispose();
    _apellidosCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillFechaInicial() async {
    if (_requiereIda && _fechaIda == null) {
      await _cargarTrayecto('ida', _diaInicialNormalizado);
    } else if (_requiereVuelta && _fechaVuelta == null) {
      await _cargarTrayecto('vuelta', _diaInicialNormalizado);
    }
  }

  List<TransporteTurnoDisponible> _candidatosCapacidad(
    List<TransporteTurnoDisponible> turnos, {
    required bool preferirCombinado,
    bool permitirCombinado = true,
  }) {
    final conCupo = turnos
        .where((item) => item.disponibles >= _cantidad)
        .toList();
    if (conCupo.isEmpty) return const [];

    if (preferirCombinado) {
      final combinados = conCupo.where((t) => t.esPaquete).toList();
      if (combinados.isNotEmpty) return combinados;
    }

    final solos = conCupo.where((t) => !t.esPaquete).toList();
    if (solos.isNotEmpty) return solos;
    if (!permitirCombinado) return const [];
    return conCupo;
  }

  TransporteTurnoDisponible? _mejorCandidato(
    List<TransporteTurnoDisponible> candidatos, {
    TransporteTurnoDisponible? preferido,
  }) {
    if (candidatos.isEmpty) return null;

    if (preferido != null) {
      final mismoTurno = candidatos.where(
        (item) => item.idTurno == preferido.idTurno,
      );
      if (mismoTurno.isNotEmpty) return mismoTurno.first;
      final mismoRecurso = candidatos.where(
        (item) => item.idRecurso == preferido.idRecurso,
      );
      if (mismoRecurso.isNotEmpty) return mismoRecurso.first;
    }

    candidatos.sort((a, b) {
      final porPaquete = (a.esPaquete ? 1 : 0).compareTo(b.esPaquete ? 1 : 0);
      if (porPaquete != 0) return porPaquete;
      final porPlazas = b.disponibles.compareTo(a.disponibles);
      if (porPlazas != 0) return porPlazas;
      return a.turno.compareTo(b.turno);
    });
    return candidatos.first;
  }

  TransporteTurnoDisponible? _elegirTurno(
    List<TransporteTurnoDisponible> turnos, {
    TransporteTurnoDisponible? preferido,
  }) {
    final soloSimple = _tipoViaje == 'ida' || _tipoViaje == 'vuelta';
    return _mejorCandidato(
      _candidatosCapacidad(
        turnos,
        preferirCombinado: !soloSimple && _usarTurnoCombinadoCapacidad,
        permitirCombinado: !soloSimple && _usarTurnoCombinadoCapacidad,
      ),
      preferido: preferido,
    );
  }

  void _reasignarTurnosSiAmbos() {
    if (_tipoViaje != 'ida_vuelta' ||
        _fechaIda == null ||
        _fechaVuelta == null ||
        _turnosIda.isEmpty ||
        _turnosVuelta.isEmpty) {
      return;
    }

    if (_usarTurnoCombinadoCapacidad) {
      final idaComb = _candidatosCapacidad(
        _turnosIda,
        preferirCombinado: true,
      );
      final vueltaComb = _candidatosCapacidad(
        _turnosVuelta,
        preferirCombinado: true,
      );
      final idsVuelta = vueltaComb.map((t) => t.idTurno).toSet();
      final comunes = idaComb.where((t) => idsVuelta.contains(t.idTurno));
      final elegido = _mejorCandidato(comunes.toList()) ??
          _mejorCandidato(idaComb) ??
          _mejorCandidato(
            _candidatosCapacidad(
              _turnosIda,
              preferirCombinado: false,
              permitirCombinado: false,
            ),
          );
      final vuelta = elegido == null
          ? null
          : _mejorCandidato(
                  vueltaComb
                      .where((t) => t.idTurno == elegido.idTurno)
                      .toList(),
                ) ??
                _mejorCandidato(
                  _candidatosCapacidad(
                    _turnosVuelta,
                    preferirCombinado: false,
                    permitirCombinado: false,
                  ),
                  preferido: elegido,
                );
      _turnoIda = elegido;
      _turnoVuelta = vuelta;
      return;
    }

    _turnoIda = _mejorCandidato(
      _candidatosCapacidad(
        _turnosIda,
        preferirCombinado: false,
        permitirCombinado: false,
      ),
      preferido: _turnoVuelta,
    );
    _turnoVuelta = _mejorCandidato(
      _candidatosCapacidad(
        _turnosVuelta,
        preferirCombinado: false,
        permitirCombinado: false,
      ),
      preferido: _turnoIda,
    );
  }

  Future<void> _seleccionarFecha(String trayecto) async {
    try {
      final fechas = await TransporteService.getFechasDisponibles(
        idLocalServicio: widget.localServicio.id,
        tipoTrayecto: trayecto,
      );
      if (!mounted) return;
      if (fechas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay fechas disponibles para este trayecto'),
          ),
        );
        return;
      }
      final actual = trayecto == 'ida' ? _fechaIda : _fechaVuelta;
      bool disponible(DateTime dia) => fechas.any(
        (fecha) =>
            fecha.year == dia.year &&
            fecha.month == dia.month &&
            fecha.day == dia.day,
      );
      final primeraFecha = fechas.reduce((a, b) => a.isBefore(b) ? a : b);
      final ultimaFecha = fechas.reduce((a, b) => a.isAfter(b) ? a : b);
      final initialDate = actual != null && disponible(actual)
          ? actual
          : primeraFecha;
      final fecha = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: primeraFecha,
        lastDate: ultimaFecha,
        selectableDayPredicate: disponible,
        helpText: trayecto == 'ida' ? 'Fecha de ida' : 'Fecha de vuelta',
      );
      if (fecha == null || !mounted) return;
      await _cargarTrayecto(trayecto, fecha);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _cargarTrayecto(String trayecto, DateTime fecha) async {
    setState(() {
      if (trayecto == 'ida') {
        _loadingIda = true;
        _fechaIda = fecha;
        _turnoIda = null;
        _turnosIda = const [];
      } else {
        _loadingVuelta = true;
        _fechaVuelta = fecha;
        _turnoVuelta = null;
        _turnosVuelta = const [];
      }
    });
    try {
      final disponibilidad = await TransporteService.getDisponibilidad(
        idLocalServicio: widget.localServicio.id,
        fecha: fecha,
        tipoTrayecto: trayecto,
      );
      if (!mounted) return;
      setState(() {
        if (trayecto == 'ida') {
          _turnosIda = disponibilidad.turnos;
          _turnoIda = _elegirTurno(
            _turnosIda,
            preferido: _turnoVuelta,
          );
        } else {
          _turnosVuelta = disponibilidad.turnos;
          _turnoVuelta = _elegirTurno(
            _turnosVuelta,
            preferido: _turnoIda,
          );
        }
        _reasignarTurnosSiAmbos();
      });
      final elegido = trayecto == 'ida' ? _turnoIda : _turnoVuelta;
      if (elegido == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No hay plazas suficientes para $_cantidad pasajero${_cantidad == 1 ? '' : 's'} en esa fecha',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (trayecto == 'ida') {
            _loadingIda = false;
          } else {
            _loadingVuelta = false;
          }
        });
      }
    }
  }

  Future<void> _actualizarCantidad(int value) async {
    setState(() => _cantidad = value);
    if (_fechaIda != null && _requiereIda) {
      await _cargarTrayecto('ida', _fechaIda!);
    }
    if (_fechaVuelta != null && _requiereVuelta) {
      await _cargarTrayecto('vuelta', _fechaVuelta!);
    }
  }

  Future<void> _onTipoViajeChanged(String tipo) async {
    setState(() {
      _tipoViaje = tipo;
      if (!_requiereIda) {
        _fechaIda = null;
        _turnoIda = null;
        _turnosIda = const [];
      }
      if (!_requiereVuelta) {
        _fechaVuelta = null;
        _turnoVuelta = null;
        _turnosVuelta = const [];
      }
      _reasignarTurnosSiAmbos();
    });
    if (_requiereIda && _fechaIda == null) {
      await _cargarTrayecto('ida', _diaInicialNormalizado);
    } else if (_requiereVuelta && _fechaVuelta == null) {
      await _cargarTrayecto('vuelta', _diaInicialNormalizado);
    }
  }

  Future<void> _reservar() async {
    if (!_formKey.currentState!.validate()) return;

    if ((_requiereIda && (_fechaIda == null || _turnoIda == null)) ||
        (_requiereVuelta && (_fechaVuelta == null || _turnoVuelta == null))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la fecha de cada trayecto'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    if (_datosKey.currentState != null && !_datosKey.currentState!.validar()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final datosAdicionales = <String, dynamic>{
        'ci': _ciCtrl.text.trim(),
        'nombre': _nombreCtrl.text.trim(),
        'apellidos': _apellidosCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'notas': _notasCtrl.text.trim(),
        'tipo_viaje': _tipoViaje,
        ..._datosAdicionales,
      };

      await AgendaAdminService.reservarPasajeOmnibus(
        idLocalServicio: widget.localServicio.id,
        tipoViaje: _tipoViaje,
        fechaIda: _fechaIda,
        idTurnoIda: _turnoIda?.idTurno,
        fechaVuelta: _fechaVuelta,
        idTurnoVuelta: _turnoVuelta?.idTurno,
        cantidad: _cantidad,
        datosAdicionales: datosAdicionales,
        moneda: _precio.moneda,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reserva creada exitosamente'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
      widget.onCreated();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Reservar pasaje',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.localServicio.servicio?.nombre ?? '',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Día seleccionado: ${DateFormat('d MMMM yyyy', 'es_ES').format(widget.diaInicial)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ida', label: Text('Ida')),
                    ButtonSegment(value: 'vuelta', label: Text('Vuelta')),
                    ButtonSegment(
                      value: 'ida_vuelta',
                      label: Text('Ida y vuelta'),
                    ),
                  ],
                  selected: {_tipoViaje},
                  onSelectionChanged: (value) =>
                      _onTipoViajeChanged(value.first),
                ),
                const SizedBox(height: 20),
                if (_requiereIda)
                  _FechaTrayectoCard(
                    titulo: 'Ida',
                    fecha: _fechaIda,
                    loading: _loadingIda,
                    turno: _turnoIda,
                    onFecha: () => _seleccionarFecha('ida'),
                  ),
                if (_requiereIda && _requiereVuelta) const SizedBox(height: 16),
                if (_requiereVuelta)
                  _FechaTrayectoCard(
                    titulo: 'Vuelta',
                    fecha: _fechaVuelta,
                    loading: _loadingVuelta,
                    turno: _turnoVuelta,
                    onFecha: () => _seleccionarFecha('vuelta'),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Pasajeros',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _cantidad > 1
                          ? () => _actualizarCantidad(_cantidad - 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$_cantidad'),
                    IconButton(
                      onPressed: () => _actualizarCantidad(_cantidad + 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Datos del pasajero',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _ciCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CI *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value?.trim().isEmpty == true ? 'Ingresa el CI' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.trim().isEmpty == true
                      ? 'Ingresa el nombre'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apellidosCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Apellidos *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.trim().isEmpty == true
                      ? 'Ingresa los apellidos'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefonoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notasCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                if (widget.localServicio.servicio?.camposAdicionales.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Información adicional',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DatosAdicionalesForm(
                    key: _datosKey,
                    campos: widget.localServicio.servicio!.camposAdicionales,
                    onChanged: (value) =>
                        setState(() => _datosAdicionales = value),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.payments_outlined,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Total estimado')),
                      Text(
                        PrecioReserva.formatear(_precio.total, _precio.moneda),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _reservar,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.confirmation_number_outlined),
                  label: Text(_saving ? 'Reservando...' : 'Confirmar pasaje'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FechaTrayectoCard extends StatelessWidget {
  final String titulo;
  final DateTime? fecha;
  final bool loading;
  final TransporteTurnoDisponible? turno;
  final VoidCallback onFecha;

  const _FechaTrayectoCard({
    required this.titulo,
    required this.fecha,
    required this.loading,
    required this.turno,
    required this.onFecha,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: loading ? null : onFecha,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            fecha == null
                ? 'Seleccionar fecha de ${titulo.toLowerCase()}'
                : DateFormat('dd/MM/yyyy').format(fecha!),
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (fecha != null && !loading && turno != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${turno!.recurso} · ${turno!.disponibles} plazas',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
      ],
    );
  }
}
