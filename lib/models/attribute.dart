import 'package:json_annotation/json_annotation.dart';

part 'attribute.g.dart';

@JsonSerializable()
class Attribute {
  String key, value;

  Attribute(this.key, this.value);
  factory Attribute.fromJson(Map<String, dynamic> json) => _$AttributeFromJson(json);
  Map<String, dynamic> toJson() => _$AttributeToJson(this);
}
