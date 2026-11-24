import 'package:aves/model/tags/tag_implications.dart';
import 'package:test/test.dart';

void main() {
  const asuna = 'Blue Archive|Asuna';
  const cc = 'Blue Archive|Groups|C&C';
  const millennium = 'Blue Archive|Groups|Millennium';

  final rules = TagImplications.empty.withRule(asuna, {cc}).withRule(cc, {millennium});

  test('direct and chained implications', () {
    expect(rules.apply({asuna}), {asuna, cc, millennium});
    expect(rules.added({asuna}), {cc, millennium});
    expect(rules.apply({'waifu'}), {'waifu'});
  });

  test('rules apply to nested tags below', () {
    expect(rules.added({'Blue Archive|Asuna|Bunny'}), {cc, millennium});
  });

  test('cycles do not loop', () {
    final cyclic = TagImplications.empty.withRule('A', {'B'}).withRule('B', {'A'});
    expect(cyclic.apply({'A'}), {'A', 'B'});
  });

  test('empty rule removes it', () {
    expect(rules.withRule(asuna, {}).impliedBy(asuna), isEmpty);
    expect(rules.withRule(asuna, {asuna}).impliedBy(asuna), isEmpty);
  });

  test('json round trip', () {
    final decoded = TagImplications.fromJson(rules.toJson());
    expect(decoded.apply({asuna}), {asuna, cc, millennium});
    expect(TagImplications.fromJson('not json').isEmpty, true);
    expect(TagImplications.fromJson(null).isEmpty, true);
  });
}
