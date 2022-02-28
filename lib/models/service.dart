import 'package:json_annotation/json_annotation.dart';

import 'content.dart';

part 'service.g.dart';

@JsonSerializable()
class Service {
  String id, local_id, name, description, protocol_id, interaction, service_group_key;
  List<Content> inputs, outputs;

  Service(this.id, this.local_id, this.name, this.description, this.protocol_id, this.interaction, this.service_group_key, this.inputs, this.outputs);
  factory Service.fromJson(Map<String, dynamic> json) => _$ServiceFromJson(json);
  Map<String, dynamic> toJson() => _$ServiceToJson(this);
}
