import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/campo_adicional.dart';
import '../../models/precio_config.dart';
import '../../models/servicio.dart';
import '../../services/auth_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/precio_config_service.dart';
import '../../widgets/precios_servicio_editor.dart';
import '../../widgets/switch_cobro_adelantado.dart';
import 'precio_config_screen.dart';

/// Pestaña «Precios» de un par local-servicio (cuerpo de `TabBarView`).
///
/// Es el bloque de precios del SERVICIO —el que vive en
/// `app_dat_servicios.config_precio`— accesible sin abrir «Editar servicio».
/// No es una pantalla propia: la AppBar y el TabBar los pone
/// `LocalServicioAdminScreen`, así que aquí solo va el cuerpo más el FAB de
/// guardar.
///
/// Importante para quien lea esto: aunque se abra desde UN local, estos precios
/// son del servicio y se comparten con todos los locales donde se ofrezca. Por
/// eso la cabecera lo dice explícitamente.
///
/// La UI y la lógica del bloque (monedas, precio base, cálculo automático con
/// la tasa del día y reglas por dato adicional) NO se reimplementan aquí: las
/// aporta `lib/widgets/precios_servicio_editor.dart`, el mismo editor que usa
/// «Editar servicio». Esta pestaña solo lo hospeda, carga la configuración de
/// la entidad, persiste y avisa.
class PreciosServicioTab extends StatefulWidget {
  /// Entidad dueña del servicio; de ella sale la configuración de precios
  /// automáticos (`flow.precio_config`).
  final int idEntidad;

  /// Servicio del par. `null` cuando el host no pudo cargar el par: sin
  /// servicio no hay `config_precio` que editar, así que se pinta un vacío.
  final Servicio? servicio;

  /// Nombre del local, solo para el texto de contexto de la cabecera.
  final String nombreLocal;

  /// Servicio de transporte: el editor muestra la casilla de «ida y vuelta».
  final bool esTransporteOmnibus;

  /// El host relee el par y marca que hubo cambios (los precios son del
  /// servicio, así que también afectan a las otras pestañas y a la lista de
  /// origen).
  final VoidCallback? onGuardado;

  const PreciosServicioTab({
    super.key,
    required this.idEntidad,
    required this.servicio,
    required this.nombreLocal,
    required this.esTransporteOmnibus,
    this.onGuardado,
  });

  @override
  State<PreciosServicioTab> createState() => _PreciosServicioTabState();
}

class _PreciosServicioTabState extends State<PreciosServicioTab> {
  late PreciosServicioControlador _ctrl;

  /// «Foto» serializada del `config_precio` con el que se construyó [_ctrl].
  ///
  /// Se compara en [didUpdateWidget] para detectar cambios hechos FUERA de esta
  /// pestaña (el menú «Editar servicio» del host). Se serializa a JSON en vez de
  /// comparar los objetos porque [ConfigPrecio] no implementa `==`.
  late String _configInicialJson;

  /// Cambia cada vez que se rehace el controlador.
  ///
  /// Va como `key` del editor: así Flutter tira el `State` viejo (con sus
  /// `TextEditingController` y sus valores) y monta uno nuevo leyendo el
  /// controlador nuevo, sin depender de que el editor sepa reaccionar a un
  /// cambio de controlador.
  int _generacion = 0;

  /// Configuración de precios de la entidad, solo para el subtítulo del pie.
  PrecioConfig _configEntidad = const PrecioConfig();
  bool _configCargada = false;

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // El MISMO controlador que usa el formulario de servicio: así esta pestaña
    // no duplica el cálculo automático ni las reglas por dato adicional.
    //
    // `proponerMonedaOrigen` se deja en false a propósito: solo tiene sentido al
    // CREAR un servicio (para proponer la moneda de la entidad). Aquí el
    // servicio ya existe y su moneda base ya está decidida.
    _configInicialJson = _fotoConfig(widget.servicio);
    _ctrl = PreciosServicioControlador(
      configInicial: widget.servicio?.configPrecio,
      camposSelect: _camposSelect(),
    );
    _cargarConfigEntidad();
  }

  /// Reacciona a un servicio nuevo que llega del host.
  ///
  /// La pestaña vive dentro de un `TabBarView`, así que su `State` NO se
  /// reinicia al cambiar de pestaña. El host (`LocalServicioAdminScreen`) tiene
  /// «⋮ → Editar servicio», que abre `ServicioFormSheet` y al guardar hace
  /// `setState(() => _ls = _ls.copyWith(servicio: actualizado))`. Sin esto, el
  /// controlador seguiría con los precios VIEJOS y pulsar «Guardar precios»
  /// sobrescribiría el cambio recién hecho con datos obsoletos.
  @override
  void didUpdateWidget(PreciosServicioTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    // `esTransporteOmnibus` es parámetro del WIDGET (no del controlador): el
    // editor lo lee de `widget`, así que este rebuild ya lo aplica. Nada que
    // recrear por ese lado.

    final cambioDeServicio = widget.servicio?.id != oldWidget.servicio?.id;
    final cambioDeConfig = _fotoConfig(widget.servicio) != _configInicialJson;
    if (!cambioDeServicio && !cambioDeConfig) return;

    // El admin tiene precios a medio editar en esta pestaña: NO se pisan. Si
    // rehiciéramos el controlador perdería lo escrito sin avisar, y el chip de
    // «cambios sin guardar» ya le está diciendo que tiene algo pendiente. Si
    // guarda, su versión es la que queda (es la que está viendo).
    if (_ctrl.hayCambios) return;

    _recrearControlador();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Foto serializada del `config_precio` del servicio, para comparar.
  String _fotoConfig(Servicio? servicio) =>
      jsonEncode(servicio?.configPrecio.toJson() ?? const <String, dynamic>{});

  /// Rehace el controlador con el servicio que acaba de llegar del host.
  ///
  /// La configuración de la entidad NO depende del servicio: se le aplica ya la
  /// última leída para que el editor no arranque ni un frame con los valores por
  /// defecto, y acto seguido se relee por si otra pantalla la cambió mientras
  /// tanto (el host pudo pasar por «Editar servicio»).
  void _recrearControlador() {
    final viejo = _ctrl;
    _ctrl = PreciosServicioControlador(
      configInicial: widget.servicio?.configPrecio,
      camposSelect: _camposSelect(),
    );
    if (_configCargada) _ctrl.actualizarConfigEntidad(_configEntidad);
    _configInicialJson = _fotoConfig(widget.servicio);
    _generacion++;
    // Se libera el viejo DESPUÉS de tener el nuevo: el `build` de este mismo
    // frame corre después de `didUpdateWidget` y ya usará el nuevo.
    viejo.dispose();
    // Relectura de la config de la entidad. Aunque ya se haya aplicado la
    // cacheada arriba, aquí se vuelve a pedir porque otra pantalla pudo
    // cambiarla mientras esta pestaña estaba montada. No hay bucle: el
    // `setState` de `_cargarConfigEntidad` solo provoca `build`, y
    // `didUpdateWidget` únicamente lo dispara el padre al reconstruir con otro
    // widget.
    _cargarConfigEntidad();
  }

  /// Campos seleccionables del servicio que pueden llevar reglas de precio.
  ///
  /// Solo los `select` con opciones: una regla se define «si este campo vale
  /// X», y sin opciones no hay nada que elegir. El slug sale de la etiqueta
  /// (como se guardaba antes en `si_clave`); la clave final es la del campo en
  /// `campos_adicionales`, que es la que viaja al `config_precio` guardado.
  List<CampoSelectPrecio> _camposSelect() {
    final campos = widget.servicio?.camposAdicionales ?? const <CampoAdicional>[];
    return <CampoSelectPrecio>[
      for (final c in campos)
        if (c.tipo == TipoCampo.select && c.opciones.isNotEmpty)
          (
            slug: CampoAdicional.slug(c.etiqueta),
            clave: c.clave,
            etiqueta: c.etiqueta,
            opciones: <String>[...c.opciones],
          ),
    ];
  }

  /// Lee la configuración de precios de la entidad (redondeo + automático).
  ///
  /// Se usa `getSeguro` porque la pestaña no puede quedarse en blanco si la
  /// migración 60 aún no está aplicada: con los valores por defecto el editor
  /// sigue funcionando. [PrecioConfigService.getSeguro] no lanza.
  Future<void> _cargarConfigEntidad() async {
    final config = await PrecioConfigService.getSeguro(widget.idEntidad);
    if (!mounted) return;
    setState(() {
      _configEntidad = config;
      _configCargada = true;
      _ctrl.actualizarConfigEntidad(config);
    });
  }

  /// Abre los ajustes de precios automáticos de la entidad y, al volver,
  /// recarga la configuración.
  ///
  /// Al volver hay que releerla: la pantalla puede haber cambiado el redondeo
  /// o apagado el cálculo automático, y el editor tiene que recalcular con eso.
  Future<void> _abrirConfigEntidad() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrecioConfigScreen(
          idEntidad: widget.idEntidad,
          // Aquí solo se conoce el local; el subtítulo de la pantalla sirve
          // para dar contexto de dónde se está configurando.
          denominacion: widget.nombreLocal,
        ),
      ),
    );
    if (!mounted) return;
    await _cargarConfigEntidad();
  }

  /// Estado actual de la config de la entidad, para el subtítulo del pie.
  String _resumenConfigEntidad() {
    if (!_configCargada) return 'Leyendo la configuración de la entidad…';
    final c = _configEntidad;
    final auto = c.autoActivo
        ? 'cálculo automático activo'
        : 'cálculo automático apagado';
    return 'Ahora: $auto, se escribe desde ${c.monedaOrigen}, con '
        '${c.redondeoCup} decimales en CUP y ${c.redondeoDivisa} en divisas.';
  }

  /// Guarda SOLO los precios del servicio.
  ///
  /// Va por la RPC `flow.admin_guardar_datos_servicio`
  /// (`docs/flow_schema/rpc admin/10_admin_config_datos_servicio.sql`), que
  /// hace `set campos_adicionales = coalesce(p_campos,'[]'),
  /// permite_tercero = ..., config_precio = ...`: **sobrescribe los tres
  /// campos** que recibe, no solo el precio.
  ///
  /// Por eso los datos adicionales se leen crudos con
  /// [CatalogoService.getDatosServicioBrutos] justo antes de guardar y se
  /// devuelven tal cual. Si se regeneraran desde el modelo ([Servicio] →
  /// [CampoAdicional.toJson]) se perdería toda clave del jsonb que el modelo no
  /// conozca (reglas escritas a mano, campos de versiones más nuevas) y editar
  /// un precio borraría datos adicionales del servicio.
  Future<void> _guardar() async {
    final servicio = widget.servicio;
    if (servicio == null || _guardando) return;

    final config = _ctrl.construir();
    if (config == null) {
      // `construir` ya dejó el motivo en `error` (un precio ilegible).
      _avisar(_ctrl.error ?? 'Revisa los precios', error: true);
      return;
    }

    setState(() => _guardando = true);
    try {
      final brutos = await CatalogoService.getDatosServicioBrutos(servicio.id);
      await CatalogoService.guardarDatosServicio(
        uuidUsuario: AuthService.currentUserId ?? '',
        idServicio: servicio.id,
        campos: brutos.campos,
        permiteTercero: brutos.permiteTercero,
        configPrecio: config.toJson(),
      );
      if (!mounted) return;
      // Se guardó: el editor deja de estar «sucio» y el host relee el par para
      // que las otras pestañas no pinten el precio viejo.
      _ctrl.marcarComoGuardado();
      // La foto se actualiza con lo que se acaba de persistir: cuando el host
      // devuelva el servicio releído, `didUpdateWidget` no debe creer que
      // cambió por fuera y rehacer el controlador.
      _configInicialJson = jsonEncode(config.toJson());
      widget.onGuardado?.call();
      _avisar(
        'Precios guardados. Se aplican a todos los locales donde se ofrece '
        'este servicio.',
      );
    } catch (e) {
      if (mounted) {
        _avisar('$e'.replaceFirst('Exception: ', ''), error: true);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: error ? AppTheme.error : AppTheme.success,
        ),
      );
  }

  Widget _fab() => FloatingActionButton.extended(
    // Etiqueta única: la pestaña vecina («Promociones», embebida) también
    // pinta un FAB y `TabBarView` puede tener las dos páginas montadas a la
    // vez durante un swipe. Sin `heroTag` propio, Flutter lanza «multiple
    // heroes share the same tag» al cambiar de ruta en esa ventana.
    heroTag: 'precios-servicio-fab',
    onPressed: _guardando ? null : _guardar,
    // El FAB sin `onPressed` no se atenúa solo: se oscurece a mano mientras
    // guarda para que se note que está deshabilitado.
    backgroundColor: _guardando
        ? AppTheme.primary.withValues(alpha: 0.6)
        : AppTheme.primary,
    foregroundColor: Colors.white,
    icon: _guardando
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : const Icon(Icons.save_outlined),
    label: Text(_guardando ? 'Guardando…' : 'Guardar precios'),
  );

  @override
  Widget build(BuildContext context) {
    final servicio = widget.servicio;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      // Embebida: sin AppBar propia (la pone el host, con su TabBar).
      appBar: null,
      // Sin servicio no hay nada que guardar: se oculta el FAB para no dejar un
      // botón muerto al lado del vacío.
      floatingActionButton: servicio == null ? null : _fab(),
      body: ListView(
        // 96 abajo para que el FAB no tape el último bloque.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: servicio == null
            ? const [_Vacio()]
            : [
                _Explicacion(
                  nombreServicio: servicio.nombre,
                  nombreLocal: widget.nombreLocal,
                ),
                // El pago por adelantado es dinero y se pide aquí también (no
                // solo en «Configuración» y en el formulario): quien está
                // ajustando precios es quien suele querer activarlo. Guarda al
                // instante con su propio aviso, así no depende del botón
                // «Guardar precios» (que persiste precios, no este flag).
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: SwitchCobroAdelantado(
                    idServicio: servicio.id,
                    idEntidad: widget.idEntidad,
                    valorInicial: servicio.cobroAdelantado,
                    // El host relee el par: así las demás pestañas y el
                    // formulario ven el valor recién guardado.
                    onGuardado: (_) => widget.onGuardado?.call(),
                  ),
                ),
                // Se repinta con el controlador: el chip aparece y desaparece
                // según lo que el editor vaya tocando, sin que esta pestaña
                // tenga que escuchar cada campo.
                ListenableBuilder(
                  listenable: _ctrl,
                  builder: (context, _) => _ctrl.hayCambios
                      ? const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: _ChipCambios(),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                PreciosServicioEditor(
                  // Cambia cuando se rehace el controlador: obliga a montar un
                  // editor nuevo en vez de reutilizar el `State` viejo con los
                  // valores anteriores.
                  key: ValueKey<int>(_generacion),
                  controlador: _ctrl,
                  // Servicio de transporte: el editor enseña la casilla de
                  // «ida y vuelta» que lee este flag del widget, no del
                  // controlador.
                  esTransporteOmnibus: widget.esTransporteOmnibus,
                ),
                const SizedBox(height: 20),
                _PieConfigEntidad(
                  resumen: _resumenConfigEntidad(),
                  onTap: _abrirConfigEntidad,
                ),
              ],
      ),
    );
  }
}

/// Cabecera que explica de qué son estos precios y a quién afectan.
class _Explicacion extends StatelessWidget {
  final String nombreServicio;
  final String nombreLocal;

  const _Explicacion({
    required this.nombreServicio,
    required this.nombreLocal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreServicio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Estos son los precios del SERVICIO: se aplican a todos los '
                  'locales donde se ofrece «$nombreServicio», también en '
                  '«$nombreLocal». Siguen estando en «Editar servicio» (menú de '
                  'arriba); las promociones de este local se editan en su '
                  'pestaña.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.35,
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

/// Indicador discreto de que hay precios tocados sin guardar.
class _ChipCambios extends StatelessWidget {
  const _ChipCambios();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 18, color: AppTheme.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Cambios sin guardar',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            'Pulsa «Guardar precios»',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Acceso a la configuración de precios automáticos de la entidad.
///
/// Va al final y con un pie propio (y no un botón más del editor) porque NO es
/// un dato del servicio: aplica a todos los servicios de la entidad.
class _PieConfigEntidad extends StatelessWidget {
  final String resumen;
  final Future<void> Function() onTap;

  const _PieConfigEntidad({required this.resumen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.border),
      ),
      child: ListTile(
        leading: const Icon(
          Icons.settings_suggest_outlined,
          color: AppTheme.primary,
        ),
        title: const Text('Precios automáticos de la entidad'),
        subtitle: Text(
          'Ahí se decide si el cálculo con la tasa del día es automático y los '
          'decimales de CUP y divisas.\n$resumen',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Estado vacío cuando el host no pudo cargar el par.
class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 38,
            color: AppTheme.textSecondary,
          ),
          SizedBox(height: 10),
          Text(
            'No se pudo cargar el servicio',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text(
            'Los precios viven en el servicio, así que sin él no hay nada que '
            'editar. Vuelve a la lista de locales y servicios y entra de nuevo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
