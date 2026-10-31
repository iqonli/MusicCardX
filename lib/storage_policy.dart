import 'dart:io';

/// Removes only regenerable shared-font copies and unreferenced local blobs.
/// Imported fonts still referenced by the catalog are user data, never cache.
Future<void> pruneFontStorage(Directory root, Set<String> localPaths) async {
  if (!await root.exists()) return;
  await for (final file in root.list(followLinks: false)) {
    if (file is! File) continue;
    final name = file.uri.pathSegments.last;
    if (RegExp(r'^[a-f0-9]{64}\.cache$').hasMatch(name) ||
        (RegExp(r'^[a-f0-9]{64}\.font$').hasMatch(name) &&
            !localPaths.contains(file.path))) {
      try {
        await file.delete();
      } on FileSystemException {
        /* Another cleanup may have removed it. */
      }
    }
  }
}
