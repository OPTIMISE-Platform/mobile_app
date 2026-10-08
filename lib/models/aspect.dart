/*
 * Copyright 2022 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import 'package:json_annotation/json_annotation.dart';

part 'aspect.g.dart';

@JsonSerializable()
class Aspect {
  String id, name;
  List<Aspect>? sub_aspects;

  Aspect(this.id, this.name, this.sub_aspects);
  factory Aspect.fromJson(Map<String, dynamic> json) => _$AspectFromJson(json);
  Map<String, dynamic> toJson() => _$AspectToJson(this);
}

/// The names of [aspectIds], searched in [aspects] and their sub-aspects,
/// joined with ", " in the list's order. An unknown id contributes [missing],
/// or nothing when that is null.
String joinAspectNames(Iterable<Aspect> aspects, List<String> aspectIds, {String? missing}) {
  final names = <String>[];
  for (final id in aspectIds) {
    final name = _findAspect(aspects, id)?.name ?? missing;
    if (name != null) names.add(name);
  }
  return names.join(", ");
}

/// Whether every aspect of [general] is one of [specific] or an ancestor of
/// one, in the tree of [aspects].
bool aspectsCover(Iterable<Aspect> aspects, List<String> general, List<String> specific) => general.every((g) {
      final subAspects = _findAspect(aspects, g)?.sub_aspects ?? const <Aspect>[];
      return specific.any((s) => s == g || _findAspect(subAspects, s) != null);
    });

Aspect? _findAspect(Iterable<Aspect> aspects, String id) {
  for (final a in aspects) {
    if (a.id == id) return a;
    final subAspects = a.sub_aspects;
    if (subAspects != null) {
      final sub = _findAspect(subAspects, id);
      if (sub != null) return sub;
    }
  }
  return null;
}
