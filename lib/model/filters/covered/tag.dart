import 'package:aves/model/filters/container/tag_group.dart';
import 'package:aves/model/filters/covered/covered.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/tags/tag_path.dart';
import 'package:aves/model/tags/tag_portraits.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

class TagFilter extends CollectionFilter with CoveredFilter, TagBaseFilter {
  static const type = 'tag';

  final String tag;
  late final EntryPredicate _test;

  @override
  List<Object?> get props => [tag, reversed];

  new(this.tag, {super.reversed = false}) {
    if (tag.isEmpty) {
      _test = (entry) => entry.tags.isEmpty;
    } else {
      // also matches entries tagged with a nested tag below this one
      _test = (entry) => entry.tagsWithAncestors.contains(tag);
    }
  }

  factory fromMap(Map<String, Object?> json) {
    return TagFilter(
      json['tag'] as String,
      reversed: json['reversed'] as bool? ?? false,
    );
  }

  @override
  Map<String, Object?> toJsonMap() => {
    'type': type,
    'tag': tag,
    if (reversed) 'reversed': reversed,
  };

  @override
  EntryPredicate get positiveTest => _test;

  @override
  bool get exclusiveProp => false;

  @override
  String get universalLabel => tag;

  @override
  String getLabel(BuildContext context) => tag.isEmpty ? context.l10n.filterNoTagLabel : TagPath.label(tag);

  // also matches the full path of nested tags,
  // e.g. `millennium` matches `Blue Archive|Millennium|C&C|Asuna`
  @override
  bool matchLabel(BuildContext context, String query) => super.matchLabel(context, query) || (tag.isNotEmpty && TagPath.matches(tag, query));

  @override
  Widget? iconBuilder(BuildContext context, double size, {bool allowGenericIcon = true}) {
    // tags with a portrait show a face, as a hint to long press them
    if (tag.isNotEmpty && TagPortraits.instance.has(tag)) return Icon(AIcons.portrait, size: size);
    return allowGenericIcon ? Icon(tag.isEmpty ? AIcons.tagUntagged : AIcons.tag, size: size) : null;
  }

  @override
  String get category => type;

  @override
  String get key => '$type-$reversed-$tag';
}
