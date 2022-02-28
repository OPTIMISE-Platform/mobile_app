import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/models/content_variable.dart';

part 'content.g.dart';

@JsonSerializable()
class Content {
  String id, serialization, protocol_segment_id;
  ContentVariable content_variable;


  Content(this.id, this.serialization, this.protocol_segment_id, this.content_variable);
  factory Content.fromJson(Map<String, dynamic> json) => _$ContentFromJson(json);
  Map<String, dynamic> toJson() => _$ContentToJson(this);
}
