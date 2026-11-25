import 'package:aves/model/filters/covered/tag.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/model/tags/tag_portraits.dart';
import 'package:aves/theme/icons.dart';
import 'package:material_ui/material_ui.dart';

// Vertical list of tags matching a query, laid out as a tree:
// `blue archive` lists Blue Archive, then Millennium, C&C, Asuna... indented below it.
// Parents of matching tags are included for context, even when they do not match.
class TagTreeList extends StatelessWidget {
  // maximum number of rows, to keep the list responsive
  static const maxRows = 300;

  final CollectionSource source;
  final String upQuery;
  final void Function(String tag) onTap;

  // e.g. to show the tag portrait
  final void Function(String tag)? onLongPress;

  // tags to show as already chosen (e.g. in the tag editor)
  final Set<String> selected;

  // tags to offer even when not used yet (e.g. from the catalog)
  final Set<String> extraTags;

  const new({
    super.key,
    required this.source,
    required this.upQuery,
    required this.onTap,
    this.onLongPress,
    this.selected = const {},
    this.extraTags = const {},
  });

  // all tags to list, in tree order
  static List<String> matchingTags(CollectionSource source, String upQuery, {Set<String> extraTags = const {}}) {
    final candidates = extraTags.isEmpty ? source.sortedTags : {...source.sortedTags, ...extraTags};
    final matching = candidates.where((tag) => TagPath.matches(tag, upQuery));
    final withParents = TagPath.expand(matching).toList()..sort(TagPath.compare);
    return withParents;
  }

  @override
  Widget build(BuildContext context) {
    final tags = matchingTags(source, upQuery, extraTags: extraTags);
    if (tags.isEmpty) return const SizedBox();

    // tags not used yet have no count
    final usedTags = source.sortedTags.toSet();
    final parents = {...source.parentTags, ...tags.map(TagPath.parent).nonNulls};

    final theme = Theme.of(context);
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: .6);
    final shown = tags.take(maxRows).toList();

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        ...shown.map((tag) {
          final depth = TagPath.depth(tag);
          final isMatch = TagPath.matches(tag, upQuery);
          final hasChildren = parents.contains(tag);
          final isSelected = selected.contains(tag);
          return InkWell(
            onTap: () => onTap(tag),
            onLongPress: onLongPress != null ? () => onLongPress!(tag) : null,
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: 16.0 + depth * 20, end: 16, top: 10, bottom: 10),
              child: Row(
                children: [
                  Icon(
                    isSelected ? AIcons.apply : (TagPortraits.instance.has(tag) ? AIcons.portrait : (hasChildren ? AIcons.group : AIcons.tag)),
                    size: 20,
                    color: isMatch ? null : dimColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      TagPath.leaf(tag),
                      style: TextStyle(
                        color: isMatch ? null : dimColor,
                        fontWeight: depth == 0 ? .w600 : null,
                      ),
                      overflow: .ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (usedTags.contains(tag))
                    Text(
                      '${source.count(TagFilter(tag))}',
                      style: TextStyle(color: dimColor),
                    ),
                ],
              ),
            ),
          );
        }),
        if (tags.length > shown.length)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${tags.length - shown.length} more — keep typing to narrow down',
              style: TextStyle(color: dimColor),
            ),
          ),
      ],
    );
  }
}
