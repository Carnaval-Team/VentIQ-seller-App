import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/disponibilidad_dia.dart';
import '../providers/auth_provider.dart';
import '../providers/reservas_provider.dart';
import '../services/agenda_service.dart';
import '../services/auth_service.dart';
import '../services/coleccion_service.dart';
import '../services/home_catalog_service.dart';
import '../services/promocion_service.dart';
import '../utils/coleccion_servicios.dart';
import '../utils/precio_reserva.dart';
import '../utils/turnos_servicio.dart';
import '../widgets/net_image.dart';
import 'local_servicio_detail_screen.dart' show DatosReserva, DatosReservaSheet;

/// Asistente de **reserva múltiple**: pone día y turno a cada servicio elegido en
/// una colección y después los reserva uno por uno.
///
/// POR QUE EXISTE
///   "Quiero hacerme todo para la cara" no es una reserva, son cinco: cada
///   servicio tiene su propio calendario, su propio turno y su propio cupo. El
///   camino viejo obligaba a abrir la ficha de cada servicio por separado,
///   reservar, volver al Home y empezar de nuevo. Aquí se elige **una vez** y se
///   resuelve cada servicio en la misma pantalla, incluido el caso de "este para
///   hoy y aquel para mañana".
///
/// REGLAS DEL SERVIDOR QUE MANDA RESPETAR
///   * Una reserva es **una llamada** por servicio: no existe ningún RPC por
///     lotes (`flow.cliente_reservar_directo` crea una sola fila de `flow.agenda`).
///     Así que esto es un bucle secuencial, y cada servicio puede fallar por su
///     cuenta (cupo agotado, lista de espera, etc.). El resultado se muestra
///     **por servicio**, nunca como un "todo o nada" que sería mentira.
///   * La reserva del mismo día exige un carné de 11 dígitos: se valida antes de
///     gastar la primera llamada, para no dejar el lote a medias por un dato.
///   * El cliente no puede repetir el **mismo** servicio, el mismo día, con el
///     mismo turno (`'Ya tienes una reserva ese dia'`). Distintos servicios el
///     mismo día sí están permitidos: es justo el caso de esta pantalla.
///
/// PRECIO
///   Cada servicio se cotiza con `flow.cotizar_reserva`, la **misma** función que
///   cobra al reservar, así que el total que se ve aquí es el que se cobra. La
///   cotización no consume cupo.
class ReservaMultipleScreen extends StatefulWidget {
  const ReservaMultipleScreen({
    super.key,
    required this.coleccion,
    required this.servicios,
  });

  final Coleccion coleccion;

  /// Servicios elegidos, en el orden curado de la colección.
  final List<HomeCatalogItem> servicios;

  @override
  State<ReservaMultipleScreen> createState() => _ReservaMultipleScreenState();
}

class _ReservaMultipleScreenState extends State<ReservaMultipleScreen> {
  final Map<int, _Eleccion> _elecciones = {};

  late List<HomeCatalogItem> _pendientes;

  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _pendientes = List<HomeCatalogItem>.of(widget.servicios);
    for (final item in widget.servicios) {
      _elecciones[item.id] = _Eleccion(item: item);
    }
    // La disponibilidad se pide en paralelo para poder decir "sin cupo" en la
    // propia tarjeta, en vez de dejar al cliente abriendo el selector para
    // descubrirlo. Es la misma lectura que hace la ficha del servicio.
    for (final item in widget.servicios) {
      _cargarDisponibilidad(_elecciones[item.id]!);
    }
  }

  // ── Datos por servicio ───────────────────────────────────────────────────

  Future<void> _cargarDisponibilidad(
    _Eleccion eleccion, {
    bool forzar = false,
  }) async {
    if (eleccion.cargandoDisponibilidad) return;
    if (!forzar && eleccion.dias.isNotEmpty) return;
    setState(() => eleccion.cargandoDisponibilidad = true);
    try {
      final dias = await AgendaService.getDisponibilidad(eleccion.item.id);
      if (!mounted) return;
      setState(() {
        eleccion.dias = diasReservables(dias);
        eleccion.cargandoDisponibilidad = false;
        eleccion.error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        eleccion.cargandoDisponibilidad = false;
        eleccion.error = 'No pudimos leer los turnos. Revisa tu conexión.';
      });
      debugPrint('[flow] ReservaMultiple._cargarDisponibilidad ERROR: $e');
    }
  }

  Future<void> _elegirTurno(_Eleccion eleccion) async {
    if (eleccion.cargandoDisponibilidad) return;
    if (eleccion.dias.isEmpty) {
      await _cargarDisponibilidad(eleccion, forzar: true);
      if (!mounted) return;
    }
    if (eleccion.dias.isEmpty) {
      _avisar(
        'No hay días con cupo para ${eleccion.item.title}. '
        'Puedes quitarlo de la reserva o intentarlo más tarde.',
      );
      return;
    }

    final elegido = await showModalBottomSheet<_TurnoElegido>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _SelectorDiaTurno(
        item: eleccion.item,
        dias: eleccion.dias,
        anterior: eleccion.fecha,
        cantidadInicial: eleccion.cantidad,
        turnoAnterior: eleccion.turno,
      ),
    );
    if (elegido == null || !mounted) return;

    setState(() {
      eleccion.dia = elegido.dia;
      eleccion.fecha = elegido.fecha;
      eleccion.turno = elegido.turno;
      eleccion.cantidad = elegido.cantidad;
      eleccion.error = null;
    });
    await _cotizar(eleccion);
  }

  Future<void> _elegirOpciones(_Eleccion eleccion) async {
    final servicio = eleccion.item.localServicio?.servicio;
    if (servicio == null) return;
    final datos = await showModalBottomSheet<DatosReserva>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DatosReservaSheet(
        campos: servicio.camposAdicionales,
        permiteTercero: servicio.permiteTercero,
        configPrecio: servicio.configPrecio,
        idLocalServicio: eleccion.item.id,
        idTurno: eleccion.turno?.idTurno,
        cantidad: eleccion.cantidad,
      ),
    );
    if (datos == null || !mounted) return;
    setState(() => eleccion.datos = datos);
    await _cotizar(eleccion);
  }

  /// Cotiza el servicio contra el servidor. No consume cupo.
  ///
  /// Sin precio configurado no se cotiza: el catálogo dice "Consultar precio" y
  /// un "0 USD" aquí sería peor que no decir nada.
  Future<void> _cotizar(_Eleccion eleccion) async {
    final uuid = AuthService.currentUserId;
    if (uuid == null || eleccion.fecha == null) return;
    if (!precioCotizable(eleccion.item)) {
      setState(() => eleccion.total = null);
      return;
    }
    setState(() => eleccion.cotizando = true);
    try {
      final c = await PromocionService.cotizar(
        uuidUsuario: uuid,
        idLocalServicio: eleccion.item.id,
        datosAdicionales: eleccion.datos?.datosAdicionales,
        moneda: eleccion.datos?.moneda,
        cantidad: eleccion.cantidad,
        idTurno: eleccion.turno?.idTurno,
      );
      if (!mounted) return;
      setState(() {
        eleccion.total = c.precioTotal;
        eleccion.monedaCotizada = c.moneda;
        eleccion.cotizando = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Sin cotización se sigue pudiendo reservar: el servidor vuelve a calcular
      // el importe al confirmar. Solo se deja de mostrar el total.
      setState(() {
        eleccion.cotizando = false;
        eleccion.total = null;
      });
      debugPrint('[flow] ReservaMultiple._cotizar ERROR: $e');
    }
  }

  void _quitar(_Eleccion eleccion) {
    setState(() {
      _pendientes = _pendientes
          .where((item) => item.id != eleccion.item.id)
          .toList();
    });
  }

  // ── Confirmación ─────────────────────────────────────────────────────────

  Future<void> _confirmar() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) {
      _avisar('Necesitas iniciar sesión para reservar.');
      return;
    }
    final pendientes = _pendientes
        .map((item) => _elecciones[item.id]!)
        .where((e) => e.listo)
        .toList();
    if (pendientes.isEmpty) return;

    final perfil = context.read<AuthProvider>().perfil;
    final ahora = DateTime.now();
    for (final eleccion in pendientes) {
      final fecha = eleccion.fecha!;
      final esHoy =
          fecha.year == ahora.year &&
          fecha.month == ahora.month &&
          fecha.day == ahora.day;
      if (!esHoy) continue;
      final ci = (eleccion.datos?.paraTercero ?? false)
          ? (eleccion.datos?.tCi ?? '').trim()
          : (perfil?.ci ?? '').trim();
      if (ci.length != 11 || int.tryParse(ci) == null) {
        _avisar(
          'Para reservar hoy el carné de identidad debe tener 11 dígitos '
          '(${eleccion.item.title}).',
        );
        return;
      }
    }

    setState(() => _enviando = true);
    final progreso = ValueNotifier<String>('Preparando las reservas…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoProgreso(progreso: progreso),
    );

    final resultados = <_ResultadoReserva>[];
    for (var i = 0; i < pendientes.length; i++) {
      final eleccion = pendientes[i];
      progreso.value =
          'Reservando ${i + 1} de ${pendientes.length}\n'
          '${eleccion.item.title}';
      final datos = eleccion.datos;
      try {
        await AgendaService.reservarDirecto(
          uuidUsuario: uuid,
          idLocalServicio: eleccion.item.id,
          fecha: eleccion.fecha!,
          cantidad: eleccion.cantidad,
          datosAdicionales: (datos == null || datos.datosAdicionales.isEmpty)
              ? null
              : datos.datosAdicionales,
          paraTercero: datos?.paraTercero ?? false,
          terceroNombre: datos?.tNombre,
          terceroApellidos: datos?.tApellidos,
          terceroCi: datos?.tCi,
          terceroTelefono: datos?.tTelefono,
          moneda: datos?.moneda,
          idTurno: eleccion.turno?.idTurno,
        );
        resultados.add(_ResultadoReserva.exito(eleccion));
      } catch (e) {
        resultados.add(
          _ResultadoReserva.fallo(eleccion, mensajeDeErrorDeReserva(e)),
        );
        debugPrint('[flow] ReservaMultiple._confirmar ERROR: $e');
      }
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    progreso.dispose();
    setState(() => _enviando = false);

    final exitosas = resultados.where((r) => r.ok).length;
    if (exitosas > 0) {
      // El badge de "Mis tickets" se actualiza solo por Realtime; esto solo
      // adelanta el número cuando la suscripción viene con retraso.
      try {
        context.read<ReservasProvider>().recargar();
      } catch (_) {}
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _ResumenReservasSheet(
        resultados: resultados,
        total: pendientes.length,
      ),
    );
    if (!mounted) return;

    final fallidas = resultados.where((r) => !r.ok).toList();
    if (fallidas.isEmpty) {
      Navigator.pop(context, true);
      return;
    }

    // Reserva parcial: la pantalla se queda solo con lo que falló, con su día y
    // su turno intactos, para que el reintento no obligue a empezar de cero.
    setState(() {
      final idsFallidos = {for (final r in fallidas) r.eleccion.item.id};
      _pendientes = _pendientes
          .where((item) => idsFallidos.contains(item.id))
          .toList();
    });
    for (final item in _pendientes) {
      _cargarDisponibilidad(_elecciones[item.id]!, forzar: true);
    }
  }

  void _avisar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }

  // ── Pintado ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final elecciones = _pendientes
        .map((item) => _elecciones[item.id]!)
        .toList();
    final listas = elecciones.where((e) => e.listo).length;
    final totales = _totalDelLote(elecciones);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Día y turno'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Volver',
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: _pendientes.isEmpty
          ? const _Aviso(
              icono: Icons.check_circle_outline_rounded,
              titulo: 'No queda nada por reservar',
              detalle: 'Quitaste todos los servicios de esta reserva.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _CabeceraProgreso(
                  coleccion: widget.coleccion,
                  listas: listas,
                  total: elecciones.length,
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < elecciones.length; i++) ...[
                  _TarjetaEleccion(
                    numero: i + 1,
                    eleccion: elecciones[i],
                    onElegirTurno: () => _elegirTurno(elecciones[i]),
                    onOpciones: requiereOpciones(elecciones[i].item)
                        ? () => _elegirOpciones(elecciones[i])
                        : null,
                    onQuitar: () => _quitar(elecciones[i]),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 2),
                const _NotaPrecio(),
              ],
            ),
      bottomNavigationBar: _pendientes.isEmpty
          ? null
          : _BarraConfirmar(
              listas: listas,
              total: elecciones.length,
              totales: totales,
              enviando: _enviando,
              onConfirmar: listas == elecciones.length && !_enviando
                  ? _confirmar
                  : null,
            ),
    );
  }

  /// Suma cotizada del lote. Se devuelve `null` hasta que **todas** las
  /// elecciones listas traigan importe: un parcial se leería como el total.
  ({double monto, String moneda})? _totalDelLote(List<_Eleccion> elecciones) {
    final listas = elecciones.where((e) => e.listo).toList();
    if (listas.isEmpty) return null;
    if (listas.any((e) => e.total == null)) return null;
    final moneda = listas.first.monedaCotizada;
    if (moneda == null) return null;
    if (listas.any((e) => e.monedaCotizada != moneda)) return null;
    var suma = 0.0;
    for (final e in listas) {
      suma += e.total!;
    }
    return (monto: suma, moneda: moneda);
  }
}

// ── Estado por servicio ────────────────────────────────────────────────────

/// Elección del cliente para **un** servicio: día, turno, plazas, opciones
/// (campos adicionales / tercero / moneda) y el precio cotizado.
class _Eleccion {
  _Eleccion({required this.item});

  final HomeCatalogItem item;

  List<DisponibilidadDia> dias = const [];
  bool cargandoDisponibilidad = false;

  DisponibilidadDia? dia;
  DateTime? fecha;
  TurnoDisponible? turno;
  int cantidad = 1;

  /// Datos de la hoja de reserva (para tercero, opciones, moneda).
  DatosReserva? datos;

  double? total;
  String? monedaCotizada;
  bool cotizando = false;

  String? error;

  /// `true` cuando el servicio ya tiene todo lo que el servidor necesita.
  ///
  /// Un día con turnos exige turno elegido; uno sin turnos (el servicio no usa
  /// recursos) se reserva con el cupo agregado del día. Si el servicio pide
  /// opciones (campos adicionales, "para alguien más" o moneda), hay que haber
  /// pasado por la hoja: sin esos valores el servidor no puede cotizar las
  /// reglas de precio.
  bool get listo {
    if (dia == null) return false;
    if (dia!.tieneTurnos && turno == null) return false;
    if (requiereOpciones(item) && datos == null) return false;
    return true;
  }
}

// ── Cabecera ───────────────────────────────────────────────────────────────

class _CabeceraProgreso extends StatelessWidget {
  const _CabeceraProgreso({
    required this.coleccion,
    required this.listas,
    required this.total,
  });

  final Coleccion coleccion;
  final int listas;
  final int total;

  @override
  Widget build(BuildContext context) {
    final completo = listas == total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D2B3A67),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  coleccion.titulo.trim().isEmpty
                      ? 'Tu reserva'
                      : coleccion.titulo.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                '$listas de $total listos',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: completo ? AppTheme.success : AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: total == 0 ? 0 : listas / total),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              builder: (_, valor, __) => LinearProgressIndicator(
                value: valor,
                minHeight: 6,
                backgroundColor: AppTheme.border.withValues(alpha: 0.7),
                valueColor: AlwaysStoppedAnimation(
                  completo ? AppTheme.success : AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cada servicio lleva su propio día y su propio turno: puedes hacerte '
            'uno hoy y otro mañana.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tarjeta de un servicio ─────────────────────────────────────────────────

class _TarjetaEleccion extends StatelessWidget {
  const _TarjetaEleccion({
    required this.numero,
    required this.eleccion,
    required this.onElegirTurno,
    required this.onQuitar,
    this.onOpciones,
  });

  final int numero;
  final _Eleccion eleccion;
  final VoidCallback onElegirTurno;
  final VoidCallback onQuitar;
  final VoidCallback? onOpciones;

  @override
  Widget build(BuildContext context) {
    final listo = eleccion.listo;
    final item = eleccion.item;
    final ahora = DateTime.now();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: listo
              ? AppTheme.success.withValues(alpha: 0.55)
              : AppTheme.border,
          width: listo ? 1.4 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D2B3A67),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: listo
                      ? AppTheme.success
                      : AppTheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: listo
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      )
                    : Text(
                        '$numero',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                        ),
                      ),
              ),
              const SizedBox(width: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: _MiniaturaItem(item: item),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.venue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onQuitar,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppTheme.textSecondary,
                tooltip: 'Quitar de la reserva',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (listo)
            _DetalleElegido(
              eleccion: eleccion,
              ahora: ahora,
              onCambiar: onElegirTurno,
              onOpciones: onOpciones,
            )
          else
            _SinElegir(
              eleccion: eleccion,
              onElegirTurno: onElegirTurno,
              onOpciones: onOpciones,
            ),
          if (eleccion.error != null) ...[
            const SizedBox(height: 8),
            _Nota(
              color: AppTheme.error,
              icono: Icons.error_outline_rounded,
              texto: eleccion.error!,
            ),
          ],
        ],
      ),
    );
  }
}

/// Estado "todavía no hay día ni turno" de una tarjeta.
class _SinElegir extends StatelessWidget {
  const _SinElegir({
    required this.eleccion,
    required this.onElegirTurno,
    this.onOpciones,
  });

  final _Eleccion eleccion;
  final VoidCallback onElegirTurno;
  final VoidCallback? onOpciones;

  @override
  Widget build(BuildContext context) {
    if (eleccion.cargandoDisponibilidad) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 9),
            // `Expanded`: la etiqueta puede ser larga y este `Row` comparte
            // línea con el resto de la tarjeta.
            Expanded(
              child: Text(
                'Buscando días con cupo…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final sinCupo = eleccion.dias.isEmpty;
    final conError = eleccion.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El aviso de "sin cupo" solo cuando la lectura fue bien: si falló, el
        // motivo real ya lo dice la nota de error y dos avisos seguidos
        // ("no hay cupo" + "no pudimos leer") se contradicen.
        if (sinCupo && !conError)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _Nota(
              color: AppTheme.warning,
              icono: Icons.hourglass_empty_rounded,
              texto:
                  'Ahora mismo no hay días con cupo para este servicio. '
                  'Puedes quitarlo y reservar el resto.',
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                // Siempre activo: si la lectura falló, este botón es la única
                // forma de reintentarla sin salir de la pantalla.
                onPressed: onElegirTurno,
                icon: Icon(
                  conError
                      ? Icons.refresh_rounded
                      : Icons.event_available_rounded,
                  size: 17,
                ),
                // Etiqueta corta a propósito: junto al chip de "Opciones" el
                // texto largo no cabe en un móvil de 320 y el `Row` desborda
                // (lo cazó `test/coleccion_widgets_test.dart`).
                label: Text(conError ? 'Reintentar' : 'Elegir turno'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (onOpciones != null) ...[
              const SizedBox(width: 8),
              _BotonOpciones(
                pendiente: true,
                compacto: true,
                onTap: onOpciones!,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Estado "ya está listo para reservar" de una tarjeta.
class _DetalleElegido extends StatelessWidget {
  const _DetalleElegido({
    required this.eleccion,
    required this.ahora,
    required this.onCambiar,
    this.onOpciones,
  });

  final _Eleccion eleccion;
  final DateTime ahora;
  final VoidCallback onCambiar;
  final VoidCallback? onOpciones;

  @override
  Widget build(BuildContext context) {
    final dia = eleccion.dia!;
    final base = precioBaseDe(
      eleccion.item.localServicio?.servicio?.configPrecio,
    );
    final datos = eleccion.datos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _Pastilla(
              icono: Icons.event_rounded,
              texto: etiquetaDiaLargo(eleccion.fecha!, ahora),
              destacada: true,
            ),
            if (eleccion.turno != null)
              _Pastilla(
                icono: Icons.schedule_rounded,
                texto: etiquetaTurno(eleccion.turno!),
                destacada: true,
              )
            else
              _Pastilla(
                icono: Icons.event_seat_outlined,
                texto: cupoDe(dia: dia) == 1
                    ? '1 lugar libre ese día'
                    : '${cupoDe(dia: dia)} lugares libres ese día',
                destacada: true,
              ),
            if (eleccion.cantidad > 1)
              _Pastilla(
                icono: Icons.groups_outlined,
                texto: '${eleccion.cantidad} plazas',
              ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            TextButton.icon(
              onPressed: onCambiar,
              icon: const Icon(Icons.edit_calendar_outlined, size: 16),
              label: const Text('Cambiar'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppTheme.primary,
              ),
            ),
            if (onOpciones != null) ...[
              const SizedBox(width: 12),
              _BotonOpciones(
                pendiente: datos == null,
                onTap: onOpciones!,
                compacto: true,
              ),
            ],
            const Spacer(),
            if (eleccion.cotizando)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (eleccion.total != null)
              Text(
                importeCorto(eleccion.total!, eleccion.monedaCotizada),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primary,
                ),
              )
            else if (base != null)
              Text(
                '≈ ${importeCorto(base.precio, base.moneda)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSecondary,
                ),
              ),
          ],
        ),
        if (datos != null && datos.paraTercero) ...[
          const SizedBox(height: 7),
          _Nota(
            color: AppTheme.primary,
            icono: Icons.person_outline_rounded,
            texto:
                'Para ${[datos.tNombre, datos.tApellidos].whereType<String>().where((t) => t.trim().isNotEmpty).join(' ')}',
          ),
        ],
      ],
    );
  }
}

/// Botón de "Opciones" (campos adicionales, tercero, moneda).
class _BotonOpciones extends StatelessWidget {
  const _BotonOpciones({
    required this.pendiente,
    required this.onTap,
    this.compacto = false,
  });

  final bool pendiente;
  final VoidCallback onTap;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final color = pendiente ? AppTheme.warning : AppTheme.success;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compacto ? 8 : 12,
          vertical: compacto ? 4 : 11,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(compacto ? 8 : 12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pendiente
                  ? Icons.tune_rounded
                  : Icons.check_circle_outline_rounded,
              size: compacto ? 14 : 17,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              pendiente ? 'Opciones' : 'Listas',
              style: TextStyle(
                fontSize: compacto ? 11.5 : 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Selector de día y turno ────────────────────────────────────────────────

typedef _TurnoElegido = ({
  DateTime fecha,
  DisponibilidadDia dia,
  TurnoDisponible? turno,
  int cantidad,
});

/// Hoja de día + turno de **un** servicio.
///
/// Se usa un riel de días en vez del calendario de la ficha: aquí el cliente ya
/// sabe que quiere reservar (los días sin cupo ni se ofrecen) y un riel permite
/// comparar "hoy / mañana / este sábado" de un vistazo, que es exactamente la
/// decisión que está tomando.
class _SelectorDiaTurno extends StatefulWidget {
  const _SelectorDiaTurno({
    required this.item,
    required this.dias,
    required this.cantidadInicial,
    this.anterior,
    this.turnoAnterior,
  });

  final HomeCatalogItem item;
  final List<DisponibilidadDia> dias;
  final int cantidadInicial;
  final DateTime? anterior;
  final TurnoDisponible? turnoAnterior;

  @override
  State<_SelectorDiaTurno> createState() => _SelectorDiaTurnoState();
}

class _SelectorDiaTurnoState extends State<_SelectorDiaTurno> {
  DisponibilidadDia? _dia;
  TurnoDisponible? _turno;
  int _cantidad = 1;

  @override
  void initState() {
    super.initState();
    final anterior = widget.anterior;
    _dia = anterior == null
        ? widget.dias.first
        : widget.dias.firstWhere(
            (d) =>
                d.fecha.year == anterior.year &&
                d.fecha.month == anterior.month &&
                d.fecha.day == anterior.day,
            orElse: () => widget.dias.first,
          );
    final turnoAnterior = widget.turnoAnterior;
    if (turnoAnterior != null && _dia!.tieneTurnos) {
      for (final t in _dia!.turnos) {
        if (t.idTurno == turnoAnterior.idTurno) {
          _turno = t;
          break;
        }
      }
    }
    _cantidad = widget.cantidadInicial < 1 ? 1 : widget.cantidadInicial;
    _ajustarCantidad();
  }

  int get _maxCantidad =>
      maxCantidadReservable(item: widget.item, dia: _dia!, turno: _turno);

  void _ajustarCantidad() {
    if (_cantidad > _maxCantidad) _cantidad = _maxCantidad;
    if (_cantidad < 1) _cantidad = 1;
  }

  bool get _puedeConfirmar =>
      _dia != null && (!_dia!.tieneTurnos || _turno != null);

  void _elegirDia(DisponibilidadDia dia) {
    setState(() {
      _dia = dia;
      _turno = null;
      _ajustarCantidad();
    });
  }

  void _confirmar() {
    if (!_puedeConfirmar) return;
    Navigator.pop(context, (
      fecha: _dia!.fecha,
      dia: _dia!,
      turno: _turno,
      cantidad: _cantidad,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dia = _dia!;
    final ahora = DateTime.now();

    return SafeArea(
      child: Padding(
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
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.event_available_rounded,
                      size: 20,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          widget.item.venue,
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
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _EtiquetaSeccion(texto: 'ELIGE EL DÍA'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 74,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.dias.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final d = widget.dias[index];
                          return _ChipDia(
                            dia: d,
                            ahora: ahora,
                            seleccionado: _mismoDia(d.fecha, dia.fecha),
                            onTap: () => _elegirDia(d),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (dia.tieneTurnos) ...[
                      const _EtiquetaSeccion(texto: 'ELIGE EL TURNO'),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final ancho = (constraints.maxWidth - 10) / 2;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final t in dia.turnos)
                                SizedBox(
                                  width: ancho,
                                  child: _ChipTurno(
                                    turno: t,
                                    seleccionado:
                                        _turno?.idTurno == t.idTurno &&
                                        _turno?.idRecurso == t.idRecurso,
                                    onTap: t.disponibles <= 0
                                        ? null
                                        : () => setState(() {
                                            _turno = t;
                                            _ajustarCantidad();
                                          }),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ] else ...[
                      const _EtiquetaSeccion(texto: 'CUPO DEL DÍA'),
                      const SizedBox(height: 8),
                      _Nota(
                        color: AppTheme.success,
                        icono: Icons.event_seat_outlined,
                        texto: cupoDe(dia: dia) == 1
                            ? 'Queda 1 lugar libre ese día.'
                            : 'Quedan ${cupoDe(dia: dia)} lugares libres ese día.',
                      ),
                    ],
                    if (_maxCantidad > 1) ...[
                      const SizedBox(height: 18),
                      const _EtiquetaSeccion(texto: 'PLAZAS'),
                      const SizedBox(height: 8),
                      _ContadorCantidad(
                        valor: _cantidad,
                        maximo: _maxCantidad,
                        onChange: (v) => setState(() => _cantidad = v),
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _puedeConfirmar ? _confirmar : null,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _EtiquetaSeccion extends StatelessWidget {
  const _EtiquetaSeccion({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _ChipDia extends StatelessWidget {
  const _ChipDia({
    required this.dia,
    required this.ahora,
    required this.seleccionado,
    required this.onTap,
  });

  final DisponibilidadDia dia;
  final DateTime ahora;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorTexto = seleccionado ? Colors.white : AppTheme.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 66,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: seleccionado ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: seleccionado ? AppTheme.primary : AppTheme.border,
            ),
            boxShadow: seleccionado
                ? const [
                    BoxShadow(
                      color: Color(0x33405F90),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                etiquetaDiaCorto(dia.fecha, ahora),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: seleccionado
                      ? Colors.white.withValues(alpha: 0.9)
                      : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${dia.fecha.day}',
                style: TextStyle(
                  fontSize: 19,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: colorTexto,
                ),
              ),
              Text(
                cupoDe(dia: dia) == 1
                    ? '1 libre'
                    : '${cupoDe(dia: dia)} libres',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: seleccionado
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppTheme.success,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipTurno extends StatelessWidget {
  const _ChipTurno({
    required this.turno,
    required this.seleccionado,
    this.onTap,
  });

  final TurnoDisponible turno;
  final bool seleccionado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    final colorBorde = seleccionado ? AppTheme.primary : AppTheme.border;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: seleccionado
                ? AppTheme.primary.withValues(alpha: 0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: seleccionado ? AppTheme.primary : colorBorde,
              width: seleccionado ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      turno.turno.trim().isEmpty ? 'Turno' : turno.turno.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: habilitado
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  if (seleccionado)
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: AppTheme.primary,
                    ),
                ],
              ),
              if (turno.etiquetaHora != null) ...[
                const SizedBox(height: 2),
                Text(
                  turno.etiquetaHora!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                etiquetaCupoTurno(turno.disponibles),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: habilitado ? AppTheme.success : AppTheme.warning,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContadorCantidad extends StatelessWidget {
  const _ContadorCantidad({
    required this.valor,
    required this.maximo,
    required this.onChange,
  });

  final int valor;
  final int maximo;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _BotonContador(
          icono: Icons.remove_rounded,
          onTap: valor > 1 ? () => onChange(valor - 1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$valor',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        _BotonContador(
          icono: Icons.add_rounded,
          onTap: valor < maximo ? () => onChange(valor + 1) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            maximo == 1
                ? 'Máximo 1 plaza'
                : 'Máximo $maximo plazas en este turno',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _BotonContador extends StatelessWidget {
  const _BotonContador({required this.icono, this.onTap});

  final IconData icono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final activo = onTap != null;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: activo ? AppTheme.primary : AppTheme.border,
            ),
          ),
          child: Icon(
            icono,
            size: 18,
            color: activo ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Progreso y resultado ───────────────────────────────────────────────────

/// Diálogo bloqueante con el avance del lote.
class _DialogoProgreso extends StatelessWidget {
  const _DialogoProgreso({required this.progreso});

  final ValueNotifier<String> progreso;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: ValueListenableBuilder<String>(
          valueListenable: progreso,
          builder: (_, texto, __) => Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(fontSize: 13.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un servicio reservado, o el motivo por el que no se pudo.
class _ResultadoReserva {
  const _ResultadoReserva._({
    required this.eleccion,
    required this.ok,
    this.mensaje,
  });

  factory _ResultadoReserva.exito(_Eleccion eleccion) =>
      _ResultadoReserva._(eleccion: eleccion, ok: true);

  factory _ResultadoReserva.fallo(_Eleccion eleccion, String mensaje) =>
      _ResultadoReserva._(eleccion: eleccion, ok: false, mensaje: mensaje);

  final _Eleccion eleccion;
  final bool ok;
  final String? mensaje;
}

/// Resumen por servicio. Nunca dice "todo listo" si algo falló: el detalle de
/// qué sí y qué no es justo lo que el cliente necesita para reaccionar.
class _ResumenReservasSheet extends StatelessWidget {
  const _ResumenReservasSheet({required this.resultados, required this.total});

  final List<_ResultadoReserva> resultados;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ok = resultados.where((r) => r.ok).length;
    final todoBien = ok == total;
    final nada = ok == 0;
    final ahora = DateTime.now();

    final (color, icono, titulo, detalle) = todoBien
        ? (
            AppTheme.success,
            Icons.check_circle_rounded,
            total == 1 ? 'Reserva creada' : 'Tus $total reservas están creadas',
            'Las encuentras en "Mis tickets", con su día y su turno.',
          )
        : nada
        ? (
            AppTheme.error,
            Icons.error_rounded,
            'No se pudo crear ninguna reserva',
            'Ningún servicio quedó reservado. Revisa el motivo y vuelve a intentarlo.',
          )
        : (
            AppTheme.warning,
            Icons.error_outline_rounded,
            '$ok de $total reservas creadas',
            'Los servicios de abajo no se pudieron reservar. Puedes reintentar solo esos.',
          );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icono, size: 24, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detalle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: resultados.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final r = resultados[index];
                  final e = r.eleccion;
                  return Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: r.ok
                            ? AppTheme.success.withValues(alpha: 0.35)
                            : AppTheme.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          r.ok
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 18,
                          color: r.ok ? AppTheme.success : AppTheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  e.item.venue,
                                  if (e.fecha != null)
                                    etiquetaDiaLargo(e.fecha!, ahora),
                                  if (e.turno != null) etiquetaTurno(e.turno!),
                                ].join(' · '),
                                maxLines: 2,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                  height: 1.3,
                                ),
                              ),
                              if (!r.ok && r.mensaje != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  r.mensaje!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.error,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(todoBien ? 'Listo' : 'Revisar y reintentar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Piezas menores ─────────────────────────────────────────────────────────

class _BarraConfirmar extends StatelessWidget {
  const _BarraConfirmar({
    required this.listas,
    required this.total,
    required this.totales,
    required this.enviando,
    this.onConfirmar,
  });

  final int listas;
  final int total;
  final ({double monto, String moneda})? totales;
  final bool enviando;
  final VoidCallback? onConfirmar;

  @override
  Widget build(BuildContext context) {
    final faltan = total - listas;
    return DecoratedBox(
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      faltan == 0
                          ? 'Todo listo para reservar'
                          : faltan == 1
                          ? 'Falta 1 servicio por elegir'
                          : 'Faltan $faltan servicios por elegir',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: faltan == 0
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  if (totales != null)
                    Text(
                      importeCorto(totales!.monto, totales!.moneda),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onConfirmar,
                  icon: enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.event_available_rounded, size: 18),
                  label: Text(
                    total == 1
                        ? 'Confirmar reserva'
                        : 'Confirmar $total reservas',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({
    required this.icono,
    required this.texto,
    this.destacada = false,
  });

  final IconData icono;
  final String texto;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    final color = destacada ? AppTheme.primary : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota({required this.color, required this.icono, required this.texto});

  final Color color;
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotaPrecio extends StatelessWidget {
  const _NotaPrecio();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'El importe lo calcula el sistema con las mismas reglas que aplica al '
        'cobrar, servicio por servicio.',
        style: TextStyle(
          fontSize: 11,
          color: AppTheme.textSecondary,
          height: 1.35,
        ),
      ),
    );
  }
}

class _MiniaturaItem extends StatelessWidget {
  const _MiniaturaItem({required this.item});

  final HomeCatalogItem item;

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primary.withValues(alpha: 0.18),
              AppTheme.accent.withValues(alpha: 0.22),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.miscellaneous_services_outlined,
            color: AppTheme.primary.withValues(alpha: 0.5),
            size: 20,
          ),
        ),
      );
    }
    return NetImage(
      url: url,
      fit: BoxFit.cover,
      errorWidget: () => const ColoredBox(color: AppTheme.border),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icono,
              size: 40,
              color: AppTheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 5),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Limpia el prefijo de `Exception` que Dart mete en `toString()` para que el
/// mensaje del servidor se lea tal cual.
String mensajeDeErrorDeReserva(Object error) {
  var texto = error.toString().trim();
  const prefijo = 'Exception: ';
  if (texto.startsWith(prefijo)) texto = texto.substring(prefijo.length);
  if (texto.isEmpty) return 'No se pudo crear la reserva.';
  return texto;
}
