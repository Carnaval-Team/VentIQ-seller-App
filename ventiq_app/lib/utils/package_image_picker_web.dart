// Implementación de picker de imágenes para Flutter Web.
//
// - Galería: <input type=file accept="image/*"> + FileReader. Funciona en
//   todos los navegadores y evita el bug "Blob revocado" de image_picker_web.
// - Cámara: getUserMedia + <video> + canvas para tomar la foto. Esto abre la
//   webcam real (también en desktop), no la galería. Si getUserMedia falla
//   (permiso denegado, sin cámara, etc.), se hace fallback al input file con
//   capture="environment" para que en móviles antiguos al menos se abra la
//   cámara nativa del SO.

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

class PickedImageData {
  final Uint8List bytes;
  final String name;
  final String? mimeType;
  const PickedImageData({
    required this.bytes,
    required this.name,
    this.mimeType,
  });
}

Future<PickedImageData?> pickImageWeb({required bool useCamera}) async {
  if (useCamera) {
    try {
      final captured = await _captureFromCamera();
      if (captured != null) return captured;
      // Si el usuario canceló el modal de cámara, no hacemos fallback.
      return null;
    } catch (e) {
      // getUserMedia no disponible / permiso denegado / navegador inseguro.
      // Caemos al input con capture para que en móvil al menos lo intente.
      html.window.console.warn('getUserMedia falló, fallback a input file: $e');
      return _pickFromFileInput(useCameraCapture: true);
    }
  }
  return _pickFromFileInput(useCameraCapture: false);
}

Future<PickedImageData?> _pickFromFileInput({
  required bool useCameraCapture,
}) async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false;
  if (useCameraCapture) {
    input.setAttribute('capture', 'environment');
  }
  input.style.display = 'none';
  html.document.body?.append(input);

  final completer = Completer<PickedImageData?>();
  StreamSubscription<html.Event>? changeSub;
  StreamSubscription<html.Event>? focusSub;
  Timer? cancelTimer;

  void cleanup() {
    changeSub?.cancel();
    focusSub?.cancel();
    cancelTimer?.cancel();
    input.remove();
  }

  changeSub = input.onChange.listen((event) async {
    try {
      final files = input.files;
      if (files == null || files.isEmpty) {
        if (!completer.isCompleted) completer.complete(null);
        cleanup();
        return;
      }
      final file = files.first;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoadEnd.first;
      final result = reader.result;
      Uint8List? bytes;
      if (result is ByteBuffer) {
        bytes = result.asUint8List();
      } else if (result is List<int>) {
        bytes = Uint8List.fromList(result);
      }
      if (!completer.isCompleted) {
        completer.complete(
          bytes == null
              ? null
              : PickedImageData(
                  bytes: bytes,
                  name: file.name,
                  mimeType: file.type.isEmpty ? null : file.type,
                ),
        );
      }
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
    } finally {
      cleanup();
    }
  });

  focusSub = html.window.onFocus.listen((_) {
    cancelTimer?.cancel();
    cancelTimer = Timer(const Duration(seconds: 1), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        cleanup();
      }
    });
  });

  input.click();
  return completer.future;
}

Future<PickedImageData?> _captureFromCamera() async {
  final mediaDevices = html.window.navigator.mediaDevices;
  if (mediaDevices == null) {
    throw StateError('mediaDevices no disponible en este navegador');
  }

  // Pedimos cámara trasera si está disponible; si no, cualquiera.
  final constraints = {
    'video': {
      'facingMode': {'ideal': 'environment'},
      'width': {'ideal': 1280},
      'height': {'ideal': 720},
    },
    'audio': false,
  };

  final stream = await mediaDevices.getUserMedia(constraints);

  final completer = Completer<PickedImageData?>();

  // --- Construir overlay con preview + botones ---
  final overlay = html.DivElement()
    ..style.position = 'fixed'
    ..style.top = '0'
    ..style.left = '0'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.zIndex = '99999'
    ..style.background = 'rgba(0,0,0,0.92)'
    ..style.display = 'flex'
    ..style.flexDirection = 'column'
    ..style.alignItems = 'center'
    ..style.justifyContent = 'center';

  final video = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', 'true')
    ..style.maxWidth = '92vw'
    ..style.maxHeight = '72vh'
    ..style.borderRadius = '10px'
    ..style.background = 'black';
  video.srcObject = stream;

  final btnRow = html.DivElement()
    ..style.display = 'flex'
    ..style.gap = '14px'
    ..style.marginTop = '20px';

  final cancelBtn = html.ButtonElement()
    ..text = 'Cancelar'
    ..style.padding = '12px 20px'
    ..style.borderRadius = '8px'
    ..style.border = 'none'
    ..style.background = '#555'
    ..style.color = 'white'
    ..style.fontSize = '15px'
    ..style.cursor = 'pointer';

  final captureBtn = html.ButtonElement()
    ..text = '📷  Tomar foto'
    ..style.padding = '12px 22px'
    ..style.borderRadius = '8px'
    ..style.border = 'none'
    ..style.background = '#194B8C'
    ..style.color = 'white'
    ..style.fontSize = '15px'
    ..style.fontWeight = 'bold'
    ..style.cursor = 'pointer';

  btnRow.append(cancelBtn);
  btnRow.append(captureBtn);
  overlay.append(video);
  overlay.append(btnRow);
  html.document.body?.append(overlay);

  void stopStream() {
    try {
      final tracks = stream.getTracks();
      for (final t in tracks) {
        t.stop();
      }
    } catch (_) {}
  }

  void cleanup() {
    stopStream();
    overlay.remove();
  }

  cancelBtn.onClick.listen((_) {
    if (!completer.isCompleted) completer.complete(null);
    cleanup();
  });

  captureBtn.onClick.listen((_) async {
    try {
      final vw = video.videoWidth;
      final vh = video.videoHeight;
      if (vw == 0 || vh == 0) return;
      final canvas = html.CanvasElement(width: vw, height: vh);
      final ctx = canvas.context2D;
      ctx.drawImageScaled(video, 0, 0, vw, vh);

      // canvas.toBlob para obtener bytes JPEG ~80% calidad.
      final blob = await _canvasToBlob(canvas, 'image/jpeg', 0.85);
      if (blob == null) {
        if (!completer.isCompleted) completer.complete(null);
        cleanup();
        return;
      }
      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      await reader.onLoadEnd.first;
      final result = reader.result;
      Uint8List? bytes;
      if (result is ByteBuffer) {
        bytes = result.asUint8List();
      } else if (result is List<int>) {
        bytes = Uint8List.fromList(result);
      }
      if (!completer.isCompleted) {
        completer.complete(
          bytes == null
              ? null
              : PickedImageData(
                  bytes: bytes,
                  name: 'camara_${DateTime.now().millisecondsSinceEpoch}.jpg',
                  mimeType: 'image/jpeg',
                ),
        );
      }
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
    } finally {
      cleanup();
    }
  });

  return completer.future;
}

Future<html.Blob?> _canvasToBlob(
  html.CanvasElement canvas,
  String mimeType,
  double quality,
) {
  final completer = Completer<html.Blob?>();
  // canvas.toBlob es una API nativa con callback; usamos js_util para
  // invocarla porque la versión Dart no expone calidad en todas las versiones.
  js_util.callMethod(canvas, 'toBlob', [
    js_util.allowInterop((html.Blob? blob) {
      if (!completer.isCompleted) completer.complete(blob);
    }),
    mimeType,
    quality,
  ]);
  return completer.future;
}
