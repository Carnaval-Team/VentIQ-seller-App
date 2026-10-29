/// Pantalla nueva del admin: **resumen de reservas** de su entidad desde hoy
/// hasta el último mes que tenga reservas (punto 3 del plan, §4).
///
/// Dos modos sobre los mismos datos:
///
/// - **calendario**: `TableCalendar<DiaResumen>` con `firstDay`/`lastDay`
///   calculados del rango que devuelve el servidor (nunca un rango fijo), un
///   marcador por día con color semántico y los items del día seleccionado
///   debajo.
/// - **lista**: `ListView.builder` agrupado por día, con cabeceras «Hoy»,
///   «Mañana» o «vie 30 oct» y filas compactas tipo to-do.
///
/// Carga en dos tiempos (§4.2): primero los contadores del rango completo
/// (`incluirItems: false`, payload mínimo para los marcadores) y, al tocar un
/// día, solo los items de ese día. El modo lista necesita los items de todos
/// los días y los pide una sola vez la primera vez que se abre.
library;

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../models/resumen_reservas.dart';
import '../../services/calendario_service.dart';
import '../../utils/estado_pago.dart';
import '../../utils/vista_reservas.dart';

/// Azul de «completadas» del marcador y de la leyenda.
///
/// El tema no expone un azul neutro: `AppTheme.primary` está reservado para el
/// día de hoy y el seleccionado, y `accent` es cian. La semántica de los cuatro
/// colores del calendario vive aquí, junto a la leyenda que la explica.
const Color _azulCompletadas = Color(0xFF1E88E5);

/// Color del marcador de un día, por prioridad:
///
/// 1. **ámbar** si hay pagos sin verificar (es lo que pide acción);
/// 2. **rojo** si *todas* las reservas del día están canceladas;
/// 3. **azul** si todas se completaron;
/// 4. **verde** en cualquier otro caso (el día tiene reservas vivas).
Color _colorDia(DiaResumen dia) {
  if (dia.hayPagosPendientes) return AppTheme.warning;
  if (dia.soloCanceladas) return AppTheme.error;
  if (dia.todoCompletado) return _azulCompletadas;
  return AppTheme.success;
}

/// Color de la barra lateral de una fila según su estado.
Color _colorEstado(ReservaResumen reserva) {
  if (reserva.esCancelada) return AppTheme.error;
  if (reserva.esCompletada) return _azulCompletadas;
  if (reserva.esReservada) return AppTheme.success;
  return AppTheme.textSecondary;
}

/// Rango navegable del calendario a partir del rango que devolvió el servidor.
///
/// El cálculo es el de [rangoReservas] (puro y testeado). Solo cuando el
/// servidor recortó por el tope de seguridad (24 meses) el `lastDay` se ajusta
/// a lo que realmente se cargó: el calendario no puede prometer un mes del que
/// no tiene ni los contadores.
({DateTime firstDay, DateTime lastDay}) _rangoDe(ResumenReservas res) {
  final calculado = rangoReservas(
    hoy: res.rango.hoy,
    ultimoDiaConReserva: res.rango.ultimoDiaConReserva,
  );
  if (res.rango.truncado &&
      res.rango.hasta.isAfter(calculado.firstDay) &&
      res.rango.hasta.isBefore(calculado.lastDay)) {
    return (firstDay: calculado.firstDay, lastDay: res.rango.hasta);
  }
  return calculado;
}

/// Día (medianoche local) de un `DateTime`.
DateTime _soloDia(DateTime f) => DateTime(f.year, f.month, f.day);

/// Diferencia en días entre dos fechas, inmune a los cambios de hora.
int _diasEntre(DateTime a, DateTime b) => DateTime.utc(
  a.year,
  a.month,
  a.day,
).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

/// «Hoy», «Mañana» o «vie 30 oct» (con [hoy] inyectado del servidor).
String _etiquetaDia(DateTime dia, DateTime hoy) {
  final diferencia = _diasEntre(dia, hoy);
  if (diferencia == 0) return 'Hoy';
  if (diferencia == 1) return 'Mañana';
  return DateFormat('EEE d MMM', 'es_ES').format(dia);
}

/// Fecha larga para la cabecera del día seleccionado: «lunes 27 de octubre».
String _fechaLarga(DateTime dia) =>
    DateFormat("EEEE d 'de' MMMM", 'es_ES').format(dia);

/// Fecha corta con año: «27 oct 2026».
String _fechaCorta(DateTime dia) => DateFormat('d MMM y', 'es_ES').format(dia);

/// Hora de la reserva tal como está en la base (`timestamp` sin zona).
String _hora(DateTime? fecha) =>
    fecha == null ? '--:--' : DateFormat('HH:mm').format(fecha);

/// Monto sin decimales cuando es entero (`18`), con dos cuando no (`18.50`).
String _monto(double valor) => valor == valor.roundToDouble()
    ? valor.toStringAsFixed(0)
    : valor.toStringAsFixed(2);

/// Quita el `Exception: ` que añade `toString` para mostrar el mensaje limpio.
String _mensajeError(Object error) {
  final texto = error.toString();
  const prefijo = 'Exception: ';
  return texto.startsWith(prefijo) ? texto.substring(prefijo.length) : texto;
}

/// Texto del chip de pago a partir de `agenda.pago_estado`.
///
/// El vocabulario vive en `utils/estado_pago.dart` para que la tarjeta del
/// cliente, esta pantalla y la bandeja digan exactamente lo mismo.
String? _etiquetaPago(String? estado) => EstadoPago.etiqueta(estado);

Color _colorPago(String? estado) => EstadoPago.color(estado);

/// Resumen de reservas del admin para una entidad.
class ResumenReservasScreen extends StatefulWidget {
  final Entidad entidad;

  const ResumenReservasScreen({super.key, required this.entidad});

  @override
  State<ResumenReservasScreen> createState() => _ResumenReservasScreenState();
}

class _ResumenReservasScreenState extends State<ResumenReservasScreen> {
  /// `initializeDateFormatting` carga las tablas de todos los locales; se llama
  /// una sola vez por proceso (la app no lo hace en `main`, y `DateFormat` con
  /// `es_ES` revienta sin ellas).
  static bool _intlListo = false;

  ResumenReservas? _resumen;
  bool _cargando = true;
  String? _error;

  VistaReservas _vista = vistaReservasPorDefecto();
  DateTime _focusedDay = DateTime.now();
  DateTime? _diaSeleccionado;
  List<ReservaResumen> _itemsDelDia = const <ReservaResumen>[];
  bool _cargandoDia = false;
  String? _errorDia;

  /// Items ya traídos, por clave de día.
  final Map<String, List<ReservaResumen>> _itemsPorClave =
      <String, List<ReservaResumen>>{};

  /// `true` cuando [_itemsPorClave] cubre **todo** el rango (modo lista).
  bool _itemsCompletos = false;
  bool _cargandoLista = false;
  String? _errorLista;

  /// Día de hoy según el servidor (La Habana), no el del dispositivo.
  DateTime _hoy = _soloDia(DateTime.now());

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // ── Carga ──────────────────────────────────────────────────────────────────

  /// Carga (a): rango + contadores, sin items.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      await _asegurarIntl();
      // Sin `desde`/`hasta`: el servidor arranca hoy y termina en el último día
      // del último mes con reservas (o en el mes en curso si no hay ninguna).
      final res = await CalendarioService.calcular(
        idEntidad: widget.entidad.id,
        incluirItems: false,
      );
      if (!mounted) return;

      final rango = _rangoDe(res);
      setState(() {
        _resumen = res;
        _hoy = res.rango.hoy;
        _focusedDay =
            res.rango.hoy.isBefore(rango.firstDay) ||
                res.rango.hoy.isAfter(rango.lastDay)
            ? rango.firstDay
            : res.rango.hoy;
        _diaSeleccionado = null;
        _itemsDelDia = const <ReservaResumen>[];
        _errorDia = null;
        _itemsPorClave.clear();
        _itemsCompletos = false;
        _errorLista = null;
      });
      // Si se refresca estando en modo lista, hay que volver a traer los items
      // de todo el rango: los contadores solos no pintan las filas.
      if (_vista == VistaReservas.lista) {
        _asegurarItemsDeTodoElRango();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _mensajeError(e));
      // Con datos previos no se tira la pantalla: se mantiene lo cargado y se
      // avisa de que el refresco falló.
      if (_resumen != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar: ${_mensajeError(e)}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Carga (b): items de un día concreto.
  Future<void> _seleccionarDia(DateTime dia) async {
    final clave = claveDia(dia);
    final enCache = _itemsPorClave.containsKey(clave);

    setState(() {
      _diaSeleccionado = _soloDia(dia);
      _errorDia = null;
      _itemsDelDia = _itemsPorClave[clave] ?? const <ReservaResumen>[];
      _cargandoDia = !enCache;
    });

    if (enCache) return;

    try {
      final res = await CalendarioService.calcular(
        idEntidad: widget.entidad.id,
        desde: dia,
        hasta: dia,
        incluirItems: true,
      );
      if (!mounted) return;
      // Si el admin ya tocó otro día, este resultado se guarda en caché pero no
      // se pinta encima del día nuevo.
      final items = res.dias.isEmpty
          ? const <ReservaResumen>[]
          : res.dias.first.items;
      final sigueSeleccionado =
          _diaSeleccionado != null && claveDia(_diaSeleccionado!) == clave;
      setState(() {
        _itemsPorClave[clave] = items;
        if (sigueSeleccionado) {
          _itemsDelDia = items;
          _cargandoDia = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      // Si mientras cargaba se tocó otro día, el error no es de ese día.
      final sigueSeleccionado =
          _diaSeleccionado != null && claveDia(_diaSeleccionado!) == clave;
      setState(() {
        if (sigueSeleccionado) {
          _cargandoDia = false;
          _errorDia = _mensajeError(e);
        }
      });
    }
  }

  /// Carga (c): items de todo el rango, solo para el modo lista.
  Future<void> _asegurarItemsDeTodoElRango() async {
    if (_itemsCompletos || _cargandoLista) return;
    final resumen = _resumen;
    if (resumen == null) return;

    setState(() {
      _cargandoLista = true;
      _errorLista = null;
    });

    try {
      final res = await CalendarioService.calcular(
        idEntidad: widget.entidad.id,
        desde: resumen.rango.desde,
        hasta: resumen.rango.hasta,
        incluirItems: true,
      );
      if (!mounted) return;

      final porDia = agruparPorClaveDia<DiaResumen>(res.dias, (d) => d.fecha);
      setState(() {
        _itemsPorClave.clear();
        porDia.forEach((clave, dias) {
          _itemsPorClave[clave] = dias.first.items;
        });
        _itemsCompletos = true;
        _cargandoLista = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoLista = false;
        _errorLista = _mensajeError(e);
      });
    }
  }

  static Future<void> _asegurarIntl() async {
    if (_intlListo) return;
    await initializeDateFormatting('es_ES');
    _intlListo = true;
  }

  // ── Derivados ──────────────────────────────────────────────────────────────

  /// Contadores por clave de día (índice de los marcadores).
  Map<String, DiaResumen> get _porDia => <String, DiaResumen>{
    for (final entrada in agruparPorClaveDia<DiaResumen>(
      _resumen?.dias ?? const <DiaResumen>[],
      (d) => d.fecha,
    ).entries)
      entrada.key: entrada.value.first,
  };

  /// Días con reservas, en orden, para el modo lista.
  List<DiaResumen> get _diasConReservas =>
      _resumen?.diasConReservas ?? const <DiaResumen>[];

  /// Aplana días y reservas en la secuencia que consume el `ListView.builder`.
  List<_EntradaLista> get _entradasLista {
    final entradas = <_EntradaLista>[];
    for (final dia in _diasConReservas) {
      entradas.add(_EntradaDia(dia));
      final items = _itemsPorClave[claveDia(dia.fecha)];
      if (items == null) {
        entradas.add(_EntradaSinDetalle(dia));
        continue;
      }
      if (items.isEmpty) {
        entradas.add(_EntradaSinDetalle(dia));
        continue;
      }
      for (final reserva in items) {
        entradas.add(_EntradaReserva(reserva));
      }
    }
    return entradas;
  }

  // ── Acciones ───────────────────────────────────────────────────────────────

  void _cambiarVista() {
    final nueva = _vista == VistaReservas.calendario
        ? VistaReservas.lista
        : VistaReservas.calendario;
    setState(() => _vista = nueva);
    if (nueva == VistaReservas.lista) {
      _asegurarItemsDeTodoElRango();
    }
  }

  void _avisoDiaDeshabilitado() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('El resumen empieza hoy: no hay datos anteriores.'),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen de reservas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.entidad.denominacion,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          if (_resumen != null)
            IconButton(
              tooltip: _vista == VistaReservas.calendario
                  ? 'Ver como lista'
                  : 'Ver como calendario',
              icon: Icon(
                _vista == VistaReservas.calendario
                    ? Icons.view_list_outlined
                    : Icons.calendar_month_outlined,
              ),
              onPressed: _cambiarVista,
            ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando && _resumen == null) return const _EsqueletoResumen();

    final error = _error;
    if (error != null && _resumen == null) {
      return _EstadoError(mensaje: error, onReintentar: _cargar);
    }

    final res = _resumen;
    if (res == null) {
      return _EstadoError(mensaje: 'Sin datos.', onReintentar: _cargar);
    }

    return _vista == VistaReservas.calendario
        ? _cuerpoCalendario(res)
        : _cuerpoLista();
  }

  // ── Modo calendario ────────────────────────────────────────────────────────

  Widget _cuerpoCalendario(ResumenReservas res) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _TarjetaResumen(resumen: res)),
        SliverToBoxAdapter(child: _calendario(res)),
        if (!res.estaVacio) SliverToBoxAdapter(child: _leyenda()),
        const SliverToBoxAdapter(child: Divider(height: 1)),
        SliverToBoxAdapter(child: _cabeceraDiaSeleccionado()),
        ..._sliversDelDia(res),
      ],
    );
  }

  Widget _calendario(ResumenReservas res) {
    final rango = _rangoDe(res);
    final porDia = _porDia;
    final focused =
        _focusedDay.isBefore(rango.firstDay) ||
            _focusedDay.isAfter(rango.lastDay)
        ? res.rango.hoy
        : _focusedDay;

    return TableCalendar<DiaResumen>(
      locale: 'es_ES',
      firstDay: rango.firstDay,
      lastDay: rango.lastDay,
      focusedDay: focused,
      startingDayOfWeek: StartingDayOfWeek.monday,
      daysOfWeekHeight: 22,
      rowHeight: 40,
      availableGestures: AvailableGestures.horizontalSwipe,
      selectedDayPredicate: (day) =>
          _diaSeleccionado != null && isSameDay(_diaSeleccionado, day),
      // El resumen empieza hoy: los días anteriores del mes en curso se ven
      // apagados y no se pueden tocar.
      enabledDayPredicate: (day) => !_soloDia(day).isBefore(res.rango.hoy),
      eventLoader: (day) {
        final dia = porDia[claveDia(day)];
        return dia == null || !dia.tieneReservas
            ? const <DiaResumen>[]
            : <DiaResumen>[dia];
      },
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        markersMaxCount: 1,
        markerSize: 6,
        markerMargin: const EdgeInsets.only(top: 1),
        markerDecoration: const BoxDecoration(
          color: AppTheme.accent,
          shape: BoxShape.circle,
        ),
        todayDecoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        selectedDecoration: const BoxDecoration(
          color: AppTheme.primary,
          shape: BoxShape.circle,
        ),
      ),
      calendarBuilders: CalendarBuilders<DiaResumen>(
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;
          return Positioned(
            bottom: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _colorDia(events.first),
                shape: BoxShape.circle,
              ),
            ),
          );
        },
      ),
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        headerPadding: EdgeInsets.symmetric(vertical: 6),
      ),
      onDaySelected: (selected, focusedDay) {
        setState(() => _focusedDay = focusedDay);
        _seleccionarDia(selected);
      },
      onDisabledDayTapped: (_) => _avisoDiaDeshabilitado(),
      onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
    );
  }

  Widget _leyenda() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 6,
        children: <Widget>[
          _PuntoLeyenda(color: AppTheme.success, label: 'Reservadas'),
          _PuntoLeyenda(color: AppTheme.warning, label: 'Pagos pendientes'),
          _PuntoLeyenda(color: AppTheme.error, label: 'Solo canceladas'),
          _PuntoLeyenda(color: _azulCompletadas, label: 'Completadas'),
        ],
      ),
    );
  }

  Widget _cabeceraDiaSeleccionado() {
    final dia = _diaSeleccionado;
    if (dia == null) return const SizedBox.shrink();

    final conteo = _porDia[claveDia(dia)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _etiquetaDia(dia, _hoy),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  _fechaLarga(dia),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (conteo != null && conteo.tieneReservas)
            _ContadoresDia(dia: conteo),
        ],
      ),
    );
  }

  List<Widget> _sliversDelDia(ResumenReservas res) {
    if (_diaSeleccionado == null) {
      return <Widget>[
        SliverToBoxAdapter(
          child: _Aviso(
            icono: Icons.touch_app_outlined,
            texto: res.estaVacio
                ? 'No hay reservas de ${widget.entidad.denominacion} desde hoy. '
                      'Cuando se registren aparecerán aquí y en el calendario.'
                : 'Toca un día del calendario para ver sus reservas.',
          ),
        ),
      ];
    }

    if (_cargandoDia) {
      return const <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }

    final error = _errorDia;
    if (error != null) {
      return <Widget>[
        SliverToBoxAdapter(
          child: _ErrorDia(mensaje: error, onReintentar: _reintentarDia),
        ),
      ];
    }

    if (_itemsDelDia.isEmpty) {
      return <Widget>[
        SliverToBoxAdapter(
          child: _Aviso(
            icono: Icons.event_available_outlined,
            texto: 'Sin reservas el ${_fechaLarga(_diaSeleccionado!)}.',
          ),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _FilaReserva(reserva: _itemsDelDia[index]),
            childCount: _itemsDelDia.length,
          ),
        ),
      ),
    ];
  }

  void _reintentarDia() {
    final dia = _diaSeleccionado;
    if (dia == null) return;
    _itemsPorClave.remove(claveDia(dia));
    _seleccionarDia(dia);
  }

  // ── Modo lista ─────────────────────────────────────────────────────────────

  Widget _cuerpoLista() {
    if (_cargandoLista) return const _EsqueletoResumen();

    final error = _errorLista;
    if (error != null) {
      return _EstadoError(
        mensaje: error,
        onReintentar: _asegurarItemsDeTodoElRango,
      );
    }

    final entradas = _entradasLista;
    if (entradas.isEmpty) {
      return _EstadoVacio(entidad: widget.entidad.denominacion);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: entradas.length,
      itemBuilder: (context, index) {
        final entrada = entradas[index];
        return switch (entrada) {
          _EntradaDia(:final dia) => _CabeceraDia(dia: dia, hoy: _hoy),
          _EntradaReserva(:final reserva) => _FilaReserva(reserva: reserva),
          _EntradaSinDetalle(:final dia) => _Aviso(
            icono: Icons.info_outline,
            texto: 'Sin detalle disponible para el ${_fechaCorta(dia.fecha)}.',
            compacto: true,
          ),
        };
      },
    );
  }
}

// ── Entradas del modo lista ──────────────────────────────────────────────────

/// Elemento de la secuencia aplanada del modo lista.
sealed class _EntradaLista {
  const _EntradaLista();
}

class _EntradaDia extends _EntradaLista {
  final DiaResumen dia;
  const _EntradaDia(this.dia);
}

class _EntradaReserva extends _EntradaLista {
  final ReservaResumen reserva;
  const _EntradaReserva(this.reserva);
}

/// Un día con reservas del que no se pudo leer ningún item.
class _EntradaSinDetalle extends _EntradaLista {
  final DiaResumen dia;
  const _EntradaSinDetalle(this.dia);
}

// ── Tarjeta de resumen ───────────────────────────────────────────────────────

class _TarjetaResumen extends StatelessWidget {
  final ResumenReservas resumen;

  const _TarjetaResumen({required this.resumen});

  @override
  Widget build(BuildContext context) {
    final r = resumen.rango;
    final t = resumen.resumen;
    final top = t.topServicios(3);
    final desde = _diasEntre(r.desde, r.hoy) == 0
        ? 'Desde hoy, ${_fechaCorta(r.desde)}'
        : 'Del ${_fechaCorta(r.desde)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.sombraTarjeta,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                'Resumen del rango',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (r.truncado)
                const Text(
                  'Tope: 24 meses',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$desde · hasta el ${_fechaCorta(r.hasta)}',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _MiniTotal(
                etiqueta: 'Total',
                valor: t.total,
                color: AppTheme.textPrimary,
              ),
              _MiniTotal(
                etiqueta: 'Reservadas',
                valor: t.reservadas,
                color: AppTheme.success,
              ),
              _MiniTotal(
                etiqueta: 'Canceladas',
                valor: t.canceladas,
                color: AppTheme.error,
              ),
              _MiniTotal(
                etiqueta: 'Completadas',
                valor: t.completadas,
                color: _azulCompletadas,
              ),
            ],
          ),
          if (top.isNotEmpty) ...<Widget>[
            const Divider(height: 22),
            const Text(
              'Top servicios',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final servicio in top)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${servicio.servicio} · ${servicio.total}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniTotal extends StatelessWidget {
  final String etiqueta;
  final int valor;
  final Color color;

  const _MiniTotal({
    required this.etiqueta,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$valor',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            etiqueta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PuntoLeyenda extends StatelessWidget {
  final Color color;
  final String label;

  const _PuntoLeyenda({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _ContadoresDia extends StatelessWidget {
  final DiaResumen dia;

  const _ContadoresDia({required this.dia});

  @override
  Widget build(BuildContext context) {
    final partes = <String>[
      dia.total == 1 ? '1 reserva' : '${dia.total} reservas',
      if (dia.personas > 0)
        dia.personas == 1 ? '1 persona' : '${dia.personas} personas',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          partes.join(' · '),
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        if (dia.hayPagosPendientes)
          Text(
            dia.pagosPendientes == 1
                ? '1 pago pendiente'
                : '${dia.pagosPendientes} pagos pendientes',
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

// ── Filas y cabeceras ────────────────────────────────────────────────────────

class _CabeceraDia extends StatelessWidget {
  final DiaResumen dia;
  final DateTime hoy;

  const _CabeceraDia({required this.dia, required this.hoy});

  @override
  Widget build(BuildContext context) {
    final etiqueta = _etiquetaDia(dia.fecha, hoy);
    final esRelativo = etiqueta == 'Hoy' || etiqueta == 'Mañana';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: <Widget>[
          Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
          if (esRelativo) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              _fechaCorta(dia.fecha),
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const Spacer(),
          Text(
            dia.total == 1 ? '1 reserva' : '${dia.total} reservas',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Fila compacta tipo to-do de una reserva.
class _FilaReserva extends StatelessWidget {
  final ReservaResumen reserva;

  const _FilaReserva({required this.reserva});

  @override
  Widget build(BuildContext context) {
    final r = reserva;
    final color = _colorEstado(r);
    final subtitulo = <String>[
      if (r.local != null) r.local!,
      if (r.turno != null) r.turno!,
    ].join(' · ');
    final motivo = r.motivoCancelacion;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 3,
              height: 42,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _hora(r.fechaHoraReserva),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (r.personas > 1)
                    Text(
                      '×${r.personas}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    r.servicio ?? 'Servicio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: r.esCancelada
                          ? AppTheme.textSecondary
                          : AppTheme.textPrimary,
                      decoration: r.esCancelada
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  if (subtitulo.isNotEmpty)
                    Text(
                      subtitulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  if (r.cliente != null)
                    Text(
                      r.cliente!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  if (r.esCancelada && motivo != null)
                    Text(
                      'Motivo: $motivo',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _Chip(texto: r.estado.isEmpty ? '—' : r.estado, color: color),
                if (_etiquetaPago(r.pagoEstado) != null) ...<Widget>[
                  const SizedBox(height: 4),
                  _Chip(
                    texto: _etiquetaPago(r.pagoEstado)!,
                    color: _colorPago(r.pagoEstado),
                  ),
                ],
                if (r.precioTotal != null && r.precioTotal! > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '${_monto(r.precioTotal!)} ${r.moneda ?? ''}'.trim(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String texto;
  final Color color;

  const _Chip({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Estados ──────────────────────────────────────────────────────────────────

class _Aviso extends StatelessWidget {
  final IconData icono;
  final String texto;
  final bool compacto;

  const _Aviso({
    required this.icono,
    required this.texto,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        compacto ? 4 : 20,
        16,
        compacto ? 4 : 20,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icono, size: compacto ? 14 : 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: compacto ? 11 : 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoError extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;

  const _EstadoError({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar el resumen',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onReintentar(),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorDia extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;

  const _ErrorDia({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: <Widget>[
          Text(
            'No se pudieron cargar las reservas del día.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final String entidad;

  const _EstadoVacio({required this.entidad});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.event_available_outlined,
              size: 44,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Sin reservas',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No hay reservas de $entidad desde hoy. Cuando se registren '
              'aparecerán aquí, agrupadas por día.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto de carga: la forma de la tarjeta de resumen y de las filas.
class _EsqueletoResumen extends StatelessWidget {
  const _EsqueletoResumen();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const <Widget>[
        _BloqueEsqueleto(alto: 132),
        SizedBox(height: 12),
        _BloqueEsqueleto(alto: 260),
        SizedBox(height: 12),
        _BloqueEsqueleto(alto: 56),
        SizedBox(height: 8),
        _BloqueEsqueleto(alto: 56),
      ],
    );
  }
}

class _BloqueEsqueleto extends StatelessWidget {
  final double alto;

  const _BloqueEsqueleto({required this.alto});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: alto,
      decoration: BoxDecoration(
        color: AppTheme.border.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
