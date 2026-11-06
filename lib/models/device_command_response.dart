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

part 'device_command_response.g.dart';

@JsonSerializable()
class DeviceCommandResponse {
  int status_code;
  dynamic message;

  /// RFC 3339 time of the stored value the answer was read from; absent for a
  /// live device answer and for group commands.
  String? time;

  DeviceCommandResponse(this.status_code, this.message, {this.time});

  /// [time] parsed, null when absent or not a valid timestamp.
  DateTime? get lastMessageTime => time == null ? null : DateTime.tryParse(time!);

  factory DeviceCommandResponse.fromJson(Map<String, dynamic> json) => _$DeviceCommandResponseFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceCommandResponseToJson(this);
}
