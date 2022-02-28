import 'package:json_annotation/json_annotation.dart';

part 'content_variable.g.dart';

typedef ContentType = String;

@JsonSerializable()
class ContentVariable {
  static final ContentVariable NONE = '' as ContentVariable;
  static final ContentVariable STRING = 'https://schema.org/Text' as ContentVariable;
  static final ContentVariable INTEGER = 'https://schema.org/Integer' as ContentVariable;
  static final ContentVariable FLOAT = 'https://schema.org/Float' as ContentVariable;
  static final ContentVariable BOOLEAN = 'https://schema.org/Boolean' as ContentVariable;
  static final ContentVariable STRUCTURE = 'https://schema.org/StructuredValue' as ContentVariable;
  static final ContentVariable LIST = 'https://schema.org/ItemList' as ContentVariable;



  String? id, name, characteristic_id, unit_reference, aspect_id, concept_id;
  ContentType type;
  List<ContentVariable>? sub_content_variables;
  dynamic value;
  List<String>? serialization_options;

  ContentVariable(this.id, this.name, this.characteristic_id, this.unit_reference, this.aspect_id, this.concept_id, this.type, this.sub_content_variables, this.value, this.serialization_options);
  factory ContentVariable.fromJson(Map<String, dynamic> json) => _$ContentVariableFromJson(json);
  Map<String, dynamic> toJson() => _$ContentVariableToJson(this);
}
