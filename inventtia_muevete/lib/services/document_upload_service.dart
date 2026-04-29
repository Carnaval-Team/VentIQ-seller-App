import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DocumentUploadService {
  static const _bucket = 'muevete';
  static const _folder = 'docs';

  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    return _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1600,
      maxHeight: 1600,
    );
  }

  Future<Uint8List> compress(XFile file) async {
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1024,
        minHeight: 1024,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      return result;
    }

    final result = await FlutterImageCompress.compressWithFile(
      file.path,
      minWidth: 1024,
      minHeight: 1024,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    if (result == null) {
      return File(file.path).readAsBytesSync();
    }
    return result;
  }

  /// Uploads a document image to muevete/docs/{uuid}/{filename}.jpg
  Future<String> upload(String uuid, String filename, Uint8List bytes) async {
    final path = '$_folder/$uuid/$filename.jpg';

    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return _supabase.storage.from(_bucket).getPublicUrl(path);
  }

  /// Full flow: pick → compress → upload → return public URL.
  Future<String?> pickCompressAndUpload({
    required String uuid,
    required String filename,
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await pickImage(source: source);
    if (file == null) return null;

    final bytes = await compress(file);
    return upload(uuid, filename, bytes);
  }
}
