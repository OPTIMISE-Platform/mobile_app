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


import 'package:flutter/cupertino.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/shared/entity_image.dart';

part 'device_class.g.dart';

const cachSubdir = "/img";

@JsonSerializable()
class DeviceClass {
  String id, image, name;

  @JsonKey(ignore: true)
  Widget? imageWidget;

  @JsonKey(ignore: true)
  List<String> deviceIds = [];

  Future<void> _initImage() async {
    // Only on success, so a later failed reload does not blank an image that
    // is already on screen.
    final loaded = await loadEntityImage(image, "deviceClass", id);
    if (loaded != null) imageWidget = loaded;
  }

  DeviceClass(this.id, this.name, this.image);

  factory DeviceClass.fromJson(Map<String, dynamic> json) {
    final c = _$DeviceClassFromJson(json);
    c._initImage();
    return c;
  }

  Map<String, dynamic> toJson() => _$DeviceClassToJson(this);
}
