import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/suscripcion_admin_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/planes_ui.dart';
import '../widgets/suscripcion_ui.dart';

/// Planes de suscripción de Inventtia Flow.
///
/// Un plan es duración + precio **y ahora también** un paquete de límites
/// (entidades, locales, servicios, usuarios), una modalidad (`pago` o
/// `contacto`) y una visibilidad (público o privado de una entidad). Los planes
/// de modalidad `contacto` no se cobran en la app: se negocian por WhatsApp, así
/// que su tarjeta muestra "Contactar con ventas" en vez del bloque de precio.
///
/// Se pueden desactivar en vez de borrar, y el borrado real está protegido en el
/// servidor (si alguien compró el plan, la historia queda y el plan se
/// desactiva).
///
/// Los planes nacen **desactivados** en la base: hasta que el superadmin ponga
/// el precio real no deben poder comprarse. Por eso uno de los avisos de esta
/// pantalla es cuántos planes activos hay (sin contar los de contacto, que nacen
/// con precio 0 a propósito).
class FlowPlanesScreen extends StatefulWidget {
  const FlowPlanesScreen({super.key});

  @override
  State<FlowPlanesScreen> createState() => _FlowPlanesScreenState();
}

class _FlowPlanesScreenState extends State<FlowPlanesScreen> {
  List<Map<String, dynamic>> _planes = const [];
  bool _cargando = true;
  String? _error;

  /// WhatsApp de ventas. Se lee de la configuración del panel; si esa lectura
  /// falla se usa [kWhatsAppVentasPorDefecto].
  String _whatsappVentas = kWhatsAppVentasPorDefecto;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // La configuración se lee en paralelo y **no** puede tumbar la pantalla:
      // sin el WhatsApp de ventas los planes de pago se siguen gestionando.
      final resultados = await Future.wait<dynamic>([
        SuscripcionAdminService.planes(),
        _leerWhatsappVentas(),
      ]);
      if (!mounted) return;
      final planes = resultados[0] as List<Map<String, dynamic>>;
      final soporte = resultados[1] as String?;
      setState(() {
        _planes = planes;
        _whatsappVentas = soporte ?? kWhatsAppVentasPorDefecto;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  Future<String?> _leerWhatsappVentas() async {
    try {
      final cfg = await SuscripcionAdminService.config();
      final digitos = whatsappDigitos(textoDe(cfg['soporte_whatsapp']));
      return digitos.length >= 8 ? digitos : null;
    } catch (_) {
      // Servidor sin `admin_config_obtener` o sin sesión plena: se usa el
      // respaldo documentado en `planes_ui.dart`.
      return null;
    }
  }

  void _avisar(String mensaje, {required bool esError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? AppColors.error : AppColors.success,
      ),
    );
  }

  int get _activos => _planes.where((p) => boolDe(p['activo'])).length;

  int get _privados => _planes.where(esPlanPrivado).length;

  int get _contactoActivos =>
      _planes.where((p) => esPlanContacto(p) && boolDe(p['activo'])).length;

  /// ¿Hay algún plan de **pago** activo con precio 0? Sería vendible gratis por
  /// descuido. Los de modalidad `contacto` quedan fuera a propósito: nacen con
  /// precio 0 porque se negocian con ventas y eso no es un error.
  bool get _hayActivoSinPrecio => _planes.any(
    (p) =>
        boolDe(p['activo']) &&
        !esPlanContacto(p) &&
        (decimalDe(p['precio']) ?? 0) <= 0,
  );

  Future<void> _editar(Map<String, dynamic>? plan) async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoPlan(plan: plan),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _alternarActivo(Map<String, dynamic> plan) async {
    final id = enteroDe(plan['id']);
    if (id == null) return;
    final activo = !boolDe(plan['activo']);

    try {
      await SuscripcionAdminService.guardarPlan(id: id, activo: activo);
      _avisar(activo ? 'Plan activado.' : 'Plan desactivado.', esError: false);
      await _cargar();
    } catch (e) {
      _avisar('$e', esError: true);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> plan) async {
    final id = enteroDe(plan['id']);
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Eliminar plan'),
            content: Text(
              'Se intentará borrar "${textoDe(plan['nombre'])}". Si alguna entidad ya '
              'lo compró, el servidor no lo borra: lo desactiva para no romper su '
              'historial.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    try {
      final res = await SuscripcionAdminService.eliminarPlan(id);
      // El servidor distingue "borrado" de "desactivado porque tenía compras" y
      // manda el motivo redactado; se muestra tal cual.
      final borrado = boolDe(res['eliminado'], porDefecto: true);
      _avisar(
        borrado
            ? 'Plan eliminado.'
            : textoDe(
              res['motivo'],
              porDefecto:
                  'El plan tenía compras: se desactivó en vez de borrarse.',
            ),
        esError: false,
      );
      await _cargar();
    } catch (e) {
      _avisar('$e', esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Planes de suscripción'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(null),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo plan'),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 44, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ancho =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 1200.0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _CabeceraPlanes(
                total: _planes.length,
                activos: _activos,
                privados: _privados,
                contacto: _contactoActivos,
              ),
              const SizedBox(height: 12),
              if (_activos == 0)
                const _Aviso(
                  color: AppColors.warning,
                  icono: Icons.warning_amber_rounded,
                  texto:
                      'No hay ningún plan activo. Los clientes no ven nada que '
                      'comprar en la app. Activa un plan o crea uno nuevo.',
                )
              else if (_hayActivoSinPrecio)
                const _Aviso(
                  color: AppColors.error,
                  icono: Icons.money_off,
                  texto:
                      'Hay un plan de pago activo con precio 0 en la moneda del '
                      'plan: se podría "comprar" gratis. Ponle precio o '
                      'desactívalo.',
                ),
              if (_contactoActivos > 0)
                _Aviso(
                  color: AppColors.info,
                  icono: Icons.support_agent,
                  texto:
                      '$_contactoActivos plan(es) de modalidad "Contactar con '
                      'ventas" activos: el botón abre el WhatsApp de soporte '
                      '($_whatsappVentas). Se cambia en Configuración.',
                ),
              if (_planes.isEmpty)
                _Vacio(onCrear: () => _editar(null))
              else
                _rejilla(ancho),
            ],
          );
        },
      ),
    );
  }

  /// 1 columna < 700 px, 2 < 1100, 3 si hay más sitio.
  ///
  /// Es el ancho de la **ventana**, no el del contenido, para que el salto de
  /// columnas sea el que espera el superadmin al redimensionar.
  Widget _rejilla(double ancho) {
    const separacion = 16.0;
    const paddingLados = 32.0; // ListView: 16 + 16
    final columnas = ancho >= 1100 ? 3 : (ancho >= 700 ? 2 : 1);
    final anchoContenido = ancho - paddingLados;
    final anchoTarjeta =
        (anchoContenido - separacion * (columnas - 1)) / columnas;

    return Wrap(
      spacing: separacion,
      runSpacing: separacion,
      children: [
        for (final plan in _planes)
          SizedBox(
            width: anchoTarjeta,
            child: TarjetaPlanFlow(
              plan: plan,
              whatsappVentas: _whatsappVentas,
              onEditar: () => _editar(plan),
              onAlternar: () => _alternarActivo(plan),
              onEliminar: () => _eliminar(plan),
            ),
          ),
      ],
    );
  }
}

/// Cabecera con el resumen del catálogo.
class _CabeceraPlanes extends StatelessWidget {
  const _CabeceraPlanes({
    required this.total,
    required this.activos,
    required this.privados,
    required this.contacto,
  });

  final int total;
  final int activos;
  final int privados;
  final int contacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Catálogo de planes',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$total planes · $activos activos · $privados privados · '
                  '$contacto de contacto',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Los planes privados solo los ve su entidad; los de contacto '
                  'no se cobran en la app.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vacío del catálogo.
class _Vacio extends StatelessWidget {
  const _Vacio({required this.onCrear});

  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    return TarjetaFlow(
      child: Column(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 40,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 10),
          const Text(
            'Todavía no hay planes. Crea el primero: el catálogo es lo que ven '
            'las entidades en la app para elegir su suscripción.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onCrear,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Crear plan'),
          ),
        ],
      ),
    );
  }
}

/// Alta y edición de un plan.
///
/// El código es la clave estable del plan (`flow_mensual`): se avisa de que no
/// conviene cambiarlo en un plan ya vendido, aunque el servidor lo permita. En
/// los planes privados el servidor puede generarlo si se deja vacío.
///
/// El diálogo se organiza en secciones (datos, precio, límites, modalidad y
/// visibilidad) porque el formulario creció con la migración 72 y una sola
/// columna de campos ya no se leía.
class _DialogoPlan extends StatefulWidget {
  const _DialogoPlan({this.plan});

  final Map<String, dynamic>? plan;

  @override
  State<_DialogoPlan> createState() => _DialogoPlanState();
}

class _DialogoPlanState extends State<_DialogoPlan> {
  static const List<String> _monedas = ['USD', 'CUP', 'EUR', 'MLC'];
  static const List<String> _sugerenciasEtiqueta = [
    'Más popular',
    'Recomendado',
    'Mejor valor',
  ];

  late final TextEditingController _codigo;
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late final TextEditingController _dias;
  late final TextEditingController _precio;
  late final TextEditingController _orden;
  late final TextEditingController _etiqueta;
  late final Map<String, TextEditingController> _limites;

  late String _moneda;
  late bool _activo;
  late String _modalidad;
  late bool _privado;
  int? _idEntidad;
  String? _entidadDenominacion;

  List<_OpcionEntidad> _entidades = const [];
  bool _cargandoEntidades = false;
  String? _errorEntidades;

  bool _guardando = false;
  String? _error;

  bool get _esNuevo => widget.plan == null;

  bool get _esContacto => _modalidad == 'contacto';

  @override
  void initState() {
    super.initState();
    final p = widget.plan ?? const <String, dynamic>{};
    _codigo = TextEditingController(text: textoDe(p['codigo']));
    _nombre = TextEditingController(text: textoDe(p['nombre']));
    _descripcion = TextEditingController(text: textoDe(p['descripcion']));
    _dias = TextEditingController(
      text: '${enteroDe(p['duracion_dias']) ?? 30}',
    );
    _precio = TextEditingController(
      text: decimalDe(p['precio'])?.toStringAsFixed(2) ?? '0.00',
    );
    _orden = TextEditingController(text: '${enteroDe(p['orden']) ?? 0}');
    _etiqueta = TextEditingController(text: textoDe(p['etiqueta']));
    _limites = <String, TextEditingController>{
      for (final clave in kClavesLimite)
        clave: TextEditingController(
          text: switch (limitesPositivos(p['limites'])[clave]) {
            final n? => '$n',
            null => '',
          },
        ),
    };
    final moneda = monedaDePlan(p);
    _moneda = _monedas.contains(moneda) ? moneda : 'USD';
    _activo = _esNuevo ? false : boolDe(p['activo']);
    _modalidad = modalidadDePlan(p);
    _privado = esPlanPrivado(p);
    _idEntidad = enteroDe(p['id_entidad']);
    _entidadDenominacion = textoDe(p['entidad_denominacion']);
    if (_esContacto) _precio.text = '0.00';
    if (_privado) {
      // Se intenta tener el listado listo para poder cambiar de entidad.
      WidgetsBinding.instance.addPostFrameCallback((_) => _leerEntidades());
    }
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _descripcion.dispose();
    _dias.dispose();
    _precio.dispose();
    _orden.dispose();
    _etiqueta.dispose();
    for (final c in _limites.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _leerEntidades() async {
    if (_cargandoEntidades) return;
    setState(() {
      _cargandoEntidades = true;
      _errorEntidades = null;
    });
    try {
      final filas = await SuscripcionAdminService.listar(filtro: 'todas');
      final opciones = <_OpcionEntidad>[
        for (final fila in filas)
          if (enteroDe(fila['id_entidad']) case final id?)
            _OpcionEntidad(
              id: id,
              nombre: textoDe(fila['denominacion'], porDefecto: 'Entidad #$id'),
            ),
      ]..sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _entidades = opciones;
        _cargandoEntidades = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoEntidades = false;
        _errorEntidades = '$e';
      });
    }
  }

  Future<void> _elegirEntidad() async {
    if (_entidades.isEmpty && !_cargandoEntidades) await _leerEntidades();
    if (!mounted) return;
    if (_entidades.isEmpty) {
      // Sin listado no se puede elegir: el propio bloque muestra el error y el
      // botón de reintentar.
      return;
    }
    final elegida = await showDialog<_OpcionEntidad>(
      context: context,
      builder:
          (_) => _DialogoSelectorEntidad(
            opciones: _entidades,
            seleccionada: _idEntidad,
          ),
    );
    if (elegida == null || !mounted) return;
    setState(() {
      _idEntidad = elegida.id;
      _entidadDenominacion = elegida.nombre;
    });
  }

  /// `limites` con SOLO las claves con valor `> 0` (contrato del servidor).
  Map<String, dynamic> _limitesDelFormulario() {
    final salida = <String, dynamic>{};
    _limites.forEach((clave, controller) {
      final texto = controller.text.trim();
      if (texto.isEmpty) return;
      final n = int.tryParse(texto);
      if (n != null && n > 0) salida[clave] = n;
    });
    return salida;
  }

  Future<void> _guardar() async {
    final codigo = _codigo.text.trim();
    final nombre = _nombre.text.trim();
    final dias = int.tryParse(_dias.text.trim()) ?? 0;
    final precioTexto = _precio.text.trim().replaceAll(',', '.');
    final precio = _esContacto ? 0.0 : (double.tryParse(precioTexto) ?? -1);
    final orden = int.tryParse(_orden.text.trim()) ?? 0;

    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    // En un plan privado el servidor puede generar el código; en uno público es
    // obligatorio porque es la clave estable del catálogo.
    if (_esNuevo && !_privado && codigo.isEmpty) {
      setState(() => _error = 'El código es obligatorio.');
      return;
    }
    if (dias < 1 || dias > 3650) {
      setState(() => _error = 'La duración debe estar entre 1 y 3650 días.');
      return;
    }
    if (precio < 0) {
      setState(() => _error = 'El precio no puede ser negativo.');
      return;
    }
    for (final clave in kClavesLimite) {
      final texto = _limites[clave]!.text.trim();
      if (texto.isEmpty) continue;
      final n = int.tryParse(texto);
      if (n == null) {
        setState(
          () =>
              _error =
                  'El límite de "${etiquetaDeLimite(clave)}" debe ser un número '
                  'entero (o vacío para no limitar).',
        );
        return;
      }
    }
    if (_privado && _idEntidad == null) {
      setState(
        () =>
            _error =
                'Un plan privado necesita una entidad. Búscala en el bloque '
                '"Visibilidad".',
      );
      return;
    }

    // Un plan de pago, activo y gratis es casi siempre un descuido: se avisa,
    // no se bloquea, porque puede ser intencional (plan de cortesía). Los de
    // modalidad contacto no pasan por aquí: su precio 0 es lo normal.
    if (_activo && !_esContacto && precio == 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Plan activo con precio 0'),
              content: const Text(
                'Se podrá "comprar" sin pagar nada. ¿Seguro que es un plan de '
                'cortesía?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Revisar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Sí, activar'),
                ),
              ],
            ),
      );
      if (ok != true) return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      // Se usa la variante detallada porque el servidor devuelve `codigo` (el
      // que genera para los planes privados) y `aviso` (plan de pago activo con
      // precio 0). Ambos se muestran al superadmin; ninguno bloquea el guardado.
      final resultado = await SuscripcionAdminService.guardarPlanDetallado(
        id: enteroDe(widget.plan?['id']),
        codigo: codigo.isEmpty ? null : codigo,
        nombre: nombre,
        descripcion: _descripcion.text.trim(),
        duracionDias: dias,
        precio: precio,
        moneda: _moneda,
        limites: _limitesDelFormulario(),
        orden: orden,
        activo: _activo,
        modalidad: _modalidad,
        // `0` = público. `null` conservaría la entidad actual: apagar "Plan
        // privado" tiene que publicar el plan, no dejarlo privado.
        idEntidad: _privado ? _idEntidad : 0,
        etiqueta: _etiqueta.text.trim(),
      );
      if (!mounted) return;
      final mensajes = <String>[];
      final codigoAsignado = textoDe(resultado['codigo']).trim();
      if (codigoAsignado.isNotEmpty) {
        mensajes.add('Código asignado: $codigoAsignado');
      }
      final aviso = textoDe(resultado['aviso']).trim();
      if (aviso.isNotEmpty) mensajes.add(aviso);
      if (mensajes.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mensajes.join(' · '))));
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.sizeOf(context).height;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: alto * 0.9 < 400 ? 400 : alto * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _cabecera(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _seccionDatos(),
                    const SizedBox(height: 14),
                    _seccionPrecio(),
                    const SizedBox(height: 14),
                    _seccionLimites(),
                    const SizedBox(height: 14),
                    _seccionModalidad(),
                    const SizedBox(height: 14),
                    _seccionVisibilidad(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _guardando ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    child:
                        _guardando
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : Text(_esNuevo ? 'Crear plan' : 'Guardar cambios'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecera() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _esNuevo ? Icons.add_circle_outline : Icons.edit_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _esNuevo ? 'Nuevo plan' : 'Editar plan',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Precio, límites y visibilidad del plan. Solo los campos con '
                  'asterisco son obligatorios.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: _guardando ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _seccionDatos() {
    return _SeccionEditor(
      icono: Icons.badge_outlined,
      titulo: 'Datos del plan',
      hijo: Column(
        children: [
          TextField(
            controller: _codigo,
            enabled: _esNuevo,
            decoration: InputDecoration(
              labelText: _esNuevo && !_privado ? 'Código *' : 'Código',
              helperText:
                  _esNuevo
                      ? (_privado
                          ? 'Opcional en un plan privado: si lo dejas vacío el '
                              'servidor genera privado_<entidad>_<n>'
                          : 'Identificador estable, p. ej. flow_mensual')
                      : 'No se cambia en un plan ya vendido',
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nombre,
            decoration: const InputDecoration(
              labelText: 'Nombre *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descripcion,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              helperText:
                  'Se muestra debajo de las características en la tarjeta',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orden,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Orden',
                    helperText: 'Menor = primero',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo', style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    'Visible para los clientes',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _activo,
                  onChanged: (v) => setState(() => _activo = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seccionPrecio() {
    return _SeccionEditor(
      icono: Icons.payments_outlined,
      titulo: 'Precio y duración',
      hijo: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dias,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Días *',
                    helperText: '1 a 3650',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _precio,
                  enabled: !_esContacto,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Precio',
                    helperText:
                        _esContacto
                            ? 'En modalidad contacto el precio es 0'
                            : 'Importe del periodo completo',
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  initialValue: _moneda,
                  decoration: const InputDecoration(
                    labelText: 'Moneda',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in _monedas)
                      DropdownMenuItem<String>(value: m, child: Text(m)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _moneda = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // La tarifa va en la moneda elegida; el cobro real, siempre en CUP.
          const NotaCobroCup(),
          const SizedBox(height: 12),
          TextField(
            controller: _etiqueta,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Etiqueta (opcional)',
              helperText:
                  'Cinta de la tarjeta: "Más popular", "Recomendado"… Vacío = '
                  'sin cinta',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final sugerencia in _sugerenciasEtiqueta)
                ActionChip(
                  label: Text(
                    sugerencia,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () => setState(() => _etiqueta.text = sugerencia),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seccionLimites() {
    return _SeccionEditor(
      icono: Icons.rule_outlined,
      titulo: 'Límites del plan',
      subtitulo:
          'Vacío = sin límite. Un número mayor que 0 es el máximo que permite '
          'el plan; 0 también se interpreta como sin límite.',
      hijo: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final clave in kClavesLimite)
            SizedBox(
              width: 210,
              child: TextField(
                controller: _limites[clave],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: etiquetaDeLimite(clave),
                  hintText: 'Sin límite',
                  helperText: ayudaDeLimite(clave),
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _seccionModalidad() {
    return _SeccionEditor(
      icono: Icons.checklist_rtl_outlined,
      titulo: 'Modalidad de cobro',
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El segmentado puede no caber en pantallas estrechas: se deja
          // desplazar en horizontal antes que romper el diálogo.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'pago',
                  icon: Icon(Icons.credit_card_outlined, size: 16),
                  label: Text('Pago'),
                ),
                ButtonSegment<String>(
                  value: 'contacto',
                  icon: Icon(Icons.handshake_outlined, size: 16),
                  label: Text('Contactar con ventas'),
                ),
              ],
              selected: {_modalidad},
              onSelectionChanged: (seleccion) {
                final valor = seleccion.first;
                setState(() {
                  _modalidad = valor;
                  if (valor == 'contacto') _precio.text = '0.00';
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _esContacto
                ? 'El plan no se compra en la app: el cliente pulsa "Contactar '
                    'con ventas" y se abre el WhatsApp de soporte.'
                : 'El cliente paga el importe del periodo con el flujo de pago '
                    'actual (Transfermóvil o el rail configurado).',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
          if (_esContacto) ...[
            const SizedBox(height: 8),
            const _Aviso(
              color: AppColors.info,
              icono: Icons.info_outline,
              texto:
                  'Con precio 0 y activo, este plan no dispara el aviso de '
                  '"plan gratis": es lo esperado en modalidad contacto.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _seccionVisibilidad() {
    return _SeccionEditor(
      icono: Icons.visibility_outlined,
      titulo: 'Visibilidad',
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Plan privado',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Solo lo ve la entidad elegida; el resto no lo ve en el catálogo.',
              style: TextStyle(fontSize: 11.5, height: 1.3),
            ),
            value: _privado,
            onChanged: (v) {
              setState(() {
                _privado = v;
                if (v && _entidades.isEmpty && !_cargandoEntidades) {
                  // Se carga el listado al activar el switch, no al abrir el
                  // diálogo: la mayoría de los planes son públicos.
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _leerEntidades(),
                  );
                }
              });
            },
          ),
          if (_privado) ...[
            const SizedBox(height: 6),
            if (_cargandoEntidades)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_errorEntidades != null && _entidades.isEmpty)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'No se pudieron cargar las entidades.',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  ),
                  TextButton(
                    onPressed: _leerEntidades,
                    child: const Text('Reintentar'),
                  ),
                ],
              )
            else if (_idEntidad == null)
              OutlinedButton.icon(
                onPressed: _elegirEntidad,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Buscar entidad…'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  InputChip(
                    avatar: const Icon(
                      Icons.business_outlined,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        _entidadDenominacion ?? 'Entidad #$_idEntidad',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onPressed: _elegirEntidad,
                    onDeleted:
                        () => setState(() {
                          _idEntidad = null;
                          _entidadDenominacion = null;
                        }),
                    deleteIcon: const Icon(Icons.close, size: 16),
                  ),
                  Text(
                    'ID $_idEntidad',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
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

/// Sección con título dentro del editor de plan.
class _SeccionEditor extends StatelessWidget {
  const _SeccionEditor({
    required this.icono,
    required this.titulo,
    required this.hijo,
    this.subtitulo,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 17, color: AppColors.primary),
              const SizedBox(width: 7),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          hijo,
        ],
      ),
    );
  }
}

/// Entidad seleccionable en el plan privado.
class _OpcionEntidad {
  const _OpcionEntidad({required this.id, required this.nombre});

  final int id;
  final String nombre;
}

/// Buscador de entidad para los planes privados.
///
/// Se apoya en `admin_suscripcion_listar`, que ya devuelve `id_entidad` y
/// `denominacion` para todas las entidades. El filtro es local (sobre la lista
/// cargada) para que buscar no dependa de otra llamada al servidor.
class _DialogoSelectorEntidad extends StatefulWidget {
  const _DialogoSelectorEntidad({
    required this.opciones,
    required this.seleccionada,
  });

  final List<_OpcionEntidad> opciones;
  final int? seleccionada;

  @override
  State<_DialogoSelectorEntidad> createState() =>
      _DialogoSelectorEntidadState();
}

class _DialogoSelectorEntidadState extends State<_DialogoSelectorEntidad> {
  final _buscar = TextEditingController();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  List<_OpcionEntidad> get _filtradas {
    final q = _buscar.text.trim().toLowerCase();
    if (q.isEmpty) return widget.opciones;
    return widget.opciones
        .where((o) => o.nombre.toLowerCase().contains(q) || '${o.id}' == q)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _filtradas;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Elegir entidad del plan privado',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _buscar,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Buscar por nombre o ID…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: filtradas.length,
                itemBuilder: (context, i) {
                  final opcion = filtradas[i];
                  final seleccionada = opcion.id == widget.seleccionada;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text(
                        opcion.nombre.trim().isEmpty
                            ? '?'
                            : opcion.nombre
                                .trim()
                                .substring(0, 1)
                                .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    title: Text(
                      opcion.nombre,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      'ID ${opcion.id}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                    trailing:
                        seleccionada
                            ? const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 20,
                            )
                            : null,
                    onTap: () => Navigator.pop(context, opcion),
                  );
                },
              ),
            ),
            if (filtradas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No hay entidades que coincidan con la búsqueda.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const Divider(height: 1, color: AppColors.divider),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.color, required this.icono, required this.texto});

  final Color color;
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TarjetaFlow(
        color: color.withValues(alpha: 0.08),
        borde: color.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
