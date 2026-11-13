import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../../services/identidad_service.dart';
import '../../utils/app_error.dart';
import '../../utils/gate_seguridad.dart';

/// Consentimiento informado obligatorio (H1).
///
/// Los textos viven en `muevete.documentos_legales`: la app sólo los muestra y
/// registra la aceptación por `fn_aceptar_consentimiento`, que guarda hash,
/// versión, fecha, IP y dispositivo en el servidor. Cuando un documento sube de
/// versión, el gate devuelve `codigo@version` en `consentimiento.faltantes` y
/// aquí se vuelve a pedir.
class ConsentimientoScreen extends StatefulWidget {
  const ConsentimientoScreen({super.key});

  @override
  State<ConsentimientoScreen> createState() => _ConsentimientoScreenState();
}

class _ConsentimientoScreenState extends State<ConsentimientoScreen> {
  final IdentidadService _identidad = IdentidadService();

  List<DocumentoLegal> _documentos = const [];
  Set<String> _faltantes = <String>{};
  Set<String> _aceptadosServidor = <String>{};
  final Map<String, bool> _marcados = <String, bool>{};

  /// El servidor da por buenos todos los consentimientos obligatorios.
  bool _consentimientoOk = false;

  bool _cargando = true;
  bool _aceptando = false;
  String? _error;
  String? _motivo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && _motivo == null) {
      _motivo = args['motivo']?.toString();
    }
  }

  // ── Carga ───────────────────────────────────────────────────────────────

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final documentos = await _identidad.documentosLegales();
      final estado = await _identidad.estado();
      final aceptados = await _identidad.documentosAceptados();
      if (!mounted) return;

      final faltantes = estado.consentimiento.faltantes
          .map((d) => d.clave)
          .toSet();

      setState(() {
        _documentos = documentos;
        _faltantes = faltantes;
        _aceptadosServidor = aceptados;
        _consentimientoOk = estado.consentimiento.ok;
        for (final doc in documentos) {
          // Ya aceptado en esta versión: se marca solo y no se puede desmarcar.
          _marcados[doc.clave] = !faltantes.contains(doc.clave);
        }
        _cargando = false;
      });
    } on IdentidadException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = AppError.message(e, action: 'cargar los documentos legales');
      });
    }
  }

  /// `true` si el documento ya está aceptado en la versión vigente.
  ///
  /// Manda el servidor: si el gate dice que el consentimiento está completo, la
  /// versión que muestra la app es la aceptada. Si falta, es esta versión
  /// (`codigo@version`) la que hay que aceptar.
  bool _yaAceptado(DocumentoLegal doc) {
    if (_aceptadosServidor.contains(doc.clave)) return true;
    return _consentimientoOk && !_faltantes.contains(doc.clave);
  }

  bool get _todoMarcado {
    if (_documentos.isEmpty) return true;
    return _documentos.every((d) => _marcados[d.clave] == true);
  }

  // ── Aceptar ─────────────────────────────────────────────────────────────

  Future<void> _aceptarTodo() async {
    if (_aceptando) return;
    if (!_todoMarcado) {
      _snack('Marca todos los documentos para continuar');
      return;
    }

    final navegador = Navigator.of(context);
    setState(() => _aceptando = true);

    try {
      var registrados = 0;
      for (final doc in _documentos) {
        if (_yaAceptado(doc)) continue;
        await _identidad.aceptar(doc.codigo, doc.version);
        registrados++;
      }

      final estado = await _identidad.estado();
      if (!mounted) return;

      setState(() {
        _faltantes = estado.consentimiento.faltantes
            .map((d) => d.clave)
            .toSet();
        _consentimientoOk = estado.consentimiento.ok;
        _aceptando = false;
      });

      if (!estado.consentimiento.ok) {
        // El servidor no dio por bueno algún documento: recargar para ver la
        // versión vigente real.
        await _cargar();
        if (!mounted) return;
        _snack('Faltan documentos por aceptar. Revisa la lista');
        return;
      }

      if (registrados > 0) {
        _snack('Consentimiento registrado');
      }

      // Siguiente paso del gate: contacto de emergencia o listo.
      final gate = await GateSeguridad.evaluar();
      if (!mounted) return;
      if (gate.paso == PasoSeguridad.contactos) {
        navegador.pushReplacementNamed(
          '/seguridad/contactos',
          arguments: {'motivo': gate.motivo},
        );
        return;
      }
      navegador.pop(true);
    } on IdentidadException catch (e) {
      if (!mounted) return;
      setState(() => _aceptando = false);
      _snack(e.mensaje);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aceptando = false);
      _snack(AppError.message(e, action: 'registrar tu aceptación'));
    }
  }

  void _snack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje, style: GoogleFonts.plusJakartaSans()),
        backgroundColor: AppTheme.error,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(isDark),
        elevation: 0,
        title: Text(
          'Privacidad y términos',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _encabezado(isDark, textPrimary, textSecondary),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  _avisoError(isDark),
                  const SizedBox(height: 12),
                ],
                if (_documentos.isEmpty && _error == null)
                  _sinDocumentos(isDark, textPrimary, textSecondary),
                for (final doc in _documentos) ...[
                  _tarjetaDocumento(doc, isDark, textPrimary, textSecondary),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_aceptando || _documentos.isEmpty)
                        ? (_documentos.isEmpty && !_aceptando
                              ? () => Navigator.of(context).pop(true)
                              : null)
                        : _aceptarTodo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primaryColor.withValues(
                        alpha: 0.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _aceptando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _documentos.isEmpty
                                ? 'Continuar'
                                : 'Aceptar y continuar',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Guardamos la versión, la fecha, la IP y el dispositivo de '
                  'cada aceptación. Si cambia un documento, te pediremos que '
                  'lo aceptes de nuevo.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _encabezado(bool isDark, Color textPrimary, Color textSecondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Documentos que debes aceptar',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _motivo ??
              'Para operar en Muevete necesitamos tu consentimiento expreso. '
                  'Léelos antes de aceptar: puedes consultarlos cuando quieras.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _avisoError(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textPrimary(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sinDocumentos(bool isDark, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Todavía no hay documentos publicados. Puedes continuar.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaDocumento(
    DocumentoLegal doc,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
  ) {
    final yaAceptado = _yaAceptado(doc);
    final marcado = _marcados[doc.clave] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: yaAceptado
              ? AppTheme.success.withValues(alpha: 0.5)
              : AppTheme.border(isDark),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.titulo.isEmpty ? doc.codigo : doc.titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Versión ${doc.version}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (yaAceptado)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Aceptado',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.success,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Pendiente',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
            ],
          ),
          if (!yaAceptado) ...[
            const SizedBox(height: 6),
            Text(
              _faltantes.contains(doc.clave) && _aceptadosServidor.isNotEmpty
                  ? 'Hay una versión nueva de este documento: vuelve a aceptarlo'
                  : 'Debes aceptarlo para poder viajar',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.warning,
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Vista previa corta con scroll: los documentos son largos.
          Container(
            constraints: const BoxConstraints(maxHeight: 190),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bg(isDark),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border(isDark)),
            ),
            child: SingleChildScrollView(
              child: MarkdownBasico(texto: doc.contenidoMd, isDark: isDark),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  value: marcado,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppTheme.primaryColor,
                  title: Text(
                    yaAceptado
                        ? 'Ya aceptaste esta versión'
                        : 'He leído y acepto este documento',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: textPrimary,
                    ),
                  ),
                  onChanged: yaAceptado
                      ? null
                      : (v) {
                          setState(() => _marcados[doc.clave] = v == true);
                        },
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _abrirLector(doc),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(
                'Leer completo',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirLector(DocumentoLegal doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _LectorDocumentoScreen(documento: doc)),
    );
  }
}

/// Lector a pantalla completa con scroll (texto completo del documento).
class _LectorDocumentoScreen extends StatelessWidget {
  final DocumentoLegal documento;

  const _LectorDocumentoScreen({required this.documento});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textSecondary = AppTheme.textSecondary(isDark);

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        backgroundColor: AppTheme.surface(isDark),
        elevation: 0,
        title: Text(
          documento.titulo.isEmpty ? documento.codigo : documento.titulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Versión ${documento.version}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            MarkdownBasico(texto: documento.contenidoMd, isDark: isDark),
            const SizedBox(height: 24),
            Text(
              'Texto íntegro publicado por Muevete. La aceptación se registra '
              'en el servidor con la versión y el hash del texto.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renderizador de markdown mínimo (encabezados, párrafos, listas, citas).
///
/// No se añade ninguna dependencia: alcanza para el texto de los documentos
/// legales, que es markdown sencillo.
class MarkdownBasico extends StatelessWidget {
  final String texto;
  final bool isDark;

  const MarkdownBasico({super.key, required this.texto, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.textPrimary(isDark);
    final secundario = AppTheme.textSecondary(isDark);
    final lineas = texto.split('\n');
    final hijos = <Widget>[];

    for (var i = 0; i < lineas.length; i++) {
      final cruda = lineas[i];
      final linea = cruda.trimRight();

      if (linea.trim().isEmpty) {
        hijos.add(const SizedBox(height: 8));
        continue;
      }

      if (linea.startsWith('---') || linea.startsWith('***')) {
        hijos.add(Divider(color: AppTheme.border(isDark), height: 20));
        continue;
      }

      if (linea.startsWith('#### ') || linea.startsWith('### ')) {
        hijos.add(
          _bloque(
            linea.replaceFirst(RegExp(r'^#+\s*'), ''),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
            espacioArriba: 10,
          ),
        );
        continue;
      }
      if (linea.startsWith('## ')) {
        hijos.add(
          _bloque(
            linea.substring(3),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
            espacioArriba: 12,
          ),
        );
        continue;
      }
      if (linea.startsWith('# ')) {
        hijos.add(
          _bloque(
            linea.substring(2),
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: color,
            espacioArriba: 14,
          ),
        );
        continue;
      }

      if (linea.startsWith('> ')) {
        hijos.add(
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.5),
                  width: 3,
                ),
              ),
            ),
            child: _parrafo(
              linea.substring(2),
              color: secundario,
              fontSize: 12.5,
            ),
          ),
        );
        continue;
      }

      final esVineta =
          linea.startsWith('- ') ||
          linea.startsWith('* ') ||
          linea.startsWith('• ');
      if (esVineta) {
        hijos.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: _parrafo(
                    linea.substring(2),
                    color: color,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      hijos.add(_parrafo(linea, color: color, fontSize: 13));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: hijos,
    );
  }

  Widget _bloque(
    String texto, {
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double espacioArriba = 0,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: espacioArriba, bottom: 4),
      child: Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _parrafo(
    String texto, {
    required Color color,
    required double fontSize,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.plusJakartaSans(
            fontSize: fontSize,
            color: color,
            height: 1.4,
          ),
          children: _spans(texto, color),
        ),
      ),
    );
  }

  /// Interpreta `**negrita**` dentro de un párrafo.
  List<TextSpan> _spans(String texto, Color color) {
    final spans = <TextSpan>[];
    final partes = texto.split('**');
    for (var j = 0; j < partes.length; j++) {
      if (partes[j].isEmpty) continue;
      spans.add(
        TextSpan(
          text: partes[j],
          style: j.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null,
        ),
      );
    }
    if (spans.isEmpty) return [TextSpan(text: texto)];
    return spans;
  }
}
