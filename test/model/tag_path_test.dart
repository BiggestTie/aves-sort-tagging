import 'package:aves/model/tags/tag_path.dart';
import 'package:test/test.dart';

void main() {
  test('normalize nested tags', () {
    expect(TagPath.normalize(' Blue Archive | Asuna '), 'Blue Archive|Asuna');
    expect(TagPath.normalize('Blue Archive||Asuna|'), 'Blue Archive|Asuna');
    expect(TagPath.normalize('waifu'), 'waifu');
  });

  test('parts of nested tags', () {
    const tag = 'Blue Archive|Millennium|C&C|Asuna';
    expect(TagPath.leaf(tag), 'Asuna');
    expect(TagPath.root(tag), 'Blue Archive');
    expect(TagPath.parent(tag), 'Blue Archive|Millennium|C&C');
    expect(TagPath.parent('waifu'), null);
    expect(TagPath.label(tag), 'Asuna · Blue Archive');
    expect(TagPath.label('waifu'), 'waifu');
  });

  test('expand and flatten', () {
    expect(TagPath.expand({'A|B|C', 'D'}), {'A', 'A|B', 'A|B|C', 'D'});
    expect(TagPath.flatten({'A|B', 'A|C', 'D'}), {'A', 'B', 'C', 'D'});
  });

  test('within', () {
    expect(TagPath.isWithin('A|B', 'A'), true);
    expect(TagPath.isWithin('A', 'A'), true);
    expect(TagPath.isWithin('AB', 'A'), false);
  });
}
