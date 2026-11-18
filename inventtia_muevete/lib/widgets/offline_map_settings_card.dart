import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/offline_map_source.dart';
import '../services/mbtiles_service.dart';

/// Tarjeta de ajustes del mapa offline.
///
/// Permite encender/apagar el mapa descargado y elegir entre las fuentes
/// disponibles: la que viene con la app (por defecto) y las opcionales, que el
/// usuario descarga desde Supabase Storage o importa desde el teléfono.
class OfflineMapSettingsCard extends StatefulWidget {
  final bool isDark;

  const OfflineMapSettingsCard({super.key, required this.isDark});

  @override
  State<OfflineMapSettingsCard> createState() => _OfflineMapSettingsCardState();
}

class _OfflineMapSettingsCardState extends State<OfflineMapSettingsCard> {
  bool _working = false;

  bool get _isDark => widget.isDark;
  Color get _cardColor => _isDark ? AppTheme.darkCard : Colors.white;
  Color get _borderColor =>
      _isDark ? AppTheme.darkBorder : (Colors.grey[200] ?? Colors.grey);
  Color get _textPrimary => _isDark ? Colors.white : Colors.black87;
  Color get _textSecondary =>
      _isDark ? Colors.white54 : (Colors.grey[600] ?? Colors.grey);

  TextStyle _title([double size = 15]) => GoogleFonts.plusJakartaSans(
    fontWeight: FontWeight.w600,
    fontSize: size,
    color: _textPrimary,
  );

  TextStyle _caption([double size = 12]) =>
      GoogleFonts.plusJakartaSans(fontSize: size, color: _textSecondary);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MbTilesService.instance,
      builder: (context, _) {
        final service = MbTilesService.instance;
        return Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSwitch(service),
              Divider(height: 1, color: _borderColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'FUENTE DEL MAPA',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _textSecondary,
                  ),
                ),
              ),
              for (final source in service.sources)
                _buildSourceRow(service, source),
              if (_working)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: AppTheme.primaryColor,
                    backgroundColor: _borderColor,
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSwitch(MbTilesService service) {
    return SwitchListTile(
      secondary: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.map_outlined,
            color: AppTheme.primaryColor,
            size: 22,
          ),
          IconButton(
            icon: Icon(
              Icons.help_outline,
              color: AppTheme.primaryColor,
              size: 20,
            ),
            tooltip: 'Cómo funciona el mapa offline',
            onPressed: _showHelp,
          ),
        ],
      ),
      title: Text('Mapa Offline', style: _title()),
      subtitle: Text(
        service.isAvailable
            ? 'Fuente activa: ${service.activeSource.label}'
            : 'Ninguna fuente descargada todavía',
        style: _caption(),
      ),
      value: service.useOffline,
      activeThumbColor: AppTheme.primaryColor,
      onChanged: service.isAvailable && !_working
          ? (value) async {
              await service.toggleOffline(value);
            }
          : null,
    );
  }

  Widget _buildSourceRow(MbTilesService service, OfflineMapSource source) {
    final isActive = service.activeSource.id == source.id;
    final available = service.isSourceAvailable(source.id);
    final sizeBytes = service.sourceSizeBytes(source.id);

    final String status;
    if (available) {
      final mb = (sizeBytes ?? 0) / (1024 * 1024);
      status = '${mb.toStringAsFixed(0)} MB · lista';
    } else {
      status = 'No descargada · ${source.sizeLabel}';
    }

    return InkWell(
      onTap: _working ? null : () => _selectSource(source),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: isActive
                    ? AppTheme.primaryColor
                    : (_isDark ? Colors.white38 : Colors.grey[400]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.label, style: _title(14)),
                  const SizedBox(height: 2),
                  Text(source.description, style: _caption(11.5)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          status,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: available
                                ? AppTheme.success
                                : (_isDark ? Colors.white38 : Colors.grey[500]),
                          ),
                        ),
                      ),
                      if (isActive && available) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.check_circle,
                          size: 13,
                          color: AppTheme.success,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (available && !source.isBundled)
              IconButton(
                tooltip: 'Eliminar del teléfono',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: _isDark ? Colors.white38 : Colors.grey[500],
                ),
                onPressed: _working ? null : () => _confirmDelete(source),
              ),
          ],
        ),
      ),
    );
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  /// Marca la fuente como activa y enciende el mapa offline.
  Future<bool> _activate(OfflineMapSource source) async {
    final service = MbTilesService.instance;
    final selected = await service.selectSource(source.id);
    if (selected && !service.useOffline) {
      await service.toggleOffline(true);
    }
    return selected;
  }

  Future<void> _selectSource(OfflineMapSource source) async {
    final service = MbTilesService.instance;
    if (service.activeSource.id == source.id) return;

    final selected = await _activate(source);
    if (selected || !mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          source.label,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Todavía no está en este teléfono. Puedes descargarlo '
          '(${source.sizeLabel}) o importar un archivo .mbtiles que ya tengas.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          if (source.canDownload)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'download'),
              child: const Text('Descargar'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'import'),
            child: const Text('Importar archivo'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'download') {
      await _downloadSource(source);
    } else if (action == 'import') {
      await _importSource(source);
    }
  }

  Future<void> _downloadSource(OfflineMapSource source) async {
    await _runTask(
      title: 'Descargando ${source.label}',
      task: (onProgress) => MbTilesService.instance.downloadSource(
        source.id,
        onProgress: onProgress,
      ),
      afterSuccess: () => _activate(source),
    );
  }

  Future<void> _importSource(OfflineMapSource source) async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
      );
    } catch (_) {
      _snack('No se pudo abrir el selector de archivos.', error: true);
      return;
    }
    final pickedPath = picked?.files.single.path;
    if (pickedPath == null) return;
    final String filePath = pickedPath;

    await _runTask(
      title: 'Importando ${source.label}',
      task: (onProgress) => MbTilesService.instance.importSource(
        source.id,
        filePath,
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _confirmDelete(OfflineMapSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          'Eliminar mapa',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Se borrará «${source.label}» del teléfono. Si lo vuelves a '
          'necesitar tendrás que descargarlo otra vez.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await MbTilesService.instance.deleteSource(source.id);
    if (!mounted) return;
    _snack(ok ? 'Mapa eliminado' : 'No se pudo eliminar el mapa', error: !ok);
  }

  /// Ejecuta una tarea con barra de progreso modal y un snackbar al terminar.
  Future<void> _runTask({
    required String title,
    required Future<OfflineMapOperationResult> Function(
      void Function(double progress),
    )
    task,
    Future<void> Function()? afterSuccess,
  }) async {
    if (_working) return;
    setState(() => _working = true);

    final progress = ValueNotifier<double>(0);
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: _cardColor,
          title: Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: value <= 0 ? null : value,
                  color: AppTheme.primaryColor,
                  backgroundColor: _borderColor,
                ),
                const SizedBox(height: 12),
                Text(
                  value <= 0
                      ? 'Preparando…'
                      : '${(value * 100).toStringAsFixed(0)} %',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    OfflineMapOperationResult result;
    try {
      result = await task((value) => progress.value = value);
    } catch (e) {
      result = const OfflineMapOperationResult.failure(
        'Ocurrió un error inesperado.',
      );
    }

    if (dialogOpen && mounted) {
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();
    if (!mounted) return;

    if (result.ok) {
      try {
        await afterSuccess?.call();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _working = false);
      _snack('Mapa listo');
    } else {
      setState(() => _working = false);
      _snack(
        result.message ?? 'No se pudo completar la operación',
        error: true,
      );
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.plusJakartaSans()),
        backgroundColor: error ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardColor,
        title: Text(
          'Mapa Offline',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _helpStep(
                '1',
                'La app guarda el mapa como un archivo .mbtiles con tiles '
                    'vectoriales dentro del teléfono.',
              ),
              _helpStep(
                '2',
                '«Cuba (incluido)» viene empaquetado con la app y se copia '
                    'solo en el primer arranque. Es la fuente por defecto.',
              ),
              _helpStep(
                '3',
                'Las fuentes opcionales se descargan desde el servidor o se '
                    'importan con el botón «Importar archivo».',
              ),
              _helpStep(
                '4',
                'Elige la fuente tocándola en la lista y enciende el '
                    'interruptor «Mapa Offline» para usar el mapa descargado.',
              ),
              _helpStep(
                '5',
                'Un .mbtiles válido para la app debe ser vectorial (formato '
                    'pbf) con el esquema OpenMapTiles. Un .osm.pbf o un .gpkg '
                    'crudos no sirven: hay que convertirlos primero.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget _helpStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
            child: Text(
              number,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
