import 'package:json_annotation/json_annotation.dart';

part 'characteristic.g.dart';

@JsonSerializable()
class Characteristic {
  String id, name, type;
  double? min_value, max_value;
  dynamic? value;
  List<Characteristic>? sub_characteristics;


  Characteristic(this.id, this.name, this.type, this.min_value, this.max_value, this.value, this.sub_characteristics);
  factory Characteristic.fromJson(Map<String, dynamic> json) => _$CharacteristicFromJson(json);
  Map<String, dynamic> toJson() => _$CharacteristicToJson(this);
}
