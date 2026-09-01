import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/muevete_map_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteMapUploadScreen extends StatefulWidget {
  const MueveteMapUploadScreen({super.key});

  @override
  State<MueveteMapUploadScreen> createState() => _MueveteMapUploadScreenState();
}

class _MueveteMapUploadScreenState extends State<MueveteMapUploadScreen> {
  final _pathCtrl = TextEditingController();
  final _versionCtrl = TextEditingController(text: '1');
  bool _isUploading = false;

  @override
  void dispose() {
    _pathCtrl.dispose();
    _versionCtrl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final path = _pathCtrl.text.trim();
    final version = int.tryParse(_versionCtrl.text.trim()) ?? 1;

    if (path.isEmpty) {
      _showMessage('Introduce la ruta del archivo .mbtiles', isError: true);
      return;
    }

    setState(() => _isUploading = true);
    try {
      await MueveteMapService.uploadMbtiles(path, version: version);
      if (mounted) _showMessage('Mapa subido correctamente a Supabase');
    } catch (e) {
      if (mounted) _showMessage('Error al subir: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(w);
    final pad = isDesktop ? 32.0 : 16.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            title: const Text('Subir mapa offline'),
            pinned: true,
          ),
          SliverPadding(
            padding: EdgeInsets.all(pad),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const Text(
                  'Publica un archivo .mbtiles en Supabase Storage para que los usuarios de la app puedan descargarlo.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pathCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ruta del archivo .mbtiles',
                    hintText: 'C:\\mapas\\cuba.mbtiles',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _versionCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Versión (número entero)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _upload,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(_isUploading ? 'Subiendo...' : 'Subir mapa'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ejemplo: pega la ruta completa de un archivo .mbtiles en este equipo y presiona Subir.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (!isDesktop) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Nota: para dispositivos móviles, recomienda usar file_picker para seleccionar el archivo.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
