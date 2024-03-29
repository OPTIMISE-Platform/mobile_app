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

import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';

part 'annotations.g.dart';

@JsonSerializable()
@embedded
class Annotations {
  bool? connected;

  Annotations();

  Annotations.New(this.connected);
  factory Annotations.fromJson(Map<String, dynamic> json) => _$AnnotationsFromJson(json);
  Map<String, dynamic> toJson() => _$AnnotationsToJson(this);
}
