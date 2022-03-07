import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';

import 'service.dart';

part 'device_type.g.dart';

@JsonSerializable()
class DeviceType {
  String id, name, description, device_class_id;
  List<Service> service;

  DeviceType(
      this.id, this.name, this.description, this.device_class_id, this.service);

  factory DeviceType.fromJson(Map<String, dynamic> json) =>
      _$DeviceTypeFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceTypeToJson(this);
}

class DeviceTypePermSearch {
  String id, name, description, device_class_id;
  dynamic _service;

  static final _logger = Logger(printer: SimplePrinter());

  List<String> get service {
    if (_service is List<String>) {
      return _service;
    }
    if (_service is String) {
      return [_service];
    }
    _logger.w("unexpected type of service in device-type: " +
        _service.runtimeType.toString());
    return [];
  }

  DeviceTypePermSearch(this.id, this.name, this.description,
      this.device_class_id, this._service);

  factory DeviceTypePermSearch.fromJson(Map<String, dynamic> json) =>
      _$DeviceTypePermSearchFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceTypePermSearchToJson(this);
}

DeviceTypePermSearch _$DeviceTypePermSearchFromJson(
        Map<String, dynamic> json) =>
    DeviceTypePermSearch(
      json['id'] as String,
      json['name'] as String,
      json['description'] as String,
      json['device_class_id'] as String,
      json['service'] as dynamic,
    );

Map<String, dynamic> _$DeviceTypePermSearchToJson(
        DeviceTypePermSearch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'device_class_id': instance.device_class_id,
      'service': instance.service,
    };
