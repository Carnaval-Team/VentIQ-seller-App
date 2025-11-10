import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';

/// Web implementation for image picker service
class ImagePickerService {
  static Future<Uint8List?> pickImage() async {
    try {
      // Create file input element
      final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
      uploadInput.accept = 'image/*';
      uploadInput.multiple = false;

      // Create a completer to handle the async file selection
      final completer = Completer<Uint8List?>();
      
      // Listen for file selection
      uploadInput.onChange.listen((e) async {
        final files = uploadInput.files;
        if (files != null && files.isNotEmpty) {
          final file = files[0];
          
          // Validate file type
          if (!file.type.startsWith('image/')) {
            completer.complete(null);
            return;
          }
          
          // Validate file size (max 5MB)
          if (file.size > 5 * 1024 * 1024) {
            completer.complete(null);
            return;
          }
          
          // Read file as bytes
          final reader = html.FileReader();
          reader.onLoadEnd.listen((e) {
            if (reader.result != null) {
              final Uint8List bytes = Uint8List.fromList(reader.result as List<int>);
              completer.complete(bytes);
            } else {
              completer.complete(null);
            }
          });
          
          reader.onError.listen((e) {
            completer.complete(null);
          });
          
          reader.readAsArrayBuffer(file);
        } else {
          completer.complete(null);
        }
      });

      // Handle case where no file is selected (user cancels)
      // This will be handled by the timeout or when user doesn't select anything

      // Trigger file picker
      uploadInput.click();
      
      // Add timeout to handle cancellation
      return completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => null,
      );
    } catch (e) {
      print('❌ Error picking image on web: $e');
      return null;
    }
  }
}
