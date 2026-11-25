import 'dart:convert';
import 'dart:io';

import 'package:aves/model/tags/tag_path.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// Portraits for tags (e.g. a character's face), to recognize who a tag is.
// Stored as PNG files in the app private storage, one per tag,
// named after the tag path, so they are not written into the user's images.
class TagPortraits {
  static final TagPortraits instance = TagPortraits._private();

  // incremented when portraits change, to rebuild widgets showing them
  final ValueNotifier<int> changeNotifier = ValueNotifier(0);

  Directory? _directory;
  final Set<String> _tags = {};
  Future<void>? _loading;

  new _private();

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final dir = Directory(p.join(await getDatabasesPath(), 'tag_portraits'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _directory = dir;
    await for (final file in dir.list()) {
      if (file is! File) continue;
      final tag = _tagForFileName(p.basename(file.path));
      if (tag != null) _tags.add(tag);
    }
    changeNotifier.value++;
  }

  bool has(String tag) => _tags.contains(TagPath.normalize(tag));

  // null if there is no portrait for this tag
  File? fileFor(String tag) {
    final dir = _directory;
    final normalized = TagPath.normalize(tag);
    if (dir == null || !_tags.contains(normalized)) return null;
    return File(p.join(dir.path, _fileNameForTag(normalized)));
  }

  Future<void> save(String tag, Uint8List pngBytes) async {
    await ensureLoaded();
    final normalized = TagPath.normalize(tag);
    final file = File(p.join(_directory!.path, _fileNameForTag(normalized)));
    await file.writeAsBytes(pngBytes, flush: true);
    // the previous portrait may still be in the image cache
    await FileImage(file).evict();
    _tags.add(normalized);
    changeNotifier.value++;
  }

  Future<void> remove(String tag) async {
    final file = fileFor(tag);
    if (file == null) return;
    await FileImage(file).evict();
    if (await file.exists()) {
      await file.delete();
    }
    _tags.remove(TagPath.normalize(tag));
    changeNotifier.value++;
  }

  // file names are the tag path encoded in base64, which is safe for file systems
  static String _fileNameForTag(String tag) => '${base64Url.encode(utf8.encode(tag)).replaceAll('=', '')}.png';

  static String? _tagForFileName(String fileName) {
    if (!fileName.endsWith('.png')) return null;
    var encoded = fileName.substring(0, fileName.length - 4);
    encoded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
    try {
      return utf8.decode(base64Url.decode(encoded));
    } catch (error) {
      debugPrint('failed to decode tag portrait file name=$fileName error=$error');
      return null;
    }
  }
}
