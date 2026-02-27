import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePhotoService {
  static const _bucket = 'muevete';
  static const _folder = 'profile_photos';

  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  /// Opens the gallery/camera picker. Returns null if cancelled.
  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    return _picker.pickImage(
      source: source,
      imageQuality: 90, // pre-shrink before we compress further
      maxWidth: 1024,
      maxHeight: 1024,
    );
  }

  /// Compresses [file] to max 512×512 JPEG at ~75% quality.
  /// Returns the compressed bytes.
  Future<Uint8List> compress(XFile file) async {
    if (kIsWeb) {
      // On web flutter_image_compress works via canvas; use XFile bytes directly
      // and skip the native compress path.
      final bytes = await file.readAsBytes();
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 512,
        minHeight: 512,
        quality: 75,
        format: CompressFormat.jpeg,
      );
      return result;
    }

    final result = await FlutterImageCompress.compressWithFile(
      file.path,
      minWidth: 512,
      minHeight: 512,
      quality: 75,
      format: CompressFormat.jpeg,
    );
    if (result == null) {
      // Fallback: return raw bytes uncompressed
      return File(file.path).readAsBytesSync();
    }
    return result;
  }

  /// Uploads compressed photo to Supabase Storage and returns the public URL.
  /// [uuid] is the auth user id — used as the filename so each user has one file.
  Future<String> upload(String uuid, Uint8List bytes) async {
    final path = '$_folder/$uuid.jpg';

    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true, // overwrite existing
          ),
        );

    return _supabase.storage.from(_bucket).getPublicUrl(path);
  }

  /// Full flow: pick → compress → upload → return public URL.
  /// Returns null if the user cancels.
  Future<String?> pickCompressAndUpload({
    required String uuid,
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await pickImage(source: source);
    if (file == null) return null;

    final bytes = await compress(file);
    return upload(uuid, bytes);
  }
}
