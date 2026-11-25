import 'package:aves/model/tags/online/online_tag_search.dart';
import 'package:test/test.dart';

void main() {
  const html = '''
<div id='pages' class="pages"><div><table><tr><th>Your image</th></tr><tr><td class='image'><img src='/thu/x.jpg'></td></tr></table></div>
<div><table><tr><th>Best match</th></tr><tr><td class='image'><a href="//danbooru.donmai.us/posts/123456"><img src='/danbooru/1/2/abc.jpg' alt="Rating: q Score: 10 Tags: 1girl hanako_(blue_archive) blue_archive long_hair" title="x" width='150' height='150'></a></td></tr><tr><td>1013&times;1500 [Questionable]</td></tr><tr><td>94% similarity</td></tr></table></div>
<div><table><tr><th>Additional match</th></tr><tr><td class='image'><a href="https://yande.re/post/show/42"><img src='/moe/a/b.jpg' alt="Rating: q Tags: maid pink_hair" width='150' height='150'></a></td></tr><tr><td>91% similarity</td></tr></table></div>
<div><table><tr><th>No relevant matches</th></tr></table></div>
''';

  test('parse IQDB results', () {
    final matches = OnlineTagSearch.parseIqdbHtml(html);
    expect(matches.length, 2);
    final first = matches.first;
    expect(first.similarity, 94);
    expect(first.sourceName, 'Danbooru');
    expect(first.danbooruId, 123456);
    expect(first.urls.first, 'https://danbooru.donmai.us/posts/123456');
    expect(first.thumbnailUrl, 'https://iqdb.org/danbooru/1/2/abc.jpg');
    expect(first.tags.characters, ['hanako_(blue_archive)']);
    expect(first.tags.franchises, ['blue_archive']);
    expect(first.tags.general, ['1girl', 'long_hair']);
    expect(matches[1].sourceName, 'Yande.re');
    expect(matches[1].danbooruId, null);
    expect(matches[1].tags.general, ['maid', 'pink_hair']);
  });
}
