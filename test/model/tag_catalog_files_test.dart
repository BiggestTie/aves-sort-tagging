import 'dart:io';

import 'package:aves/model/tags/tag_path.dart';
import 'package:test/test.dart';

// sanity checks of the bundled tag catalog files
void main() {
  final files = Directory('assets').listSync().whereType<File>().where((f) => f.path.contains('tag_catalog_')).toList();

  test('catalog files exist', () {
    expect(files.length, greaterThanOrEqualTo(6));
  });

  for (final file in files) {
    test('catalog entries are well formed in ${file.path}', () {
      final lines = file.readAsLinesSync().map((v) => v.trim()).where((v) => v.isNotEmpty && !v.startsWith('#'));
      expect(lines, isNotEmpty);
      final paths = <String>{};
      for (final line in lines) {
        final path = line.split(';').first.trim();
        expect(TagPath.normalize(path), path, reason: line);
        expect(TagPath.segments(path).length, greaterThanOrEqualTo(2), reason: line);
        expect(paths.add(path), true, reason: 'duplicate: $line');
      }
    });
  }
}
