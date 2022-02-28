import 'package:json_annotation/json_annotation.dart';

part 'aspect.g.dart';

@JsonSerializable()
class Aspect {
  String id, name;
  List<Aspect>? sub_aspects;

  Aspect(this.id, this.name, this.sub_aspects);
  factory Aspect.fromJson(Map<String, dynamic> json) => _$AspectFromJson(json);
  Map<String, dynamic> toJson() => _$AspectToJson(this);
}
