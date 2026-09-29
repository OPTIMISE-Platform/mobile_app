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
import 'package:mobile_app/models/aspect_ids.dart';

part 'content_variable.g.dart';

typedef ContentType = String;

@JsonSerializable()
class ContentVariable {
  static const ContentType none = '';
  static const ContentType string = "https://schema.org/Text";
  static const ContentType integer = 'https://schema.org/Integer';
  static const ContentType float = 'https://schema.org/Float';
  static const ContentType boolean = 'https://schema.org/Boolean';
  static const ContentType structure = 'https://schema.org/StructuredValue';
  static const ContentType list = 'https://schema.org/ItemList';



  String? id, name, characteristic_id, unit_reference, aspect_id, function_id;
  ContentType type;
  List<ContentVariable>? sub_content_variables;
  dynamic value;
  List<String>? serialization_options;

  /// Replaces the deprecated [aspect_id], which a device-repository read sets
  /// to the alphabetically first entry of this list.
  @JsonKey(includeIfNull: false)
  List<String>? aspect_ids;

  ContentVariable(this.id, this.name, this.characteristic_id, this.unit_reference, this.aspect_id, this.function_id, this.type, this.sub_content_variables, this.value, this.serialization_options, [this.aspect_ids]);

  /// The aspects this variable carries, sorted; see [effectiveAspectIds].
  List<String> get effectiveAspects => effectiveAspectIds(aspect_id, aspect_ids);

  factory ContentVariable.fromJson(Map<String, dynamic> json) => _$ContentVariableFromJson(json);
  Map<String, dynamic> toJson() => _$ContentVariableToJson(this);
}
