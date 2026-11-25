import 'dart:convert';

import 'package:aves/model/tags/online/online_tag_suggester.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OnlineTagSearchException implements Exception {
  final String message;

  const new(this.message);

  @override
  String toString() => message;
}

// A match from SauceNAO, a reverse image search engine for art.
class SauceNaoMatch {
  final double similarity;
  final String indexName;
  final int? danbooruId;
  final List<String> urls;

  // small preview of the matched image, hosted by SauceNAO for a while
  final String? thumbnailUrl;

  // tags given by SauceNAO itself for booru sources, e.g. `asuna (blue archive)`
  final OnlinePostTags tags;

  const new({
    required this.similarity,
    required this.indexName,
    required this.danbooruId,
    required this.urls,
    required this.thumbnailUrl,
    required this.tags,
  });

  String get sourceName {
    final name = indexName.replaceFirst(RegExp(r'^Index #\d+:\s*'), '');
    final dash = name.indexOf(' - ');
    return dash > 0 ? name.substring(0, dash) : name;
  }
}

class OnlineTagSearchResult {
  final SauceNaoMatch match;

  // where the tags came from, e.g. `Danbooru`
  final String tagSource;
  final OnlinePostTags tags;

  // remaining searches for the next 30 seconds and 24 hours, when known
  final int? shortRemaining;
  final int? longRemaining;

  // why the full tags could not be fetched, if they could not
  final String? tagError;

  // Danbooru post of the match, if any
  final int? danbooruId;

  // search engine that found the match, e.g. `SauceNAO`
  final String engine;

  // image to compare with: from the post when available, otherwise SauceNAO's preview
  String? get imageUrl => tags.imageUrl ?? match.thumbnailUrl;

  const new({
    required this.match,
    required this.tagSource,
    required this.tags,
    this.shortRemaining,
    this.longRemaining,
    this.tagError,
    this.danbooruId,
    this.engine = 'SauceNAO',
  });
}

class OnlineTagSearch {
  // Danbooru's bot check rejects some user agents, so a few plain ones are tried
  static const userAgent = 'AvesTagging/1.0';
  static const _danbooruUserAgents = ['AvesTagging/1.0', 'aves-tagging/1.0.0'];

  // below this similarity, matches are usually other images
  static const minSimilarity = 70.0;

  static final Uri _sauceNaoUri = Uri.parse('https://saucenao.com/search.php');

  // below this similarity, IQDB matches are usually other images
  static const minIqdbSimilarity = 85.0;

  // finds the image online and returns the tags of the best match,
  // or null when there is no confident match.
  // Search engines are tried in turn, until one finds a confident match:
  // SauceNAO (needs an API key), Danbooru's own search (needs a Danbooru login), IQDB.
  static Future<OnlineTagSearchResult?> search(
    Uint8List imageBytes, {
    String? sauceNaoApiKey,
    String? danbooruLogin,
    String? danbooruApiKey,
  }) async {
    final hasDanbooruLogin = (danbooruLogin?.isNotEmpty ?? false) && (danbooruApiKey?.isNotEmpty ?? false);
    final engines = <(String, Future<OnlineTagSearchResult?> Function())>[
      if (sauceNaoApiKey != null && sauceNaoApiKey.isNotEmpty)
        ('SauceNAO', () => _searchSauceNao(imageBytes, apiKey: sauceNaoApiKey, danbooruLogin: danbooruLogin, danbooruApiKey: danbooruApiKey)),
      if (hasDanbooruLogin) ('Danbooru', () => _searchDanbooru(imageBytes, login: danbooruLogin!, apiKey: danbooruApiKey!)),
      ('IQDB', () => _searchIqdb(imageBytes, danbooruLogin: danbooruLogin, danbooruApiKey: danbooruApiKey)),
    ];
    final errors = <String>[];
    for (final (name, engine) in engines) {
      try {
        final result = await engine();
        if (result != null) return result;
      } catch (error) {
        debugPrint('failed to search with engine=$name error=$error');
        errors.add('$name: $error');
      }
    }
    // when every engine failed, there was no real search
    if (errors.length == engines.length) {
      throw OnlineTagSearchException(errors.join('\n'));
    }
    return null;
  }

  static Future<OnlineTagSearchResult?> _searchSauceNao(
    Uint8List imageBytes, {
    required String apiKey,
    String? danbooruLogin,
    String? danbooruApiKey,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _sauceNaoUri.replace(
              queryParameters: {
                'output_type': '2',
                'api_key': apiKey,
                'numres': '8',
                'db': '999',
              },
            ),
          )
          ..headers['User-Agent'] = userAgent
          ..files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'image.png'));

    final http.Response response;
    try {
      response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 60)));
    } catch (error) {
      throw OnlineTagSearchException('Could not reach SauceNAO. Check your connection.\n$error');
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 403:
        throw const OnlineTagSearchException('SauceNAO refused the API key. Check it in the key settings.');
      case 429:
        throw const OnlineTagSearchException('SauceNAO search limit reached. Wait a little (30 seconds, or until tomorrow for the daily limit).');
      default:
        throw OnlineTagSearchException('SauceNAO error (HTTP ${response.statusCode}).');
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final header = json['header'] as Map<String, dynamic>? ?? {};
    final status = header['status'];
    if (status is int && status != 0) {
      throw OnlineTagSearchException('SauceNAO: ${header['message'] ?? 'search failed (status $status)'}');
    }
    final shortRemaining = header['short_remaining'] as int?;
    final longRemaining = header['long_remaining'] as int?;

    final matches = (json['results'] as List? ?? []).whereType<Map<String, dynamic>>().map(_parseMatch).nonNulls.where((v) => v.similarity >= minSimilarity).toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity));
    if (matches.isEmpty) return null;

    // prefer a Danbooru match, which has the most complete tags
    final best = matches.first;
    final danbooruMatch = matches.firstWhere((v) => v.danbooruId != null && v.similarity >= best.similarity - 5, orElse: () => best);
    final danbooruId = danbooruMatch.danbooruId;
    String? tagError;
    if (danbooruId != null) {
      try {
        final tags = await fetchDanbooruTags(danbooruId, login: danbooruLogin, apiKey: danbooruApiKey);
        return OnlineTagSearchResult(
          match: danbooruMatch,
          tagSource: 'Danbooru',
          tags: tags,
          shortRemaining: shortRemaining,
          longRemaining: longRemaining,
          danbooruId: danbooruId,
        );
      } catch (error) {
        debugPrint('failed to fetch Danbooru post id=$danbooruId error=$error');
        tagError = '$error';
      }
    }

    // otherwise, the short tags SauceNAO has for the best match with some
    final withTags = matches.firstWhere((v) => !v.tags.isEmpty, orElse: () => best);
    return OnlineTagSearchResult(
      match: withTags,
      tagSource: 'SauceNAO (${withTags.sourceName} summary)',
      tags: withTags.tags,
      shortRemaining: shortRemaining,
      longRemaining: longRemaining,
      tagError: tagError,
      danbooruId: danbooruId,
    );
  }

  static SauceNaoMatch? _parseMatch(Map<String, dynamic> result) {
    final header = result['header'] as Map<String, dynamic>?;
    final data = result['data'] as Map<String, dynamic>?;
    if (header == null || data == null) return null;
    final similarity = double.tryParse('${header['similarity']}') ?? 0;

    // `a (b), c` -> [`a_(b)`, `c`], in the same form as Danbooru tags
    List<String> split(Object? value) => value is String ? value.split(',').map((v) => v.trim().replaceAll(' ', '_')).where((v) => v.isNotEmpty).toList() : const [];

    final creator = data['creator'];
    return SauceNaoMatch(
      similarity: similarity,
      indexName: '${header['index_name'] ?? ''}',
      danbooruId: _parseInt(data['danbooru_id']),
      urls: (data['ext_urls'] as List? ?? []).whereType<String>().toList(),
      thumbnailUrl: header['thumbnail'] is String ? header['thumbnail'] as String : null,
      tags: OnlinePostTags(
        characters: split(data['characters']),
        franchises: split(data['material']),
        artists: creator is String ? split(creator) : (creator is List ? creator.whereType<String>().map((v) => v.replaceAll(' ', '_')).toList() : const []),
      ),
    );
  }

  static int? _parseInt(Object? value) => value is int ? value : int.tryParse('${value ?? ''}');

  // tries the post endpoint, then the search endpoint, with a few user agents,
  // and with the user's Danbooru login when set (which may get past the bot check)
  static Future<OnlinePostTags> fetchDanbooruTags(int id, {String? login, String? apiKey}) async {
    final auth = login != null && login.isNotEmpty && apiKey != null && apiKey.isNotEmpty ? {'login': login, 'api_key': apiKey} : <String, String>{};
    final attempts = [
      for (final agent in _danbooruUserAgents) ...[
        (agent, Uri.https('danbooru.donmai.us', '/posts/$id.json', auth.isEmpty ? null : auth)),
        (agent, Uri.https('danbooru.donmai.us', '/posts.json', {'tags': 'id:$id', 'limit': '1', ...auth})),
      ],
    ];
    final errors = <String>{};
    for (final (agent, uri) in attempts) {
      try {
        final response = await http.get(
          uri,
          headers: {'User-Agent': agent},
        ).timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          final isChallenge = response.body.contains('Just a moment') || response.headers['cf-mitigated'] != null;
          errors.add('HTTP ${response.statusCode}${isChallenge ? ' (Cloudflare bot check)' : ''}');
          continue;
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(response.bodyBytes));
        } on FormatException {
          // e.g. a bot check page
          errors.add('got a web page instead of data');
          continue;
        }
        final post = decoded is List ? decoded.firstOrNull : decoded;
        if (post is! Map<String, dynamic>) {
          errors.add('post not found');
          continue;
        }
        return _danbooruPostTags(post);
      } catch (error) {
        errors.add('$error');
      }
    }
    throw OnlineTagSearchException('Danbooru refused: ${errors.join(', ')}');
  }
  static OnlinePostTags _danbooruPostTags(Map<String, dynamic> post) {
    List<String> split(String key) => '${post[key] ?? ''}'.split(' ').where((v) => v.isNotEmpty).toList();
    return OnlinePostTags(
      characters: split('tag_string_character'),
      franchises: split('tag_string_copyright'),
      artists: split('tag_string_artist'),
      general: split('tag_string_general'),
      imageUrl: (post['large_file_url'] ?? post['preview_file_url']) as String?,
    );
  }

  // Danbooru's own reverse image search, which needs a login
  static Future<OnlineTagSearchResult?> _searchDanbooru(Uint8List imageBytes, {required String login, required String apiKey}) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.https('danbooru.donmai.us', '/iqdb_queries.json', {'login': login, 'api_key': apiKey, 'limit': '5'}),
    )
      ..headers['User-Agent'] = userAgent
      ..files.add(http.MultipartFile.fromBytes('search[file]', imageBytes, filename: 'image.png'));
    final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 60)));
    if (response.statusCode != 200) {
      throw OnlineTagSearchException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return null;
    final results = decoded.whereType<Map<String, dynamic>>().where((v) => ((v['score'] as num?) ?? 0) >= minSimilarity).toList()
      ..sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
    final best = results.firstOrNull;
    if (best == null) return null;

    final postId = _parseInt(best['post_id']);
    if (postId == null) return null;
    final post = best['post'];
    final tags = post is Map<String, dynamic> && post['tag_string_general'] != null ? _danbooruPostTags(post) : await fetchDanbooruTags(postId, login: login, apiKey: apiKey);
    final match = SauceNaoMatch(
      similarity: (best['score'] as num).toDouble(),
      indexName: 'Danbooru',
      danbooruId: postId,
      urls: ['https://danbooru.donmai.us/posts/$postId'],
      thumbnailUrl: post is Map<String, dynamic> ? post['preview_file_url'] as String? : null,
      tags: tags,
    );
    return OnlineTagSearchResult(
      match: match,
      tagSource: 'Danbooru',
      tags: tags,
      danbooruId: postId,
      engine: 'Danbooru',
    );
  }

  // IQDB.org, which searches several image boards at once (Danbooru, Gelbooru, Yande.re, Konachan...)
  static Future<OnlineTagSearchResult?> _searchIqdb(Uint8List imageBytes, {String? danbooruLogin, String? danbooruApiKey}) async {
    final request = http.MultipartRequest('POST', Uri.parse('https://iqdb.org/'))
      ..headers['User-Agent'] = userAgent
      ..files.add(http.MultipartFile.fromBytes('file', imageBytes, filename: 'image.png'));
    final response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 60)));
    if (response.statusCode != 200) {
      throw OnlineTagSearchException('HTTP ${response.statusCode}');
    }
    final matches = parseIqdbHtml(utf8.decode(response.bodyBytes, allowMalformed: true)).where((v) => v.similarity >= minIqdbSimilarity).toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity));
    if (matches.isEmpty) return null;

    // prefer a Danbooru match, which has categorized tags
    final best = matches.first;
    final danbooruMatch = matches.firstWhereOrNull((v) => v.danbooruId != null && v.similarity >= best.similarity - 5);
    final danbooruId = danbooruMatch?.danbooruId;
    if (danbooruMatch != null && danbooruId != null) {
      try {
        final tags = await fetchDanbooruTags(danbooruId, login: danbooruLogin, apiKey: danbooruApiKey);
        return OnlineTagSearchResult(match: danbooruMatch, tagSource: 'Danbooru', tags: tags, danbooruId: danbooruId, engine: 'IQDB');
      } catch (error) {
        debugPrint('failed to fetch Danbooru post id=$danbooruId error=$error');
      }
    }
    return OnlineTagSearchResult(match: best, tagSource: best.sourceName, tags: best.tags, danbooruId: best.danbooruId, engine: 'IQDB');
  }

  static final _iqdbTablePattern = RegExp(r'<table>(.*?)</table>', dotAll: true);
  static final _iqdbSimilarityPattern = RegExp(r'(\d+(?:\.\d+)?)% similarity');
  static final _iqdbLinkPattern = RegExp(r'<a href="([^"]+)"');
  static final _iqdbAltPattern = RegExp(r'alt="([^"]*)"');
  static final _iqdbImagePattern = RegExp('<img src=[\'"]?([^\'" >]+)');

  // matches listed on an IQDB result page
  @visibleForTesting
  static List<SauceNaoMatch> parseIqdbHtml(String html) {
    String absolute(String url) => url.startsWith('//') ? 'https:$url' : (url.startsWith('/') ? 'https://iqdb.org$url' : url);

    final matches = <SauceNaoMatch>[];
    for (final table in _iqdbTablePattern.allMatches(html).map((m) => m.group(1)!)) {
      if (table.contains('Your image') || table.contains('No relevant')) continue;
      final similarity = double.tryParse(_iqdbSimilarityPattern.firstMatch(table)?.group(1) ?? '');
      final href = _iqdbLinkPattern.firstMatch(table)?.group(1);
      if (similarity == null || href == null) continue;
      final url = absolute(href);
      final alt = _decodeHtml(_iqdbAltPattern.firstMatch(table)?.group(1) ?? '');
      final tagsIndex = alt.indexOf('Tags: ');
      final tagsText = tagsIndex >= 0 ? alt.substring(tagsIndex + 6) : '';
      final thumb = _iqdbImagePattern.firstMatch(table)?.group(1);
      final host = Uri.tryParse(url)?.host ?? '';
      const names = {
        'danbooru': 'Danbooru',
        'gelbooru': 'Gelbooru',
        'yande.re': 'Yande.re',
        'konachan': 'Konachan',
        'sankaku': 'Sankaku',
        'zerochan': 'Zerochan',
        'e-shuushuu': 'E-Shuushuu',
        'anime-pictures': 'Anime-Pictures',
      };
      final name = names.entries.firstWhereOrNull((kv) => host.contains(kv.key))?.value ?? host;
      matches.add(
        SauceNaoMatch(
          similarity: similarity,
          indexName: name,
          danbooruId: host.contains('danbooru') ? int.tryParse(RegExp(r'/posts/(\d+)').firstMatch(url)?.group(1) ?? '') : null,
          urls: [url],
          thumbnailUrl: thumb != null ? absolute(thumb) : null,
          tags: classifyFlatTags(tagsText.split(' ').where((v) => v.isNotEmpty).toList()),
        ),
      );
    }
    return matches;
  }

  // sorts uncategorized board tags: `x_(series)` as characters, series as franchises, the rest as general
  @visibleForTesting
  static OnlinePostTags classifyFlatTags(List<String> tags) {
    final known = OnlineTagSuggester.franchiseNames.keys.toSet();
    final tagSet = tags.map((v) => v.toLowerCase()).toSet();
    final characters = <String>[];
    final franchises = <String>[];
    final general = <String>[];
    for (final tag in tags) {
      final lower = tag.toLowerCase();
      if (lower.startsWith('rating:')) continue;
      final (_, qualifiers) = OnlineTagSuggester.splitCharacter(lower);
      if (qualifiers.any((q) => known.contains(q) || tagSet.contains(q))) {
        characters.add(lower);
      } else if (known.contains(lower)) {
        franchises.add(lower);
      } else {
        general.add(lower);
      }
    }
    // series named in character tags are franchises too
    for (final character in characters) {
      final (_, qualifiers) = OnlineTagSuggester.splitCharacter(character);
      for (final q in qualifiers) {
        if (tagSet.contains(q) && !franchises.contains(q)) {
          franchises.add(q);
          general.remove(q);
        }
      }
    }
    return OnlinePostTags(characters: characters, franchises: franchises, general: general);
  }

  static String _decodeHtml(String text) => text.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>');
}
