import 'package:json_annotation/json_annotation.dart';

part 'device_class.g.dart';

@JsonSerializable()
class DeviceClass {
  String id, image, name;

  DeviceClass(this.id, this.name, this.image);
  factory DeviceClass.fromJson(Map<String, dynamic> json) => _$DeviceClassFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceClassToJson(this);
}
