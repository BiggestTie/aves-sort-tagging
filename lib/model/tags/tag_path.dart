// Nested ("hierarchical") tags, e.g. `Blue Archive|Millennium|C&C|Asuna`.
//
// The full path is stored in XMP `lr:hierarchicalSubject` (the convention used by
// Lightroom, digiKam, etc.), while every path segment is also written as a plain
// keyword in XMP `dc:subject` and IPTC keywords, so other apps still see the tags.
class TagPath {
  static const separator = '|';

  // cleans up spacing around separators and drops empty segments,
  // e.g. ` Blue Archive | Asuna ` -> `Blue Archive|Asuna`
  static String normalize(String tag) => segments(tag).join(separator);

  static List<String> segments(String tag) => tag.split(separator).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();

  static bool isNested(String tag) => tag.contains(separator);

  // last segment, e.g. `Asuna`
  static String leaf(String tag) {
    final parts = segments(tag);
    return parts.isEmpty ? tag : parts.last;
  }

  // first segment, e.g. `Blue Archive`
  static String root(String tag) {
    final parts = segments(tag);
    return parts.isEmpty ? tag : parts.first;
  }

  // parent path, or null for top level tags
  static String? parent(String tag) {
    final parts = segments(tag);
    if (parts.length < 2) return null;
    return parts.sublist(0, parts.length - 1).join(separator);
  }

  // the path itself and all its ancestors,
  // e.g. `A|B|C` -> [`A`, `A|B`, `A|B|C`]
  static List<String> selfAndAncestors(String tag) {
    final parts = segments(tag);
    return List.generate(parts.length, (i) => parts.sublist(0, i + 1).join(separator));
  }

  static Set<String> expand(Iterable<String> tags) => tags.expand(selfAndAncestors).toSet();

  // every segment as a plain keyword, for `dc:subject` and IPTC keywords
  static Set<String> flatten(Iterable<String> tags) => tags.expand(segments).toSet();

  // whether `tag` is `ancestor` or nested somewhere below it
  static bool isWithin(String tag, String ancestor) => tag == ancestor || tag.startsWith('$ancestor$separator');

  // short label for chips, e.g. `Asuna · Blue Archive`
  static String label(String tag) {
    final parts = segments(tag);
    if (parts.length < 2) return tag;
    return '${parts.last} · ${parts.first}';
  }
}
