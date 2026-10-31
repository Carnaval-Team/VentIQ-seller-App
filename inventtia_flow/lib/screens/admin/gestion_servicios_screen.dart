import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_theme.dart';
import '../../models/campo_adicional.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../services/auth_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/cobro_service.dart';
import '../../services/imagen_service.dart';
import '../../services/precio_config_service.dart';
import '../../services/tipo_actividad_service.dart';
import '../../tutorial/tutorial_anchor.dart';
import '../../utils/foto_obligatoria.dart';
import '../../widgets/campo_foto_obligatoria.dart';
import '../../widgets/opciones_list_editor.dart';
import '../../widgets/precios_servicio_editor.dart';
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
  ///
  /// OJO: el `Servicio` con el que se abre el formulario **no siempre trae este
  /// dato**. El listado del local usa `cliente_obtener_servicios`, un payload de
  /// cliente que no incluye `cobro_adelantado` (migración 67), así que el modelo
  /// lo deja en `false`. Si se guardara sin más, editar cualquier cosa apagaría
  /// el cobro sin avisar. Por eso `_reconciliarCobro()` relee la fila admin al
  /// abrir, y `_submit` no escribe si el valor no es de fiar.
  bool _cobroAdelantado = false;

  /// El admin tocó el interruptor en ESTA edición: su valor manda sobre la
  /// relectura (que puede llegar después y no debe pisarlo).
  bool _cobroTocado = false;

  /// El valor se leyó de la fila real (`app_dat_servicios`): es de fiar y se
  /// puede escribir tal cual.
  bool _cobroCargado = false;

  /// ¿La entidad tiene activo el cobro por adelantado? `null` = todavía no se
  /// sabe (mientras se lee la configuración).
  ///
  /// Ya **no** bloquea el switch del servicio: solo decide qué subtítulo se
  /// muestra, porque el flag de este servicio se guarda siempre y un servicio
  /// marcado con el maestro apagado queda a la espera (P1-3).
  bool? _entidadCobra;
  late List<_CampoEditable> _campos;

  /// Estado y lógica del bloque de precios, en el editor compartido.
  ///
  /// Aquí vivía una copia local del bloque (monedas, precios base, cálculo
  /// automático con la tasa del día y reglas por dato adicional); ahora es la
  /// única fuente de verdad, compartida con la pestaña «Precios». Se crea en
  /// `initState` porque necesita `_campos` ya montados.
  late final PreciosServicioControlador _precios;

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
    // El editor compartido arranca con lo guardado en el servicio (o con sus
    // valores por defecto) y con los campos seleccionables ya resueltos.
    _precios = PreciosServicioControlador(
      configInicial: widget.servicio?.configPrecio,
      camposSelect: _camposSelectParaPrecio(),
      proponerMonedaOrigen: widget.servicio == null,
    );
    _cargarPrecioConfig();
    _cargarCobroEntidad();
    _reconciliarCobro();
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

  /// [67] Lee si la **entidad** tiene activo el cobro por adelantado.
  ///
  /// Es el interruptor maestro: aporta la cuenta que cobra (número de proveedor,
  /// WhatsApp de verificación, moneda y plazo). Sin él el servicio no se ofrece,
  /// por eso se avisa en el subtítulo; el switch se deja usable de todos modos
  /// para poder marcar y, sobre todo, **desmarcar** un servicio (P1-3).
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

  /// Corrige el interruptor de pago por adelantado con la fila **real**.
  ///
  /// El `Servicio` que recibe el formulario no siempre trae `cobro_adelantado`:
  /// el camino `local → servicio → ⋮ editar` arrastra el payload de
  /// `cliente_obtener_servicios`, que no incluye esa columna (migración 67), y
  /// `Servicio.fromJson` la deja en `false`. Sin esta relectura, abrir el
  /// formulario enseñaría el switch apagado y guardar lo apagaría de verdad.
  ///
  /// Es una lectura de UNA fila (`CatalogoService.getServicio`, que sí trae la
  /// columna). Si falla, `_cobroCargado` sigue en `false` y `_submit` se
  /// abstiene de escribir: mejor no tocar el flag que apagarlo a ciegas.
  Future<void> _reconciliarCobro() async {
    final id = widget.servicio?.id;
    if (id == null) {
      // Alta: no hay nada guardado que corregir; el valor del formulario manda.
      _cobroCargado = true;
      return;
    }
    try {
      final fresco = await CatalogoService.getServicio(id);
      if (!mounted) return;
      setState(() {
        _cobroCargado = true;
        // Si el admin ya tocó el switch, su elección manda.
        if (!_cobroTocado) _cobroAdelantado = fresco.cobroAdelantado;
      });
    } catch (_) {
      // Sin red o sin permiso de lectura: se deja el valor que vino y no se
      // escribirá (ver `_submit`).
    }
  }

  /// Lee la configuración de precios de la entidad (redondeo y moneda
  /// **preferida**) y se la pasa al editor compartido. Si la migración 60 no está
  /// aplicada se usan los valores por defecto: el formulario nunca se bloquea por
  /// esto.
  ///
  /// La propuesta de moneda base (solo al crear) y el disparo del cálculo
  /// automático que quedó pendiente los hace ya el controlador.
  Future<void> _cargarPrecioConfig() async {
    final config = await PrecioConfigService.getSeguro(widget.idEntidad);
    if (!mounted) return;
    _precios.actualizarConfigEntidad(config);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _campos) {
      c.dispose();
    }
    _precios.dispose();
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

  /// Campos seleccionables que pueden llevar reglas de precio, con su clave
  /// **final** (la misma que acaba guardada en `campos_adicionales`).
  ///
  /// Recalcula las claves únicas con la MISMA lógica de la pasada 1 de
  /// `_camposToJson` (slug + sufijo `_2`, `_3`…) pero **sin** validar ni tocar
  /// `_campoError`: se llama desde `initState`, desde `build` y desde los
  /// callbacks de los datos adicionales, donde no toca avisar de nada.
  List<CampoSelectPrecio> _camposSelectParaPrecio() {
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

    final out = <CampoSelectPrecio>[];
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
    // El editor compartido valida y arma el `config_precio` con las claves
    // finales de los campos seleccionables (el slug se resuelve a `clave`).
    final configPrecio = _precios.construir();
    if (configPrecio == null) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_precios.error ?? 'Revisa la configuración de precio'),
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
        configPrecio: configPrecio.toJson(),
      );
      // [67] Interruptor de pago por adelantado de ESTE servicio. Va aparte
      // porque la RPC de arriba no lo toca (es una columna del servicio, no de
      // los datos adicionales) y así sigue valiendo con la 67 sin aplicar.
      //
      // [P1-3] Se escribe el valor del formulario sin atajo por `_entidadCobra`:
      // antes, con el maestro apagado y el servicio en `true`, no se escribía
      // nada y ese `true` sobrevivía escondido; al reactivar el maestro el
      // servicio volvía a cobrar en silencio.
      //
      // Pero SOLO si el valor es de fiar (`_cobroCargado` tras releer la fila, o
      // `_cobroTocado` porque el admin lo cambió). Escribir a ciegas el `false`
      // con el que llega el payload del cliente apagaría el cobro al editar
      // cualquier otra cosa del servicio.
      if (_cobroCargado || _cobroTocado) {
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
    setState(() {
      _campos.add(_CampoEditable.nuevo());
      // Los campos seleccionables del editor de precios van con los datos
      // adicionales: al añadir uno hay que refrescar su lista.
      _precios.actualizarCamposSelect(_camposSelectParaPrecio());
    });
  }

  void _quitarCampo(int i) {
    setState(() {
      _campos[i].dispose();
      _campos.removeAt(i);
      _precios.actualizarCamposSelect(_camposSelectParaPrecio());
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
                // [P1-3] Siempre habilitado, también con el maestro apagado. Si
                // se bloqueara, un servicio que ya tenía `true` no se podría
                // apagar desde aquí: el flag sobreviviría escondido y se
                // reactivaría solo al volver a activar el maestro. El subtítulo
                // explica el estado real en vez de esconder el control.
                //
                // `_cobroTocado`: la elección del admin manda sobre la relectura
                // de `_reconciliarCobro`, que puede llegar después.
                onChanged: (v) => setState(() {
                  _cobroAdelantado = v;
                  _cobroTocado = true;
                }),
                secondary: _entidadCobra == false
                    ? const Icon(Icons.info_outline, size: 20)
                    : null,
                title: const Text('Pago por adelantado en línea'),
                subtitle: Text(
                  _entidadCobra == false
                      ? 'La entidad tiene el pago por adelantado apagado: este '
                            'servicio quedará marcado pero no se ofrecerá hasta '
                            'que lo actives en «Mi suscripción → Cobro por '
                            'adelantado».'
                      : 'El cliente podrá pagar este servicio con Transfermóvil '
                            'antes de la cita.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(),

              // -- Precio del servicio (editor compartido) --
              // La UI y la logica viven en PreciosServicioEditor: el formulario
              // de alta/edicion y la pestana de precios usan el MISMO editor.
              // Aqui solo se engancha el controlador del formulario y se piden
              // los anchors del tutorial (admin_precio, admin_precio_auto y
              // admin_reglas_precio).
              PreciosServicioEditor(
                controlador: _precios,
                esTransporteOmnibus: _esTransporteOmnibus,
                conAnchorsTutorial: true,
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
                        // Un cambio en el campo (etiqueta, tipo, opciones…)
                        // cambia las claves finales que usan las reglas de
                        // precio: el editor compartido se resincroniza aquí.
                        onChanged: () => setState(() {
                          _precios.actualizarCamposSelect(
                            _camposSelectParaPrecio(),
                          );
                        }),
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
