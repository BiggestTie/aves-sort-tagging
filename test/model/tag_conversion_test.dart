import 'package:aves/model/tags/tag_conversion.dart';
import 'package:test/test.dart';

void main() {
  final counts = {
    'waifu': 100,
    'Gacha Girls': 50,
    'Blue Archive': 30,
    'ZZZ': 40,
    'Asuna-Blue Archive': 10,
    'C&C - Blue Archive': 8,
    'Toki-Blue Archive': 5,
    'Hu Tao - Genshin': 12,
    'Raiden Ei - Genshin': 9,
    'Trigger - ZZZ': 7,
    'Ellen Joe ZZZ': 6,
    'Jane Doe zzz': 4,
    'Norza - Artist': 3,
    'Spider-Man': 2,
    'Kamisato Ayaka': 5,
    'Blue Archive|Asuna': 1,
  };

  test('detects franchises', () {
    final plan = TagConversionPlanner.plan(counts);
    expect(plan.franchises.map((v) => v.name).toSet(), {'Blue Archive', 'Genshin', 'ZZZ'});
  });

  test('converts tags', () {
    final mapping = TagConversionPlanner.plan(counts).mapping;
    expect(mapping['Asuna-Blue Archive'], 'Blue Archive|Asuna');
    expect(mapping['C&C - Blue Archive'], 'Blue Archive|C&C');
    expect(mapping['Hu Tao - Genshin'], 'Genshin|Hu Tao');
    expect(mapping['Trigger - ZZZ'], 'ZZZ|Trigger');
    expect(mapping['Ellen Joe ZZZ'], 'ZZZ|Ellen Joe');
    expect(mapping['Jane Doe zzz'], 'ZZZ|Jane Doe');
    expect(mapping['Norza - Artist'], 'Artist|Norza');
    // untouched
    expect(mapping.containsKey('waifu'), false);
    expect(mapping.containsKey('Blue Archive'), false);
    expect(mapping.containsKey('Spider-Man'), false);
    expect(mapping.containsKey('Kamisato Ayaka'), false);
    expect(mapping.containsKey('Blue Archive|Asuna'), false);
  });

  test('excluded franchise', () {
    final plan = TagConversionPlanner.plan(counts, excludedFranchises: {'zzz'});
    expect(plan.mapping.containsKey('Trigger - ZZZ'), false);
    expect(plan.unchanged, contains('Trigger - ZZZ'));
  });

  test('convert item tags', () {
    final mapping = TagConversionPlanner.plan(counts).mapping;
    expect(
      TagConversionPlanner.convertTags({'waifu', 'Blue Archive', 'Asuna-Blue Archive', 'C&C - Blue Archive'}, mapping),
      {'waifu', 'Blue Archive|Asuna', 'Blue Archive|C&C'},
    );
  });

  test('uses catalog paths', () {
    String? lookup(String franchise, String name) => franchise == 'Blue Archive' && name == 'Asuna' ? 'Blue Archive|Millennium|C&C|Asuna' : null;
    final mapping = TagConversionPlanner.plan(counts, catalogLookup: lookup).mapping;
    expect(mapping['Asuna-Blue Archive'], 'Blue Archive|Millennium|C&C|Asuna');
    expect(mapping['Toki-Blue Archive'], 'Blue Archive|Toki');
  });
}
