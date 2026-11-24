import 'package:collection/collection.dart';

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

  // whether all words of the query appear somewhere in the full path,
  // so `blue archive` matches `Blue Archive|Millennium|C&C|Asuna`
  // and so does `millennium asuna`. `upQuery` must be upper case.
  static bool matches(String tag, String upQuery) {
    final words = upQuery.split(RegExp(r'\s+')).where((v) => v.isNotEmpty);
    if (words.isEmpty) return true;
    final upTag = tag.toUpperCase();
    return words.every(upTag.contains);
  }

  // orders tags as a tree: each tag right before the tags nested below it
  static int compare(String a, String b) {
    final segmentsA = segments(a);
    final segmentsB = segments(b);
    final length = segmentsA.length < segmentsB.length ? segmentsA.length : segmentsB.length;
    for (var i = 0; i < length; i++) {
      final c = compareAsciiUpperCaseNatural(segmentsA[i], segmentsB[i]);
      if (c != 0) return c;
    }
    return segmentsA.length.compareTo(segmentsB.length);
  }

  static int depth(String tag) => segments(tag).length - 1;

  // short label for chips, e.g. `Asuna · Blue Archive`
  static String label(String tag) {
    final parts = segments(tag);
    if (parts.length < 2) return tag;
    return '${parts.last} · ${parts.first}';
  }
}
