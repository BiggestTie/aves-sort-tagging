import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/grouping/common.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/tag.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/empty.dart';
import 'package:aves/widgets/common/providers/filter_group_provider.dart';
import 'package:aves/widgets/filter_grids/common/action_delegates/tag_set.dart';
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:aves/widgets/filter_grids/common/filter_nav_page.dart';
import 'package:aves/widgets/filter_grids/common/section_keys.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class TagListPage extends StatelessWidget {
  static const routeName = '/tags';

  final Uri? initialGroup;

  // for nested tags: the parent tag whose direct children are listed,
  // e.g. `Blue Archive`, or null for top level tags
  final String? tagPath;

  const new({
    super.key,
    required this.initialGroup,
    this.tagPath,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<FilterGrouping>.value(value: tagGrouping),
        FilterGroupProvider(initialValue: initialGroup),
      ],
      child: Builder(
        // to access filter group provider from subtree context
        builder: (context) {
          final source = context.read<CollectionSource>();
          return Selector<Settings, (ChipSectionFactor, SortFactor, bool, Set<CollectionFilter>)>(
            selector: (context, s) => (s.tagSectionFactor, s.tagSortFactor, s.tagSortReverse, s.pinnedFilters),
            shouldRebuild: (t1, t2) {
              // `Selector` by default uses `DeepCollectionEquality`, which does not go deep in collections within records
              const eq = DeepCollectionEquality();
              return !(eq.equals(t1.$1, t2.$1) && eq.equals(t1.$2, t2.$2) && eq.equals(t1.$3, t2.$3) && eq.equals(t1.$4, t2.$4));
            },
            builder: (context, _, child) {
              return ListenableBuilder(
                listenable: tagGrouping,
                builder: (context, child) => StreamBuilder<TagsChangedEvent>(
                  stream: source.eventBus.on<TagsChangedEvent>(),
                  builder: (context, _) {
                    final groupUri = context.watch<FilterGroupNotifier>().value;
                    final gridItems = getGridItems(source, ChipType.values.toSet(), groupUri, nested: true, tagPath: tagPath);
                    return FilterNavigationPage<TagBaseFilter, TagChipSetActionDelegate>(
                      source: source,
                      title: tagPath != null ? TagPath.leaf(tagPath!) : context.l10n.tagPageTitle,
                      // tapping a tag with nested tags opens the next level,
                      // except for the current level itself, listed first to show all its items
                      canDrillDown: (filter) => filter is TagFilter && filter.tag != tagPath && source.hasNestedTags(filter.tag),
                      onDrillDown: (context, filter) {
                        if (filter is! TagFilter) return;
                        Navigator.maybeOf(context)?.push(
                          MaterialPageRoute(
                            settings: const RouteSettings(name: TagListPage.routeName),
                            builder: (context) => TagListPage(
                              initialGroup: null,
                              tagPath: filter.tag,
                            ),
                          ),
                        );
                      },
                      sortFactor: settings.tagSortFactor,
                      showHeaders: settings.tagSectionFactor != ChipSectionFactor.none,
                      actionDelegate: TagChipSetActionDelegate(gridItems),
                      filterSections: groupToSections(context, gridItems),
                      emptyBuilder: () => EmptyContent(
                        icon: AIcons.tag,
                        text: context.l10n.tagEmpty,
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  // common with picking page

  // with `nested`, only tags directly below `tagPath` are listed
  // (top level tags when `tagPath` is null), with `tagPath` itself listed first
  static List<FilterGridItem<TagBaseFilter>> getGridItems(
    CollectionSource source,
    Set<ChipType> chipTypes,
    Uri? groupUri, {
    bool nested = false,
    String? tagPath,
  }) {
    final groupContent = tagGrouping.getDirectChildren(groupUri);

    Set<T> whereTypeRecursively<T>(Set<CollectionFilter> filters) {
      return {
        ...filters.whereType<T>(),
        ...filters.whereType<TagGroupFilter>().expand((v) => whereTypeRecursively<T>(v.filter.innerFilters)),
      };
    }

    final listedTags = <String>{};
    if (chipTypes.contains(ChipType.regular)) {
      final allTags = source.sortedTags;
      if (groupUri == null) {
        final withinGroups = whereTypeRecursively<TagFilter>(groupContent).map((v) => v.tag).toSet();
        var candidates = allTags.whereNot(withinGroups.contains);
        if (nested) {
          candidates = candidates.where((tag) => TagPath.parent(tag) == tagPath);
          if (tagPath != null && allTags.contains(tagPath)) {
            candidates = [tagPath, ...candidates];
          }
        }
        listedTags.addAll(candidates);
      } else {
        // check that group content is listed from source, to prevent displaying hidden content
        listedTags.addAll(groupContent.whereType<TagFilter>().map((v) => v.tag).where(allTags.contains));
      }
    }

    // always show groups, which are needed to navigate to other types
    // (manual groups only appear at the top level when browsing nested tags)
    final tagGroupFilters = nested && tagPath != null ? <TagGroupFilter>{} : groupContent.whereType<TagGroupFilter>().whereNot(settings.hiddenFilters.contains).toSet();

    final filters = <TagBaseFilter>{
      ...tagGroupFilters,
      ...listedTags.map(TagFilter.new),
    };

    final sorted = FilterNavigationPage.sort(settings.tagSortFactor, settings.tagSortReverse, source, filters);
    if (nested && tagPath != null) {
      // list the current level first, to show all its items
      final self = sorted.firstWhereOrNull((v) {
        final filter = v.filter;
        return filter is TagFilter && filter.tag == tagPath;
      });
      if (self != null) {
        sorted
          ..remove(self)
          ..insert(0, self);
      }
    }
    return sorted;
  }

  static Map<ChipSectionKey, List<FilterGridItem<TagBaseFilter>>> groupToSections(BuildContext context, Iterable<FilterGridItem<TagBaseFilter>> sortedMapEntries) {
    final pinned = settings.pinnedFilters.whereType<TagFilter>();
    final byPin = groupBy<FilterGridItem<TagBaseFilter>, bool>(sortedMapEntries, (v) => pinned.contains(v.filter));
    final pinnedMapEntries = (byPin[true] ?? []);
    final unpinnedMapEntries = (byPin[false] ?? []);

    var sections = <ChipSectionKey, List<FilterGridItem<TagBaseFilter>>>{};
    switch (settings.tagSectionFactor) {
      case ChipSectionFactor.importance:
        final groupKey = ChipImportanceSectionKey.group(context);
        final regularKey = ChipImportanceSectionKey.regular(context, AIcons.tag);
        sections = groupBy<FilterGridItem<TagBaseFilter>, ChipSectionKey>(unpinnedMapEntries, (kv) {
          final filter = kv.filter;
          switch (filter) {
            case TagGroupFilter _:
              return groupKey;
            case TagFilter _:
            default:
              return regularKey;
          }
        });

        sections = {
          // group ordering
          if (sections.containsKey(groupKey)) groupKey: sections[groupKey]!,
          if (sections.containsKey(regularKey)) regularKey: sections[regularKey]!,
        };
      case ChipSectionFactor.mimeType:
      case ChipSectionFactor.volume:
      case ChipSectionFactor.none:
        return {
          if (sortedMapEntries.isNotEmpty)
            const ChipSectionKey(): [
              ...pinnedMapEntries,
              ...unpinnedMapEntries,
            ],
        };
    }

    if (pinnedMapEntries.isNotEmpty) {
      sections = Map.fromEntries([
        MapEntry(ChipImportanceSectionKey.pinned(context), pinnedMapEntries),
        ...sections.entries,
      ]);
    }

    return sections;
  }
}
