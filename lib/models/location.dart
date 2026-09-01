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


import 'package:flutter/widgets.dart';
import 'package:isar_community/isar.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:mobile_app/shared/entity_image.dart';
import 'package:mobile_app/shared/isar.dart';

part 'location.g.dart';

@JsonSerializable()
@collection
class Location {
  @Index(type: IndexType.hash)
  String id;
  @Index(caseSensitive: false)
  String name;
  String description, image;
  List<String> device_ids, device_group_ids;

  @JsonKey(ignore: true)
  @ignore
  Widget? imageWidget;

  @JsonKey(ignore: true)
  Id isarId = -1;

  Future<Location> initImage() async {
    // Only on success, so a later failed reload does not blank an image that
    // is already on screen.
    final loaded = await loadEntityImage(image, "location", id);
    if (loaded != null) imageWidget = loaded;
    return this;
  }


  Location(this.id, this.name, this.description, this.image, this.device_ids, this.device_group_ids) {
    isarId = fastHash(id);
  }
  factory Location.fromJson(Map<String, dynamic> json) => _$LocationFromJson(json);
  Map<String, dynamic> toJson() => _$LocationToJson(this);
}
