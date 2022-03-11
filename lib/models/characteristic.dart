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

part 'characteristic.g.dart';

@JsonSerializable()
class Characteristic {
  String id, name, type, display_unit;
  double? min_value, max_value;
  dynamic value;
  List<Characteristic>? sub_characteristics;


  Characteristic(this.id, this.name, this.type, this.min_value, this.max_value, this.value, this.sub_characteristics, this.display_unit);
  factory Characteristic.fromJson(Map<String, dynamic> json) => _$CharacteristicFromJson(json);
  Map<String, dynamic> toJson() => _$CharacteristicToJson(this);
}
