import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../config/app_theme.dart';
import '../models/campo_adicional.dart';
import '../models/config_precio.dart';
import '../models/servicio.dart';
import '../models/sala_espera.dart';
import '../models/disponibilidad_dia.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/lista_service.dart';
import '../services/promocion_service.dart';
import '../services/resena_service.dart';
import '../services/agenda_service.dart';
import '../services/catalogo_service.dart';
import '../services/tipo_actividad_service.dart';
import '../utils/esquema_pendiente.dart';
import '../utils/horario_atencion.dart';
import '../utils/precio_reserva.dart';
import '../utils/turnos_servicio.dart';
import '../widgets/boton_favorito.dart';
import '../widgets/datos_adicionales_form.dart';
import '../widgets/detalle_hero_header.dart';
import '../widgets/resenas.dart';
import 'reserva_transporte_sheet.dart';

/// Día y turno elegidos en el calendario de disponibilidad
/// ([_DisponibilidadSheet]).
///
/// Se usa el mismo registro para reservar y para anotarse en la lista de espera
/// porque el cliente elige lo mismo en los dos casos; `cantidad` solo se usa al
/// reservar (la cola anota una entrada por persona).
typedef _SeleccionTurno = ({
  DateTime fecha,
  int cantidad,
  int? idTurno,
  String? turnoNombre,
});

class LocalServicioDetailScreen extends StatefulWidget {
  final LocalServicio localServicio;

  const LocalServicioDetailScreen({super.key, required this.localServicio});

  @override
  State<LocalServicioDetailScreen> createState() =>
      _LocalServicioDetailScreenState();
}

class _LocalServicioDetailScreenState extends State<LocalServicioDetailScreen> {
  late LocalServicio _localServicio;
  bool _isLoading = true;
  bool _isActing = false;
  bool _hasDisponibilidad = false;

  /// Días con disponibilidad tal como los devuelve la RPC. Se guardan (y no
  /// solo el booleano `_hasDisponibilidad`) para poder enseñar los **turnos**
  /// del servicio con el cupo del día, que es lo que el cliente necesita ver
  /// antes de decidir.
  List<DisponibilidadDia> _dias = const [];

  /// Turnos **configurados** por el admin (`flow.recurso` + `flow.turno`), con
  /// independencia del cupo.
  ///
  /// La RPC de disponibilidad solo devuelve turnos con plazas libres, así que sin
  /// esto la ficha no podría decir nada de un servicio lleno —que es justo cuando
  /// el cliente necesita saber a qué turnos puede apuntarse.
  List<TurnoDisponible> _turnosConfig = const [];
  SalaEspera? _miLugar;
  int _ultimoOtorgado = 0;
  int _ultimoEnAnotarse = 0;
  bool _terminosExpanded = false;

  // Reseñas del servicio. Se cargan aparte del resto para que un fallo (o que la
  // migración `26_resenas.sql` no esté aplicada) no impida ver el servicio.
  ResenasDeServicio _resenas = ResenasDeServicio.vacio;
  bool _cargandoResenas = true;
  bool _resenasDisponibles = true;

  /// Promos vigentes del servicio, para el badge. Vacío si la migración
  /// `27_promociones.sql` no está aplicada.
  List<Promocion> _promociones = const [];

  /// Taxonomía (migración 47) para poder decir "Categoría › Subcategoría" en vez
  /// del código crudo. Si no está disponible, se pinta el nombre que trajo el
  /// servicio (o el código embellecido, como antes).
  Taxonomia _taxonomia = Taxonomia.vacia;

  @override
  void initState() {
    super.initState();
    _localServicio = widget.localServicio;
    _init();
  }

  /// Aviso flotante corto, con el mismo formato que el resto de la pantalla.
  void _showToast(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _init() async {
    await _ensureFullService();
    _load();
    _checkDisponibilidad();
    _cargarResenas();
    _cargarPromociones();
    _cargarTaxonomia();
  }

  /// Taxonomía para la fila "Tipo de actividad". Aislado: si la migración 47 no
  /// está aplicada (o falla la red) la ficha se pinta igual con el dato que ya
  /// trae el servicio.
  Future<void> _cargarTaxonomia() async {
    try {
      final taxonomia = await TipoActividadService.taxonomia();
      if (!mounted) return;
      setState(() => _taxonomia = taxonomia);
    } catch (e) {
      debugPrint('[flow] LocalServicioDetailScreen._cargarTaxonomia ERROR: $e');
    }
  }

  /// Promos vigentes del servicio. Aislado: si la tabla no existe todavía, el
  /// detalle se ve igual, solo que sin badge.
  Future<void> _cargarPromociones() async {
    try {
      final promos = await PromocionService.deServicio(_localServicio.id);
      if (!mounted) return;
      setState(() => _promociones = promos);
    } catch (e) {
      debugPrint('[flow] LocalServicioDetail._cargarPromociones ERROR: $e');
    }
  }

  /// Carga resumen, lista y si el usuario puede reseñar.
  ///
  /// Aislado a propósito: si `flow.resena` todavía no existe o el RPC falla, el
  /// resto de la pantalla debe seguir funcionando.
  Future<void> _cargarResenas() async {
    if (mounted) setState(() => _cargandoResenas = true);
    try {
      final data = await ResenaService.deServicio(_localServicio.id);
      if (!mounted) return;
      setState(() {
        _resenas = data;
        _cargandoResenas = false;
        _resenasDisponibles = true;
      });
    } catch (e) {
      debugPrint('[flow] LocalServicioDetailScreen._cargarResenas ERROR: $e');
      if (!mounted) return;
      setState(() {
        _cargandoResenas = false;
        // Si la tabla no existe aún, la sección no se pinta en vez de mostrar
        // un error permanente.
        _resenasDisponibles = !esErrorDeEsquemaAusente(e, tabla: 'resena');
      });
    }
  }

  Future<void> _escribirResena() async {
    final existente = _resenas.miResena;
    // Al editar manda la agenda de mi reseña; al publicar, la reserva completada
    // que el RPC marcó como reseñable.
    final idAgenda = existente?.idAgenda ?? _resenas.agendaResenable?.idAgenda;
    if (idAgenda == null) return;

    final guardado = await mostrarEscribirResena(
      context,
      idAgenda: idAgenda,
      nombreServicio: _localServicio.servicio?.nombre ?? 'Servicio',
      existente: existente,
    );
    if (guardado && mounted) {
      await _cargarResenas();
      if (mounted) _showToast('¡Gracias por tu reseña!');
    }
  }

  Future<void> _eliminarResena() async {
    final mi = _resenas.miResena;
    final uuid = AuthService.currentUserId;
    if (mi == null || uuid == null) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Eliminar tu reseña'),
        content: const Text(
          '¿Seguro que quieres borrarla? Podrás volver a escribirla mientras '
          'la reserva siga completada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    try {
      await ResenaService.eliminar(uuidUsuario: uuid, idResena: mi.id);
      await _cargarResenas();
      if (mounted) _showToast('Reseña eliminada.');
    } catch (e) {
      if (!mounted) return;
      _showToast('$e'.replaceFirst('Exception: ', ''));
    }
  }

  /// Si el servicio no vino con campos adicionales, recarga el local-servicio
  /// completo para asegurar que el cliente vea y envíe los datos configurados.
  Future<void> _ensureFullService() async {
    final servicio = _localServicio.servicio;
    if (servicio != null && servicio.camposAdicionales.isNotEmpty) return;
    try {
      final refreshed = await CatalogoService.getLocalServicio(
        _localServicio.id,
      );
      if (mounted) setState(() => _localServicio = refreshed);
    } catch (_) {
      // Si falla, seguimos con el objeto original.
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final uuid = AuthService.currentUserId ?? '';
      final results = await Future.wait([
        ListaService.getMisListas(uuid),
        ListaService.getContadoresCola(_localServicio.id),
      ]);
      final listas = results[0] as List<SalaEspera>;
      final contadores =
          results[1] as ({int ultimoOtorgado, int ultimoEnAnotarse});
      final miLugar = listas
          .where((s) => s.idLocalServicio == _localServicio.id)
          .firstOrNull;
      if (mounted) {
        setState(() {
          _miLugar = miLugar;
          _ultimoOtorgado = contadores.ultimoOtorgado;
          _ultimoEnAnotarse = contadores.ultimoEnAnotarse;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkDisponibilidad() async {
    // La configuración de turnos del servicio se pide en paralelo: cuando no hay
    // ninguna disponibilidad (el caso típico de la lista de espera), es lo único
    // que permite decir qué turnos ofrece el servicio.
    final futuroConfig = AgendaService.getTurnosConfigurados(_localServicio.id);
    try {
      final dias = await AgendaService.getDisponibilidad(_localServicio.id);

      // Check if there are available slots for future dates
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      bool hasAvailable = false;

      for (final dia in dias) {
        final selectedDay = DateTime(
          dia.fecha.year,
          dia.fecha.month,
          dia.fecha.day,
        );
        if (selectedDay.isAfter(today) && dia.disponibles > 0) {
          hasAvailable = true;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _hasDisponibilidad = hasAvailable;
          _dias = dias;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasDisponibilidad = false;
          _dias = const [];
        });
      }
    }

    // Nunca lanza: si no se puede leer, `[]`.
    final config = await futuroConfig;
    if (mounted && config.isNotEmpty) {
      setState(() => _turnosConfig = config);
    }
  }

  /// Anota al cliente en la lista de espera **eligiendo día y turno**.
  ///
  /// Antes solo se pedía una fecha con `showDatePicker`, así que la cola no
  /// sabía para qué turno se anotaba la persona; el bot de la cola sí filtra por
  /// turno (`bot_procesar_recurso_dia`), de modo que llamaba a quien hubiera
  /// elegido cualquier turno. Ahora se usa el mismo selector que la reserva
  /// (`_DisponibilidadSheet` en modo espera, donde también valen los días sin
  /// cupo, que es justo cuando uno se anota), se envía `p_id_turno` al RPC y se
  /// cotizan los datos adicionales con ese turno, igual que en `_reservarAhora`.
  Future<void> _anotarse() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;

    _SeleccionTurno? seleccion;

    setState(() => _isActing = true);
    try {
      final dias = await AgendaService.getDisponibilidad(_localServicio.id);
      if (!mounted) return;
      setState(() => _isActing = false);
      seleccion = await _mostrarSelectorDia(dias, paraEspera: true);
    } catch (_) {
      // Sin agenda (o sin red) se conserva el mínimo: elegir día y turno. Es
      // preferible anotarse sin turno (el servidor lo acepta y el bot lo trata
      // como "cualquier turno") que no poder anotarse. Se abre el mismo selector
      // con la lista de días vacía: en modo cola el calendario no necesita cupo y
      // los turnos salen de la configuración del admin, no de la agenda.
      if (!mounted) return;
      setState(() => _isActing = false);
      seleccion = await _mostrarSelectorDia(const [], paraEspera: true);
    }
    if (seleccion == null || !mounted) return;

    final datos = await _recolectarDatosReserva(idTurno: seleccion.idTurno);
    if (datos == null || !mounted) return;

    setState(() => _isActing = true);
    try {
      await ListaService.entrarSalaEspera(
        uuidUsuario: uuid,
        idLocalServicio: _localServicio.id,
        fechaRegla: seleccion.fecha,
        idTurno: seleccion.idTurno,
        datosAdicionales: datos.datosAdicionales.isEmpty
            ? null
            : datos.datosAdicionales,
        paraTercero: datos.paraTercero,
        terceroNombre: datos.tNombre,
        terceroApellidos: datos.tApellidos,
        terceroCi: datos.tCi,
        terceroTelefono: datos.tTelefono,
      );
      await _load();
      if (mounted) {
        final turno = seleccion.turnoNombre;
        _showToast(
          '✅ Anotado para el ${DateFormat('dd/MM/yyyy').format(seleccion.fecha)}'
          '${turno == null ? '' : ' · turno $turno'}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  /// Abre el selector de día + turno con la disponibilidad ya cargada.
  ///
  /// Con [paraEspera] se abre en modo lista de espera: valen también los días
  /// sin cupo y no se pregunta cantidad.
  Future<_SeleccionTurno?> _mostrarSelectorDia(
    List<DisponibilidadDia> dias, {
    bool paraEspera = false,
  }) {
    return showModalBottomSheet<_SeleccionTurno>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DisponibilidadSheet(
        localServicio: _localServicio,
        dias: dias,
        paraEspera: paraEspera,
      ),
    );
  }

  // ── Reserva directa: abre el calendario de disponibilidad ──
  Future<void> _reservarAhora() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;

    if (_localServicio.esTransporteOmnibus) {
      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => ReservaTransporteSheet(
          localServicio: _localServicio,
          uuidUsuario: uuid,
        ),
      );
      if (result != null && mounted) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pasaje reservado correctamente'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isActing = true);
    List<DisponibilidadDia> dias;
    try {
      dias = await AgendaService.getDisponibilidad(_localServicio.id);

      // Check if there are available slots for future dates
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      bool hasAvailable = false;

      for (final dia in dias) {
        final selectedDay = DateTime(
          dia.fecha.year,
          dia.fecha.month,
          dia.fecha.day,
        );
        if (selectedDay.isAfter(today) && dia.disponibles > 0) {
          hasAvailable = true;
          break;
        }
      }

      if (!hasAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay turnos disponibles para reservar'),
              backgroundColor: AppTheme.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _hasDisponibilidad = false);
        return;
      }

      setState(() => _hasDisponibilidad = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _hasDisponibilidad = false);
      return;
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
    if (!mounted) return;

    final sel = await _mostrarSelectorDia(dias);
    if (sel == null || !mounted) return;

    final datos = await _recolectarDatosReserva(
      cantidad: sel.cantidad,
      idTurno: sel.idTurno,
    );
    if (datos == null || !mounted) return;

    await _confirmarReservaDirecta(
      uuid,
      sel.fecha,
      sel.cantidad,
      datos,
      sel.idTurno,
    );
  }

  Future<void> _confirmarReservaDirecta(
    String uuid,
    DateTime fecha,
    int cantidad,
    _DatosReserva datos,
    int? idTurno,
  ) async {
    setState(() => _isActing = true);

    // Validar carné para reservas del mismo día
    final ahora = DateTime.now();
    final esHoy =
        fecha.year == ahora.year &&
        fecha.month == ahora.month &&
        fecha.day == ahora.day;
    if (esHoy) {
      String ci;
      if (datos.paraTercero) {
        ci = datos.tCi?.trim() ?? '';
      } else {
        final perfil = context.read<AuthProvider>().perfil;
        ci = (perfil?.ci ?? '').trim();
      }
      if (ci.length != 11 || int.tryParse(ci) == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Para reservar hoy el carné de identidad debe tener 11 dígitos.',
              ),
              backgroundColor: AppTheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _isActing = false);
        return;
      }
    }

    try {
      await AgendaService.reservarDirecto(
        uuidUsuario: uuid,
        idLocalServicio: _localServicio.id,
        fecha: fecha,
        cantidad: cantidad,
        datosAdicionales: datos.datosAdicionales.isEmpty
            ? null
            : datos.datosAdicionales,
        paraTercero: datos.paraTercero,
        terceroNombre: datos.tNombre,
        terceroApellidos: datos.tApellidos,
        terceroCi: datos.tCi,
        terceroTelefono: datos.tTelefono,
        moneda: datos.moneda,
        idTurno: idTurno,
      );
      await _load();
      // El cupo de los turnos que enseña la pantalla cambia con la reserva que
      // se acaba de hacer.
      _checkDisponibilidad();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Reservado ${cantidad > 1 ? '($cantidad turnos) ' : ''}para el ${DateFormat('dd/MM/yyyy').format(fecha)}',
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  /// Flujo previo común a reserva directa y cola: si el servicio permite
  /// terceros pregunta "¿para ti o para alguien más?" (y pide el perfil del
  /// tercero), y si tiene campos adicionales los recolecta. Devuelve null si
  /// el usuario cancela. Si el servicio no requiere nada, devuelve datos vacíos
  /// sin mostrar diálogo.
  Future<_DatosReserva?> _recolectarDatosReserva({
    int cantidad = 1,
    int? idTurno,
  }) async {
    final servicio = _localServicio.servicio;
    final campos = servicio?.camposAdicionales ?? const <CampoAdicional>[];
    final permiteTercero = servicio?.permiteTercero ?? false;
    final configPrecio = servicio?.configPrecio ?? ConfigPrecio();

    if (!permiteTercero && campos.isEmpty && !configPrecio.tienePrecio) {
      return const _DatosReserva(paraTercero: false, datosAdicionales: {});
    }

    return showModalBottomSheet<_DatosReserva>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DatosReservaSheet(
        campos: campos,
        permiteTercero: permiteTercero,
        configPrecio: configPrecio,
        idLocalServicio: _localServicio.id,
        idTurno: idTurno,
        cantidad: cantidad,
      ),
    );
  }

  Future<void> _cambiarFecha() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null || _miLugar == null) return;

    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final fecha = await showDatePicker(
      context: context,
      initialDate: _miLugar!.fechaRegla.isAfter(tomorrow)
          ? _miLugar!.fechaRegla
          : tomorrow,
      firstDate: tomorrow,
      lastDate: now.add(const Duration(days: 365)),
      helpText: '¿A partir de qué fecha quieres el turno?',
      confirmText: 'Confirmar',
      cancelText: 'Cancelar',
    );
    if (fecha == null || !mounted) return;

    setState(() => _isActing = true);
    try {
      await ListaService.actualizarFechaRegla(
        uuidUsuario: uuid,
        idSalaEspera: _miLugar!.id,
        fechaRegla: fecha,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '📅 Fecha actualizada al ${DateFormat('dd/MM/yyyy').format(fecha)}',
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _salir() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Salir de la lista'),
        content: const Text('¿Deseas salir de la cola de espera?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isActing = true);
    try {
      await ListaService.salirSalaEspera(
        uuidUsuario: uuid,
        idLocalServicio: _localServicio.id,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saliste de la lista'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = _localServicio.local;
    final servicio = _localServicio.servicio;
    final enLista = _miLugar != null;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildHeader(local, servicio),
                  SliverToBoxAdapter(
                    // La primera tarjeta se monta 12px sobre el hero: así la
                    // foto y el contenido se leen como una sola pieza y no como
                    // dos bloques pegados. El desplazamiento es de pintado, no
                    // de caja, así que no altera el scroll.
                    child: Transform.translate(
                      offset: const Offset(0, -12),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (enLista) _buildMiTurnoCard(),
                            if (enLista) const SizedBox(height: 14),
                            _buildPromocionesBanner(),
                            _buildContadoresCard(),
                            _buildTurnosCard(),
                            const SizedBox(height: 14),
                            _buildInfoCard(local, servicio),
                            const SizedBox(height: 14),
                            _buildResenasSection(servicio),
                            if (local?.terminosCondiciones != null &&
                                local!.terminosCondiciones!.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _buildTerminosCard(local.terminosCondiciones!),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _isLoading ? null : _buildBottomBar(),
    );
  }

  /// Banner de promociones vigentes del servicio (o de su entidad).
  ///
  /// El descuento definitivo se aplica al confirmar y se muestra en la hoja de
  /// datos, cotizado por el servidor. Aquí solo se anuncia, para que el cliente
  /// sepa antes de empezar el flujo que hay una oferta.
  Widget _buildPromocionesBanner() {
    if (_promociones.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final promo in _promociones)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.success.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      promo.etiquetaDescuento,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promo.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (promo.hasta != null)
                          Text(
                            'Vigente hasta ${_fechaPromo(promo.hasta!)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        // Los cupos solo se muestran si la promo los limita:
                        // decir "sin limite" en cada tarjeta es ruido.
                        if (promo.cuposRestantes != null)
                          Text(
                            promo.cuposRestantes == 1
                                ? 'Queda 1 cupo'
                                : 'Quedan ${promo.cuposRestantes} cupos',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _fechaPromo(DateTime d) {
    final dia = d.day.toString().padLeft(2, '0');
    final mes = d.month.toString().padLeft(2, '0');
    return '$dia/$mes/${d.year}';
  }

  /// Sección de reseñas: resumen, lista y acción de escribir/editar.
  ///
  /// No se pinta si la migración `26_resenas.sql` no está aplicada, en vez de
  /// mostrar un error permanente. Tampoco si el servicio no tiene ninguna
  /// reseña y el usuario no puede escribir: no hay nada que contar.
  Widget _buildResenasSection(Servicio? servicio) {
    if (!_resenasDisponibles) return const SizedBox.shrink();

    final resumen = _resenas.resumen;
    final mi = _resenas.miResena;
    final puedoEscribir = mi == null && _resenas.puedoResenar;

    if (!resumen.hayDatos && mi == null && !puedoEscribir) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.reviews_outlined,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Reseñas',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              if (mi != null)
                TextButton.icon(
                  onPressed: _escribirResena,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (_cargandoResenas)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            if (resumen.hayDatos) ...[
              ResumenValoraciones(resumen: resumen),
              const SizedBox(height: 14),
            ],

            // Invitación a reseñar: solo aparece si hay una reserva completada
            // propia sin reseñar, así que guardar no puede fallar.
            if (puedoEscribir) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _escribirResena,
                  icon: const Icon(Icons.star_outline_rounded, size: 18),
                  label: const Text('Escribe tu reseña'),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (mi != null) ...[
              TarjetaResena(
                resena: mi,
                onEditar: _escribirResena,
                onEliminar: _eliminarResena,
              ),
            ],

            if (_resenas.items.where((r) => !r.esMia).isEmpty &&
                resumen.hayDatos)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'De momento solo está tu reseña.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              )
            else
              for (final r in _resenas.items.where((r) => !r.esMia))
                TarjetaResena(resena: r),
          ],
        ],
      ),
    );
  }

  // ── Cabecera hero: foto del local, velo en capas y bloque de identidad ──
  //
  // El nombre vive dentro de la foto, así que el contraste no puede depender de
  // la foto: van un velo superior (iconos de la barra), un velo inferior oscuro
  // (el texto) y un tinte de marca, más sombra en el texto. Con foto blanca,
  // oscura o cargada el bloque se lee igual. Al colapsar, el bloque se
  // desvanece y aparece el título compacto de la barra.
  Widget _buildHeader(Local? local, Servicio? servicio) {
    return SliverAppBar(
      // 230 y no 300: con 300 el hero se comía media pantalla y dejaba media
      // tarjeta fuera de la vista en el primer pantallazo. El bloque de texto
      // ocupa ~160px, así que sigue habiendo foto de sobra encima.
      expandedHeight: 230,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.primaryDark,
      foregroundColor: Colors.white,
      elevation: 0,
      // Sin tinte de "scrolled under": ensuciaría la foto del hero.
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      actions: [
        // Sobre la foto: corazón con fondo translúcido. Se auto-oculta si
        // `flow.favorito` aún no existe o no hay sesión.
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: BotonFavorito(
              idLocalServicio: _localServicio.id,
              titulo: servicio?.nombre ?? 'Servicio',
              size: 36,
              sobreClaro: false,
            ),
          ),
        ),
      ],
      flexibleSpace: DetalleHeroHeader(
        local: local,
        servicio: servicio,
        nombreServicio: servicio?.nombre ?? 'Servicio',
        resenas: _resenas.resumen,
        precioTexto: etiquetaPrecioBase(servicio?.configPrecio),
        permiteDirecta: _localServicio.permiteReservaDirecta,
      ),
    );
  }

  // ── Tarjeta de estado en la cola (número, cola, fecha y turno) ──
  Widget _buildMiTurnoCard() {
    final mi = _miLugar!;
    final esTurno = mi.esSuTurno;
    final delante = mi.personasDelante - 1;
    final accent = esTurno ? AppTheme.success : AppTheme.primary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: esTurno
              ? [const Color(0xFF2E7D32), AppTheme.success]
              : [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        // Compacta a propósito: cuando ya estás en la cola esto es lo primero que
        // ves, y antes ocupaba un montón (cuadro de 76px + tres fichas que caían
        // una por línea en un móvil normal). Los mismos datos caben en una fila
        // por línea de texto, sin perder nada: número, estado, cola, fecha,
        // turno y cambiar fecha.
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        esTurno ? Icons.notifications_active : Icons.event_seat,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      // `Flexible` + elipsis: el título cede antes que desbordar
                      // la fila en un móvil estrecho (o con un número de 3 cifras).
                      Flexible(
                        child: Text(
                          esTurno ? '¡Es tu turno!' : 'Estás en la lista',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 14,
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                      const SizedBox(width: 8),
                      // El número, en línea: se lee igual y deja sitio al resto.
                      Text(
                        'N°',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${mi.numeroCola}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    esTurno
                        ? 'Acércate, ya casi te toca'
                        : (delante <= 0
                              ? 'Eres el siguiente'
                              : '$delante ${delante == 1 ? 'persona' : 'personas'} delante de ti'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 5),
                      // `Flexible` en los dos: en un móvil estrecho se recortan
                      // con elipsis en vez de desbordar la fila.
                      Flexible(
                        child: Text(
                          'Desde ${DateFormat('dd/MM/yy').format(mi.fechaRegla)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Turno elegido al anotarse. Si la entrada es anterior a
                      // que se pidiera el turno (o el servicio no trabaja por
                      // turnos) se dice explícitamente que vale cualquiera.
                      const Icon(Icons.schedule, color: Colors.white, size: 12),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          mi.turnoNombre ?? 'Cualquier turno',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Antes era una ficha de texto ("Modificar fecha"); con el icono y el
            // tooltip cabe en la misma fila y libera el ancho que necesitaban la
            // fecha y el turno.
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                onPressed: _isActing ? null : _cambiarFecha,
                tooltip: 'Modificar fecha',
                padding: EdgeInsets.zero,
                iconSize: 19,
                color: Colors.white,
                disabledColor: Colors.white38,
                icon: const Icon(Icons.edit_calendar),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Contadores de la cola ──
  Widget _buildContadoresCard() {
    final enEspera = _ultimoEnAnotarse - _ultimoOtorgado;
    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionTitle('Cola del servicio')),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (enEspera > 0 ? AppTheme.warning : AppTheme.success)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  enEspera > 0 ? 'En espera · $enEspera' : 'Sin espera',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: enEspera > 0 ? AppTheme.warning : AppTheme.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Sin `CrossAxisAlignment.stretch`: la fila vive en un scroll vertical
          // (alto sin acotar) y estirar en el eje cruzado no tiene altura de la
          // que tirar. Las dos cajas miden lo mismo solas, porque tienen la
          // misma estructura.
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'Último atendido',
                  value: '$_ultimoOtorgado',
                  icon: Icons.how_to_reg_outlined,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatItem(
                  label: 'Último anotado',
                  value: '$_ultimoEnAnotarse',
                  icon: Icons.person_add_alt_1_outlined,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Turnos del servicio ─────────────────────────────────────────────────

  /// Día cuyos turnos enseña la ficha (ver `diaDeTurnosAMostrar`).
  DisponibilidadDia? get _diaDeTurnos => diaDeTurnosAMostrar(_dias);

  /// "Hoy", "Mañana" o la fecha corta: nadie lee "12/05/2026" de un vistazo.
  String _etiquetaDiaTurnos(DateTime fecha) {
    final relativa = etiquetaRelativaDia(fecha, DateTime.now());
    if (relativa != null) return relativa;
    return DateFormat('EEE d MMM', 'es_ES').format(fecha);
  }

  /// Turnos del servicio con el cupo del día.
  ///
  /// Sin esto, en un servicio que trabaja por turnos el cliente solo descubría
  /// cuáles existen al abrir el flujo de reserva. Aquí se ven antes: nombre,
  /// recurso (solo si hay más de uno) y plazas libres.
  ///
  /// Cuando no hay ningún día con cupo (habitual cuando hay que anotarse en la
  /// lista) se enseñan los turnos **configurados**, todos como "sin cupo": es
  /// mejor decir a qué turnos se puede optar que no decir nada.
  Widget _buildTurnosCard() {
    final dia = _diaDeTurnos;
    final turnos = (dia != null && dia.turnos.isNotEmpty)
        ? dia.turnos
        : _turnosConfig;
    if (turnos.isEmpty) return const SizedBox.shrink();

    final variosRecursos = {for (final t in turnos) t.recurso}.length > 1;
    final hayCupo = turnos.any((t) => t.disponibles > 0);
    final enLista = _miLugar != null;
    final puedeReservar = _localServicio.permiteReservaDirecta;
    final etiquetaDia = dia == null ? null : _etiquetaDiaTurnos(dia.fecha);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _SectionTitle('Turnos')),
                if (etiquetaDia != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      etiquetaDia,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Sin cupo',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hayCupo && etiquetaDia != null
                  ? 'Estos son los turnos de ${etiquetaDia.toLowerCase()}. '
                        'El turno se elige al reservar.'
                  : (hayCupo
                        ? 'Los turnos con plazas libres son estos. El turno se '
                              'elige al reservar.'
                        : 'Ahora mismo no hay cupo en ningún turno. Anótate en la '
                              'lista y te avisamos.'),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < turnos.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _TurnoFila(turno: turnos[i], mostrarRecurso: variosRecursos),
            ],
            // Solo cuando hay cupo y el servicio lo permite: si no, el botón de
            // abajo ya ofrece lo que toca y repetirlo aquí sería ruido.
            if (!enLista && hayCupo && puedeReservar) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isActing ? null : _reservarAhora,
                  icon: const Icon(Icons.event_available, size: 18),
                  label: const Text('Elegir día y turno'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Texto de "Tipo de actividad", en orden de preferencia:
  /// 1. la taxonomía real (`Categoría › Subcategoría`) si está cargada;
  /// 2. el nombre legible que trajo el payload;
  /// 3. el código con `_` convertidos en espacios y la inicial en mayúscula.
  String? _etiquetaActividad(Servicio? servicio) {
    if (servicio == null) return null;
    final conTaxonomia = _taxonomia.etiquetaCompleta(servicio.idTipoActividad);
    if (conTaxonomia.isNotEmpty) return conTaxonomia;
    final nombre = servicio.tipoActividadNombre;
    if (nombre != null && nombre.isNotEmpty) return nombre;
    final codigo = servicio.tipoActividad;
    if (codigo == null || codigo.isEmpty) return null;
    return codigo
        .split('_')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  // ── Información del local y el servicio ──
  Widget _buildInfoCard(Local? local, Servicio? servicio) {
    final rows = <Widget>[];

    // "Belleza › Uñas / Manicure" con la taxonomía; si no está, el nombre que
    // trajo el payload o el código embellecido de siempre.
    final etiquetaActividad = _etiquetaActividad(servicio);
    if (etiquetaActividad != null) {
      rows.add(
        _InfoRow(
          icon: Icons.category_outlined,
          label: 'Tipo de actividad',
          value: etiquetaActividad,
        ),
      );
    }
    if (servicio?.descripcion != null && servicio!.descripcion!.isNotEmpty) {
      rows.add(
        _InfoRow(
          icon: Icons.design_services_outlined,
          label: 'Sobre el servicio',
          value: servicio.descripcion!,
        ),
      );
    }
    // Punto 10: cuando el local tiene horario estructurado (`horario_detalle`)
    // se muestra ESE texto, no el de la columna, porque el detalle es exacto
    // (días sueltos como "Lun, Mié, Vie" no se malinterpretan).
    final horario = HorarioAtencion.parseConDetalle(
      local?.horarioAtencion,
      local?.horarioDetalle,
    );
    if (local?.horarioAtencion != null && local!.horarioAtencion!.isNotEmpty) {
      rows.add(
        _InfoRow(
          icon: Icons.access_time,
          label: 'Horario de atención',
          value: horario.esDesconocido
              ? local.horarioAtencion!
              : horario.etiqueta,
        ),
      );
    }
    if (local?.direccion != null && local!.direccion!.isNotEmpty) {
      rows.add(
        _InfoRow(
          icon: Icons.location_on_outlined,
          label: 'Dirección',
          value: local.direccion!,
        ),
      );
    }
    if (local?.ubicacion.isNotEmpty == true) {
      rows.add(
        _InfoRow(
          icon: Icons.location_city_outlined,
          label: 'Ubicación',
          value: local!.ubicacion,
        ),
      );
    }
    if (servicio?.camposAdicionales.isNotEmpty == true) {
      rows.add(
        _InfoRow(
          icon: Icons.format_list_bulleted_outlined,
          label: 'Información adicional requerida',
          value: servicio!.camposAdicionales.map((c) => c.etiqueta).join(', '),
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return _Tarjeta(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Información'),
          const SizedBox(height: 12),
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const Divider(height: 24, color: AppTheme.border),
          ],
        ],
      ),
    );
  }

  // ── Términos y condiciones (expandible) ──
  Widget _buildTerminosCard(String terminos) {
    return _Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _terminosExpanded = !_terminosExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Términos y condiciones',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _terminosExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                terminos,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            crossFadeState: _terminosExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  // ── Barra de acción fija abajo ──
  Widget _buildBottomBar() {
    final enLista = _miLugar != null;
    final permiteDirecta = _localServicio.permiteReservaDirecta;

    Widget child;
    if (enLista) {
      child = _ActionButton(
        onPressed: _isActing ? null : _salir,
        isLoading: _isActing,
        icon: Icons.exit_to_app,
        label: 'Salir de la lista',
        variant: _ButtonVariant.danger,
      );
    } else if (permiteDirecta) {
      // Reserva directa habilitada: acción primaria clara + alternativa secundaria.
      List<Widget> buttons = [];

      // Solo mostrar el botón de "Reservar ahora" si hay disponibilidad
      if (_hasDisponibilidad) {
        buttons.add(
          _ActionButton(
            onPressed: _isActing ? null : _reservarAhora,
            isLoading: _isActing,
            icon: Icons.event_available,
            label: 'Reservar ahora',
            variant: _ButtonVariant.primary,
          ),
        );
        buttons.add(const SizedBox(height: 10));
      }

      // Siempre mostrar el botón de "Anotarme en la lista"
      buttons.add(
        _ActionButton(
          onPressed: _isActing ? null : _anotarse,
          isLoading: false,
          icon: Icons.playlist_add,
          label: 'Anotarme en la lista',
          variant: _ButtonVariant.secondary,
        ),
      );

      child = Column(mainAxisSize: MainAxisSize.min, children: buttons);
    } else {
      child = _ActionButton(
        onPressed: _isActing ? null : _anotarse,
        isLoading: _isActing,
        icon: Icons.playlist_add,
        label: 'Anotarme en la lista',
        variant: _ButtonVariant.primary,
      );
    }

    // AnimatedSwitcher para transiciones suaves entre estados (lista ↔ no lista).
    child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Container(
        key: ValueKey(
          'bottom-${enLista ? 'lista' : (permiteDirecta ? 'directa' : 'cola')}',
        ),
        child: child,
      ),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: child,
        ),
      ),
    );
  }
}

enum _ButtonVariant { primary, secondary, danger }

/// Botón de acción con feedback físico al presionar (scale 0.97, 120ms ease-out).
/// Los botones ocupan el ancho disponible, tienen altura táctil generosa y
/// muestran un indicador de carga sin cambiar de tamaño.
class _ActionButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData icon;
  final String label;
  final _ButtonVariant variant;

  const _ActionButton({
    required this.onPressed,
    required this.isLoading,
    required this.icon,
    required this.label,
    required this.variant,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  Color get _foregroundColor {
    switch (widget.variant) {
      case _ButtonVariant.primary:
        return Colors.white;
      case _ButtonVariant.secondary:
        return AppTheme.primary;
      case _ButtonVariant.danger:
        return AppTheme.error;
    }
  }

  Color get _backgroundColor {
    switch (widget.variant) {
      case _ButtonVariant.primary:
        return AppTheme.primary;
      case _ButtonVariant.secondary:
        return Colors.white;
      case _ButtonVariant.danger:
        return const Color(0xFFFFF5F5);
    }
  }

  Color get _borderColor {
    switch (widget.variant) {
      case _ButtonVariant.primary:
        return AppTheme.primary;
      case _ButtonVariant.secondary:
        return AppTheme.primary;
      case _ButtonVariant.danger:
        return AppTheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    Widget button = Material(
      color: _backgroundColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled && !widget.isLoading ? widget.onPressed : null,
        onTapDown: enabled && !widget.isLoading
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderColor, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(_foregroundColor),
                  ),
                )
              else
                Icon(widget.icon, size: 20, color: _foregroundColor),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Scale físico al presionar: elementos reales se comprimen ligeramente,
    // confirmando que la interfaz escuchó el toque.
    return AnimatedScale(
      scale: _pressed && enabled ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: button,
    );
  }
}

/// Tarjeta de sección del detalle.
///
/// Sustituye al `Card` del tema (radio 16 y color `surface`) que, sobre el
/// fondo `surface` de la pantalla, quedaba casi invisible: aquí es blanca, con
/// radio 22, borde suave y una sombra corta, para que cada sección se lea como
/// una pieza separada.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0B1B3A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              // 20 y no 24: la cifra es lo que se mira, pero 24 en dos cajas
              // seguidas pesaba demasiado en la ficha.
              fontSize: 20,
              height: 1,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila de turno en la ficha: nombre, recurso (si el servicio tiene varios)
/// y plazas libres del día que se está enseñando.
class _TurnoFila extends StatelessWidget {
  const _TurnoFila({required this.turno, required this.mostrarRecurso});

  final TurnoDisponible turno;
  final bool mostrarRecurso;

  @override
  Widget build(BuildContext context) {
    final hayCupo = turno.disponibles > 0;
    final color = hayCupo ? AppTheme.success : AppTheme.warning;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.confirmation_number_outlined,
              size: 17,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  turno.turno.isEmpty ? 'Turno' : turno.turno,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (mostrarRecurso && turno.recurso.isNotEmpty)
                  Text(
                    turno.recurso,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                // Punto 7: horas del turno, si el admin las puso.
                if (turno.etiquetaHora != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 12,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          turno.etiquetaHora!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              etiquetaCupoTurno(turno.disponibles),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Datos recolectados antes de reservar: tercero (si aplica) + datos adicionales.
class _DatosReserva {
  final bool paraTercero;
  final String? tNombre;
  final String? tApellidos;
  final String? tCi;
  final String? tTelefono;
  final Map<String, dynamic> datosAdicionales;
  final String? moneda;

  const _DatosReserva({
    required this.paraTercero,
    this.tNombre,
    this.tApellidos,
    this.tCi,
    this.tTelefono,
    required this.datosAdicionales,
    this.moneda,
  });
}

/// Diálogo simple para elegir la cantidad de turnos en reserva directa.
class _CantidadDialog extends StatefulWidget {
  final DateTime fecha;
  final int maximo;
  final int inicial;
  const _CantidadDialog({
    required this.fecha,
    required this.maximo,
    this.inicial = 1,
  });

  @override
  State<_CantidadDialog> createState() => _CantidadDialogState();
}

class _CantidadDialogState extends State<_CantidadDialog> {
  late int _cantidad;

  @override
  void initState() {
    super.initState();
    _cantidad = widget.inicial.clamp(1, widget.maximo);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('¿Cuántos turnos?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${DateFormat('dd/MM/yyyy').format(widget.fecha)} · ${widget.maximo} disponibles',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: _cantidad > 1
                    ? () => setState(() => _cantidad--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '$_cantidad',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _cantidad < widget.maximo
                    ? () => setState(() => _cantidad++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _cantidad),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

/// Hoja para recolectar: ¿para ti o un tercero? + perfil del tercero + datos
/// adicionales configurados por el admin.
class _DatosReservaSheet extends StatefulWidget {
  final List<CampoAdicional> campos;
  final bool permiteTercero;
  final ConfigPrecio configPrecio;
  final int cantidad;

  /// Necesarios para cotizar contra el servidor: el precio que se muestra debe
  /// salir del MISMO calculo que cobra al reservar.
  final int idLocalServicio;
  final int? idTurno;

  const _DatosReservaSheet({
    required this.campos,
    required this.permiteTercero,
    required this.configPrecio,
    required this.idLocalServicio,
    this.idTurno,
    this.cantidad = 1,
  });

  @override
  State<_DatosReservaSheet> createState() => _DatosReservaSheetState();
}

class _DatosReservaSheetState extends State<_DatosReservaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _datosKey = GlobalKey<DatosAdicionalesFormState>();
  bool _paraTercero = false;
  late String _monedaSeleccionada;
  Map<String, dynamic> _valoresActuales = {};

  /// Precio calculado por el SERVIDOR (`cotizar_reserva`), no en Dart.
  ///
  /// Antes esta hoja calculaba el precio con `PrecioReserva.calcular` (Dart) y
  /// el servidor lo recalculaba al cobrar. Eran dos implementaciones de la
  /// misma regla, y con promociones habrian descuadrado en cuanto una regla
  /// cambiara en un solo lado. Ahora hay una unica fuente.
  CotizacionReserva? _cotizacion;
  bool _cotizando = false;
  Timer? _debounceCotizacion;

  final _nombreCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _ciCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final monedas = widget.configPrecio.monedas.isEmpty
        ? ['USD']
        : widget.configPrecio.monedas;
    _monedaSeleccionada = monedas.contains(widget.configPrecio.monedaDefault)
        ? widget.configPrecio.monedaDefault
        : monedas.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _valoresActuales = _datosKey.currentState?.valores ?? {};
      });
      _cotizar();
    });
  }

  @override
  void dispose() {
    _debounceCotizacion?.cancel();
    _nombreCtrl.dispose();
    _apellidosCtrl.dispose();
    _ciCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  /// Pide el precio al servidor. Con un pequeño retardo para no lanzar una
  /// consulta por cada tecla que el cliente escribe en un campo adicional.
  void _cotizarProgramado() {
    _debounceCotizacion?.cancel();
    _debounceCotizacion = Timer(const Duration(milliseconds: 320), _cotizar);
  }

  Future<void> _cotizar() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;
    if (mounted) setState(() => _cotizando = true);
    try {
      final datos = _datosKey.currentState?.valores ?? _valoresActuales;
      final c = await PromocionService.cotizar(
        uuidUsuario: uuid,
        idLocalServicio: widget.idLocalServicio,
        datosAdicionales: datos,
        moneda: _monedaSeleccionada,
        cantidad: widget.cantidad,
        idTurno: widget.idTurno,
      );
      if (!mounted) return;
      setState(() {
        _cotizacion = c;
        _cotizando = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Si la cotizacion falla se deja la anterior y se avisa: es mejor mostrar
      // un precio algo desactualizado que inventar uno.
      setState(() => _cotizando = false);
      debugPrint('[flow] _DatosReservaSheet._cotizar ERROR: $e');
    }
  }

  void _confirmar() {
    final formOk = _formKey.currentState?.validate() ?? true;
    final datosOk = _datosKey.currentState?.validar() ?? true;
    if (!formOk || !datosOk) return;

    final valores = _datosKey.currentState?.valores ?? {};
    Navigator.pop(
      context,
      _DatosReserva(
        paraTercero: _paraTercero,
        tNombre: _paraTercero ? _nombreCtrl.text.trim() : null,
        tApellidos: _paraTercero ? _apellidosCtrl.text.trim() : null,
        tCi: _paraTercero ? _ciCtrl.text.trim() : null,
        tTelefono: _paraTercero ? _telefonoCtrl.text.trim() : null,
        datosAdicionales: valores,
        moneda: _monedaSeleccionada,
      ),
    );
  }

  /// Etiqueta del descuento: "Promo verano · -12" o "Bienvenida + Promo · -12".
  ///
  /// El importe es el descuento **total** (promoción + bienvenida). Mostrar solo
  /// el de la promoción diría menos de lo que se está rebajando.
  String _etiquetaDescuento(CotizacionReserva c) {
    final total = PrecioReserva.formatear(c.descuentoTotal, c.moneda);
    final nombres = <String>[
      if (c.descuento > 0 && (c.promoTitulo?.isNotEmpty ?? false))
        c.promoTitulo!,
      if (c.descuentoBeneficio > 0 && (c.beneficioTitulo?.isNotEmpty ?? false))
        c.beneficioTitulo!,
    ];
    return nombres.isEmpty
        ? 'Descuento aplicado: -$total'
        : '${nombres.join(' + ')} · -$total';
  }

  @override
  Widget build(BuildContext context) {
    final monedas = widget.configPrecio.monedas.isEmpty
        ? ['USD']
        : widget.configPrecio.monedas;
    final cotizacion = _cotizacion;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, size: 24),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    foregroundColor: AppTheme.textPrimary,
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Datos de la reserva',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 48), // Balance the back button
              ],
            ),
            const SizedBox(height: 16),

            // ── ¿Para ti o alguien más? ──
            if (widget.permiteTercero) ...[
              const Text(
                '¿Para quién es la reserva?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Para mí'),
                    icon: Icon(Icons.person),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Para alguien más'),
                    icon: Icon(Icons.group_add),
                  ),
                ],
                selected: {_paraTercero},
                onSelectionChanged: (s) =>
                    setState(() => _paraTercero = s.first),
              ),
              const SizedBox(height: 16),
            ],

            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_paraTercero) ...[
                    const Text(
                      'Datos de la persona',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apellidosCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Apellidos *',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ciCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Carné de identidad *',
                        prefixIcon: Icon(Icons.credit_card),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Requerido';
                        if (t.length != 11)
                          return 'El CI debe tener 11 dígitos';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono *',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    if (widget.campos.isNotEmpty) const SizedBox(height: 16),
                  ],

                  // ── Datos adicionales del servicio ──
                  if (widget.campos.isNotEmpty) ...[
                    const Text(
                      'Información adicional',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DatosAdicionalesForm(
                      key: _datosKey,
                      campos: widget.campos,
                      // Los campos adicionales pueden cambiar el precio (reglas
                      // por opcion), asi que cada cambio recotiza.
                      onChanged: (v) {
                        setState(() => _valoresActuales = v);
                        _cotizarProgramado();
                      },
                    ),
                  ],
                ],
              ),
            ),

            if (widget.configPrecio.tienePrecio) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (monedas.length > 1) ...[
                      DropdownButtonFormField<String>(
                        value: _monedaSeleccionada,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Moneda',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: monedas
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(MonedasApp.etiqueta(m)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _monedaSeleccionada = v);
                          // La moneda cambia el precio: hay que recotizar.
                          _cotizar();
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        const Icon(
                          Icons.payments_outlined,
                          color: AppTheme.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cotizacion?.tieneDescuento == true
                                    ? 'Total con descuento'
                                    : 'Total de la reserva',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    cotizacion != null && cotizacion.hayPrecio
                                        ? PrecioReserva.formatear(
                                            cotizacion.precioTotal,
                                            cotizacion.moneda,
                                          )
                                        : '—',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  // Precio de lista tachado: sale del mismo
                                  // calculo que el total, asi que el descuento
                                  // mostrado es siempre el que se cobrara.
                                  if (cotizacion?.tieneDescuento == true) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      PrecioReserva.formatear(
                                        cotizacion!.precioLista,
                                        cotizacion.moneda,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                  if (_cotizando) ...[
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (cotizacion?.tieneDescuento == true)
                                Text(
                                  _etiquetaDescuento(cotizacion!),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (widget.cantidad > 1 &&
                                  cotizacion != null &&
                                  cotizacion.hayPrecio)
                                Text(
                                  '${PrecioReserva.formatear(cotizacion.precioUnit, cotizacion.moneda)} × ${widget.cantidad}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _confirmar,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Continuar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hoja: calendario de disponibilidad para "Reservar ahora" ──
class _DisponibilidadSheet extends StatefulWidget {
  final LocalServicio localServicio;
  final List<DisponibilidadDia> dias;

  /// Modo lista de espera.
  ///
  /// En la reserva solo se pueden tocar los días **con cupo**; en la cola
  /// interesan justo los que no lo tienen, así que aquí vale cualquier día
  /// futuro con plan (o sin datos de plan, si el servicio no trabaja por días)
  /// y no se pregunta cantidad. Además, el selector de turno ofrece **todos los
  /// turnos configurados** del servicio (no solo los del día con cupo): quien se
  /// anota lo hace porque no hay hueco.
  final bool paraEspera;

  const _DisponibilidadSheet({
    required this.localServicio,
    required this.dias,
    this.paraEspera = false,
  });

  @override
  State<_DisponibilidadSheet> createState() => _DisponibilidadSheetState();
}

class _DisponibilidadSheetState extends State<_DisponibilidadSheet> {
  late final Map<String, DisponibilidadDia> _porDia;
  late DateTime _focusedDay;

  /// Turnos configurados por el admin, con independencia del cupo del día.
  ///
  /// Solo se cargan en modo cola: en la reserva directa un turno sin cupo no se
  /// puede reservar, así que ahí manda la disponibilidad. Si la consulta falla
  /// (o el servicio no trabaja por turnos) queda vacío y todo sigue igual.
  List<TurnoDisponible> _turnosConfig = const [];

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _porDia = {for (final d in widget.dias) _key(d.fecha): d};
    // Enfoca el primer día con cupo (o hoy si la lista está vacía).
    _focusedDay = widget.dias.isNotEmpty
        ? widget.dias.first.fecha
        : DateTime.now();
    if (widget.paraEspera) _cargarTurnosConfig();
  }

  Future<void> _cargarTurnosConfig() async {
    final turnos = await AgendaService.getTurnosConfigurados(
      widget.localServicio.id,
    );
    if (!mounted) return;
    setState(() => _turnosConfig = turnos);
  }

  DisponibilidadDia? _disp(DateTime day) => _porDia[_key(day)];

  Future<void> _confirmar(DateTime day) async {
    final disp = _disp(day);
    // En la reserva el día tiene que tener cupo; en la cola puede estar lleno.
    if (!widget.paraEspera && (disp == null || disp.disponibles <= 0)) return;
    final fecha = DateTime(day.year, day.month, day.day);

    // Turnos que se pueden elegir. En la cola, además de los del día (con su
    // cupo real) entran los configurados que ese día no aparecen: anotarse es
    // precisamente para cuando no hay hueco.
    final ofrecidos = widget.paraEspera
        ? combinarTurnosConConfig(disp?.turnos ?? const [], _turnosConfig)
        : (disp?.turnos ?? const <TurnoDisponible>[]);

    TurnoDisponible? turnoSel;
    int disponiblesTurno = disp?.disponibles ?? 0;
    if (ofrecidos.isNotEmpty) {
      final elegido = await showModalBottomSheet<TurnoDisponible>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _TurnoPickerSheet(
          fecha: fecha,
          turnos: ofrecidos,
          paraEspera: widget.paraEspera,
        ),
      );
      if (elegido == null || !mounted) return;
      turnoSel = elegido;
      disponiblesTurno = elegido.disponibles;
    }

    // La cola anota una sola entrada por persona: nunca pregunta cantidad.
    if (widget.paraEspera) {
      if (!mounted) return;
      Navigator.pop(context, (
        fecha: fecha,
        cantidad: 1,
        idTurno: turnoSel?.idTurno,
        turnoNombre: turnoSel?.turno,
      ));
      return;
    }

    final ls = widget.localServicio;
    final cantidadDefault = ls.cantidadDefault;
    final cantidadMax = ls.cantidadMaxCapacidad;

    // Si solo hay 1 cupo o el máximo configurado es 1, no preguntamos cantidad.
    if (disponiblesTurno <= 1 || cantidadMax <= 1) {
      if (!mounted) return;
      Navigator.pop(context, (
        fecha: fecha,
        cantidad: 1,
        idTurno: turnoSel?.idTurno,
        turnoNombre: turnoSel?.turno,
      ));
      return;
    }

    final maxCant = cantidadMax < disponiblesTurno
        ? cantidadMax
        : disponiblesTurno;
    final cantidad = await showDialog<int>(
      context: context,
      builder: (_) => _CantidadDialog(
        fecha: fecha,
        maximo: maxCant,
        inicial: cantidadDefault.clamp(1, maxCant),
      ),
    );
    if (cantidad == null || !mounted) return;
    Navigator.pop(context, (
      fecha: fecha,
      cantidad: cantidad,
      idTurno: turnoSel?.idTurno,
      turnoNombre: turnoSel?.turno,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final vacio = widget.dias.isEmpty;
    final first = widget.dias.isNotEmpty
        ? widget.dias.first.fecha
        : DateTime.now();
    final last = widget.dias.isNotEmpty
        ? widget.dias.last.fecha
        : DateTime.now().add(const Duration(days: 90));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(
                  widget.paraEspera
                      ? Icons.playlist_add_check_circle_outlined
                      : Icons.event_available,
                  size: 20,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.paraEspera
                            ? 'Anotarme en la lista'
                            : 'Reservar ahora',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        widget.localServicio.servicio?.nombre ?? 'Servicio',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (vacio && !widget.paraEspera)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 24, 40),
              child: Column(
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    size: 56,
                    color: AppTheme.textSecondary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No hay turnos disponibles',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Por ahora no quedan cupos para reservar.\nPuedes anotarte en la lista de espera.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            TableCalendar<DisponibilidadDia>(
              locale: 'es_ES',
              firstDay: DateTime.utc(first.year, first.month, 1),
              lastDay: DateTime.utc(last.year, last.month + 1, 0),
              focusedDay: _focusedDay,
              eventLoader: (day) {
                final d = _disp(day);
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final selectedDay = DateTime(day.year, day.month, day.day);

                // Don't show events for current day
                final isTomorrowOrLater = selectedDay.isAfter(today);

                if (!isTomorrowOrLater) return [];
                // En la cola se marca también el día lleno: saber que no hay
                // cupo es la razón para anotarse.
                if (widget.paraEspera) return d != null ? [d] : [];
                return d != null && d.disponibles > 0 ? [d] : [];
              },
              enabledDayPredicate: (day) {
                final d = _disp(day);
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final selectedDay = DateTime(day.year, day.month, day.day);

                // Disable current day and only allow from tomorrow onwards
                final isTomorrowOrLater = selectedDay.isAfter(today);

                if (!isTomorrowOrLater) return false;
                if (widget.paraEspera) return true;
                return d != null && d.disponibles > 0;
              },
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                disabledTextStyle: TextStyle(
                  color: Colors.grey.shade300,
                  fontSize: 14,
                ),
                defaultTextStyle: const TextStyle(fontSize: 15),
                selectedTextStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                todayTextStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
                weekendTextStyle: const TextStyle(fontSize: 15),
                holidayTextStyle: const TextStyle(fontSize: 15),
                markersMaxCount: 1,
                markerDecoration: const BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primary, width: 1.5),
                ),
                selectedDecoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                cellMargin: const EdgeInsets.all(4),
                cellPadding: const EdgeInsets.all(8),
                rowDecoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(
                      color: Colors.grey.shade200,
                      width: 0.5,
                    ),
                  ),
                ),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  final disp = events.first;
                  final sinCupo = disp.disponibles <= 0;
                  return Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        // Ámbar cuando no queda cupo: en la cola es el dato que
                        // importa, no un día "malo".
                        color: sinCupo ? AppTheme.warning : AppTheme.success,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Text(
                        '${disp.disponibles}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                headerPadding: EdgeInsets.symmetric(vertical: 12),
                titleTextStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
                leftChevronIcon: Icon(Icons.chevron_left, size: 24),
                rightChevronIcon: Icon(Icons.chevron_right, size: 24),
              ),
              availableGestures: AvailableGestures.horizontalSwipe,
              onPageChanged: (f) => setState(() => _focusedDay = f),
              onDaySelected: (selected, focused) => _confirmar(selected),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                widget.paraEspera
                    ? 'Elige el día en que quieres entrar a la cola; si el servicio trabaja por turnos, te pediremos también el turno.'
                    : 'Toca un día con cupo para reservar. El número indica los turnos libres.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Selector de turno para un día concreto (servicios con recursos). Agrupa los
/// turnos por recurso y muestra la disponibilidad de cada uno. Devuelve el
/// [TurnoDisponible] elegido.
///
/// Con [paraEspera] (lista de espera) también se pueden elegir los turnos sin
/// cupo —es el caso normal al anotarse— y el texto lo dice. La lista que llega
/// en [turnos] ya viene preparada por quien abre la hoja: en la cola incluye los
/// turnos configurados del servicio, no solo los del día.
class _TurnoPickerSheet extends StatelessWidget {
  final DateTime fecha;
  final List<TurnoDisponible> turnos;
  final bool paraEspera;

  const _TurnoPickerSheet({
    required this.fecha,
    required this.turnos,
    this.paraEspera = false,
  });

  @override
  Widget build(BuildContext context) {
    // Agrupa turnos por recurso conservando el orden de llegada.
    final porRecurso = <int, List<TurnoDisponible>>{};
    final nombreRecurso = <int, String>{};
    for (final t in turnos) {
      porRecurso.putIfAbsent(t.idRecurso, () => []).add(t);
      nombreRecurso[t.idRecurso] = t.recurso;
    }
    final hayVariosRecursos = porRecurso.length > 1;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.schedule,
                    size: 20,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        paraEspera ? 'Elige el turno' : 'Elige un turno',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE d/MM', 'es_ES').format(fecha),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (paraEspera)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'No hace falta que queden plazas: te avisamos.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                for (final idRec in porRecurso.keys) ...[
                  if (hayVariosRecursos)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_bus_outlined,
                            size: 14,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              nombreRecurso[idRec] ?? 'Recurso',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final t in porRecurso[idRec]!)
                    _TurnoOpcion(
                      turno: t,
                      paraEspera: paraEspera,
                      onTap: () => Navigator.pop(context, t),
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

/// Turno tocable dentro del selector: muestra la hora y el cupo que queda.
///
/// Sin cupo sigue siendo elegible cuando la pantalla viene de la lista de
/// espera; en una reserva no se llega aquí con 0 disponibles.
class _TurnoOpcion extends StatelessWidget {
  final TurnoDisponible turno;
  final bool paraEspera;
  final VoidCallback onTap;

  const _TurnoOpcion({
    required this.turno,
    required this.paraEspera,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sinCupo = turno.disponibles <= 0;
    final color = sinCupo ? AppTheme.warning : AppTheme.success;
    final detalle = sinCupo
        ? (paraEspera ? 'Sin cupo · te avisamos' : 'Sin cupo')
        : '${turno.disponibles} ${turno.disponibles == 1 ? 'lugar libre' : 'lugares libres'}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: sinCupo
                    ? AppTheme.warning.withValues(alpha: 0.45)
                    : AppTheme.border,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          turno.turno,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        // Punto 7: la hora del turno, si está configurada.
                        if (turno.etiquetaHora != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 13,
                                  color: AppTheme.textSecondary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  turno.etiquetaHora!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              sinCupo
                                  ? Icons.hourglass_bottom
                                  : Icons.event_seat_outlined,
                              size: 13,
                              color: color,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              detalle,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.primary.withValues(alpha: 0.8),
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
