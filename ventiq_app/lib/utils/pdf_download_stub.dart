// Stub para mobile/desktop. En esas plataformas se usa Share.shareXFiles, no este helper.
import 'dart:typed_data';

void downloadPdfWeb(Uint8List bytes, String fileName) {
  throw UnsupportedError(
    'downloadPdfWeb solo esta disponible en Flutter Web.',
  );
}
