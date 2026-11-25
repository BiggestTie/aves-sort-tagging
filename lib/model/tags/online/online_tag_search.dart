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

  // tags given by SauceNAO itself for booru sources, e.g. `asuna (blue archive)`
  final OnlinePostTags tags;

  const new({
    required this.similarity,
    required this.indexName,
    required this.danbooruId,
    required this.urls,
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

  const new({
    required this.match,
    required this.tagSource,
    required this.tags,
    this.shortRemaining,
    this.longRemaining,
    this.tagError,
    this.danbooruId,
  });
}

class OnlineTagSearch {
  // Danbooru's bot check rejects some user agents, so a few plain ones are tried
  static const userAgent = 'AvesTagging/1.0';
  static const _danbooruUserAgents = ['AvesTagging/1.0', 'aves-tagging/1.0.0'];

  // below this similarity, matches are usually other images
  static const minSimilarity = 70.0;

  static final Uri _sauceNaoUri = Uri.parse('https://saucenao.com/search.php');

  // finds the image online and returns the tags of the best match,
  // or null when there is no confident match
  static Future<OnlineTagSearchResult?> search(
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
        List<String> split(String key) => '${post[key] ?? ''}'.split(' ').where((v) => v.isNotEmpty).toList();
        return OnlinePostTags(
          characters: split('tag_string_character'),
          franchises: split('tag_string_copyright'),
          artists: split('tag_string_artist'),
          general: split('tag_string_general'),
        );
      } catch (error) {
        errors.add('$error');
      }
    }
    throw OnlineTagSearchException('Danbooru refused: ${errors.join(', ')}');
  }
}
