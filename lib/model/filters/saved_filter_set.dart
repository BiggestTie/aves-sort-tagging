import 'dart:convert';

import 'package:aves/model/filters/filters.dart';
import 'package:flutter/foundation.dart';

// A named set of collection filters (e.g. tags and albums, filtered in or out),
// saved in the app, like a home screen shortcut but listed in the drawer.
@immutable
class SavedFilterSet {
  final String name;
  final Set<CollectionFilter> filters;

  const new(this.name, this.filters);

  Map<String, Object?> toJsonMap() => {
    'name': name,
    'filters': filters.map((v) => v.toJsonString()).toList(),
  };

  static SavedFilterSet? fromJsonMap(Map<String, Object?> json) {
    final name = json['name'];
    final filters = json['filters'];
    if (name is! String || filters is! List) return null;
    return SavedFilterSet(name, filters.map(CollectionFilter.fromJson).nonNulls.toSet());
  }

  static List<SavedFilterSet> listFromJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((v) => fromJsonMap(v.cast<String, Object?>())).nonNulls.toList();
    } catch (error) {
      debugPrint('failed to decode saved filter sets from json=$jsonString error=$error');
      return [];
    }
  }

  static String listToJson(List<SavedFilterSet> sets) => jsonEncode(sets.map((v) => v.toJsonMap()).toList());
}
