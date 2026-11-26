import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/filters/placeholder.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/tags/tag_catalog.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/model/tags/tag_portraits.dart';
import 'package:aves/theme/durations.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/basic/divider.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/expandable_filter_row.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/aves_filter_chip.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/dialogs/entry_editors/tag_implication_dialog.dart';
import 'package:aves/widgets/tags/online_tag_search_page.dart';
import 'package:aves/widgets/tags/tag_portrait_crop_page.dart';
import 'package:aves/widgets/tags/tag_portrait_popup.dart';
import 'package:aves/widgets/tags/tag_tree_list.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class const TagEditorPage({
  super.key,
  required final Map<AvesEntry, Set<TagFilter>> tagsByEntry,
}) extends StatefulWidget {
  static const routeName = '/info/tag_editor';

  @override
  State<TagEditorPage> createState() => _TagEditorPageState();
}

class _TagEditorPageState extends State<TagEditorPage> {
  final TextEditingController _newTagTextController = TextEditingController();
  final FocusNode _newTagTextFocusNode = FocusNode();
  final ValueNotifier<String?> _expandedSectionNotifier = ValueNotifier(null);
  late final Map<AvesEntry, Set<CollectionFilter>> filtersByEntry;
  late final List<CollectionFilter> _topTags;
  final List<CollectionFilter> _userAddedFilters = [];

  static final List<PlaceholderFilter> _placeholders = [
    PlaceholderFilter.country,
    PlaceholderFilter.state,
    PlaceholderFilter.place,
  ];

  @override
  void initState() {
    super.initState();
    filtersByEntry = widget.tagsByEntry.map((key, value) => MapEntry(key, value.cast<CollectionFilter>().toSet()));
    _expandedSectionNotifier.value = settings.tagEditorExpandedSection;
    _expandedSectionNotifier.addListener(() => settings.tagEditorExpandedSection = _expandedSectionNotifier.value);
    _initTopTags();
    // known characters are offered while typing, once loaded
    TagCatalog.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final source = context.read<CollectionSource?>();
      settings.removeObsoleteRecentTags(source);
    });
  }

  @override
  void dispose() {
    _newTagTextController.dispose();
    _newTagTextFocusNode.dispose();
    _expandedSectionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showCount = filtersByEntry.length > 1;
    final Map<CollectionFilter, int> entryCountByTag = {};
    filtersByEntry.entries.forEach((kv) {
      kv.value.forEach((tag) => entryCountByTag[tag] = (entryCountByTag[tag] ?? 0) + 1);
    });
    List<MapEntry<CollectionFilter, int>> sortedTags = _sortCurrentTags(entryCountByTag);

    final untaggedColor = Themes.backgroundTextColor(context);

    return PopScope(
      canPop: !_isModified,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final NavigatorState navigator = Navigator.of(context);
        if (await showConfirmationDialog(
          context: context,
          message: context.l10n.tagEditorDiscardDialogMessage,
        )) {
          navigator.pop();
        }
      },
      child: AvesScaffold(
        appBar: AppBar(
          title: Text(l10n.tagEditorPageTitle),
          actions: [
            // looks the image up online, for a single item
            if (filtersByEntry.length == 1)
              IconButton(
                icon: const Icon(AIcons.onlineTagSearch),
                onPressed: _findTagsOnline,
                tooltip: 'Find tags online',
              ),
            IconButton(
              icon: const Icon(AIcons.reset),
              onPressed: _reset,
              tooltip: l10n.resetTooltip,
            ),
            IconButton(
              icon: const Icon(AIcons.apply),
              onPressed: () => Navigator.maybeOf(context)?.pop<Map<AvesEntry, Set<CollectionFilter>>>(filtersByEntry),
              tooltip: l10n.saveTooltip,
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: SafeArea(
          child: ValueListenableBuilder<String?>(
            valueListenable: _expandedSectionNotifier,
            builder: (context, expandedSection, child) {
              return ValueListenableBuilder<TextEditingValue>(
                valueListenable: _newTagTextController,
                builder: (context, value, child) {
                  final upQuery = value.text.trim().toUpperCase();
                  final source = context.read<CollectionSource?>();
                  bool containQuery(CollectionFilter v) => v.matchLabel(context, upQuery);
                  final recentFilters = settings.recentTags.where(containQuery).toList();
                  final topTagFilters = _topTags.where(containQuery).toList();
                  final placeholderFilters = _placeholders.where(containQuery).toList();
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8, end: 16),
                        child: Row(
                          crossAxisAlignment: .end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newTagTextController,
                                focusNode: _newTagTextFocusNode,
                                decoration: InputDecoration(
                                  labelText: l10n.tagEditorPageNewTagFieldLabel,
                                ),
                                autofocus: true,
                                onSubmitted: (newTag) {
                                  _addCustomTag(newTag);
                                  _newTagTextFocusNode.requestFocus();
                                },
                              ),
                            ),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _newTagTextController,
                              builder: (context, value, child) {
                                return IconButton(
                                  icon: const Icon(AIcons.add),
                                  onPressed: value.text.trim().isEmpty ? null : () => _addCustomTag(_newTagTextController.text),
                                  tooltip: l10n.tagEditorPageAddTagTooltip,
                                );
                              },
                            ),
                            Selector<Settings, bool>(
                              selector: (context, s) => s.tagEditorCurrentFilterSectionExpanded,
                              builder: (context, isExpanded, child) {
                                return IconButton(
                                  icon: Icon(isExpanded ? AIcons.collapse : AIcons.expand),
                                  onPressed: sortedTags.isEmpty ? null : () => settings.tagEditorCurrentFilterSectionExpanded = !isExpanded,
                                  tooltip: isExpanded ? MaterialLocalizations.of(context).expandedIconTapHint : MaterialLocalizations.of(context).collapsedIconTapHint,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: AnimatedCrossFade(
                          firstChild: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: AvesFilterChip.minChipHeight),
                            child: Center(
                              child: Row(
                                mainAxisSize: .min,
                                children: [
                                  Icon(AIcons.tagUntagged, color: untaggedColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.filterNoTagLabel,
                                    style: TextStyle(color: untaggedColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          secondChild: ExpandableFilterRow(
                            filters: sortedTags.map((kv) => kv.key).toList(),
                            isExpanded: context.select<Settings, bool>((v) => v.tagEditorCurrentFilterSectionExpanded),
                            showGenericIcon: false,
                            leadingBuilder: showCount
                                ? (filter) => _TagCount(
                                    count: sortedTags.firstWhere((kv) => kv.key == filter).value,
                                  )
                                : null,
                            onTap: (filter) {
                              if (filtersByEntry.keys.length > 1) {
                                // for multiple entries, set tag for all of them
                                filtersByEntry.forEach((entry, filters) => filters.add(filter));
                                setState(() {});
                              } else {
                                // for single entry, remove tag (like pressing on the remove icon)
                                _removeTag(filter);
                              }
                            },
                            onRemove: _removeTag,
                            // long press a tag to see its portrait, and change it or its implied tags
                            onLongPress: _onTagLongPress,
                          ),
                          crossFadeState: sortedTags.isEmpty ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                          duration: ADurations.tagEditorTransition,
                        ),
                      ),
                      // while typing, all known tags matching the text, as a tree
                      if (upQuery.isNotEmpty && source != null) ...[
                        const ThinDivider(),
                        TagTreeList(
                          source: source,
                          upQuery: upQuery,
                          selected: _commonTags,
                          extraTags: TagCatalog.instance.tags,
                          onLongPress: _showTagPopup,
                          // keeps the text, so several tags of the same franchise can be picked in a row
                          onTap: (tag) {
                            final filter = TagFilter(tag);
                            if (_commonTags.contains(tag)) {
                              _removeTag(filter);
                            } else {
                              _addTag(filter, clearQuery: false);
                            }
                          },
                        ),
                      ],
                      const ThinDivider(),
                      _FilterRow(
                        title: l10n.statsTopTagsSectionTitle,
                        filters: topTagFilters,
                        expandedNotifier: _expandedSectionNotifier,
                        onTap: _addTag,
                        onLongPress: _onTagLongPress,
                      ),
                      _FilterRow(
                        title: l10n.tagEditorSectionRecent,
                        filters: recentFilters,
                        expandedNotifier: _expandedSectionNotifier,
                        onTap: _addTag,
                        onLongPress: _onTagLongPress,
                      ),
                      _FilterRow(
                        title: l10n.tagEditorSectionPlaceholders,
                        filters: placeholderFilters,
                        expandedNotifier: _expandedSectionNotifier,
                        onTap: _addTag,
                        onLongPress: _onTagLongPress,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _initTopTags() {
    final Map<String, int> entryCountByTag = {};
    final visibleEntries = context.read<CollectionSource?>()?.visibleEntries;
    visibleEntries?.forEach((entry) {
      entry.tags.forEach((tag) => entryCountByTag[tag] = (entryCountByTag[tag] ?? 0) + 1);
    });
    List<MapEntry<CollectionFilter, int>> sortedTopTags = _sortCurrentTags(entryCountByTag.map((key, value) => MapEntry(TagFilter(key), value)));
    _topTags = sortedTopTags.map((kv) => kv.key).toList();
  }

  List<MapEntry<CollectionFilter, int>> _sortCurrentTags(Map<CollectionFilter, int> entryCountByTag) {
    return entryCountByTag.entries.toList()..sort((kv1, kv2) {
      final filter1 = kv1.key;
      final filter2 = kv2.key;

      final recent1 = _userAddedFilters.indexOf(filter1);
      final recent2 = _userAddedFilters.indexOf(filter2);
      var c = recent2.compareTo(recent1);
      if (c != 0) return c;

      final count1 = kv1.value;
      final count2 = kv2.value;
      c = count2.compareTo(count1);
      if (c != 0) return c;

      return filter1.compareTo(filter2);
    });
  }

  // tags present on all edited items
  Set<String> get _commonTags {
    final tagSets = filtersByEntry.values.map((filters) => filters.whereType<TagFilter>().map((v) => v.tag).toSet());
    return tagSets.isEmpty ? {} : tagSets.reduce((a, b) => a.intersection(b));
  }

  bool get _isModified {
    for (final kv in filtersByEntry.entries) {
      final oldFilters = kv.key.tags.map(TagFilter.new).toSet();
      final newFilters = kv.value;
      if (newFilters.length != oldFilters.length || !newFilters.containsAll(oldFilters)) return true;
    }
    return false;
  }

  void _reset() {
    _userAddedFilters.clear();
    filtersByEntry.forEach((entry, tags) {
      final originalFilters = entry.tags.map(TagFilter.new).toSet();
      tags
        ..clear()
        ..addAll(originalFilters);
    });
    setState(() {});
  }

  void _addCustomTag(String newTag) {
    final tag = TagPath.normalize(newTag);
    if (tag.isNotEmpty) {
      _addTag(TagFilter(tag));
    }
  }

  void _addTag(CollectionFilter filter, {bool clearQuery = true}) {
    settings.recentTags = settings.recentTags
      ..remove(filter)
      ..insert(0, filter);
    _userAddedFilters
      ..remove(filter)
      ..add(filter);
    // also add the tags implied by this one, e.g. `C&C` for `Asuna`
    final Set<CollectionFilter> impliedFilters = filter is TagFilter ? settings.tagImplications.added({filter.tag}).map(TagFilter.new).toSet() : {};
    filtersByEntry.forEach(
      (entry, tags) => tags
        ..add(filter)
        ..addAll(impliedFilters),
    );
    if (clearQuery) {
      _newTagTextController.clear();
    }
    setState(() {});
  }

  void _onTagLongPress(BuildContext context, CollectionFilter filter, Offset tapPosition) {
    if (filter is TagFilter && filter.tag.isNotEmpty) {
      _showTagPopup(filter.tag);
    }
  }

  // portrait of the tag, with actions to change it and the tags it implies
  Future<void> _showTagPopup(String tag) async {
    final portraits = TagPortraits.instance;
    final singleEntry = filtersByEntry.length == 1 ? filtersByEntry.keys.first : null;
    await showTagPortraitPopup(
      context,
      tag: tag,
      actions: [
        if (singleEntry != null)
          TagPopupAction(
            label: portraits.has(tag) ? 'Use this image' : 'Set from this image',
            icon: AIcons.portrait,
            onTap: () => _setPortrait(singleEntry, tag),
          ),
        if (portraits.has(tag))
          TagPopupAction(
            label: 'Remove portrait',
            icon: AIcons.delete,
            onTap: () async {
              await portraits.remove(tag);
              if (mounted) setState(() {});
            },
          ),
        TagPopupAction(
          label: 'New tag under it',
          icon: AIcons.add,
          onTap: () => _startTagUnder(tag),
        ),
        TagPopupAction(
          label: 'Implied tags',
          icon: AIcons.tag,
          onTap: () => _editImplications(tag),
        ),
      ],
    );
  }

  // fills the text field with the tag path, ready to type the new last part,
  // e.g. `Outfit|Lingerie|Thighhighs|`
  void _startTagUnder(String tag) {
    final text = '$tag${TagPath.separator}';
    _newTagTextController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _newTagTextFocusNode.requestFocus();
  }

  Future<void> _findTagsOnline() async {
    final entry = filtersByEntry.keys.first;
    final currentTags = filtersByEntry[entry]!.whereType<TagFilter>().map((v) => v.tag).toSet();
    final tags = await Navigator.maybeOf(context)?.push<Set<String>>(
      MaterialPageRoute(
        settings: const RouteSettings(name: OnlineTagSearchPage.routeName),
        builder: (context) => OnlineTagSearchPage(entry: entry, currentTags: currentTags),
      ),
    );
    if (tags == null || !mounted) return;
    // added like typed tags, with their implied tags
    tags.forEach((tag) => _addTag(TagFilter(tag), clearQuery: false));
  }

  Future<void> _setPortrait(AvesEntry entry, String tag) async {
    await Navigator.maybeOf(context)?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: TagPortraitCropPage.routeName),
        builder: (context) => TagPortraitCropPage(entry: entry, tag: tag),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editImplications(String tag) async {
    final implications = settings.tagImplications;
    final implied = await showAvesDialog<Set<String>>(
      context: context,
      builder: (context) => TagImplicationDialog(
        tag: tag,
        implied: implications.impliedBy(tag),
      ),
      routeSettings: const RouteSettings(name: TagImplicationDialog.routeName),
    );
    if (implied == null || !mounted) return;

    final updated = implications.withRule(tag, implied);
    settings.tagImplications = updated;

    // apply the rule right away to the items being edited
    filtersByEntry.forEach((entry, filters) {
      final tags = filters.whereType<TagFilter>().map((v) => v.tag).toSet();
      if (tags.any((v) => TagPath.isWithin(v, tag))) {
        filters.addAll(updated.added(tags).map(TagFilter.new));
      }
    });
    setState(() {});
  }

  void _removeTag(CollectionFilter filter) {
    _userAddedFilters.remove(filter);
    filtersByEntry.forEach((entry, filters) => filters.remove(filter));
    setState(() {});
  }
}

class const _FilterRow({
  required final String title,
  required final List<CollectionFilter> filters,
  required final ValueNotifier<String?> expandedNotifier,
  required final void Function(CollectionFilter filter) onTap,
  final OffsetFilterCallback? onLongPress,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return filters.isEmpty
        ? const SizedBox()
        : TitledExpandableFilterRow(
            title: title,
            filters: filters,
            expandedNotifier: expandedNotifier,
            showGenericIcon: false,
            onTap: onTap,
            onLongPress: onLongPress,
          );
  }
}

class const _TagCount({
  required final int count,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(
          BorderSide(
            color: DefaultTextStyle.of(context).style.color!,
          ),
        ),
        borderRadius: const BorderRadius.all(Radius.circular(123)),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: AvesFilterChip.fontSize),
      ),
    );
  }
}
