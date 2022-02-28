import 'package:json_annotation/json_annotation.dart';

part 'function.g.dart';

@JsonSerializable()
class Function {
  String id, name, concept_id;

  Function(this.id, this.name, this.concept_id);
  factory Function.fromJson(Map<String, dynamic> json) => _$FunctionFromJson(json);
  Map<String, dynamic> toJson() => _$FunctionToJson(this);
}
