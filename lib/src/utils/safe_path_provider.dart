/// Web-safe wrapper for path_provider.
///
/// On web, path_provider throws MissingPluginException and
/// dart:io Directory throws UnsupportedError.
/// This utility returns null on web so callers can bail out early.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart' as pp;
import 'dart:io';

/// Returns the application documents directory, or null on web.
Future<Directory?> getSafeDocumentsDirectory() async {
  if (kIsWeb) return null;
  return pp.getApplicationDocumentsDirectory();
}

/// Returns the temporary directory, or null on web.
Future<Directory?> getSafeTempDirectory() async {
  if (kIsWeb) return null;
  return pp.getTemporaryDirectory();
}

/// Returns the application support directory, or null on web.
Future<Directory?> getSafeAppSupportDirectory() async {
  if (kIsWeb) return null;
  return pp.getApplicationSupportDirectory();
}
