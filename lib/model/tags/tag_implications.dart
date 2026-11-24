import 'dart:convert';

import 'package:aves/model/tags/tag_path.dart';
import 'package:flutter/foundation.dart';

// Implied tags: rules like `Blue Archive|Asuna` -> {`Blue Archive|Groups|C&C`},
// so that adding a tag also adds the tags it implies.
//
// Rules chain (if C&C implies Millennium, adding Asuna adds both),
// and a rule on a tag also applies to tags nested below it
// (a rule on `Blue Archive|Asuna` also applies to `Blue Archive|Asuna|Bunny`).
@immutable
class TagImplications {
  final Map<String, Set<String>> rules;

  const new(this.rules);

  static const empty = TagImplications({});

  bool get isEmpty => rules.isEmpty;

  Set<String> impliedBy(String tag) => rules[TagPath.normalize(tag)] ?? const {};

  // returns a copy with the rule for `tag` replaced
  TagImplications withRule(String tag, Iterable<String> implied) {
    final key = TagPath.normalize(tag);
    final values = implied.map(TagPath.normalize).where((v) => v.isNotEmpty && v != key).toSet();
    final newRules = Map<String, Set<String>>.of(rules);
    if (key.isEmpty || values.isEmpty) {
      newRules.remove(key);
    } else {
      newRules[key] = values;
    }
    return TagImplications(newRules);
  }

  // the given tags, plus every tag they imply, directly or through other rules
  Set<String> apply(Iterable<String> tags) {
    final result = tags.map(TagPath.normalize).where((v) => v.isNotEmpty).toSet();
    if (rules.isEmpty) return result;

    final queue = List.of(result);
    while (queue.isNotEmpty) {
      final tag = queue.removeLast();
      for (final source in TagPath.selfAndAncestors(tag)) {
        for (final implied in rules[source] ?? const <String>{}) {
          if (result.add(implied)) {
            queue.add(implied);
          }
        }
      }
    }
    return result;
  }

  // only the tags that `apply` would add
  Set<String> added(Iterable<String> tags) {
    final original = tags.map(TagPath.normalize).toSet();
    return apply(original).difference(original);
  }

  static TagImplications fromJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return empty;
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) return empty;
      final rules = <String, Set<String>>{};
      decoded.forEach((key, value) {
        if (key is String && value is List) {
          final implied = value.whereType<String>().toSet();
          if (implied.isNotEmpty) rules[key] = implied;
        }
      });
      return TagImplications(rules);
    } catch (error) {
      debugPrint('failed to decode tag implications from json=$jsonString error=$error');
      return empty;
    }
  }

  String toJson() => jsonEncode(rules.map((key, value) => MapEntry(key, value.toList()..sort())));
}
