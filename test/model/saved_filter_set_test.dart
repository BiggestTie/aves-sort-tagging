import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/saved_filter_set.dart';
import 'package:test/test.dart';

void main() {
  test('saved filter sets round trip', () {
    final sets = [
      SavedFilterSet('Blue Archive, no Asuna', {TagFilter('Blue Archive'), TagFilter('Blue Archive|Millennium|C&C|Asuna').reverse()}),
    ];
    final decoded = SavedFilterSet.listFromJson(SavedFilterSet.listToJson(sets));
    expect(decoded.length, 1);
    expect(decoded.first.name, 'Blue Archive, no Asuna');
    expect(decoded.first.filters, sets.first.filters);
    expect(SavedFilterSet.listFromJson('nope'), isEmpty);
  });
}
