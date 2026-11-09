/*
 * Copyright 2026 InfAI (CC SES)
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

part 'protocol.g.dart';

/// A protocol of a device-repository service. Its segments name the messages
/// a device sends: a service output reads one segment, see [extractValue].
@JsonSerializable()
class Protocol {
  String id;
  String? name;

  /// The platform's Go model writes a protocol without segments as null.
  @JsonKey(defaultValue: <ProtocolSegment>[])
  List<ProtocolSegment> protocol_segments;

  Protocol(this.id, this.name, this.protocol_segments);
  factory Protocol.fromJson(Map<String, dynamic> json) => _$ProtocolFromJson(json);
  Map<String, dynamic> toJson() => _$ProtocolToJson(this);
}

@JsonSerializable()
class ProtocolSegment {
  String id;
  String name;

  ProtocolSegment(this.id, this.name);
  factory ProtocolSegment.fromJson(Map<String, dynamic> json) => _$ProtocolSegmentFromJson(json);
  Map<String, dynamic> toJson() => _$ProtocolSegmentToJson(this);
}
