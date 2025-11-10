import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

/// Mobile implementation for image picker service
class ImagePickerService {
  static Future<Uint8List?> pickImage() async {
    try {
      final ImagePicker imagePicker = ImagePicker();
      
      // Show options dialog for camera or gallery
      final ImageSource? source = await _showImageSourceDialog();
      if (source == null) return null;
      
      final XFile? image = await imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (image != null) {
        return await image.readAsBytes();
      }
      
      return null;
    } catch (e) {
      print('❌ Error picking image on mobile: $e');
      return null;
    }
  }
  
  static Future<ImageSource?> _showImageSourceDialog() async {
    // This will be called from the UI context
    // For now, default to gallery
    return ImageSource.gallery;
  }
}
