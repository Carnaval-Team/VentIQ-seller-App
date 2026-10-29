import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/campo_adicional.dart';
import '../../models/cobro.dart';
import '../../models/config_precio.dart';
import '../../models/entidad.dart';
import '../../models/precio_config.dart';
import '../../models/servicio.dart';
import '../../models/tasa_cambio.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/cobro_service.dart';
import '../../services/imagen_service.dart';
import '../../services/precio_config_service.dart';
import '../../services/tasa_cambio_service.dart';
import '../../services/tipo_actividad_service.dart';
import '../../tutorial/tutorial_anchor.dart';
import '../../utils/conversion_precio.dart';
import '../../utils/foto_obligatoria.dart';
import '../../utils/parse_monto.dart';
import '../../widgets/campo_foto_obligatoria.dart';
import '../../widgets/opciones_list_editor.dart';
import 'precio_config_screen.dart';
import 'servicio_detail_screen.dart';

class GestionServiciosScreen extends StatefulWidget {
  final Entidad entidad;

  /// Abre el formulario de alta nada más entrar.
  ///
  /// Lo usa el tutorial: sus pasos de precio, datos adicionales, reglas y guardar
  /// viven dentro del formulario, así que el destino `serviciosFormulario` lleva
  /// al admin directo al alta en vez de dejarlo buscando el botón.
  final bool abrirNuevoAlEntrar;

  const GestionServiciosScreen({
    super.key,
    required this.entidad,
    this.abrirNuevoAlEntrar = false,
  });

  @override
  State<GestionServiciosScreen> createState() => _GestionServiciosScreenState();
}

class _GestionServiciosScreenState extends State<GestionServiciosScreen> {
  List<Servicio> _servicios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
    if (widget.abrirNuevoAlEntrar) {
      // Post-frame: la hoja modal necesita el contexto ya montado.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nuevoServicio();
      });
    }
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      _servicios = await CatalogoService.getServiciosByEntidad(
        widget.entidad.id,
      );
    } catch (e) {
      print('[flow] GestionServiciosScreen _cargar ERROR: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _nuevoServicio() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ServicioFormSheet(idEntidad: widget.entidad.id),
    ).then((_) => _cargar());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Servicios · ${widget.entidad.denominacion}'),
        actions: [
          IconButton(
            tooltip: 'Precios automáticos',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PrecioConfigScreen(
                  idEntidad: widget.entidad.id,
                  denominacion: widget.entidad.denominacion,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: TutorialAnchor(
        id: 'admin_nuevo_servicio',
        child: FloatingActionButton.extended(
          onPressed: _nuevoServicio,
          icon: const Icon(Icons.add),
          label: const Text('Nuevo Servicio'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servicios.isEmpty
          ? const Center(
              child: Text(
                'Sin servicios registrados',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _servicios.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final s = _servicios[i];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    // Un servicio inactivo sigue listado (hay que poder
                    // reactivarlo) pero atenuado: los clientes no lo ven en
                    // ningún local (punto 4).
                    child: Opacity(
                      opacity: s.activo ? 1 : 0.6,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.surface,
                          backgroundImage: s.foto != null
                              ? (kIsWeb
                                    ? NetworkImage(
                                        ImagenService.conVersion(s.foto),
                                      )
                                    : CachedNetworkImageProvider(
                                        ImagenService.conVersion(s.foto),
                                      ))
                              : null,
                          child: s.foto == null
                              ? const Icon(
                                  Icons.miscellaneous_services_outlined,
                                  color: AppTheme.primary,
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                s.nombre,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (!s.activo)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: _SrvChipInactivo(),
                              ),
                          ],
                        ),
                        subtitle: s.descripcion != null
                            ? Text(
                                s.descripcion!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ServicioDetailScreen(
                              servicio: s,
                              idEntidad: widget.entidad.id,
                            ),
                          ),
                        ).then((_) => _cargar()),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class ServicioFormSheet extends StatefulWidget {
  final int idEntidad;
  final Servicio? servicio;
  const ServicioFormSheet({
    super.key,
    required this.idEntidad,
    this.servicio,
  });

  @override
  State<ServicioFormSheet> createState() => ServicioFormSheetState();
}

class ServicioFormSheetState extends State<ServicioFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  XFile? _imagenFile;
  String? _fotoUrl;
  bool _saving = false;

  /// Punto 4: publicar/ocultar el servicio en todos los locales.
  late bool _activo;

  // Datos adicionales + terceros + precio
  bool _permiteTercero = false;

  /// [67] ¿Este servicio se puede pagar por adelantado?
  bool _cobroAdelantado = false;

  /// ¿La entidad tiene activo el cobro por adelantado? `null` = todavía no se
  /// sabe (mientras se lee la configuración). Manda sobre el switch: sin el
  /// interruptor de la entidad, el del servicio no puede encenderse.
  bool? _entidadCobra;
  late List<_CampoEditable> _campos;
  List<String> _monedasHabilitadas = ['USD'];
  String _monedaDefault = 'USD';
  final Map<String, TextEditingController> _precioBaseCtrls = {};
  final List<_ReglaPrecioEditable> _reglasPrecio = [];
  /// Taxonomía de dos niveles (migración 47): categorías y sus subcategorías.
  /// Se lee una vez y se resuelve en memoria; si la migración no está aplicada
  /// llega plana (todo raíces) y el formulario sigue funcionando con un solo
  /// desplegable útil.
  Taxonomia _taxonomia = Taxonomia.vacia;

  /// Hoja guardada: es lo que se escribe en `app_dat_servicios.id_tipo_actividad`.
  /// Puede ser una categoría sin subcategorías o una subcategoría.
  int? _idTipoActividad;

  /// Selección de la interfaz en dos pasos.
  int? _idCategoria;
  int? _idSubcategoria;

  bool _cargandoTiposActividad = true;
  bool _aplicaPrecioIdaVueltaTodos = false;

  // ── Precios automáticos por tasa de cambio (punto 4) ─────────────────────
  /// Hay un cartel de extracción abierto (y el cálculo en curso).
  bool _calculandoPrecios = false;

  /// Contexto del diálogo de extracción, para poder cerrarlo sin tocar el resto
  /// de la pila de navegación (debajo vive la hoja modal del formulario).
  BuildContext? _cartelCtx;

  /// Configuración de redondeo de la entidad (y su moneda preferida, que solo se
  /// usa para **proponerla** al crear un servicio nuevo).
  PrecioConfig _precioConfig = const PrecioConfig();

  /// La configuración ya se leyó (o falló): el cálculo automático no se dispara
  /// antes, para no usar valores por defecto que el admin no eligió.
  bool _configCargada = false;

  /// Tasa con la que se calcularon los precios que hay ahora en el formulario.
  TasasDia? _tasasUsadas;

  /// Se está extrayendo la tasa: banner discreto dentro del formulario (el
  /// diálogo modal se reserva para el botón de recalcular a mano).
  bool _extrayendoTasa = false;

  /// Último valor YA calculado, por origen: «base|CUP» → 17000,
  /// «regla:0|USD» → 18.
  ///
  /// Es un mapa y no una única firma global (que es lo que había): con una sola
  /// firma, el cálculo de una moneda **bloqueaba** el de otra si coincidía el
  /// patrón, y por eso editar CUP después de haber editado USD no recalculaba
  /// nada. Ahora cada origen se compara consigo mismo.
  final Map<String, double> _ultimoCalculado = {};

  /// Monedas cuyo precio lo puso el cálculo automático: se pintan **en verde y
  /// con su icono**. Al editar ese campo a mano deja de estar marcado, porque el
  /// valor ya no lo calculó la app.
  final Set<String> _calculadas = {};

  /// El aviso de «no hay tasa» se da una vez por formulario: si no, escribir
  /// tres cifras seguidas sin red lanzaría tres avisos seguidos.
  bool _avisoTasaMostrado = false;

  /// Debounce del cálculo automático mientras el admin escribe.
  Timer? _debounceAuto;

  /// Código de la hoja elegida, para las reglas que dependen de él (transporte
  /// en ómnibus). Se apoya en la taxonomía y, si no está, en el código que trajo
  /// el servicio.
  String? get _codigoTipoActividad =>
      _taxonomia.porId(_idTipoActividad)?.codigo ??
      widget.servicio?.tipoActividad;

  bool get _esTransporteOmnibus => _codigoTipoActividad == 'transporte_omnibus';

  /// Subcategorías de la categoría elegida (vacío si no tiene o si la migración
  /// 47 no está aplicada).
  List<TipoActividad> get _subcategoriasDeCategoria =>
      _taxonomia.subcategoriasDe(_idCategoria);

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.servicio?.nombre ?? '');
    _descCtrl = TextEditingController(text: widget.servicio?.descripcion ?? '');
    _fotoUrl = widget.servicio?.foto;
    _activo = widget.servicio?.activo ?? true;
    _permiteTercero = widget.servicio?.permiteTercero ?? false;
    _cobroAdelantado = widget.servicio?.cobroAdelantado ?? false;
    _campos = (widget.servicio?.camposAdicionales ?? [])
        .map(_CampoEditable.fromModel)
        .toList();
    final cfg = widget.servicio?.configPrecio ?? ConfigPrecio();
    _monedasHabilitadas = cfg.monedas.isEmpty ? ['USD'] : [...cfg.monedas];
    _monedaDefault = cfg.monedaDefault;
    _aplicaPrecioIdaVueltaTodos = cfg.aplicaPrecioIdaVueltaTodos;
    if (!_monedasHabilitadas.contains(_monedaDefault)) {
      _monedaDefault = _monedasHabilitadas.first;
    }
    for (final m in _monedasHabilitadas) {
      _precioBaseCtrls[m] = TextEditingController(
        text: _fmtPrecio(cfg.preciosBase[m]),
      );
    }
    _reglasPrecio.addAll(
      cfg.reglas.map(
        (r) => _ReglaPrecioEditable.fromModel(r, monedas: _monedasHabilitadas),
      ),
    );
    _cargarPrecioConfig();
    _cargarCobroEntidad();
    _cargarTiposActividad();
  }

  /// Carga la taxonomía y reparte la hoja guardada entre los dos desplegables.
  ///
  /// Si el servicio ya tenía una subcategoría, se abren los dos niveles con ella
  /// seleccionada. Si tenía una categoría (o nada), se elige la primera
  /// categoría asignable y el servicio queda **en la categoría**, que es válido:
  /// un servicio puede no tener subcategoría.
  Future<void> _cargarTiposActividad() async {
    try {
      final taxonomia = await TipoActividadService.taxonomia(soloActivos: true);
      if (!mounted) return;

      final actual = widget.servicio?.idTipoActividad;
      final hoja = taxonomia.porId(actual);
      final asignables = taxonomia.asignables;

      int? idCategoria;
      int? idSubcategoria;
      int? idHoja;

      if (hoja != null && hoja.esSubcategoria) {
        idCategoria = hoja.idPadre;
        idSubcategoria = hoja.id;
        idHoja = hoja.id;
      } else if (hoja != null) {
        idCategoria = hoja.id;
        idHoja = hoja.id;
      } else if (asignables.isNotEmpty) {
        // Sin tipo previo: la primera hoja asignable, igual que antes se
        // proponía `general`. Si esa hoja tiene padre, se abre su categoría.
        final primera = asignables.first;
        idHoja = primera.id;
        idCategoria = primera.idPadre ?? primera.id;
        idSubcategoria = primera.esSubcategoria ? primera.id : null;
      }

      setState(() {
        _taxonomia = taxonomia;
        _idTipoActividad = idHoja;
        _idCategoria = idCategoria;
        _idSubcategoria = idSubcategoria;
        _cargandoTiposActividad = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargandoTiposActividad = false);
    }
  }

  /// Texto inicial de un precio ya guardado.
  ///
  /// Se limita a [Redondeo.maxDecimales]: un valor viejo con 3 decimales
  /// (`18.375`) se releería como **18375** al guardar, porque `parseMonto`
  /// interpreta tres dígitos tras el separador como millares.
  String _fmtPrecio(double? v) {
    if (v == null || v == 0) return '';
    return Redondeo.texto(v, Redondeo.maxDecimales);
  }

  // ── Precios automáticos (punto 4) ────────────────────────────────────────

  /// Moneda de origen efectiva: la que dice la configuración de la entidad si
  /// está habilitada en este servicio; si no, la moneda por defecto del
  /// servicio. El botón y el disparo automático siempre usan esta.
  /// Moneda **base** del servicio: la que elige el desplegable «Moneda por
  /// defecto». Es la que el admin escribe y de la que sale todo lo demás.
  ///
  /// OJO: antes mandaba `precio_config.moneda_origen` (la preferencia de la
  /// entidad) y por eso, al elegir MLC en el desplegable, el sello BASE seguía
  /// en USD. Esa preferencia ahora solo se usa para **proponerla** al crear un
  /// servicio nuevo (`_cargarPrecioConfig`).
  String get _origenEfectivo {
    if (_monedasHabilitadas.contains(_monedaDefault)) return _monedaDefault;
    return _monedasHabilitadas.isNotEmpty
        ? _monedasHabilitadas.first
        : _monedaDefault;
  }

  /// Monedas habilitadas con la **base primero**: es la que el admin escribe y
  /// de la que sale todo lo demás, así que va arriba del bloque de precios.
  List<String> get _monedasOrdenadas => [
    _origenEfectivo,
    ..._monedasHabilitadas.where((m) => m != _origenEfectivo),
  ];

  /// Decoración de un campo de precio base.
  ///
  /// Dos señales distintas, para que no se confundan:
  ///  * **moneda base** → etiqueta con el sello «BASE» y borde/fondo de marca;
  ///  * **precio calculado** → borde y fondo **verdes** con un icono dentro del
  ///    cuadro. Al editarlo a mano deja de estar verde, porque ya no lo calculó
  ///    la app.
  InputDecoration _decoracionPrecio(String m) {
    final esBase = m == _origenEfectivo;
    final calculada = _calculadas.contains(m);
    final color = calculada
        ? AppTheme.success
        : (esBase ? AppTheme.primary : null);

    return InputDecoration(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Precio base (${MonedasApp.simbolo(m)})'),
          if (esBase) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'BASE',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      isDense: true,
      // `null` deja el relleno del tema; solo se tiñe cuando hay color.
      fillColor: color?.withValues(alpha: 0.07),
      border: const OutlineInputBorder(),
      enabledBorder: color == null
          ? null
          : OutlineInputBorder(
              borderSide: BorderSide(color: color, width: 1.5),
            ),
      focusedBorder: color == null
          ? null
          : OutlineInputBorder(
              borderSide: BorderSide(color: color, width: 1.8),
            ),
      suffixIcon: calculada
          ? const Tooltip(
              message: 'Calculado con la tasa del día',
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppTheme.success,
              ),
            )
          : null,
    );
  }

  /// [67] Lee si la **entidad** tiene activo el cobro por adelantado.
  ///
  /// Es el interruptor maestro: aporta la cuenta que cobra (número de proveedor,
  /// WhatsApp de verificación, moneda y plazo). Sin él, el switch del servicio
  /// no puede encenderse, así que se muestra deshabilitado con la explicación.
  Future<void> _cargarCobroEntidad() async {
    bool cobra;
    try {
      final config = await CobroService.configGet(widget.idEntidad);
      cobra = config.activo;
    } catch (_) {
      // Sin migración 62, sin permisos o sin red: se trata como apagado. El
      // formulario del servicio NUNCA se bloquea por esto.
      cobra = false;
    }
    if (!mounted) return;
    setState(() => _entidadCobra = cobra);
  }

  /// Lee la configuración de precios de la entidad (redondeo y moneda
  /// **preferida**). Si la migración 60 no está aplicada se usan los valores por
  /// defecto: el formulario nunca se bloquea por esto.
  Future<void> _cargarPrecioConfig() async {
    final config = await PrecioConfigService.getSeguro(widget.idEntidad);
    if (!mounted) return;
    setState(() {
      _precioConfig = config;
      // La moneda preferida de la entidad solo PROPONE la base, y solo cuando el
      // servicio es nuevo: en uno que ya existe manda lo que el admin guardó en
      // «Moneda por defecto» (y lo que elija después en el desplegable).
      if (widget.servicio == null &&
          _monedasHabilitadas.contains(config.monedaOrigen)) {
        _monedaDefault = config.monedaOrigen;
      }
      _configCargada = true;
    });
    // Si el admin ya había escrito un precio mientras se leía la configuración,
    // ahora que se conoce la moneda base y el redondeo se calcula.
    _programarCalculoAutomatico(_origenEfectivo);
  }

  /// Lee un precio escrito a mano. `null` si no hay número o no es positivo:
  /// en esta app `0` significa «sin precio».
  double? _precioEscrito(TextEditingController? ctrl) {
    final valor = parseMonto(ctrl?.text ?? '');
    if (valor == null || valor <= 0) return null;
    return valor;
  }

  /// De dónde sale el precio que se convierte: el de la moneda de origen o, si
  /// está vacío, el de la primera moneda habilitada con precio.
  ({String moneda, double valor})? _baseParaCalcular(String origen) {
    final propio = _precioEscrito(_precioBaseCtrls[origen]);
    if (propio != null) return (moneda: origen, valor: propio);
    for (final m in _monedasHabilitadas) {
      final valor = _precioEscrito(_precioBaseCtrls[m]);
      if (valor != null) return (moneda: m, valor: valor);
    }
    return null;
  }

  void _snack(String mensaje, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: color ?? AppTheme.warning,
        ),
      );
  }

  /// Cartel no descartable con el aviso obligatorio mientras se pide la tasa.
  ///
  /// El `await` de un frame garantiza que el diálogo ya está construido (y su
  /// contexto guardado) antes de que empiece la petición: así el cierre siempre
  /// encuentra la ruta correcta y nunca se lleva por delante la hoja modal.
  Future<void> _mostrarCartelExtraccion() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        _cartelCtx = ctx;
        return const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text('Extrayendo los precios automáticamente...'),
                ),
              ],
            ),
          ),
        );
      },
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  void _cerrarCartelExtraccion() {
    final ctx = _cartelCtx;
    _cartelCtx = null;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).pop();
  }

  /// Calcula el resto de monedas (precio base y reglas por opción) con la tasa
  /// del día, tomando como base el precio de la moneda de origen.
  ///
  /// Sin tasa **no se toca ningún precio**: se avisa y el admin sigue como
  /// estaba.
  Future<void> _calcularRestoDesdeOrigen({bool avisar = true}) async {
    if (_calculandoPrecios) return;
    if (_monedasHabilitadas.length < 2) {
      if (avisar) {
        _snack('Habilita más de una moneda para calcular el resto.');
      }
      return;
    }

    setState(() => _calculandoPrecios = true);
    await _mostrarCartelExtraccion();

    TasasDia? tasas;
    try {
      tasas = await TasaCambioService.obtener();
    } finally {
      _cerrarCartelExtraccion();
      if (mounted) setState(() => _calculandoPrecios = false);
    }
    if (!mounted) return;

    if (tasas == null) {
      _snack(
        'No se pudo obtener la tasa de cambio. Los precios no se han '
        'modificado.',
        color: AppTheme.error,
      );
      return;
    }

    _escribirPreciosCalculados(tasas);
  }

  /// Vuelca los precios convertidos en los controladores, formateados con los
  /// decimales configurados. Se redondea y se usa `toStringAsFixed` porque
  /// `parseMonto` lee tres decimales como millares (`18.375` → 18375).
  void _escribirPreciosCalculados(
    TasasDia tasas, {
    String? origen,
    bool avisar = true,
  }) {
    final base = _baseParaCalcular(origen ?? _origenEfectivo);
    if (base == null) {
      _snack(
        'Escribe primero un precio en $_origenEfectivo (o en cualquier '
        'moneda) para calcular el resto.',
      );
      return;
    }

    String formatear(String moneda, double valor) =>
        Redondeo.texto(valor, _precioConfig.decimalesDe(moneda));

    setState(() {
      // Precio base. Se marca lo que ESCRIBE el cálculo: esas monedas salen en
      // verde con su icono. La moneda desde la que se calculó conserva lo que
      // tecleó el admin, así que no se marca.
      _calculadas.clear();
      final convertidos = convertirVarios(
        precios: {base.moneda: base.valor},
        origen: base.moneda,
        monedas: _monedasHabilitadas,
        tasas: tasas,
        decimalesDe: _precioConfig.decimalesDe,
      );
      for (final entrada in convertidos.entries) {
        if (entrada.key == base.moneda) continue;
        final valor = entrada.value;
        if (valor == null) continue; // sin tasa para esa moneda: no se toca
        _precioBaseCtrls[entrada.key]?.text = formatear(entrada.key, valor);
        _calculadas.add(entrada.key);
      }

      // Reglas de precio por opción: se convierten las que ya tienen precio en
      // la moneda de origen.
      for (final regla in _reglasPrecio) {
        regla.syncMonedas(_monedasHabilitadas);
        regla.calculadas.clear();
        for (final opcion in regla.preciosPorOpcion.entries) {
          final ctrls = opcion.value;
          final precioBase = _precioEscrito(ctrls[base.moneda]);
          if (precioBase == null) continue;
          for (final m in _monedasHabilitadas) {
            if (m == base.moneda) continue;
            final valor = convertirPrecio(
              valor: precioBase,
              origen: base.moneda,
              destino: m,
              tasas: tasas,
              decimales: _precioConfig.decimalesDe(m),
            );
            if (valor == null) continue;
            ctrls[m]?.text = formatear(m, valor);
            regla.calculadas.add('${opcion.key}|$m');
          }
        }
      }

      _tasasUsadas = tasas;
    });

    // El aviso solo lo pide el botón: al teclear sería un SnackBar por pausa.
    if (avisar) {
      _snack(
        'Precios calculados con la tasa del ${tasas.fechaTexto}.',
        color: AppTheme.success,
      );
    }
  }

  /// Programa el cálculo automático mientras el admin escribe (debounce de
  /// 700 ms).
  ///
  /// **No** es «solo la primera vez»: cada vez que cambia un precio se
  /// recalculan las demás monedas, que es lo que se espera al teclear. El botón
  /// «Calcular desde …» queda para forzar el refresco de la tasa.
  void _programarCalculoAutomatico(
    String moneda, {
    _ReglaPrecioEditable? regla,
  }) {
    _debounceAuto?.cancel();
    _debounceAuto = Timer(const Duration(milliseconds: 700), () {
      _debounceAuto = null;
      if (!mounted) return;
      _calcularAutomatico(moneda, regla: regla);
    });
  }

  /// Cálculo disparado por el tecleo: sin diálogo y sin avisos repetidos.
  ///
  /// Si ya hay una tasa de hoy en memoria no se llama a la red (instantáneo);
  /// si no, se extrae mostrando el banner discreto del formulario.
  Future<void> _calcularAutomatico(
    String moneda, {
    _ReglaPrecioEditable? regla,
  }) async {
    if (!mounted || _calculandoPrecios) return;
    if (!_precioConfig.autoActivo) return;
    // Si el admin empezó a escribir antes de que llegara la config de la
    // entidad, el cálculo se reprograma al cargarla (ver `_cargarPrecioConfig`).
    if (!_configCargada) return;
    if (_monedasHabilitadas.length < 2) return;

    // Se calcula desde la moneda que el admin acaba de tocar (da igual cuál sea
    // la «de origen» de la entidad): así escribir en CUP también rellena USD.
    final origen = _monedasHabilitadas.contains(moneda)
        ? moneda
        : _origenEfectivo;

    final valor = regla == null
        ? _precioEscrito(_precioBaseCtrls[origen])
        : _primerPrecioDeRegla(regla, origen);
    if (valor == null || valor <= 0) return;

    final firma = '${regla == null ? 'base' : 'regla:${_reglasPrecio.indexOf(regla)}'}|$origen';
    if (_ultimoCalculado[firma] == valor) return;
    _ultimoCalculado[firma] = valor;

    var tasas = _tasasUsadas;
    if (tasas == null || !tasas.vigente) {
      setState(() => _extrayendoTasa = true);
      try {
        tasas = await TasaCambioService.obtener();
      } finally {
        if (mounted) setState(() => _extrayendoTasa = false);
      }
      if (!mounted) return;
    }

    if (tasas == null) {
      _avisarSinTasaUnaVez();
      return;
    }

    if (regla != null) {
      _convertirRegla(regla, origen, tasas);
    } else {
      _escribirPreciosCalculados(tasas, origen: origen, avisar: false);
    }
  }

  /// Traduce «no hay tasa» una sola vez por formulario.
  void _avisarSinTasaUnaVez() {
    if (_avisoTasaMostrado) return;
    _avisoTasaMostrado = true;
    _snack(
      'No se pudo obtener la tasa de cambio. Los precios no se han modificado.',
      color: AppTheme.error,
    );
  }

  /// Primer precio escrito en la moneda [moneda] dentro de una regla.
  double? _primerPrecioDeRegla(_ReglaPrecioEditable regla, String moneda) {
    for (final ctrls in regla.preciosPorOpcion.values) {
      final valor = _precioEscrito(ctrls[moneda]);
      if (valor != null && valor > 0) return valor;
    }
    return null;
  }

  /// Convierte **una** regla desde [origen] (la casilla que se acaba de
  /// teclear), sin tocar el precio base ni las demás reglas.
  void _convertirRegla(
    _ReglaPrecioEditable regla,
    String origen,
    TasasDia tasas,
  ) {
    setState(() {
      regla.syncMonedas(_monedasHabilitadas);
      regla.calculadas.clear();
      for (final opcion in regla.preciosPorOpcion.entries) {
        final ctrls = opcion.value;
        final base = _precioEscrito(ctrls[origen]);
        if (base == null) continue;
        for (final m in _monedasHabilitadas) {
          if (m == origen) continue;
          final valor = convertirPrecio(
            valor: base,
            origen: origen,
            destino: m,
            tasas: tasas,
            decimales: _precioConfig.decimalesDe(m),
          );
          if (valor == null) continue;
          ctrls[m]?.text = Redondeo.texto(valor, _precioConfig.decimalesDe(m));
          regla.calculadas.add('${opcion.key}|$m');
        }
      }
      _tasasUsadas = tasas;
    });
  }

  void _syncPrecioCtrls() {
    for (final m in List<String>.from(_precioBaseCtrls.keys)) {
      if (!_monedasHabilitadas.contains(m)) {
        _precioBaseCtrls.remove(m)?.dispose();
      }
    }
    for (final m in _monedasHabilitadas) {
      _precioBaseCtrls.putIfAbsent(m, () => TextEditingController());
    }
    for (final r in _reglasPrecio) {
      r.syncMonedas(_monedasHabilitadas);
    }
  }

  void _toggleMoneda(String m, bool on) {
    setState(() {
      if (on) {
        if (!_monedasHabilitadas.contains(m)) {
          _monedasHabilitadas.add(m);
        }
      } else if (_monedasHabilitadas.length > 1) {
        _monedasHabilitadas.remove(m);
        if (_monedaDefault == m) _monedaDefault = _monedasHabilitadas.first;
      }
      _syncPrecioCtrls();
    });
    // Al habilitar una moneda, su precio se rellena solo con la tasa del día
    // (si ya hay un precio escrito y el cálculo automático está activo).
    if (on) _programarCalculoAutomatico(_origenEfectivo);
  }

  @override
  void dispose() {
    _debounceAuto?.cancel();
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _campos) {
      c.dispose();
    }
    for (final c in _precioBaseCtrls.values) {
      c.dispose();
    }
    for (final r in _reglasPrecio) {
      r.dispose();
    }
    super.dispose();
  }

  /// Construye la lista de campos en formato jsonb, autogenerando claves únicas.
  /// Devuelve null si hay un campo inválido (sin etiqueta, o select sin opciones).
  List<Map<String, dynamic>>? _camposToJson() {
    // Pasada 1: calcular la clave única (slug) de cada campo, para poder
    // resolver las referencias de las reglas condicionales (si_clave).
    final claves = <_CampoEditable, String>{};
    final usadas = <String>{};
    for (final c in _campos) {
      final etiqueta = c.etiquetaCtrl.text.trim();
      if (etiqueta.isEmpty) {
        _campoError = 'Cada dato adicional necesita una etiqueta';
        return null;
      }
      var clave = CampoAdicional.slug(etiqueta);
      final base = clave;
      var n = 2;
      while (usadas.contains(clave)) {
        clave = '${base}_$n';
        n++;
      }
      usadas.add(clave);
      claves[c] = clave;
    }

    // Resuelve el slug base seleccionado en una regla a la clave final del campo.
    String? resolverSiClave(String? siBase) {
      if (siBase == null || siBase.isEmpty) return null;
      for (final c in _campos) {
        if (CampoAdicional.slug(c.etiquetaCtrl.text.trim()) == siBase) {
          return claves[c];
        }
      }
      return siBase;
    }

    // Pasada 2: construir el jsonb de cada campo.
    final out = <Map<String, dynamic>>[];
    for (final c in _campos) {
      final etiqueta = c.etiquetaCtrl.text.trim();
      final opciones = c.tipo == TipoCampo.select
          ? [...c.opciones]
          : <String>[];
      if (c.tipo == TipoCampo.select && opciones.isEmpty) {
        _campoError = '"$etiqueta": un seleccionable necesita opciones';
        return null;
      }

      // Valor por defecto fijo según el tipo.
      Object? defaultVal;
      if (c.tipo == TipoCampo.booleano) {
        if (c.defaultBool) defaultVal = true; // false == ausencia
      } else {
        final dt = c.defaultCtrl.text.trim();
        if (dt.isNotEmpty) {
          defaultVal = c.tipo == TipoCampo.numero
              ? (int.tryParse(dt) ?? dt)
              : dt;
        }
      }

      // Reglas de default condicional (se ignoran las incompletas).
      final reglasJson = <Map<String, dynamic>>[];
      for (final r in c.reglas) {
        final si = resolverSiClave(r.siClave);
        final ig = r.igualCtrl.text.trim();
        final va = r.valorCtrl.text.trim();
        if (si == null || si.isEmpty || ig.isEmpty || va.isEmpty) continue;
        reglasJson.add({
          'si_clave': si,
          'igual': ig,
          'valor': c.tipo == TipoCampo.numero ? (int.tryParse(va) ?? va) : va,
        });
      }

      out.add({
        'clave': claves[c],
        'etiqueta': etiqueta,
        'tipo': c.tipo.valor,
        'requerido': c.requerido,
        'opciones': opciones,
        if (c.min != null) 'min': c.min,
        if (c.max != null) 'max': c.max,
        if (defaultVal != null) 'default': defaultVal,
        if (c.contabilizar) 'contabilizar': true,
        if (reglasJson.isNotEmpty) 'reglas': reglasJson,
      });
    }
    _campoError = null;
    return out;
  }

  String? _campoError;

  Map<String, dynamic>? _configPrecioToJson(
    Map<_CampoEditable, String> claves,
  ) {
    final base = <String, double>{};
    for (final m in _monedasHabilitadas) {
      final t = _precioBaseCtrls[m]?.text.trim() ?? '';
      if (t.isNotEmpty) {
        // `parseMonto` entiende es-CU y en-US: "1.500" → 1500 (antes se
        // guardaba como 1,5) y "1,50" → 1,5.
        final v = parseMonto(t);
        if (v == null) {
          _campoError = 'Precio base inválido para $m';
          return null;
        }
        base[m] = v;
      }
    }

    final reglasOut = <Map<String, dynamic>>[];
    for (final r in _reglasPrecio) {
      if (r.siClave == null || r.siClave!.isEmpty) continue;

      final preciosOpcion = <String, Map<String, double>>{};
      for (final opcion in r.preciosPorOpcion.keys) {
        final pmap = <String, double>{};
        for (final m in _monedasHabilitadas) {
          final t = r.preciosPorOpcion[opcion]?[m]?.text.trim() ?? '';
          if (t.isEmpty) continue;
          // Mismo parseo que el precio base: admite "1.500" y "1,50".
          final v = parseMonto(t);
          if (v == null) {
            _campoError = 'Precio inválido para "$opcion"';
            return null;
          }
          pmap[m] = v;
        }
        if (pmap.isNotEmpty) preciosOpcion[opcion] = pmap;
      }
      if (preciosOpcion.isEmpty) continue;

      String? claveFinal;
      for (final e in claves.entries) {
        if (CampoAdicional.slug(e.key.etiquetaCtrl.text.trim()) == r.siClave ||
            e.value == r.siClave) {
          claveFinal = e.value;
          break;
        }
      }
      reglasOut.add({
        'si_clave': claveFinal ?? r.siClave,
        'precios_opcion': preciosOpcion,
      });
    }

    return ConfigPrecio(
      monedaDefault: _monedaDefault,
      monedas: _monedasHabilitadas,
      preciosBase: base,
      reglas: reglasOut.map((e) => ReglaPrecio.fromJson(e)).toList(),
      aplicaPrecioIdaVueltaTodos: _aplicaPrecioIdaVueltaTodos,
    ).toJson();
  }

  List<({String slug, String clave, String etiqueta, List<String> opciones})>
  _camposSelectParaPrecio(Map<_CampoEditable, String> claves) {
    final out =
        <
          ({String slug, String clave, String etiqueta, List<String> opciones})
        >[];
    for (final e in claves.entries) {
      final c = e.key;
      if (c.tipo != TipoCampo.select) continue;
      final etq = c.etiquetaCtrl.text.trim();
      if (etq.isEmpty || c.opciones.isEmpty) continue;
      out.add((
        slug: CampoAdicional.slug(etq),
        clave: e.value,
        etiqueta: etq,
        opciones: [...c.opciones],
      ));
    }
    return out;
  }

  Future<void> _pickImagen(ImageSource source) async {
    final file = await ImagenService.seleccionarImagen(source: source);
    if (file != null) setState(() => _imagenFile = file);
  }

  void _showImagenPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImagen(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cámara'),
              onTap: () {
                Navigator.pop(context);
                _pickImagen(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Defensa en profundidad: la foto la valida `CampoFotoObligatoria`, pero el
    // alta no puede depender de que ese campo esté montado. Sin foto no se
    // escribe nada, y menos una fila nueva.
    if (errorFotoObligatoria(
          queEs: 'servicio',
          fotoGuardada: _fotoUrl,
          archivoElegido: _imagenFile != null,
        ) !=
        null) {
      setState(() {});
      return;
    }

    if (_idTipoActividad == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la categoría del servicio'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    final campos = _camposToJson();
    if (campos == null) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_campoError ?? 'Revisa los datos adicionales'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    final claves = <_CampoEditable, String>{};
    final usadas = <String>{};
    for (final c in _campos) {
      final etiqueta = c.etiquetaCtrl.text.trim();
      if (etiqueta.isEmpty) continue;
      var clave = CampoAdicional.slug(etiqueta);
      final base = clave;
      var n = 2;
      while (usadas.contains(clave)) {
        clave = '${base}_$n';
        n++;
      }
      usadas.add(clave);
      claves[c] = clave;
    }
    final configPrecio = _configPrecioToJson(claves);
    if (configPrecio == null) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_campoError ?? 'Revisa la configuración de precio'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    final uuid = AuthService.currentUserId ?? '';
    setState(() => _saving = true);
    try {
      String? fotoFinal = _fotoUrl;
      int idServicio;
      if (widget.servicio == null) {
        // Se crea primero la fila (el path de la foto necesita su id) y después
        // se sube la imagen. Si esa subida falla, el alta se **deshace**: la foto
        // es obligatoria, así que un servicio recién creado sin ella no puede
        // quedarse en el catálogo. Antes se quedaba, en silencio.
        final nuevo = await CatalogoService.createServicio(
          nombre: _nombreCtrl.text.trim(),
          descripcion: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          idEntidad: widget.idEntidad,
          idTipoActividad: _idTipoActividad,
          activo: _activo,
        );
        idServicio = nuevo.id;
        try {
          fotoFinal = await ImagenService.subirImagen(
            imagen: _imagenFile!,
            path: ImagenService.pathServicio(nuevo.id),
          );
          await CatalogoService.updateServicio(
            id: nuevo.id,
            nombre: nuevo.nombre,
            descripcion: nuevo.descripcion,
            foto: fotoFinal,
            idTipoActividad: _idTipoActividad,
            activo: _activo,
          );
        } catch (e) {
          final deshecho = await _deshacerAlta(
            idServicio: nuevo.id,
            pathSubido: ImagenService.pathServicio(nuevo.id),
          );
          throw Exception(
            deshecho
                ? 'No se pudo guardar la foto ($e), así que el servicio no se '
                      'creó. Vuelve a intentarlo.'
                : 'No se pudo guardar la foto ($e) y el servicio quedó creado '
                      'SIN foto. Edítalo para añadirla.',
          );
        }
      } else {
        idServicio = widget.servicio!.id;
        if (_imagenFile != null) {
          fotoFinal = await ImagenService.subirImagen(
            imagen: _imagenFile!,
            path: ImagenService.pathServicio(widget.servicio!.id),
          );
        }
        await CatalogoService.updateServicio(
          id: widget.servicio!.id,
          nombre: _nombreCtrl.text.trim(),
          descripcion: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          foto: fotoFinal,
          idTipoActividad: _idTipoActividad,
          activo: _activo,
        );
      }
      // Guarda datos adicionales + flag de terceros (RPC admin)
      await CatalogoService.guardarDatosServicio(
        uuidUsuario: uuid,
        idServicio: idServicio,
        campos: campos,
        permiteTercero: _permiteTercero,
        configPrecio: configPrecio,
      );
      // [67] Interruptor de pago por adelantado de ESTE servicio. Va aparte
      // porque la RPC de arriba no lo toca (es una columna del servicio, no de
      // los datos adicionales) y así sigue valiendo con la 67 sin aplicar.
      if (_entidadCobra == true || !_cobroAdelantado) {
        // Solo se escribe si tiene sentido: no se enciende un servicio cuando la
        // entidad no cobra (quedaría sin efecto y confundiría al admin).
        await CatalogoService.setCobroAdelantado(
          id: idServicio,
          activo: _cobroAdelantado,
        );
      }
      if (!mounted) return;
      // Punto 5: se devuelve el servicio RECIÉN leído, no `true`. El detalle lo
      // usa para repintarse en el sitio sin obligar a salir y volver a entrar.
      final actualizado = await CatalogoService.getServicio(idServicio);
      // La URL guardada ya trae su propio `?v=` (ver `ImagenService.subirImagen`),
      // así que cualquier cliente descarga la foto nueva. `invalidar` queda como
      // red de seguridad para una sesión que ya tenía la URL vieja en pantalla.
      ImagenService.invalidar(actualizado.foto);
      if (!mounted) return;
      Navigator.pop(context, actualizado);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${_mensajeLegible(e)}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  /// Deshace un alta que quedó a medias: la fila se creó pero la foto no llegó a
  /// guardarse.
  ///
  /// Solo se llama desde la rama de **crear** y solo con el id que acaba de
  /// devolver `createServicio`, y antes de guardar los datos adicionales: si el
  /// que falla es `guardarDatosServicio`, el servicio ya tiene foto y no se
  /// borra (el alta se conserva y el admin puede reeditarla).
  ///
  /// El orden importa: primero se borra la fila y **después** el archivo. Si el
  /// borrado de la fila falla, el archivo se conserva — la fila sigue viva y su
  /// foto con ella, así que el admin la arregla editando. Al revés se quedaría
  /// una fila sin foto apuntando a un archivo que ya no está.
  ///
  /// Devuelve `true` si el alta quedó deshecha. Si el borrado falla, se registra
  /// y el aviso al admin cambia: hay que decirle que el servicio existe sin
  /// foto, no mentirle diciendo que no se creó.
  Future<bool> _deshacerAlta({
    required int idServicio,
    required String pathSubido,
  }) async {
    try {
      await CatalogoService.deleteServicio(idServicio);
    } catch (e) {
      debugPrint(
        '[flow] ServicioFormSheet: no se pudo deshacer el alta $idServicio: $e',
      );
      return false;
    }
    try {
      await ImagenService.eliminarImagen(pathSubido);
    } catch (e) {
      // Un archivo huérfano en el bucket es inofensivo; la fila ya no está.
      debugPrint('[flow] ServicioFormSheet: no se pudo borrar $pathSubido: $e');
    }
    return true;
  }

  void _agregarCampo() {
    setState(() => _campos.add(_CampoEditable.nuevo()));
  }

  void _quitarCampo(int i) {
    setState(() {
      _campos[i].dispose();
      _campos.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.servicio == null
                        ? 'Nuevo Servicio'
                        : 'Editar Servicio',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
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
              const SizedBox(height: 16),

              // ── Foto del servicio (obligatoria) ───────────
              // El campo valida por su cuenta: es un `FormField`, así que el
              // error de la foto sale junto a los demás al pulsar Guardar.
              CampoFotoObligatoria(
                queEs: 'servicio',
                fotoGuardada: _fotoUrl,
                archivo: _imagenFile,
                alto: 130,
                placeholder: _SrvImagePlaceholder(),
                onElegir: _showImagenPicker,
              ),
              const SizedBox(height: 8),
              if (_cargandoTiposActividad)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                )
              else ...[
                // ── Categoría + Subcategoría (migración 47) ─────────
                // Antes había un solo desplegable "Actividad". Ahora son dos
                // niveles: la categoría agrupa y la subcategoría concreta. Un
                // servicio SIN subcategoría es válido (queda en la categoría),
                // por eso el segundo desplegable no es obligatorio y solo
                // aparece si esa categoría tiene hijas.
                DropdownButtonFormField<int>(
                  initialValue: _idCategoria,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Categoría *',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: _taxonomia.raices
                      .map(
                        (categoria) => DropdownMenuItem<int>(
                          value: categoria.id,
                          child: Text(categoria.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _idCategoria = value;
                      _idSubcategoria = null;
                      // Hasta que se elija subcategoría, el servicio vive en la
                      // categoría: nunca queda sin tipo.
                      _idTipoActividad = value;
                    });
                  },
                  validator: (value) =>
                      value == null ? 'Elige una categoría' : null,
                ),
                if (_subcategoriasDeCategoria.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    // Al cambiar de categoría hay que rehacer el campo: su
                    // estado interno conservaría la subcategoría anterior, que
                    // ya no pertenece a esta categoría.
                    key: ValueKey<int?>(_idCategoria),
                    initialValue: _idSubcategoria,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Subcategoría',
                      helperText: 'Opcional. Sin ella, el servicio queda en la '
                          'categoría.',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Sin subcategoría'),
                      ),
                      ..._subcategoriasDeCategoria.map(
                        (sub) => DropdownMenuItem<int?>(
                          value: sub.id,
                          child: Text(sub.nombre),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _idSubcategoria = value;
                      _idTipoActividad = value ?? _idCategoria;
                    }),
                  ),
                ],
              ],
              const SizedBox(height: 12),

              // ── Publicación del servicio (punto 4) ─────────
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _activo,
                activeThumbColor: AppTheme.primary,
                onChanged: (v) => setState(() => _activo = v),
                title: const Text(
                  'Servicio activo',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _activo
                      ? 'Disponible en los locales donde esté vinculado.'
                      : 'Oculto en TODOS los locales: no se muestra ni se '
                            'puede reservar.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),

              TextFormField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  prefixIcon: Icon(Icons.miscellaneous_services_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),

              // ── Reservar para terceros ────────────────────
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _permiteTercero,
                onChanged: (v) => setState(() => _permiteTercero = v),
                title: const Text('Permitir reservar para terceros'),
                subtitle: const Text(
                  'El cliente podrá reservar a nombre de otra persona',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(),

              // ── Pago por adelantado (migración 67) ────────
              // El interruptor maestro está en la entidad (número de proveedor,
              // WhatsApp de verificación, moneda y plazo); aquí se decide si
              // ESTE servicio se puede pagar por adelantado.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _cobroAdelantado,
                // Sin el cobro activo en la entidad, encenderlo aquí no serviría
                // de nada: se explica en vez de dejar un switch que no hace nada.
                onChanged: _entidadCobra == true
                    ? (v) => setState(() => _cobroAdelantado = v)
                    : null,
                secondary: _entidadCobra == false
                    ? const Icon(Icons.lock_outline, size: 20)
                    : null,
                title: const Text('Pago por adelantado en línea'),
                subtitle: Text(
                  _entidadCobra == false
                      ? 'Primero actívalo para tu entidad en «Mi suscripción → '
                            'Cobro por adelantado».'
                      : 'El cliente podrá pagar este servicio con Transfermóvil '
                            'antes de la cita.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(),

              // ── Precio del servicio ───────────────────────
              TutorialAnchor(
                id: 'admin_precio',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Precio del servicio',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Monedas disponibles',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final m in MonedasApp.todas)
                          FilterChip(
                            label: Text(
                              MonedasApp.etiqueta(m),
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _monedasHabilitadas.contains(m),
                            onSelected: (v) => _toggleMoneda(m, v),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _monedaDefault,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Moneda por defecto',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: _monedasHabilitadas
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(MonedasApp.etiqueta(m)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _monedaDefault = v);
                        // Al cambiar la moneda base, el resto se recalcula desde
                        // ella de inmediato (antes había que tocar el campo de
                        // USD para que pasara algo).
                        _programarCalculoAutomatico(v);
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Esta es la moneda base: es la que escribes y de la que se '
                      'calculan las demás.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Punto 4: con un solo precio, la app calcula el resto con
                    // la tasa del día. El ancla es la del paso del tutorial.
                    TutorialAnchor(
                      id: 'admin_precio_auto',
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Precio base',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _calculandoPrecios
                                ? null
                                : () => _calcularRestoDesdeOrigen(),
                            icon: const Icon(Icons.calculate_outlined, size: 16),
                            label: Text(
                              'Calcular desde $_origenEfectivo',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Banner discreto: el cálculo automático se dispara al
                    // teclear, así que no puede abrir el diálogo modal cada vez.
                    if (_extrayendoTasa)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Extrayendo los precios automáticamente...',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_precioConfig.autoActivo && _monedasHabilitadas.length < 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Habilita otra moneda y el resto se calculará solo con '
                          'la tasa del día.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    // La moneda base va SIEMPRE primera y, al cambiarla en el
                    // desplegable, la lista se reordena con animación: se ve
                    // moverse en vez de cambiar de golpe.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.08),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        // La clave depende de la base: al cambiarla, Flutter ve
                        // otro hijo y anima el cambio de orden.
                        key: ValueKey('precios-base-$_origenEfectivo'),
                        children: [
                          for (final m in _monedasOrdenadas)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: TextField(
                                controller: _precioBaseCtrls[m],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: _decoracionPrecio(m),
                                // Cálculo automático: se dispara en CUALQUIERA
                                // de las monedas (la que el admin esté
                                // escribiendo, incluida la base) y recalcula el
                                // resto, sin pulsar nada.
                                onChanged: (_) {
                                  // Escrito a mano ⇒ este campo deja de ser
                                  // «calculado» y pierde el verde.
                                  if (_calculadas.remove(m)) setState(() {});
                                  if (_precioConfig.autoActivo) {
                                    _programarCalculoAutomatico(m);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_tasasUsadas != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Precios calculados con la tasa del '
                                '${_tasasUsadas!.fechaTexto}. Revísalos antes '
                                'de guardar: puedes cambiarlos a mano.',
                                style: const TextStyle(
                                  fontSize: 11,
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
              if (_esTransporteOmnibus) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _aplicaPrecioIdaVueltaTodos,
                  onChanged: (v) =>
                      setState(() => _aplicaPrecioIdaVueltaTodos = v ?? false),
                  title: const Text(
                    'Aplica precio de Ida y vuelta para todos los pasajes',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: const Text(
                    'Si está desactivado (recomendado), el precio del turno '
                    'combinado solo aplica cuando ida y vuelta son el mismo día. '
                    'En fechas distintas se cobran ida + vuelta por separado.',
                    style: TextStyle(fontSize: 12),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 8),
              TutorialAnchor(
                id: 'admin_reglas_precio',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Reglas de precio por dato adicional',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(
                              () => _reglasPrecio.add(
                                _ReglaPrecioEditable.nueva(_monedasHabilitadas),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Regla'),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Configura un precio distinto para cada opción del campo '
                        'seleccionable. Si dos reglas coinciden, se aplica la primera.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final claves = <_CampoEditable, String>{};
                        final usadas = <String>{};
                        for (final c in _campos) {
                          final etq = c.etiquetaCtrl.text.trim();
                          if (etq.isEmpty) continue;
                          var clave = CampoAdicional.slug(etq);
                          final base = clave;
                          var n = 2;
                          while (usadas.contains(clave)) {
                            clave = '${base}_$n';
                            n++;
                          }
                          usadas.add(clave);
                          claves[c] = clave;
                        }
                        final selects = _camposSelectParaPrecio(claves);
                        if (selects.isEmpty && _reglasPrecio.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Agrega campos tipo seleccionable para definir reglas.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (var i = 0; i < _reglasPrecio.length; i++)
                              _ReglaPrecioTile(
                                regla: _reglasPrecio[i],
                                camposSelect: selects,
                                monedas: _monedasHabilitadas,
                                onChanged: () => setState(() {}),
                                // Al teclear el precio de una opción, sus demás
                                // monedas se calculan con la tasa del día.
                                onPrecioCambiado: (moneda) =>
                                    _programarCalculoAutomatico(
                                      moneda,
                                      regla: _reglasPrecio[i],
                                    ),
                                onRemove: () {
                                  setState(() {
                                    _reglasPrecio[i].dispose();
                                    _reglasPrecio.removeAt(i);
                                  });
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Divider(),

              // ── Datos adicionales ─────────────────────────
              TutorialAnchor(
                id: 'admin_datos_adicionales',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Datos adicionales',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _agregarCampo,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                    if (_campos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Sin datos adicionales. El cliente solo verá lo básico.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    for (var i = 0; i < _campos.length; i++)
                      _CampoEditableTile(
                        key: ValueKey(_campos[i]),
                        campo: _campos[i],
                        todosCampos: _campos,
                        onChanged: () => setState(() {}),
                        onRemove: () => _quitarCampo(i),
                      ),
                    if (_campoError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _campoError!,
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              TutorialAnchor(
                id: 'admin_guardar_servicio',
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          widget.servicio == null
                              ? 'Crear Servicio'
                              : 'Guardar',
                          style: const TextStyle(fontSize: 16),
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

/// Regla editable: un campo select con precio por cada opción y moneda.
class _ReglaPrecioEditable {
  String? siClave;

  /// opción → moneda → controlador
  final Map<String, Map<String, TextEditingController>> preciosPorOpcion = {};

  /// Claves `'opcion|moneda'` cuyo precio escribió el cálculo automático: esos
  /// campos se pintan en verde con su icono. Se limpia al recalcular y al
  /// editar el campo a mano.
  final Set<String> calculadas = {};

  _ReglaPrecioEditable({this.siClave});

  factory _ReglaPrecioEditable.nueva(List<String> monedas) =>
      _ReglaPrecioEditable();

  factory _ReglaPrecioEditable.fromModel(
    ReglaPrecio r, {
    required List<String> monedas,
    List<String>? opcionesCampo,
  }) {
    final editable = _ReglaPrecioEditable(siClave: r.siClave);
    final opciones = opcionesCampo ?? r.preciosOpcion.keys.toList();
    editable.syncCampo(opciones, monedas);
    for (final opcion in r.preciosOpcion.entries) {
      for (final precio in opcion.value.entries) {
        final ctrl = editable.preciosPorOpcion[opcion.key]?[precio.key];
        if (ctrl == null) continue;
        final v = precio.value;
        // Mismo motivo que `_fmtPrecio`: nunca `v.toString()` (3 decimales se
        // releen como millares).
        ctrl.text = v == 0 ? '' : Redondeo.texto(v, Redondeo.maxDecimales);
      }
    }
    return editable;
  }

  void syncCampo(List<String> opciones, List<String> monedas) {
    for (final o in List<String>.from(preciosPorOpcion.keys)) {
      if (!opciones.contains(o)) {
        for (final c in preciosPorOpcion[o]!.values) {
          c.dispose();
        }
        preciosPorOpcion.remove(o);
        calculadas.removeWhere((k) => k.startsWith('$o|'));
      }
    }
    for (final o in opciones) {
      preciosPorOpcion.putIfAbsent(o, () => {});
      final map = preciosPorOpcion[o]!;
      for (final m in List<String>.from(map.keys)) {
        if (!monedas.contains(m)) map.remove(m)?.dispose();
      }
      for (final m in monedas) {
        map.putIfAbsent(m, () => TextEditingController());
      }
    }
  }

  void syncMonedas(List<String> monedas) {
    syncCampo(preciosPorOpcion.keys.toList(), monedas);
  }

  void dispose() {
    for (final map in preciosPorOpcion.values) {
      for (final c in map.values) {
        c.dispose();
      }
    }
    preciosPorOpcion.clear();
  }
}

class _ReglaPrecioTile extends StatefulWidget {
  final _ReglaPrecioEditable regla;
  final List<
    ({String slug, String clave, String etiqueta, List<String> opciones})
  >
  camposSelect;
  final List<String> monedas;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  /// Se llama al teclear un precio de la regla, con la moneda tocada: así el
  /// cálculo automático también rellena las demás monedas de esa regla.
  final ValueChanged<String>? onPrecioCambiado;

  const _ReglaPrecioTile({
    required this.regla,
    required this.camposSelect,
    required this.monedas,
    required this.onChanged,
    required this.onRemove,
    this.onPrecioCambiado,
  });

  @override
  State<_ReglaPrecioTile> createState() => _ReglaPrecioTileState();
}

class _ReglaPrecioTileState extends State<_ReglaPrecioTile> {
  ({String slug, String clave, String etiqueta, List<String> opciones})?
  _campoActual() {
    for (final c in widget.camposSelect) {
      if (c.slug == widget.regla.siClave || c.clave == widget.regla.siClave) {
        return c;
      }
    }
    return null;
  }

  void _syncOpciones() {
    final campo = _campoActual();
    widget.regla.syncCampo(campo?.opciones ?? [], widget.monedas);
  }

  /// Igual que en el precio base: si el precio de esta opción lo puso el cálculo
  /// automático, el cuadro sale en verde con el icono dentro.
  InputDecoration _decoracionPrecio(String opcion, String m) {
    final calculada = widget.regla.calculadas.contains('$opcion|$m');
    return InputDecoration(
      labelText: 'Precio (${MonedasApp.simbolo(m)})',
      isDense: true,
      fillColor: calculada ? AppTheme.success.withValues(alpha: 0.07) : null,
      border: const OutlineInputBorder(),
      enabledBorder: calculada
          ? const OutlineInputBorder(
              borderSide: BorderSide(color: AppTheme.success, width: 1.5),
            )
          : null,
      focusedBorder: calculada
          ? const OutlineInputBorder(
              borderSide: BorderSide(color: AppTheme.success, width: 1.8),
            )
          : null,
      suffixIcon: calculada
          ? const Tooltip(
              message: 'Calculado con la tasa del día',
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppTheme.success,
              ),
            )
          : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _syncOpciones();
  }

  @override
  void didUpdateWidget(covariant _ReglaPrecioTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOpciones();
  }

  @override
  Widget build(BuildContext context) {
    final campoActual = _campoActual();
    final opcionesDisp = campoActual?.opciones ?? const <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value:
                      widget.camposSelect.any(
                        (c) => c.slug == widget.regla.siClave,
                      )
                      ? widget.regla.siClave
                      : (widget.camposSelect.any(
                              (c) => c.clave == widget.regla.siClave,
                            )
                            ? widget.camposSelect
                                  .firstWhere(
                                    (c) => c.clave == widget.regla.siClave,
                                  )
                                  .slug
                            : null),
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Campo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: widget.camposSelect
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.slug,
                          child: Text(
                            c.etiqueta,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    widget.regla.siClave = v;
                    _syncOpciones();
                    widget.onChanged();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppTheme.error),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          if (opcionesDisp.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Selecciona un campo con opciones definidas.',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            )
          else
            for (final opcion in opcionesDisp) ...[
              const Divider(height: 16),
              Text(
                opcion,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (final m in widget.monedas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TextField(
                    controller: widget.regla.preciosPorOpcion[opcion]?[m],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoracionPrecio(opcion, m),
                    onChanged: (_) {
                      // Escrito a mano ⇒ deja de estar «calculado».
                      widget.regla.calculadas.remove('$opcion|$m');
                      widget.onChanged();
                      widget.onPrecioCambiado?.call(m);
                    },
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

/// Estado mutable de una regla de default condicional mientras se edita.
class _ReglaEditable {
  String? siClave; // slug base del campo del que depende (etiqueta -> slug)
  final TextEditingController igualCtrl;
  final TextEditingController valorCtrl;

  _ReglaEditable({this.siClave, String igual = '', String valor = ''})
    : igualCtrl = TextEditingController(text: igual),
      valorCtrl = TextEditingController(text: valor);

  void dispose() {
    igualCtrl.dispose();
    valorCtrl.dispose();
  }
}

/// Estado mutable de un campo adicional mientras se edita en el formulario.
class _CampoEditable {
  final TextEditingController etiquetaCtrl;
  List<String> opciones;
  TipoCampo tipo;
  bool requerido;
  int? min;
  int? max;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;

  // Datos adicionales nuevos: default, contabilizar, reglas.
  final TextEditingController defaultCtrl; // default para texto/numero/select
  bool defaultBool; // default para booleano
  bool contabilizar;
  final List<_ReglaEditable> reglas;

  _CampoEditable({
    required String etiqueta,
    required this.tipo,
    required this.requerido,
    required List<String> opciones,
    this.min,
    this.max,
    String defaultTexto = '',
    this.defaultBool = false,
    this.contabilizar = false,
    List<_ReglaEditable>? reglas,
  }) : etiquetaCtrl = TextEditingController(text: etiqueta),
       opciones = [...opciones],
       minCtrl = TextEditingController(text: min?.toString() ?? ''),
       maxCtrl = TextEditingController(text: max?.toString() ?? ''),
       defaultCtrl = TextEditingController(text: defaultTexto),
       reglas = reglas ?? [];

  factory _CampoEditable.nuevo() => _CampoEditable(
    etiqueta: '',
    tipo: TipoCampo.texto,
    requerido: false,
    opciones: [],
  );

  factory _CampoEditable.fromModel(CampoAdicional c) => _CampoEditable(
    etiqueta: c.etiqueta,
    tipo: c.tipo,
    requerido: c.requerido,
    opciones: c.opciones,
    min: c.min,
    max: c.max,
    defaultTexto: c.tipo == TipoCampo.booleano
        ? ''
        : (c.valorDefault?.toString() ?? ''),
    defaultBool:
        c.tipo == TipoCampo.booleano &&
        DatosAdicionalesBoolParse.asBool(c.valorDefault),
    contabilizar: c.contabilizar,
    reglas: c.reglas
        .map(
          (r) => _ReglaEditable(
            siClave: r.siClave,
            igual: r.igual,
            valor: r.valor.toString(),
          ),
        )
        .toList(),
  );

  void dispose() {
    etiquetaCtrl.dispose();
    minCtrl.dispose();
    maxCtrl.dispose();
    defaultCtrl.dispose();
    for (final r in reglas) {
      r.dispose();
    }
  }
}

/// Pequeño helper para interpretar un default booleano guardado como bool o texto.
class DatosAdicionalesBoolParse {
  static bool asBool(Object? v) {
    if (v is bool) return v;
    final s = v?.toString().toLowerCase().trim();
    return s == 'true' || s == 'sí' || s == 'si' || s == '1';
  }
}

/// Tarjeta editable para un campo adicional (etiqueta, tipo, requerido, opciones,
/// min/max, valor por defecto, contabilizar y reglas de default condicional).
class _CampoEditableTile extends StatelessWidget {
  final _CampoEditable campo;
  final List<_CampoEditable> todosCampos;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _CampoEditableTile({
    super.key,
    required this.campo,
    required this.todosCampos,
    required this.onChanged,
    required this.onRemove,
  });

  /// Opciones del dropdown "depende de": los demás campos con etiqueta no vacía.
  List<DropdownMenuItem<String>> _otrosCamposItems() {
    final items = <DropdownMenuItem<String>>[];
    for (final c in todosCampos) {
      if (identical(c, campo)) continue;
      final etq = c.etiquetaCtrl.text.trim();
      if (etq.isEmpty) continue;
      items.add(
        DropdownMenuItem(
          value: CampoAdicional.slug(etq),
          child: Text(etq, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return items;
  }

  Widget _buildDefault() {
    if (campo.tipo == TipoCampo.booleano) {
      return Row(
        children: [
          const Text('Valor por defecto', style: TextStyle(fontSize: 13)),
          const Spacer(),
          Switch(
            value: campo.defaultBool,
            onChanged: (v) {
              campo.defaultBool = v;
              onChanged();
            },
          ),
        ],
      );
    }
    if (campo.tipo == TipoCampo.select) {
      final opciones = campo.opciones;
      final current = campo.defaultCtrl.text.trim();
      return DropdownButtonFormField<String>(
        value: opciones.contains(current) ? current : null,
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Valor por defecto',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('— Ninguno —')),
          ...opciones.map((o) => DropdownMenuItem(value: o, child: Text(o))),
        ],
        onChanged: (v) {
          campo.defaultCtrl.text = v ?? '';
          onChanged();
        },
      );
    }
    return TextField(
      controller: campo.defaultCtrl,
      keyboardType: campo.tipo == TipoCampo.numero
          ? TextInputType.number
          : TextInputType.text,
      decoration: const InputDecoration(
        labelText: 'Valor por defecto',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => onChanged(),
    );
  }

  Widget _buildReglas() {
    final otros = _otrosCamposItems();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Default según otro campo',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: otros.isEmpty
                  ? null
                  : () {
                      campo.reglas.add(_ReglaEditable());
                      onChanged();
                    },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Regla'),
            ),
          ],
        ),
        if (otros.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Agrega otros campos para poder condicionar.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        for (var i = 0; i < campo.reglas.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Si ', style: TextStyle(fontSize: 12)),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: otros.any((o) => o.value == campo.reglas[i].siClave)
                        ? campo.reglas[i].siClave
                        : null,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    hint: const Text('campo', style: TextStyle(fontSize: 12)),
                    items: otros,
                    onChanged: (v) {
                      campo.reglas[i].siClave = v;
                      onChanged();
                    },
                  ),
                ),
                const Text(' = ', style: TextStyle(fontSize: 12)),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: campo.reglas[i].igualCtrl,
                    decoration: const InputDecoration(
                      hintText: 'valor',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const Text(' → ', style: TextStyle(fontSize: 12)),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: campo.reglas[i].valorCtrl,
                    decoration: const InputDecoration(
                      hintText: 'default',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: AppTheme.error,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    campo.reglas[i].dispose();
                    campo.reglas.removeAt(i);
                    onChanged();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: campo.etiquetaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Etiqueta',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppTheme.error,
                  size: 20,
                ),
                onPressed: onRemove,
                tooltip: 'Quitar',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TipoCampo>(
                  value: campo.tipo,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: TipoCampo.values
                      .map(
                        (t) =>
                            DropdownMenuItem(value: t, child: Text(t.etiqueta)),
                      )
                      .toList(),
                  onChanged: (t) {
                    if (t != null) {
                      campo.tipo = t;
                      onChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Checkbox(
                      value: campo.requerido,
                      onChanged: (v) {
                        campo.requerido = v ?? false;
                        onChanged();
                      },
                    ),
                    const Flexible(child: Text('Requerido')),
                  ],
                ),
              ),
            ],
          ),
          if (campo.tipo == TipoCampo.select) ...[
            const SizedBox(height: 8),
            OpcionesListEditor(
              opciones: campo.opciones,
              onChanged: (next) {
                campo.opciones = next;
                onChanged();
              },
            ),
          ],
          if (campo.tipo == TipoCampo.numero ||
              campo.tipo == TipoCampo.texto) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: campo.minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: campo.tipo == TipoCampo.numero
                          ? 'Mín. dígitos'
                          : 'Mín. caracteres',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => campo.min = int.tryParse(v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: campo.maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: campo.tipo == TipoCampo.numero
                          ? 'Máx. dígitos'
                          : 'Máx. caracteres',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => campo.max = int.tryParse(v.trim()),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          _buildDefault(),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(
                value: campo.contabilizar,
                onChanged: (v) {
                  campo.contabilizar = v ?? false;
                  onChanged();
                },
              ),
              const Flexible(
                child: Text(
                  'Totalizar en reportes',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const Divider(height: 12),
          _buildReglas(),
        ],
      ),
    );
  }
}

class _SrvImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.miscellaneous_services_outlined,
            size: 36,
            color: AppTheme.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Toca para agregar imagen',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip "Inactivo" de la lista de servicios (punto 4).
class _SrvChipInactivo extends StatelessWidget {
  const _SrvChipInactivo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Inactivo',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.warning,
        ),
      ),
    );
  }
}

/// Quita el prefijo `Exception: ` que Dart añade en `toString()`, para que el
/// aviso al admin se lea como el mensaje real y no como un volcado técnico.
String _mensajeLegible(Object e) {
  const prefijo = 'Exception: ';
  final texto = e.toString();
  return texto.startsWith(prefijo) ? texto.substring(prefijo.length) : texto;
}
