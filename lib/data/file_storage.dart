import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileStorage {
  Directory? _root;

  Future<Directory> get root async {
    final cached = _root;
    if (cached != null) return cached;
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'fatech_files'));
    await directory.create(recursive: true);
    _root = directory;
    return directory;
  }

  Future<String> absolutePath(String relativePath) async =>
      p.join((await root).path, relativePath);

  Future<File> copyAttachment({
    required String sourcePath,
    required String id,
    required String kind,
    required String extension,
  }) async {
    final safeExtension = extension.startsWith('.') ? extension : '.$extension';
    final relative = p.join('attachments', kind, '$id$safeExtension');
    final target = File(await absolutePath(relative));
    await target.parent.create(recursive: true);
    return File(sourcePath).copy(target.path);
  }

  Future<String> relativePath(File file) async =>
      p.relative(file.path, from: (await root).path);

  Future<File> audioTarget(String id) async {
    final file = File(
      await absolutePath(p.join('attachments', 'audio', '$id.m4a')),
    );
    await file.parent.create(recursive: true);
    return file;
  }

  Future<File> writeKml(
    String visitId,
    String exportId,
    String contents,
  ) async {
    final file = File(
      await absolutePath(p.join('exports', 'fatech_${visitId}_$exportId.kml')),
    );
    await file.parent.create(recursive: true);
    return file.writeAsString(contents, flush: true);
  }

  Future<void> deleteRelative(String relativePath) async {
    final file = File(await absolutePath(relativePath));
    if (await file.exists()) await file.delete();
  }
}
