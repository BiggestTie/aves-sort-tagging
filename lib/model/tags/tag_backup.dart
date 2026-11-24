import 'dart:convert';
import 'dart:io';

import 'package:aves/model/entry/entry.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// Snapshots of item tags, saved before bulk tag changes so they can be undone.
// Stored as JSON files in the app private storage.
class TagBackup {
  final File file;
  final DateTime created;
  final int itemCount;

  const new(this.file, this.created, this.itemCount);

  static Future<Directory> _directory() async {
    final dir = Directory(p.join(await getDatabasesPath(), 'tag_backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<TagBackup> save(Iterable<AvesEntry> entries, {required String label}) async {
    final created = DateTime.now();
    final items = entries
        .map(
          (entry) => {
            'id': entry.id,
            'path': entry.path,
            'tags': entry.tags.toList()..sort(),
          },
        )
        .toList();
    final content = jsonEncode({
      'created': created.toIso8601String(),
      'label': label,
      'items': items,
    });
    final dir = await _directory();
    final file = File(p.join(dir.path, 'tags_${created.millisecondsSinceEpoch}.json'));
    await file.writeAsString(content, flush: true);
    return TagBackup(file, created, items.length);
  }

  static Future<List<TagBackup>> list() async {
    final dir = await _directory();
    final backups = <TagBackup>[];
    await for (final file in dir.list().where((v) => v is File && v.path.endsWith('.json')).cast<File>()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final created = DateTime.parse(json['created'] as String);
        final items = json['items'] as List;
        backups.add(TagBackup(file, created, items.length));
      } catch (error) {
        debugPrint('failed to read tag backup at ${file.path} error=$error');
      }
    }
    backups.sort((a, b) => b.created.compareTo(a.created));
    return backups;
  }

  // tags by item, for items still present in `entries`, matched by path then by ID
  Future<Map<AvesEntry, Set<String>>> read(Iterable<AvesEntry> entries) async {
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final items = (json['items'] as List).cast<Map<String, dynamic>>();
    final byPath = <String, AvesEntry>{};
    final byId = <int, AvesEntry>{};
    for (final entry in entries) {
      final path = entry.path;
      if (path != null) byPath[path] = entry;
      byId[entry.id] = entry;
    }
    final result = <AvesEntry, Set<String>>{};
    for (final item in items) {
      final path = item['path'] as String?;
      final id = item['id'] as int?;
      final entry = (path != null ? byPath[path] : null) ?? (id != null ? byId[id] : null);
      if (entry != null) {
        result[entry] = (item['tags'] as List).cast<String>().toSet();
      }
    }
    return result;
  }

  Future<void> delete() => file.delete();
}
