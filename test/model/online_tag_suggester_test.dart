import 'package:aves/model/tags/online/online_tag_suggester.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:test/test.dart';

void main() {
  final known = TagPath.expand({'Blue Archive|Millennium|C&C|Asuna', 'Long Hair', 'waifu', 'Artist|Norza', 'Genshin|Liyue|Hu Tao'});
  String? catalog(String franchise, String name) => franchise == 'Blue Archive' && name == 'Toki' ? 'Blue Archive|Millennium|C&C|Toki' : null;

  test('split character tags', () {
    expect(OnlineTagSuggester.splitCharacter('asuna_(bunny)_(blue_archive)'), ('Asuna', ['bunny', 'blue_archive']));
    expect(OnlineTagSuggester.splitCharacter('hu_tao_(genshin_impact)'), ('Hu Tao', ['genshin_impact']));
    expect(OnlineTagSuggester.splitCharacter('raiden_shogun'), ('Raiden Shogun', <String>[]));
  });

  test('suggests the user tags', () {
    final suggester = OnlineTagSuggester(knownTags: known, catalogLookup: catalog);
    final suggestions = suggester.suggest(
      const OnlinePostTags(
        characters: ['asuna_(bunny)_(blue_archive)', 'toki_(blue_archive)', 'new_girl_(blue_archive)'],
        franchises: ['blue_archive'],
        artists: ['norza'],
        general: ['long_hair', 'bunny_ears'],
      ),
    );
    final byTarget = {for (final v in suggestions) v.target: v};
    expect(byTarget['Blue Archive|Millennium|C&C|Asuna']?.isKnown, true);
    expect(byTarget['Blue Archive|Millennium|C&C|Toki']?.isKnown, true);
    expect(byTarget['Blue Archive|New Girl']?.isKnown, false);
    // franchise implied by characters
    expect(byTarget.containsKey('Blue Archive'), false);
    expect(byTarget['Artist|Norza']?.isKnown, true);
    expect(byTarget['Long Hair']?.recommended, true);
    expect(byTarget['Bunny Ears']?.recommended, false);
  });

  test('franchise names and remembered choices', () {
    final suggester = OnlineTagSuggester(
      knownTags: known,
      catalogLookup: catalog,
      rememberedMappings: {'bunny_ears': 'Outfit|Bunny Suit', 'blush': ''},
    );
    final suggestions = suggester.suggest(
      const OnlinePostTags(
        characters: ['hu_tao_(genshin_impact)'],
        franchises: ['genshin_impact', 'honkai_(series)'],
        general: ['bunny_ears', 'blush'],
      ),
    );
    final targets = suggestions.map((v) => v.target).toSet();
    expect(targets, containsAll(['Genshin|Liyue|Hu Tao', 'Outfit|Bunny Suit']));
    expect(targets.any((v) => v.toLowerCase().contains('blush')), false);
    expect(targets.any((v) => v.toLowerCase().contains('honkai')), false);
  });
}
