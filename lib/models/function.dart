import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/models/concept.dart';

part 'function.g.dart';

@JsonSerializable()
class PlatformFunction {
  String id, name, concept_id;

  PlatformFunction(this.id, this.name, this.concept_id);
  factory PlatformFunction.fromJson(Map<String, dynamic> json) => _$PlatformFunctionFromJson(json);
  Map<String, dynamic> toJson() => _$PlatformFunctionToJson(this);
}

@JsonSerializable()
class NestedFunction extends PlatformFunction {
  Concept concept;

  NestedFunction(String id, String name, String concept_id, this.concept): super(id, name, concept_id);
  factory NestedFunction.fromJson(Map<String, dynamic> json) => _$NestedFunctionFromJson(json);
  Map<String, dynamic> toJson() => _$NestedFunctionToJson(this);
}
