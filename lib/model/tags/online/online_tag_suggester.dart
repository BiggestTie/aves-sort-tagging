import 'package:aves/model/tags/tag_path.dart';
import 'package:collection/collection.dart';

enum OnlineTagCategory { character, franchise, artist, general }

// A tag found online (e.g. Danbooru `asuna_(blue_archive)`),
// with the tag suggested for it among the user's tags (e.g. `Blue Archive|Millennium|C&C|Asuna`).
class TagSuggestion {
  final String source;
  final OnlineTagCategory category;
  final String target;

  // whether it is ticked by default
  final bool recommended;

  // whether the target is already one of the user's tags (or a catalog tag)
  final bool isKnown;

  const new({
    required this.source,
    required this.category,
    required this.target,
    required this.recommended,
    required this.isKnown,
  });

  TagSuggestion copyWith({String? target}) => TagSuggestion(
    source: source,
    category: category,
    target: target ?? this.target,
    recommended: true,
    isKnown: true,
  );
}

// Raw tags of an online post, by category, as on Danbooru.
class OnlinePostTags {
  final List<String> characters;
  final List<String> franchises;
  final List<String> artists;
  final List<String> general;

  const new({
    this.characters = const [],
    this.franchises = const [],
    this.artists = const [],
    this.general = const [],
  });

  bool get isEmpty => characters.isEmpty && franchises.isEmpty && artists.isEmpty && general.isEmpty;
}

// Maps tags found online to the user's own tags, to avoid duplicates:
// - remembered choices first (when the user picked another tag for a source tag before)
// - franchises with the user's naming (e.g. `genshin_impact` -> `Genshin`)
// - characters with their catalog path, or an existing tag with the same name
// - general tags only recommended when matching an existing tag (e.g. `long_hair` -> `Hair|Long`
//   when remembered, or `Long Hair` when that tag exists)
class OnlineTagSuggester {
  static const artistGroup = 'Artist';

  // Danbooru copyright tags -> franchise names used in tags
  static const franchiseNames = {
    'azur_lane': 'Azur Lane',
    'blue_archive': 'Blue Archive',
    'genshin_impact': 'Genshin',
    'honkai:_star_rail': 'HSR',
    'zenless_zone_zero': 'ZZZ',
    'goddess_of_victory:_nikke': 'Nikke',
    'nikke': 'Nikke',
  };

  // umbrella copyrights, redundant with a specific one
  static const ignoredFranchises = {
    'honkai_(series)',
    'hoyoverse',
    'mihoyo',
    'original',
  };

  // the user's tags (with parents)
  final Set<String> knownTags;

  // catalog lookup, e.g. (`Blue Archive`, `Asuna`) -> `Blue Archive|Millennium|C&C|Asuna`
  final String? Function(String franchise, String name) catalogLookup;

  // source tag -> tag chosen by the user before
  final Map<String, String> rememberedMappings;

  late final Map<String, String> _knownByLowerCase;
  late final Map<String, List<String>> _knownByLowerLeaf;

  new({
    required this.knownTags,
    required this.catalogLookup,
    this.rememberedMappings = const {},
  }) {
    _knownByLowerCase = {for (final tag in knownTags) tag.toLowerCase(): tag};
    _knownByLowerLeaf = groupBy(knownTags, (tag) => TagPath.leaf(tag).toLowerCase());
  }

  List<TagSuggestion> suggest(OnlinePostTags post) {
    final suggestions = <TagSuggestion>[];
    final seenTargets = <String>{};

    void add(String source, OnlineTagCategory category, String target, {required bool recommended, required bool isKnown}) {
      target = TagPath.normalize(target);
      if (target.isEmpty || !seenTargets.add(target)) return;
      suggestions.add(TagSuggestion(source: source, category: category, target: target, recommended: recommended, isKnown: isKnown));
    }

    bool addRemembered(String source, OnlineTagCategory category) {
      final remembered = rememberedMappings[source];
      if (remembered == null) return false;
      // an empty mapping means the user does not want this tag
      if (remembered.isNotEmpty) {
        add(source, category, remembered, recommended: true, isKnown: true);
      }
      return true;
    }

    final franchises = post.franchises.whereNot(ignoredFranchises.contains).map(franchiseName).toList();
    final mainFranchise = franchises.firstOrNull;

    for (final source in post.characters) {
      if (addRemembered(source, .character)) continue;
      final (name, qualifiers) = splitCharacter(source);
      // qualifiers are the series (e.g. `blue_archive`) or a version (e.g. `bunny`)
      final seriesQualifier = qualifiers.lastWhereOrNull((v) => franchiseNames.containsKey(v) || post.franchises.contains(v));
      final franchise = seriesQualifier != null ? franchiseName(seriesQualifier) : mainFranchise;
      final target = _characterTarget(name, franchise);
      add(source, .character, target.$1, recommended: true, isKnown: target.$2);
    }

    // franchises are implied by character tags, so only suggested on their own when no character is
    for (final (i, source) in post.franchises.whereNot(ignoredFranchises.contains).indexed) {
      if (addRemembered(source, .franchise)) continue;
      final name = franchises[i];
      final alreadyCovered = suggestions.any((v) => TagPath.root(v.target).toLowerCase() == name.toLowerCase());
      if (alreadyCovered) continue;
      final known = _knownByLowerCase[name.toLowerCase()];
      add(source, .franchise, known ?? name, recommended: true, isKnown: known != null);
    }

    for (final source in post.artists) {
      if (addRemembered(source, .artist)) continue;
      final name = humanize(source);
      final path = '$artistGroup|$name';
      final known = _knownByLowerCase[path.toLowerCase()] ?? _findLeaf(name, under: artistGroup);
      add(source, .artist, known ?? path, recommended: true, isKnown: known != null);
    }

    for (final source in post.general) {
      if (addRemembered(source, .general)) continue;
      final name = humanize(source);
      final known = _knownByLowerCase[name.toLowerCase()] ?? _findLeaf(name);
      // general tags are many, so only those matching existing tags are recommended
      add(source, .general, known ?? name, recommended: known != null, isKnown: known != null);
    }

    return suggestions;
  }

  // returns the target, and whether it is known
  (String, bool) _characterTarget(String name, String? franchise) {
    if (franchise != null) {
      final fromCatalog = catalogLookup(franchise, name);
      if (fromCatalog != null) return (fromCatalog, true);
      final existing = _findLeaf(name, under: franchise);
      if (existing != null) return (existing, true);
      return ('$franchise|$name', false);
    }
    final existing = _findLeaf(name);
    return (existing ?? name, existing != null);
  }

  // an existing tag with this last segment, optionally below a given root
  String? _findLeaf(String name, {String? under}) {
    final candidates = _knownByLowerLeaf[name.toLowerCase()];
    if (candidates == null) return null;
    if (under == null) return candidates.firstOrNull;
    final root = under.toLowerCase();
    return candidates.firstWhereOrNull((v) => TagPath.root(v).toLowerCase() == root && v.toLowerCase() != root);
  }

  String franchiseName(String source) {
    final known = franchiseNames[source.toLowerCase()];
    if (known != null) return known;
    final name = humanize(source);
    // reuse an existing top level tag with the same name, whatever its case
    final existing = _knownByLowerCase[name.toLowerCase()];
    return existing != null && !TagPath.isNested(existing) ? existing : name;
  }

  // `asuna_(bunny)_(blue_archive)` -> (`Asuna`, [`bunny`, `blue_archive`])
  static (String, List<String>) splitCharacter(String source) {
    final qualifiers = RegExp(r'\(([^)]*)\)').allMatches(source).map((m) => m.group(1)!).where((v) => v.isNotEmpty).toList();
    final base = source.replaceAll(RegExp(r'_?\([^)]*\)'), '');
    return (humanize(base), qualifiers);
  }

  // `hu_tao` -> `Hu Tao`, keeping inner capitals and symbols
  static String humanize(String source) {
    return source
        .split('_')
        .where((v) => v.isNotEmpty)
        .map((word) => word.length > 1 ? '${word[0].toUpperCase()}${word.substring(1)}' : word.toUpperCase())
        .join(' ');
  }
}
