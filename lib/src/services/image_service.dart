import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/safe_path_provider.dart';
import 'package:path/path.dart' as path;
import '../l10n/fluera_localizations.dart';

/// 🖼️ IMAGE SERVICE
/// Handles selezione e caricamento immagini from the galleria
class ImageService {
  /// Seleziona un'immagine from the galleria
  /// Returns il path locale of the image salvata
  static Future<String?> pickImageFromGallery(BuildContext context) async {
    try {
      // Open galleria con file_picker (cross-platform: mobile + desktop)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return null;
      final pickedFile = result.files.first;
      if (pickedFile.path == null) return null;

      // Save the image in the app directory
      final appDir = await getSafeDocumentsDirectory();
      if (appDir == null) return null; // Web: no filesystem
      final imagesDir = Directory('${appDir.path}/canvas_images');

      // Create directory if not esiste
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      // Genera nome unico
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(pickedFile.path!);
      final fileName = 'image_$timestamp$extension';
      final savedPath = '${imagesDir.path}/$fileName';

      // Copia il file
      await File(pickedFile.path!).copy(savedPath);

      return savedPath;
    } catch (e) {
      if (context.mounted) {
        final l10n = FlueraLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.proCanvas_errorLoadingImage(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  /// Loads un'immagine da file in memoria (ui.Image)
  /// Images larger than [maxDimension] are downscaled proportionally.
  static Future<ui.Image?> loadImageFromPath(
    String imagePath, {
    int maxDimension = 2048,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;

      // Within limits — use as-is
      if (w <= maxDimension && h <= maxDimension) {
        codec.dispose();
        return frame.image;
      }

      // Downscale: dispose full-res, re-decode capped
      frame.image.dispose();
      codec.dispose();

      int targetW, targetH;
      if (w >= h) {
        targetW = maxDimension;
        targetH = (h * maxDimension / w).round();
      } else {
        targetH = maxDimension;
        targetW = (w * maxDimension / h).round();
      }

      final cappedCodec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final cappedFrame = await cappedCodec.getNextFrame();
      cappedCodec.dispose();
      return cappedFrame.image;
    } catch (e) {
      return null;
    }
  }

  /// Calculates le dimensioni of the image da un path
  static Future<Size?> getImageSize(String imagePath) async {
    final image = await loadImageFromPath(imagePath);
    if (image == null) return null;
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  /// Elimina un'immagine dal filesystem
  static Future<void> deleteImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {}
  }

  /// Clears tutte le immagini non utilizzate
  static Future<void> cleanupUnusedImages(List<String> usedPaths) async {
    try {
      final appDir = await getSafeDocumentsDirectory();
      if (appDir == null) return; // Web: no filesystem
      final imagesDir = Directory('${appDir.path}/canvas_images');

      if (!await imagesDir.exists()) return;

      final files = await imagesDir.list().toList();
      for (final file in files) {
        if (file is File) {
          final filePath = file.path;
          if (!usedPaths.contains(filePath)) {
            await file.delete();
          }
        }
      }
    } catch (e) {}
  }
}
