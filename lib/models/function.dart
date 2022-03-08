import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/models/concept.dart';

part 'function.g.dart';

@JsonSerializable()
class Function {
  String id, name, concept_id;

  Function(this.id, this.name, this.concept_id);
  factory Function.fromJson(Map<String, dynamic> json) => _$FunctionFromJson(json);
  Map<String, dynamic> toJson() => _$FunctionToJson(this);
}

@JsonSerializable()
class NestedFunction extends Function {
  Concept concept;

  NestedFunction(String id, String name, String concept_id, this.concept): super(id, name, concept_id);
  factory NestedFunction.fromJson(Map<String, dynamic> json) => _$NestedFunctionFromJson(json);
  Map<String, dynamic> toJson() => _$NestedFunctionToJson(this);
}
