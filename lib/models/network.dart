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
import 'package:mobile_app/models/annotations.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:nsd/nsd.dart';

import '../shared/isar.dart';
import 'device_instance.dart';

part 'network.g.dart';

@JsonSerializable()
@collection
class Network {
  @Index(type: IndexType.hash)
  String id;
  @Index(caseSensitive: false)
  String name;
  String creator;
  Annotations? annotations;
  bool shared;
  List<String>? device_local_ids, device_ids;

  @JsonKey(ignore: true)
  Id isarId = -1;

  @JsonKey(ignore: true)
  @ignore
  Service? localService;

  @JsonKey(ignore: true)
  @ignore
  final List<DeviceState> states = [];

  Network(this.id, this.name,  this.annotations, this.shared, this.creator, this.device_local_ids, this.device_ids) {
    isarId = fastHash(id);
  }


  factory Network.fromJson(Map<String, dynamic> json) =>
      _$NetworkFromJson(json);

  Map<String, dynamic> toJson() => _$NetworkToJson(this);


  DeviceConnectionStatus getConnectionStatus() {
    if (annotations?.connected == null) {
      return DeviceConnectionStatus.unknown;
    }
    if (annotations!.connected!) {
      return DeviceConnectionStatus.online;
    } else {
      return DeviceConnectionStatus.offline;
    }
  }
}
