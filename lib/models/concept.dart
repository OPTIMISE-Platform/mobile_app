import 'package:json_annotation/json_annotation.dart';

part 'concept.g.dart';

@JsonSerializable()
class Concept {
  String id, name, base_characteristic_id;
  List<String> characteristic_ids;

  Concept(this.id, this.name, this.base_characteristic_id, this.characteristic_ids);
  factory Concept.fromJson(Map<String, dynamic> json) => _$ConceptFromJson(json);
  Map<String, dynamic> toJson() => _$ConceptToJson(this);
}
