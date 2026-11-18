import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_muevete/models/offline_map_source.dart';

void main() {
  group('kOfflineMapSources', () {
    test('la fuente por defecto es la primera y viene empaquetada', () {
      expect(kOfflineMapSources, isNotEmpty);
      final first = kOfflineMapSources.first;
      expect(first.id, kDefaultOfflineMapSourceId);
      expect(first.isBundled, isTrue);
      expect(first.assetPath, 'assets/tiles/cuba.mbtiles');
    });

    test('los ids y los nombres de archivo no se repiten', () {
      final ids = kOfflineMapSources.map((s) => s.id).toSet();
      final files = kOfflineMapSources.map((s) => s.fileName).toSet();
      expect(ids.length, kOfflineMapSources.length);
      expect(files.length, kOfflineMapSources.length);
    });

    test('las fuentes opcionales no se empaquetan en el APK', () {
      final opcionales = kOfflineMapSources
          .where((s) => s.id != kDefaultOfflineMapSourceId)
          .toList();
      expect(opcionales, isNotEmpty);
      for (final source in opcionales) {
        expect(source.isBundled, isFalse,
            reason: '${source.id} no debe viajar en assets/tiles');
        expect(source.canDownload, isTrue,
            reason: '${source.id} necesita ruta en Supabase Storage');
        expect(source.fileName, endsWith('.mbtiles'));
      }
    });

    test('sizeLabel formatea MB y usa "tamaño variable" sin dato', () {
      const conTamano = OfflineMapSource(
        id: 'x',
        label: 'X',
        description: '',
        fileName: 'x.mbtiles',
        approxSizeBytes: 111276032,
      );
      expect(conTamano.sizeLabel, '106 MB');

      const sinTamano = OfflineMapSource(
        id: 'y',
        label: 'Y',
        description: '',
        fileName: 'y.mbtiles',
      );
      expect(sinTamano.sizeLabel, 'tamaño variable');
    });
  });
}