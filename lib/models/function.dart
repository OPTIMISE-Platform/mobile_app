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
import 'package:mobile_app/models/concept.dart';

part 'function.g.dart';

const controllingFunctionPrefix = "urn:infai:ses:controlling-function";

@JsonSerializable()
class PlatformFunction {
  String id, name, concept_id, display_name;

  PlatformFunction(this.id, this.name, this.concept_id, this.display_name);
  factory PlatformFunction.fromJson(Map<String, dynamic> json) => _$PlatformFunctionFromJson(json);
  Map<String, dynamic> toJson() => _$PlatformFunctionToJson(this);
}

@JsonSerializable()
class NestedFunction extends PlatformFunction {
  Concept concept;

  NestedFunction(String id, String name, String concept_id, String display_name, this.concept): super(id, name, concept_id, display_name);
  factory NestedFunction.fromJson(Map<String, dynamic> json) => _$NestedFunctionFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$NestedFunctionToJson(this);

  bool isControlling() {
    return id.startsWith(controllingFunctionPrefix);
  }

  bool hasInput() {
    return concept.base_characteristic != null && concept.base_characteristic!.type != "";
  }
}
