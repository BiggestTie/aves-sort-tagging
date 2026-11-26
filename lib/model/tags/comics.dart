import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

enum ComicReadingMode { leftToRight, rightToLeft, vertical }

// Comics: groups of images read in an order chosen by the user.
// Pages are tagged `Comic|<title>` (written in the files, so the group survives moves),
// and the page order is kept in the app settings.
class Comics {
  static const root = 'Comic';

  static String tagFor(String title) => TagPath.normalize('$root${TagPath.separator}$title');

  static bool isComicTag(String tag) => TagPath.isNested(tag) && TagPath.root(tag) == root;

  // `Comic|Series|Chapter 1` -> `Series › Chapter 1`
  static String title(String comicTag) => TagPath.segments(comicTag).skip(1).join(' › ');

  // comic tag -> its pages, in reading order, including pages hidden from the gallery
  static Map<String, List<AvesEntry>> collect(CollectionSource source) {
    final pagesByComic = <String, List<AvesEntry>>{};
    for (final entry in source.allEntries.where((v) => !v.trashed)) {
      for (final tag in entry.tags.where(isComicTag)) {
        pagesByComic.putIfAbsent(tag, () => []).add(entry);
      }
    }
    return pagesByComic.map((tag, pages) => MapEntry(tag, ordered(tag, pages)));
  }

  static List<AvesEntry> pagesOf(CollectionSource source, String comicTag) {
    final pages = source.allEntries.where((v) => !v.trashed && v.tags.contains(comicTag)).toList();
    return ordered(comicTag, pages);
  }

  // pages in the saved order, then pages not ordered yet, by file name
  static List<AvesEntry> ordered(String comicTag, List<AvesEntry> pages) {
    final order = settings.comicOrders[comicTag] ?? const [];
    final rank = {for (final (i, key) in order.indexed) key: i};
    final known = pages.where((v) => rank.containsKey(keyOf(v))).sortedBy<num>((v) => rank[keyOf(v)]!);
    final others = pages.whereNot((v) => rank.containsKey(keyOf(v))).sorted(compareByFileName);
    return [...known, ...others];
  }

  static void saveOrder(String comicTag, List<AvesEntry> pages) {
    settings.comicOrders = {...settings.comicOrders, comicTag: pages.map(keyOf).toList()};
  }

  static int compareByFileName(AvesEntry a, AvesEntry b) => compareAsciiUpperCaseNatural(_fileName(a), _fileName(b));

  static String _fileName(AvesEntry entry) => p.basename(entry.path ?? entry.uri);

  // pages are identified by path, which Aves keeps up to date when moving files
  static String keyOf(AvesEntry entry) => entry.path ?? entry.uri;

  static ComicReadingMode readingMode(String comicTag) {
    final name = settings.comicReadingModes[comicTag];
    return ComicReadingMode.values.firstWhereOrNull((v) => v.name == name) ?? .leftToRight;
  }

  static void setReadingMode(String comicTag, ComicReadingMode mode) {
    settings.comicReadingModes = {...settings.comicReadingModes, comicTag: mode.name};
  }

  // whether each comic shows as a single tile (its cover) in the gallery
  static bool get stackInGallery => !settings.comicPagesShown;

  static set stackInGallery(bool stacked) => settings.comicPagesShown = !stacked;

  // comic of a gallery tile stacking a comic, if it is one
  static String? comicOfStack(AvesEntry entry) {
    final pages = entry.stackedEntries;
    if (pages == null || pages.isEmpty) return null;
    final first = pages.first.tags.where(isComicTag);
    return first.firstWhereOrNull((tag) => pages.every((page) => page.tags.contains(tag)));
  }
}
