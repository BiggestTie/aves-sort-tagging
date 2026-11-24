import 'package:aves/model/tags/tag_path.dart';
import 'package:collection/collection.dart';

// Converts flat tags written like `Asuna - Blue Archive`, `Asuna-Blue Archive`
// or `Jane Doe zzz` into nested tags like `Blue Archive|Asuna`.
//
// Franchises are detected from the tags themselves: a suffix after a dash
// counts as a franchise when it is used by several tags, or exists as its own tag.

class TagConversion {
  final String from;
  final String to;

  const new(this.from, this.to);

  @override
  String toString() => '$from -> $to';
}

class TagFranchise {
  // spelling used for the converted tags
  final String name;

  // number of tags that would be converted with this franchise
  final int tagCount;

  const new(this.name, this.tagCount);
}

class TagConversionPlan {
  final List<TagFranchise> franchises;
  final List<TagConversion> conversions;

  // flat tags that are neither converted nor franchises
  final List<String> unchanged;

  const new({
    required this.franchises,
    required this.conversions,
    required this.unchanged,
  });

  Map<String, String> get mapping => Map.fromEntries(conversions.map((v) => MapEntry(v.from, v.to)));
}

class TagConversionPlanner {
  static const artistGroup = 'Artist';

  // tags appearing this many times as a suffix are considered franchises
  static const minSuffixUses = 2;

  // `tagCounts`: flat tag -> number of items with it
  // `excludedFranchises`: franchise names (any case) not to use
  static TagConversionPlan plan(
    Map<String, int> tagCounts, {
    Set<String> excludedFranchises = const {},
  }) {
    final flatTags = tagCounts.keys.where((tag) => !TagPath.isNested(tag)).toSet();
    final excluded = excludedFranchises.map(_key).toSet();

    // split `name - suffix` tags
    final dashSplits = <String, (String, String)>{};
    for (final tag in flatTags) {
      final split = splitAtDash(tag);
      if (split != null) dashSplits[tag] = split;
    }

    // franchise candidates by normalized key, with all spellings seen
    final spellingsByKey = <String, List<String>>{};
    final suffixUsesByKey = <String, int>{};
    dashSplits.values.forEach((split) {
      final suffix = split.$2;
      final key = _key(suffix);
      spellingsByKey.putIfAbsent(key, () => []).add(suffix);
      suffixUsesByKey[key] = (suffixUsesByKey[key] ?? 0) + 1;
    });
    final standaloneByKey = <String, String>{};
    for (final tag in flatTags) {
      standaloneByKey.putIfAbsent(_key(tag), () => tag);
    }

    final franchiseNameByKey = <String, String>{};
    suffixUsesByKey.forEach((key, uses) {
      if (key == _key(artistGroup) || excluded.contains(key)) return;
      final standalone = standaloneByKey[key];
      if (uses >= minSuffixUses || standalone != null) {
        // prefer the spelling of the standalone tag, then the most common one
        franchiseNameByKey[key] = standalone ?? _mostCommon(spellingsByKey[key]!);
      }
    });

    final conversions = <TagConversion>[];
    final unchanged = <String>[];
    final franchiseTagCounts = <String, int>{};

    void convert(String from, String to) {
      to = TagPath.normalize(to);
      if (to.isNotEmpty && to != from) {
        conversions.add(TagConversion(from, to));
        final root = TagPath.root(to);
        franchiseTagCounts[root] = (franchiseTagCounts[root] ?? 0) + 1;
      } else {
        unchanged.add(from);
      }
    }

    for (final tag in flatTags.sorted(compareAsciiUpperCaseNatural)) {
      final key = _key(tag);

      // standalone franchise tag in another spelling, e.g. `zzz` -> `ZZZ`
      final franchiseForTag = franchiseNameByKey[key];
      if (franchiseForTag != null) {
        if (franchiseForTag != tag) {
          convert(tag, franchiseForTag);
        } else {
          unchanged.add(tag);
        }
        continue;
      }

      final split = dashSplits[tag];
      if (split != null) {
        final (name, suffix) = split;
        final suffixKey = _key(suffix);
        if (suffixKey == _key(artistGroup)) {
          convert(tag, '$artistGroup|$name');
          continue;
        }
        if (_key(name) == _key(artistGroup)) {
          convert(tag, '$artistGroup|$suffix');
          continue;
        }
        final franchise = franchiseNameByKey[suffixKey];
        if (franchise != null) {
          convert(tag, '$franchise|$name');
          continue;
        }
      }

      // `Jane Doe zzz`: ends with a known franchise, without a dash
      final franchiseSuffix = _findFranchiseSuffix(tag, franchiseNameByKey);
      if (franchiseSuffix != null) {
        final (name, franchise) = franchiseSuffix;
        convert(tag, '$franchise|$name');
        continue;
      }

      unchanged.add(tag);
    }

    final franchises = franchiseNameByKey.values.toSet().map((name) => TagFranchise(name, franchiseTagCounts[name] ?? 0)).toList()
      ..sort((a, b) {
        final c = b.tagCount.compareTo(a.tagCount);
        return c != 0 ? c : compareAsciiUpperCaseNatural(a.name, b.name);
      });

    return TagConversionPlan(
      franchises: franchises,
      conversions: conversions,
      unchanged: unchanged,
    );
  }

  // splits at the last dash: `Asuna - Blue Archive` -> (`Asuna`, `Blue Archive`)
  static (String, String)? splitAtDash(String tag) {
    final index = tag.lastIndexOf('-');
    if (index <= 0 || index >= tag.length - 1) return null;
    final name = tag.substring(0, index).trim();
    final suffix = tag.substring(index + 1).trim();
    if (name.isEmpty || suffix.isEmpty) return null;
    return (name, suffix);
  }

  static (String, String)? _findFranchiseSuffix(String tag, Map<String, String> franchiseNameByKey) {
    final words = tag.trim().split(RegExp(r'\s+'));
    // try longest franchise names first, e.g. `Blue Archive` before `Archive`
    for (var i = 1; i < words.length; i++) {
      final name = words.sublist(0, i).join(' ');
      final suffix = words.sublist(i).join(' ');
      final franchise = franchiseNameByKey[_key(suffix)];
      if (franchise != null) return (name, franchise);
    }
    return null;
  }

  static String _mostCommon(List<String> values) {
    final counts = <String, int>{};
    values.forEach((v) => counts[v] = (counts[v] ?? 0) + 1);
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  // case and spacing insensitive key
  static String _key(String value) => value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  // applies the mapping to an item's tags, also dropping tags made redundant
  // by nested ones (e.g. `Blue Archive` when `Blue Archive|Asuna` is present)
  static Set<String> convertTags(Set<String> tags, Map<String, String> mapping) {
    final converted = tags.map((tag) => mapping[tag] ?? tag).toSet();
    final ancestors = converted.expand((tag) {
      final all = TagPath.selfAndAncestors(tag);
      return all.take(all.length - 1);
    }).toSet();
    return converted.where((tag) => !ancestors.contains(tag)).toSet();
  }
}
