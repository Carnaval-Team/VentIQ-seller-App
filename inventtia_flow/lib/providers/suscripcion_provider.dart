import 'package:flutter/foundation.dart';

import '../models/suscripcion.dart';
import '../services/suscripcion_service.dart';

/// Estado de la suscripción de la entidad que el admin tiene seleccionada.
///
/// Vive en la raíz de la app (no dentro de una pantalla) porque el aviso de
/// impago tiene que verse **en todo momento**: si el estado viviera en la
/// pantalla de suscripción, el aviso desaparecería al cambiar de pestaña, que es
/// justo lo que el usuario pidió evitar.
///
/// Una sola carga alimenta las tres piezas: la píldora de estado, el aviso
/// permanente y la pantalla "Mi suscripción". Cuando el admin cambia de entidad,
/// [cargar] se vuelve a llamar con el id nuevo.
class SuscripcionProvider extends ChangeNotifier {
  int? _idEntidad;
  EstadoSuscripcionEntidad? _estado;
  List<PlanSuscripcion> _planes = const <PlanSuscripcion>[];
  MiSuscripcion _miSuscripcion = const MiSuscripcion();

  bool _cargando = false;
  bool _esquemaPendiente = false;
  String? _error;

  /// Entidad de la que es este estado. `null` mientras no se ha cargado nada.
  int? get idEntidad => _idEntidad;

  EstadoSuscripcionEntidad? get estado => _estado;
  List<PlanSuscripcion> get planes => _planes;
  MiSuscripcion get miSuscripcion => _miSuscripcion;
  bool get cargando => _cargando;
  String? get error => _error;

  /// `true` si la migración 43–46 todavía no está aplicada en la base.
  ///
  /// La UI se apaga en silencio: no se muestra el aviso de impago ni el menú,
  /// porque no hay nada que cobrar todavía. Es lo que permite publicar la app
  /// antes que la base.
  bool get esquemaPendiente => _esquemaPendiente;

  /// Hay algo que mostrar (estado cargado y esquema presente).
  bool get disponible => !_esquemaPendiente && _estado != null;

  /// La entidad no tiene suscripción pagada: se pinta el aviso permanente.
  bool get mostrarAvisoImpago => _estado?.mostrarAvisoImpago ?? false;

  /// La entidad no puede operar: sus locales y servicios dejaron de mostrarse y
  /// no admiten reservas. Lo decide el servidor con `flow.entidad_activa`.
  bool get bloqueada => _estado != null && !_estado!.activa;

  /// Hay un pago reportado esperando verificación. Mientras tanto no tiene
  /// sentido ofrecer "pagar otra vez".
  bool get esperandoVerificacion => _miSuscripcion.pagoPendiente != null;

  /// Carga estado, planes e historial de la entidad indicada.
  ///
  /// Si [idEntidad] es `null` limpia todo: no hay entidad, no hay suscripción.
  /// Volver a llamar con el mismo id ya cargado no repite la red salvo que
  /// [forzar] sea `true` (recarga manual o tras reportar un pago).
  Future<void> cargar(int? idEntidad, {bool forzar = false}) async {
    if (idEntidad == null) {
      limpiar();
      return;
    }

    if (!forzar && _idEntidad == idEntidad && _estado != null) return;

    _idEntidad = idEntidad;
    _cargando = true;
    _error = null;
    notifyListeners();

    // Las tres llamadas son independientes: se lanzan juntas y se esperan
    // después, así la pantalla tarda lo que tarde la más lenta y no la suma.
    // Se guardan en variables separadas (y no en un `Future.wait`) para que cada
    // una conserve su tipo exacto.
    final futuroEstado = SuscripcionService.estado(idEntidad);
    final futuroPlanes = SuscripcionService.planes();
    final futuroPagos = SuscripcionService.miSuscripcion(idEntidad);

    final resEstado = await futuroEstado;
    final resPlanes = await futuroPlanes;
    final resPagos = await futuroPagos;

    // Si falta el esquema, cualquiera de las tres lo delata y la sección entera
    // se apaga. Mezclar "estado cargado" con "planes ausentes" daría una
    // pantalla a medias que no se puede usar.
    if (resEstado.esquemaPendiente ||
        resPlanes.esquemaPendiente ||
        resPagos.esquemaPendiente) {
      _esquemaPendiente = true;
      _estado = null;
      _planes = const <PlanSuscripcion>[];
      _miSuscripcion = const MiSuscripcion();
      _cargando = false;
      notifyListeners();
      return;
    }

    _esquemaPendiente = false;
    _estado = resEstado.data;

    // Los planes son globales: si esa llamada falla pero el estado llegó, se
    // conserva lo que ya estuviera cargado en vez de vaciar la lista.
    if (resPlanes.ok) _planes = resPlanes.data!;

    if (resPagos.ok) _miSuscripcion = resPagos.data!;

    // El primer error con texto es el que se muestra. Un fallo de planes no debe
    // tapar que el estado sí cargó.
    _error = resEstado.mensajeError ?? resPagos.mensajeError;

    _cargando = false;
    notifyListeners();
  }

  /// Recarga forzada de la entidad actual.
  Future<void> recargar() => cargar(_idEntidad, forzar: true);

  /// Crea un intent de pago para el plan indicado.
  ///
  /// Devuelve la respuesta tal cual: quien llama (la pantalla) decide si lanza
  /// Transfermóvil o muestra el error. El provider no navega ni abre nada.
  Future<RespuestaSuscripcion<IntentPagoCreado>> crearIntent(int idPlan) async {
    final id = _idEntidad;
    if (id == null) {
      return RespuestaSuscripcion.error('No hay una entidad seleccionada');
    }
    final res = await SuscripcionService.crearIntent(
      idEntidad: id,
      idPlan: idPlan,
    );
    // Un intent nuevo cambia el historial: al volver de Transfermóvil la
    // pantalla tiene que verlo.
    if (res.ok) await recargar();
    return res;
  }

  /// Reporta el pago ("Ya he pagado") y recarga para que aparezca en espera de
  /// verificación. No acredita nada: eso lo hace el superadmin.
  Future<RespuestaSuscripcion<ReportePago>> reportarPago({
    required int idIntent,
    required String codigoConfirmacion,
    String? comprobanteUrl,
  }) async {
    final res = await SuscripcionService.reportarPago(
      idIntent: idIntent,
      codigoConfirmacion: codigoConfirmacion,
      comprobanteUrl: comprobanteUrl,
    );
    if (res.ok) await recargar();
    return res;
  }

  /// Vacía el estado (cierre de sesión o cambio a un rol sin entidad).
  void limpiar() {
    _idEntidad = null;
    _estado = null;
    _planes = const <PlanSuscripcion>[];
    _miSuscripcion = const MiSuscripcion();
    _cargando = false;
    _error = null;
    // `esquemaPendiente` NO se resetea: es un hecho de la base, no del usuario.
    notifyListeners();
  }
}
