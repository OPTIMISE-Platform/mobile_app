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
import 'package:mobile_app/models/characteristic.dart';

part 'concept.g.dart';

@JsonSerializable()
class Concept {
  String id, name, base_characteristic_id;
  List<Characteristic> characteristics;

  /// Null in cache entries written before the field existed.
  List<ConceptConversion>? conversions;

  Concept(this.id, this.name, this.base_characteristic_id, this.characteristics, [this.conversions]);
  factory Concept.fromJson(Map<String, dynamic> json) => _$ConceptFromJson(json);
  Map<String, dynamic> toJson() => _$ConceptToJson(this);

  Characteristic getBaseCharacteristic() {
    return characteristics.firstWhere((element) => element.id == base_characteristic_id);
  }
}

/// One edge of the conversion graph between the characteristics of a concept.
/// [formula] maps the variable [placeholder_name] from [from] to [to].
@JsonSerializable()
class ConceptConversion {
  String from, to;
  int distance;
  String formula, placeholder_name;

  ConceptConversion(this.from, this.to, this.distance, this.formula, this.placeholder_name);
  factory ConceptConversion.fromJson(Map<String, dynamic> json) => _$ConceptConversionFromJson(json);
  Map<String, dynamic> toJson() => _$ConceptConversionToJson(this);
}
