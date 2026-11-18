import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../providers/theme_provider.dart';

/// Pantalla PÚBLICA para leer un documento legal (`muevete.documentos_legales`).
///
/// Se usa desde el **landing** y desde **login/registro**, es decir SIN sesión:
/// por eso la RLS de `046` deja a `anon` leer los documentos publicados y
/// vigentes. Si no hay documento vigente, muestra un aviso claro en vez de una
/// pantalla vacía.
///
/// Códigos: `terminos`, `privacidad`, `kyc`, `contacto_emergencia`.
class DocumentoLegalScreen extends StatefulWidget {
  final String codigo;
  final String? tituloRespaldo;

  const DocumentoLegalScreen({
    super.key,
    required this.codigo,
    this.tituloRespaldo,
  });

  /// Abre el documento con una ruta normal (no requiere registrar navegación).
  static Future<void> abrir(
    BuildContext context, {
    required String codigo,
    String? tituloRespaldo,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentoLegalScreen(
          codigo: codigo,
          tituloRespaldo: tituloRespaldo,
        ),
      ),
    );
  }

  @override
  State<DocumentoLegalScreen> createState() => _DocumentoLegalScreenState();
}

class _DocumentoLegalScreenState extends State<DocumentoLegalScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _doc;

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
      final rows = await Supabase.instance.client
          .schema('muevete')
          .from('documentos_legales')
          .select('codigo, version, titulo, resumen, contenido_md, '
              'publicado, vigente_desde, vigente_hasta')
          .eq('codigo', widget.codigo)
          .eq('publicado', true)
          .order('vigente_desde', ascending: false);

      final ahora = DateTime.now();
      Map<String, dynamic>? vigente;
      for (final raw in (rows as List)) {
        final fila = Map<String, dynamic>.from(raw as Map);
        final hasta = DateTime.tryParse((fila['vigente_hasta'] ?? '').toString());
        if (hasta == null || hasta.isAfter(ahora)) {
          vigente = fila;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _doc = vigente;
        _cargando = false;
        if (vigente == null) {
          _error = 'Este documento no está disponible por el momento.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No pudimos cargar el documento. Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  String get _titulo {
    final doc = _doc;
    final t = doc?['titulo']?.toString();
    if (t != null && t.trim().isNotEmpty) return t.trim();
    if (widget.tituloRespaldo != null) return widget.tituloRespaldo!;
    switch (widget.codigo) {
      case 'terminos':
        return 'Términos y condiciones';
      case 'privacidad':
        return 'Política de privacidad';
      case 'kyc':
        return 'Uso y tratamiento de datos para verificar tu identidad';
      default:
        return 'Documento legal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final texto = (_doc?['contenido_md'] ?? '').toString();
    final version = _doc?['version']?.toString();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkBg : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary(isDark)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          _titulo,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(isDark)
              : _buildContenido(isDark, texto, version),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 44, color: AppTheme.textTertiary(isDark)),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                height: 1.5,
                color: AppTheme.textSecondary(isDark),
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido(bool isDark, String texto, String? version) {
    final bloques = _bloques(texto, isDark, 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        if (version != null && version.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Versión $version · vigente',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        const SizedBox(height: 14),
        ...bloques,
      ],
    );
  }

  // ── Markdown mínimo (encabezados, listas, negritas, párrafos) ─────────────

  List<Widget> _bloques(String md, bool isDark, double _) {
    final salida = <Widget>[];
    final lineas = md.replaceAll('\r\n', '\n').split('\n');

    for (final raw in lineas) {
      final linea = raw.trimRight();
      final t = linea.trim();

      if (t.isEmpty) {
        salida.add(const SizedBox(height: 8));
        continue;
      }
      if (t == '---' || t == '***' || t == '___') {
        salida.add(const Divider(height: 26));
        continue;
      }
      if (t.startsWith('### ')) {
        salida.add(_tituloBloque(t.substring(4), 14.5, isDark));
        continue;
      }
      if (t.startsWith('## ')) {
        salida.add(_tituloBloque(t.substring(3), 17, isDark));
        continue;
      }
      if (t.startsWith('# ')) {
        salida.add(_tituloBloque(t.substring(2), 21, isDark));
        continue;
      }
      if (t.startsWith('- ') || t.startsWith('* ') || t.startsWith('• ')) {
        salida.add(_vineta(t.substring(2), isDark));
        continue;
      }
      final numerada = RegExp(r'^(\d{1,2})[.)]\s+(.*)$').firstMatch(t);
      if (numerada != null) {
        salida.add(_vineta(numerada.group(2)!, isDark,
            numero: numerada.group(1)));
        continue;
      }
      salida.add(_parrafo(t, isDark));
    }
    return salida;
  }

  Widget _tituloBloque(String texto, double tam, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        _sinMarcas(texto),
        style: GoogleFonts.plusJakartaSans(
          fontSize: tam,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: AppTheme.textPrimary(isDark),
        ),
      ),
    );
  }

  Widget _parrafo(String texto, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(children: _spans(texto, AppTheme.textSecondary(isDark))),
        style: GoogleFonts.plusJakartaSans(fontSize: 13.5, height: 1.55),
      ),
    );
  }

  Widget _vineta(String texto, bool isDark, {String? numero}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              numero == null ? '•' : '$numero.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                height: 1.55,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: _spans(texto, AppTheme.textSecondary(isDark))),
              style: GoogleFonts.plusJakartaSans(fontSize: 13.5, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  /// Convierte `**negrita**` en spans; el resto es texto normal.
  List<TextSpan> _spans(String texto, Color color) {
    final spans = <TextSpan>[];
    final partes = texto.split('**');
    for (var i = 0; i < partes.length; i++) {
      final parte = _sinMarcas(partes[i]);
      if (parte.isEmpty) continue;
      spans.add(TextSpan(
        text: parte,
        style: TextStyle(
          color: color,
          fontWeight: i.isOdd ? FontWeight.w700 : FontWeight.w400,
        ),
      ));
    }
    return spans;
  }

  /// Quita marcas de markdown que no representamos (código inline, enlaces …).
  String _sinMarcas(String texto) {
    return texto
        .replaceAll('`', '')
        .replaceAllMapped(
            RegExp(r'\[([^\]]+)\]\([^\)]+\)'), (m) => m.group(1) ?? '');
  }
}