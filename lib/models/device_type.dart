import 'package:json_annotation/json_annotation.dart';
import 'service.dart';

part 'device_type.g.dart';

@JsonSerializable()
class DeviceType {
  String id, name, description, device_class_id;
  List<Service> services;

  DeviceType(this.id, this.name, this.description, this.device_class_id, this.services);
  factory DeviceType.fromJson(Map<String, dynamic> json) => _$DeviceTypeFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceTypeToJson(this);
}
