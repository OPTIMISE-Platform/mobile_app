import 'package:json_annotation/json_annotation.dart';

part 'device_command.g.dart';

@JsonSerializable()
class DeviceCommand {
  String function_id, device_id, service_id;
  dynamic input;

  DeviceCommand(this.function_id, this.device_id, this.service_id);
  factory DeviceCommand.fromJson(Map<String, dynamic> json) => _$DeviceCommandFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceCommandToJson(this);
}
