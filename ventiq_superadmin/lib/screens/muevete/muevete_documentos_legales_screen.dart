import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_colors.dart';
import '../../services/muevete_documentos_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Pantalla: Documentos y Consentimientos (H1)
//
// 1) Documentos legales versionados: texto, hash SHA-256, vigencia y publicación.
//    Cambiar la versión obliga a TODOS los usuarios a re-aceptar.
// 2) Auditoría de `consentimientos`: quién aceptó qué versión, cuándo y desde
//    qué app. La consola lee, nunca edita ni borra la evidencia.
// ═══════════════════════════════════════════════════════════════════════════

class MueveteDocumentosLegalesScreen extends StatefulWidget {
  const MueveteDocumentosLegalesScreen({super.key});

  @override
  State<MueveteDocumentosLegalesScreen> createState() =>
      _MueveteDocumentosLegalesScreenState();
}

class _MueveteDocumentosLegalesScreenState
    extends State<MueveteDocumentosLegalesScreen> {
  /// Centinela de «sin filtro» para los desplegables (no se puede usar `null`
  /// como valor de un `DropdownMenuItem` porque la selección no se pintaría).
  static const String _todos = '__todos__';

  // ── Documentos ──────────────────────────────────────────────────────
  bool _cargandoDocs = true;
  String? _errorDocs;
  List<Map<String, dynamic>> _docs = [];
  final Set<int> _publicando = {};

  // ── Resumen de aceptación (X de Y) ──────────────────────────────────
  bool _cargandoResumen = true;
  List<AceptacionDocumento> _resumen = [];
  Map<String, Map<String, int>> _aceptacionesPorVersion = {};
  String? _errorResumen;

  // ── Auditoría ───────────────────────────────────────────────────────
  bool _cargandoAuditoria = true;
  String? _errorAuditoria;
  List<Map<String, dynamic>> _consentimientos = [];
  Map<String, Map<String, dynamic>> _usuarios = {};
  int _paginaAuditoria = 0;
  bool _haySiguiente = false;
  String? _filtroCodigo;
  String? _filtroAceptado; // null = todos, 'true', 'false'
  DateTime? _filtroDesde;
  DateTime? _filtroHasta;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    await _cargarDocumentos();
    await _cargarResumen();
    await _cargarAuditoria();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Carga de datos
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _cargarDocumentos() async {
    setState(() {
      _cargandoDocs = true;
      _errorDocs = null;
    });
    try {
      final docs = await MueveteDocumentosService.listarDocumentos();
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _cargandoDocs = false;
      });
    } on MueveteLegalException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoDocs = false;
        _errorDocs = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoDocs = false;
        _errorDocs = 'No se pudieron cargar los documentos legales: $e';
      });
    }
  }

  Future<void> _cargarResumen() async {
    setState(() {
      _cargandoResumen = true;
      _errorResumen = null;
    });
    try {
      final codigos =
          _docs.map((d) => '${d['codigo']}').toSet().where((c) => c.isNotEmpty);
      final porVersion = <String, Map<String, int>>{};
      for (final codigo in codigos) {
        porVersion[codigo] =
            await MueveteDocumentosService.aceptacionesPorVersion(codigo);
      }
      final resumen = await MueveteDocumentosService.resumenAceptacion(_docs);
      if (!mounted) return;
      setState(() {
        _aceptacionesPorVersion = porVersion;
        _resumen = resumen;
        _cargandoResumen = false;
      });
    } on MueveteLegalException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoResumen = false;
        _errorResumen = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoResumen = false;
        _errorResumen = 'No se pudo calcular la aceptación: $e';
      });
    }
  }

  Future<void> _cargarAuditoria({int? pagina}) async {
    final destino = pagina ?? _paginaAuditoria;
    setState(() {
      _cargandoAuditoria = true;
      _errorAuditoria = null;
      _paginaAuditoria = destino;
    });
    try {
      final filas = await MueveteDocumentosService.listarConsentimientos(
        codigo: _filtroCodigo,
        desde: _filtroDesde,
        hasta: _filtroHasta,
        aceptado:
            _filtroAceptado == null ? null : _filtroAceptado == 'true',
        page: destino,
        filas: MueveteDocumentosService.filasPorPagina,
      );
      final haySiguiente =
          filas.length > MueveteDocumentosService.filasPorPagina;
      final visibles = haySiguiente
          ? filas
              .take(MueveteDocumentosService.filasPorPagina)
              .toList(growable: false)
          : filas;
      final usuarios = await MueveteDocumentosService.usuariosPorUuid(
        visibles.map((c) => '${c['user_uuid']}'),
      );
      if (!mounted) return;
      setState(() {
        _consentimientos = List<Map<String, dynamic>>.from(visibles);
        _usuarios = usuarios;
        _haySiguiente = haySiguiente;
        _cargandoAuditoria = false;
      });
    } on MueveteLegalException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoAuditoria = false;
        _errorAuditoria = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoAuditoria = false;
        _errorAuditoria = 'No se pudo cargar la auditoría: $e';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Acciones sobre documentos
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _abrirEditor(
    Map<String, dynamic> doc, {
    bool soloLectura = false,
  }) async {
    final cambiado = await showDialog<bool>(
      context: context,
      builder: (_) => _EditorDocumentoDialog(
        documento: doc,
        soloLectura: soloLectura,
      ),
    );
    if (cambiado == true) {
      await _cargarDocumentos();
      await _cargarResumen();
      _avisar('Documento guardado y hash recalculado.');
    }
  }

  Future<void> _abrirNuevaVersion(Map<String, dynamic> doc) async {
    final creada = await showDialog<bool>(
      context: context,
      builder: (_) => _NuevaVersionDialog(documento: doc),
    );
    if (creada == true) {
      await _cargarDocumentos();
      await _cargarResumen();
      _avisar('Versión nueva creada como borrador. Revísala y publícala.');
    }
  }

  Future<void> _publicar(Map<String, dynamic> doc) async {
    final id = (doc['id'] as num).toInt();
    final codigo = '${doc['codigo']}';
    final version = '${doc['version']}';
    final publicado = doc['publicado'] == true;

    final confirmado = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              publicado ? 'Despublicar $codigo@$version' : 'Publicar $codigo@$version',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: Text(
              publicado
                  ? 'La versión deja de mostrarse en la app. La evidencia de '
                      'los consentimientos ya registrados se conserva intacta.'
                  : 'Al publicar esta versión:\n\n'
                      '• Queda vigente desde ahora ($codigo@$version).\n'
                      '• La versión anterior se cierra con fecha de hoy '
                      '(se conserva como histórico).\n'
                      '• TODOS los usuarios deberán aceptar de nuevo antes de '
                      'poder publicar o tomar viajes.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      publicado ? AppColors.error : AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  publicado ? 'Despublicar' : 'Publicar y exigir re-aceptación',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
    );
    if (confirmado != true) return;

    setState(() => _publicando.add(id));
    try {
      if (publicado) {
        await MueveteDocumentosService.despublicar(id);
      } else {
        await MueveteDocumentosService.publicar(id);
      }
      await _cargarDocumentos();
      await _cargarResumen();
      _avisar(publicado ? 'Documento despublicado' : 'Documento publicado');
    } on MueveteLegalException catch (e) {
      _avisar(e.mensaje, error: true);
    } catch (e) {
      _avisar('No se pudo cambiar la publicación: $e', error: true);
    } finally {
      if (mounted) setState(() => _publicando.remove(id));
    }
  }

  Future<void> _verificarIntegridad() async {
    if (_docs.isEmpty) return;
    final fallos = <Map<String, dynamic>>[];
    for (final d in _docs) {
      if (!MueveteDocumentosService.hashCoincide(d)) fallos.add(d);
    }
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  fallos.isEmpty
                      ? Icons.verified_rounded
                      : Icons.gpp_bad_rounded,
                  color: fallos.isEmpty ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 8),
                Text(
                  fallos.isEmpty ? 'Hashes íntegros' : 'Hash no coincide',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fallos.isEmpty
                        ? 'Se recalculó el SHA-256 del texto de '
                            '${_docs.length} documento(s) y coincide con el '
                            'hash guardado. El criterio es el mismo del trigger '
                            'muevete.fn_doc_legal_hash() '
                            "(sha256 de los bytes UTF-8 de contenido_md)."
                        : 'Estos documentos tienen un hash que NO corresponde '
                            'al texto guardado. Eso significa que el texto se '
                            'alteró por fuera de la consola: trátalo como '
                            'incidente y publica una versión nueva.',
                    style: TextStyle(fontSize: 12.5,
                        color: AppColors.textSecondary),
                  ),
                  if (fallos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...fallos.map(
                      (d) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• ${d['codigo']}@${d['version']} '
                          '(id ${d['id']})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(ancho);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.white,
          elevation: 0.5,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.gavel_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Documentos y Consentimientos',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _resumenCabecera(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Verificar integridad de los hashes',
              onPressed: _docs.isEmpty ? null : _verificarIntegridad,
              icon: Icon(
                Icons.fingerprint_rounded,
                color: AppColors.textSecondary,
              ),
            ),
            IconButton(
              tooltip: 'Recargar',
              onPressed: _cargandoDocs ? null : _cargarTodo,
              icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(height: 44, text: 'Documentos legales'),
              Tab(height: 44, text: 'Auditoría de consentimientos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tabDocumentos(isDesktop),
            _tabAuditoria(isDesktop),
          ],
        ),
      ),
    );
  }

  String _resumenCabecera() {
    if (_cargandoDocs) return 'Cargando documentos…';
    if (_errorDocs != null) return 'Error al cargar';
    final codigos = _docs.map((d) => '${d['codigo']}').toSet().length;
    final publicados = _docs.where((d) => d['publicado'] == true).length;
    return '$codigos documento(s) · $publicados versión(es) publicada(s) · '
        'hash SHA-256';
  }

  // ─── Tab 1: documentos ────────────────────────────────────────────────

  Widget _tabDocumentos(bool isDesktop) {
    if (_cargandoDocs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorDocs != null) {
      return _EstadoError(mensaje: _errorDocs!, onReintentar: _cargarTodo);
    }
    if (_docs.isEmpty) {
      return const _EstadoVacio(
        icono: Icons.gavel_rounded,
        titulo: 'Sin documentos legales',
        mensaje:
            'La tabla documentos_legales está vacía. Aplica el seed de los '
            'textos legales antes de publicar el módulo de taxi.',
      );
    }

    // Agrupados por código, con la versión más reciente arriba.
    final porCodigo = <String, List<Map<String, dynamic>>>{};
    for (final d in _docs) {
      porCodigo.putIfAbsent('${d['codigo']}', () => []).add(d);
    }
    final codigos = porCodigo.keys.toList()..sort();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bannerReaceptacion(),
              const SizedBox(height: 14),
              if (_cargandoResumen)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else if (_errorResumen != null)
                _textoError(_errorResumen!)
              else
                ..._resumen.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _tarjetaResumen(r),
                  ),
                ),
              const SizedBox(height: 14),
              ...codigos.map((c) => _grupo(c, porCodigo[c]!)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bannerReaceptacion() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18,
              color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cambiar la versión obliga a TODOS los usuarios a re-aceptar',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Al publicar una versión nueva, la anterior se cierra con la '
                  'fecha de hoy y se conserva como histórico (no se borra). '
                  'Ningún usuario puede publicar ni tomar viajes hasta aceptar '
                  'la versión vigente. La evidencia de los consentimientos ya '
                  'registrados es inmutable: esta consola no la edita ni la '
                  'borra.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textoError(String mensaje) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16,
              color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(fontSize: 11.5, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaResumen(AceptacionDocumento r) {
    final pct = r.porcentaje;
    final color =
        pct >= 100
            ? AppColors.success
            : (pct >= 50 ? AppColors.warning : AppColors.error);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.titulo,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${r.aceptaron} de ${r.totalUsuarios} usuarios aceptaron la '
                  'v${r.version}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${pct.toStringAsFixed(0)} %',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                r.publicado ? 'publicado' : 'borrador',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _grupo(String codigo, List<Map<String, dynamic>> versiones) {
    final ordenadas = [...versiones]
      ..sort(
        (a, b) => '${b['vigente_desde']}'.compareTo('${a['vigente_desde']}'),
      );
    final etiqueta = MueveteDocumentosService.etiquetaCodigo(
      codigo,
      ordenadas.first['titulo'] as String?,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: AppColors.surfaceVariant,
            child: Row(
              children: [
                const Icon(Icons.description_rounded, size: 16,
                    color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    etiqueta,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                _miniChip(codigo, AppColors.textSecondary),
              ],
            ),
          ),
          ...ordenadas.map(_filaVersion),
        ],
      ),
    );
  }

  Widget _filaVersion(Map<String, dynamic> doc) {
    final id = (doc['id'] as num).toInt();
    final codigo = '${doc['codigo']}';
    final version = '${doc['version']}';
    final publicado = doc['publicado'] == true;
    final cerrado = doc['vigente_hasta'] != null;
    final vigente = publicado && !cerrado;
    final obligatorio = doc['es_obligatorio'] == true;
    final ocupado = _publicando.contains(id);
    final hash = (doc['hash_contenido'] as String?) ?? '';
    final hashOk = MueveteDocumentosService.hashCoincide(doc);
    final aceptaron = _aceptacionesPorVersion[codigo]?[version] ?? 0;

    final estadoColor =
        vigente
            ? AppColors.success
            : (publicado ? AppColors.info : AppColors.textSecondary);
    final estadoTexto =
        vigente ? 'VIGENTE' : (publicado ? 'PUBLICADO' : 'BORRADOR');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _miniChip('v$version', AppColors.primary),
              _miniChip(estadoTexto, estadoColor),
              if (cerrado) _miniChip('histórico', AppColors.textSecondary),
              if (obligatorio)
                _miniChip('obligatorio', AppColors.warning),
              _miniChip('$aceptaron aceptación(es)', AppColors.secondary),
              if (!hashOk) _miniChip('hash no coincide', AppColors.error),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            doc['titulo'] as String? ?? codigo,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _dato(
                'Vigente desde',
                _fecha(doc['vigente_desde'] as String?),
              ),
              _dato(
                'Vigente hasta',
                doc['vigente_hasta'] == null
                    ? 'abierta'
                    : _fecha(doc['vigente_hasta'] as String?),
              ),
              _dato('Hash SHA-256', _corto(hash)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: ocupado ? null : () => _abrirEditor(doc),
                icon: const Icon(Icons.edit_note_rounded, size: 17),
                label: const Text('Ver / editar texto'),
                style: _estiloBoton(AppColors.primary),
              ),
              OutlinedButton.icon(
                onPressed: ocupado ? null : () => _abrirNuevaVersion(doc),
                icon: const Icon(Icons.copy_all_rounded, size: 17),
                label: const Text('Nueva versión'),
                style: _estiloBoton(AppColors.secondary),
              ),
              ElevatedButton.icon(
                onPressed: ocupado ? null : () => _publicar(doc),
                icon:
                    ocupado
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : Icon(
                          publicado
                              ? Icons.unpublished_rounded
                              : Icons.publish_rounded,
                          size: 17,
                        ),
                label: Text(publicado ? 'Despublicar' : 'Publicar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      publicado ? AppColors.error : AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copiar hash',
                onPressed:
                    hash.isEmpty
                        ? null
                        : () async {
                          await Clipboard.setData(ClipboardData(text: hash));
                          _avisar('Hash copiado al portapapeles');
                        },
                icon: const Icon(Icons.copy_rounded, size: 17),
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        children: [
          TextSpan(text: '$etiqueta: '),
          TextSpan(
            text: valor,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _estiloBoton(Color color) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
  }

  Widget _miniChip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _corto(String hash) =>
      hash.isEmpty ? '—' : '${hash.substring(0, 16)}…';

  // ─── Tab 2: auditoría de consentimientos ──────────────────────────────

  Widget _tabAuditoria(bool isDesktop) {
    final codigos = _docs.map((d) => '${d['codigo']}').toSet().toList()..sort();
    // Si el filtro apunta a un código que ya no está en la lista, se cae a
    // «todos» para que el desplegable no reviente por un valor inexistente.
    final codigoSeleccionado =
        codigos.contains(_filtroCodigo) ? _filtroCodigo : null;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('filtro-doc-${codigoSeleccionado ?? 'todos'}'),
                        initialValue: codigoSeleccionado ?? _todos,
                        isExpanded: true,
                        isDense: true,
                        decoration: _decoracion('Documento'),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: _todos,
                            child: Text(
                              'Todos los documentos',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          ...codigos.map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(
                                c,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(
                            () => _filtroCodigo = (v == _todos) ? null : v,
                          );
                          _cargarAuditoria(pagina: 0);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          'filtro-estado-${_filtroAceptado ?? 'todos'}',
                        ),
                        initialValue: _filtroAceptado ?? _todos,
                        isExpanded: true,
                        isDense: true,
                        decoration: _decoracion('Resultado'),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                        items: const [
                          DropdownMenuItem<String>(
                            value: _todos,
                            child: Text(
                              'Aceptados y rechazos',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'true',
                            child: Text(
                              'Solo aceptados',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'false',
                            child: Text(
                              'Solo rechazos / retiradas',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(
                            () => _filtroAceptado = (v == _todos) ? null : v,
                          );
                          _cargarAuditoria(pagina: 0);
                        },
                      ),
                    ),
                    _botonFecha('Desde', _filtroDesde, esDesde: true),
                    _botonFecha('Hasta', _filtroHasta, esDesde: false),
                    if (_filtroCodigo != null ||
                        _filtroAceptado != null ||
                        _filtroDesde != null ||
                        _filtroHasta != null)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _filtroCodigo = null;
                            _filtroAceptado = null;
                            _filtroDesde = null;
                            _filtroHasta = null;
                          });
                          _cargarAuditoria(pagina: 0);
                        },
                        icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                        label: const Text(
                          'Limpiar filtros',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_cargandoAuditoria)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorAuditoria != null)
                SizedBox(
                  height: 260,
                  child: _EstadoError(
                    mensaje: _errorAuditoria!,
                    onReintentar: () => _cargarAuditoria(),
                  ),
                )
              else if (_consentimientos.isEmpty)
                const SizedBox(
                  height: 260,
                  child: _EstadoVacio(
                    icono: Icons.how_to_reg_rounded,
                    titulo: 'Sin consentimientos en este filtro',
                    mensaje:
                        'No hay aceptaciones ni rechazos registrados con los '
                        'filtros elegidos. Prueba a ampliar el rango de fechas.',
                  ),
                )
              else
                _tablaConsentimientos(),
              const SizedBox(height: 12),
              _paginadorAuditoria(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botonFecha(String etiqueta, DateTime? valor, {required bool esDesde}) {
    return OutlinedButton.icon(
      onPressed: () async {
        final ahora = DateTime.now();
        final inicial = valor ?? ahora;
        final elegida = await showDatePicker(
          context: context,
          initialDate: inicial,
          firstDate: DateTime(2024),
          lastDate: ahora.add(const Duration(days: 365)),
          helpText: 'Fecha $etiqueta',
        );
        if (elegida == null) return;
        final ajustada =
            esDesde
                ? DateTime(elegida.year, elegida.month, elegida.day)
                : DateTime(
                  elegida.year,
                  elegida.month,
                  elegida.day,
                  23,
                  59,
                  59,
                );
        setState(() {
          if (esDesde) {
            _filtroDesde = ajustada;
          } else {
            _filtroHasta = ajustada;
          }
        });
        await _cargarAuditoria(pagina: 0);
      },
      icon: const Icon(Icons.date_range_rounded, size: 16),
      label: Text(
        valor == null ? etiqueta : '$etiqueta: ${_fechaCorta(valor)}',
        style: const TextStyle(fontSize: 12),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: valor == null
            ? AppColors.textSecondary
            : AppColors.primary,
        side: BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _tablaConsentimientos() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _celda('USUARIO', flex: 4, cabecera: true),
                _celda('DOCUMENTO', flex: 3, cabecera: true),
                _celda('RESULTADO', flex: 2, cabecera: true),
                _celda('FECHA', flex: 3, cabecera: true),
                _celda('MÉTODO', flex: 2, cabecera: true),
                _celda('APP', flex: 2, cabecera: true),
              ],
            ),
          ),
          ..._consentimientos.map((c) {
            final uuid = '${c['user_uuid']}';
            final usuario = _usuarios[uuid];
            final nombre =
                (usuario?['name'] as String?)?.trim().isNotEmpty == true
                    ? usuario!['name'] as String
                    : 'Sin nombre';
            final aceptado = c['aceptado'] == true;
            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _celda(
                    '$nombre\n${_cortoUuid(uuid)}',
                    flex: 4,
                    secundario: true,
                  ),
                  _celda(
                    '${c['documento_codigo']}@${c['documento_version']}',
                    flex: 3,
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _miniChip(
                          aceptado ? 'Aceptado' : 'Rechazado',
                          aceptado ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ),
                  ),
                  _celda(_fecha(c['aceptado_at'] as String?), flex: 3),
                  _celda('${c['metodo'] ?? '—'}', flex: 2),
                  _celda(
                    '${c['app_version'] ?? '—'}',
                    flex: 2,
                    secundario: true,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _celda(
    String texto, {
    int flex = 1,
    bool cabecera = false,
    bool secundario = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          texto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: cabecera ? 10 : 11.5,
            fontWeight: cabecera ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: cabecera ? 0.4 : 0,
            color:
                cabecera
                    ? AppColors.textSecondary
                    : (secundario
                        ? AppColors.textSecondary
                        : AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _paginadorAuditoria() {
    if (_cargandoAuditoria) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Página anterior',
          onPressed:
              _paginaAuditoria == 0
                  ? null
                  : () => _cargarAuditoria(pagina: _paginaAuditoria - 1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          'Página ${_paginaAuditoria + 1}',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed:
              _haySiguiente
                  ? () => _cargarAuditoria(pagina: _paginaAuditoria + 1)
                  : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  String _cortoUuid(String uuid) =>
      uuid.length <= 13 ? uuid : '${uuid.substring(0, 8)}…';

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      labelStyle: TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }

  String _fecha(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} $hh:$mi';
  }

  String _fechaCorta(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Diálogo: editor de contenido (ver / editar)
// ═══════════════════════════════════════════════════════════════════════════

class _EditorDocumentoDialog extends StatefulWidget {
  final Map<String, dynamic> documento;
  final bool soloLectura;

  const _EditorDocumentoDialog({
    required this.documento,
    required this.soloLectura,
  });

  @override
  State<_EditorDocumentoDialog> createState() => _EditorDocumentoDialogState();
}

class _EditorDocumentoDialogState extends State<_EditorDocumentoDialog> {
  late final TextEditingController _texto;
  late final TextEditingController _titulo;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _texto = TextEditingController(
      text: (widget.documento['contenido_md'] as String?) ?? '',
    );
    _titulo = TextEditingController(
      text: (widget.documento['titulo'] as String?) ?? '',
    );
    _texto.addListener(_alCambiarTexto);
  }

  @override
  void dispose() {
    _texto.removeListener(_alCambiarTexto);
    _texto.dispose();
    _titulo.dispose();
    super.dispose();
  }

  void _alCambiarTexto() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.documento;
    final original =
        (doc['contenido_md'] as String?) ?? '';
    final actual = _texto.text;
    final hashLocal = MueveteDocumentosService.calcularHash(actual);
    final hashGuardado = (doc['hash_contenido'] as String?) ?? '';
    final sinCambios = actual == original &&
        _titulo.text.trim() == ((doc['titulo'] as String?) ?? '').trim();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.soloLectura
                              ? 'Contenido del documento'
                              : 'Editar contenido',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${doc['codigo']}@${doc['version']} · '
                          '${actual.length} caracteres · hash local '
                          '${_corto(hashLocal)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (!widget.soloLectura)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 46,
                  child: TextField(
                    controller: _titulo,
                    enabled: !_guardando,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Título del documento',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _texto,
                  readOnly: widget.soloLectura,
                  enabled: !_guardando,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Texto en Markdown que verá el usuario antes de '
                        'aceptar…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    hashLocal == hashGuardado
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    size: 15,
                    color:
                        hashLocal == hashGuardado
                            ? AppColors.success
                            : AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hashLocal == hashGuardado
                          ? 'El hash local coincide con el guardado.'
                          : 'El texto cambió: al guardar, el servidor '
                              'recalcula hash_contenido. Publicar una versión '
                              'nueva obliga a re-aceptar.',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            hashLocal == hashGuardado
                                ? AppColors.textSecondary
                                : AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 11.5, color: AppColors.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _guardando ? null : () => Navigator.pop(context, false),
                    child: Text(widget.soloLectura ? 'Cerrar' : 'Cancelar'),
                  ),
                  if (!widget.soloLectura) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_guardando || sinCambios) ? null : _guardar,
                      icon:
                          _guardando
                              ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.save_rounded, size: 17),
                      label: Text(
                        _guardando ? 'Guardando…' : 'Guardar texto',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final fila = await MueveteDocumentosService.guardarContenido(
        (widget.documento['id'] as num).toInt(),
        contenidoMd: _texto.text,
        titulo: _titulo.text,
      );
      final hashServidor = (fila['hash_contenido'] as String?) ?? '';
      final hashLocal = MueveteDocumentosService.calcularHash(_texto.text);
      if (hashServidor.isNotEmpty && hashServidor != hashLocal) {
        setState(() {
          _guardando = false;
          _error =
              'Se guardó, pero el hash del servidor no coincide con el '
              'calculado aquí (servidor ${_corto(hashServidor)}). Verifica la '
              'integridad del documento.';
        });
        return;
      }
      if (mounted) Navigator.pop(context, true);
    } on MueveteLegalException catch (e) {
      setState(() {
        _guardando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      setState(() {
        _guardando = false;
        _error = 'No se pudo guardar: $e';
      });
    }
  }

  String _corto(String hash) =>
      hash.length <= 16 ? hash : '${hash.substring(0, 16)}…';
}

// ═══════════════════════════════════════════════════════════════════════════
// Diálogo: crear versión nueva
// ═══════════════════════════════════════════════════════════════════════════

class _NuevaVersionDialog extends StatefulWidget {
  final Map<String, dynamic> documento;

  const _NuevaVersionDialog({required this.documento});

  @override
  State<_NuevaVersionDialog> createState() => _NuevaVersionDialogState();
}

class _NuevaVersionDialogState extends State<_NuevaVersionDialog> {
  late final TextEditingController _version;
  late final TextEditingController _titulo;
  late bool _obligatorio;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final doc = widget.documento;
    _version = TextEditingController(
      text: MueveteDocumentosService.siguienteVersion(
        doc['version'] as String?,
      ),
    );
    _titulo = TextEditingController(text: (doc['titulo'] as String?) ?? '');
    _obligatorio = doc['es_obligatorio'] == true;
  }

  @override
  void dispose() {
    _version.dispose();
    _titulo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.documento;
    final contenido = (doc['contenido_md'] as String?) ?? '';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Crear versión nueva',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se copia el texto actual de ${doc['codigo']}@${doc['version']} '
                '(${contenido.length} caracteres) y se recalcula el hash '
                'SHA-256. La versión nace como borrador: publicarla es lo que '
                'obliga a re-aceptar.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _version,
                enabled: !_guardando,
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Versión nueva (x.y.z)',
                  hintText: '1.1.0',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titulo,
                enabled: !_guardando,
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Título',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _obligatorio,
                onChanged:
                    _guardando
                        ? null
                        : (v) => setState(() => _obligatorio = v),
                title: Text(
                  'Documento obligatorio',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Sin aceptarlo, el usuario no puede operar.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 11.5, color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _guardando ? null : _crear,
          icon:
              _guardando
                  ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : const Icon(Icons.copy_all_rounded, size: 17),
          label: Text(
            _guardando ? 'Creando…' : 'Crear borrador',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _crear() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await MueveteDocumentosService.crearNuevaVersion(
        base: widget.documento,
        versionNueva: _version.text.trim(),
        titulo: _titulo.text.trim(),
        esObligatorio: _obligatorio,
      );
      if (mounted) Navigator.pop(context, true);
    } on MueveteLegalException catch (e) {
      setState(() {
        _guardando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      setState(() {
        _guardando = false;
        _error = 'No se pudo crear la versión: $e';
      });
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Estados de carga / error / vacío
// ═══════════════════════════════════════════════════════════════════════════

class _EstadoError extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;

  const _EstadoError({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No se pudieron cargar los datos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String mensaje;

  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}