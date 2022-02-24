import 'package:json_annotation/json_annotation.dart';

part 'annotations.g.dart';

@JsonSerializable()
class Annotations {
  bool connected;

  Annotations(this.connected);
  factory Annotations.fromJson(Map<String, dynamic> json) => _$AnnotationsFromJson(json);
  Map<String, dynamic> toJson() => _$AnnotationsToJson(this);
}
