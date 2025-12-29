import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:qr_flutter/qr_flutter.dart';

class CatalogQrPrintServiceImpl {
  Future<bool> printQr({required String title, required String data}) async {
    try {
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: true,
      );

      final byteData = await painter.toImageData(
        512,
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return false;

      final bytes = byteData.buffer.asUint8List();
      final encoded = base64Encode(bytes);

      final safeTitle = htmlEscape.convert(title);
      final safeUrl = htmlEscape.convert(data);

      final htmlString =
          '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>$safeTitle</title>
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; }
    .wrap { display:flex; flex-direction:column; align-items:center; gap: 12px; }
    .title { font-size: 18px; font-weight: 700; }
    .url { font-size: 12px; color: #555; word-break: break-all; text-align:center; max-width: 560px; }
    img { width: 320px; height: 320px; }
    @media print { body { padding: 0; } }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="title">$safeTitle</div>
    <img alt="QR" src="data:image/png;base64,$encoded" />
    <div class="url">$safeUrl</div>
  </div>
  <script>
    window.onload = function() { window.print(); };
  </script>
</body>
</html>
''';

      final htmlBase64 = base64Encode(utf8.encode(htmlString));
      final decodedHtml = utf8.decode(base64Decode(htmlBase64));

      final blob = html.Blob([decodedHtml], 'text/html');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);

      final printWindow = html.window.open(blobUrl, '_blank');
      if (printWindow.closed == true) return false;

      Future<void>.delayed(const Duration(seconds: 30), () {
        try {
          html.Url.revokeObjectUrl(blobUrl);
        } catch (_) {}
      });

      return true;
    } catch (_) {
      return false;
    }
  }
}
