import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/models/annotations.dart';
import 'package:mobile_app/models/attribute.dart';

part 'device_permsearch.g.dart';

@JsonSerializable()
class DevicePermSearch {
  String id, local_id, name, device_type_id, creator;
  List<Attribute>? attributes;
  Annotations? annotations;
  bool shared;

  DevicePermSearch(this.id, this.local_id, this.name, this.attributes,
      this.device_type_id, this.annotations, this.shared, this.creator);

  factory DevicePermSearch.fromJson(Map<String, dynamic> json) =>
      _$DevicePermSearchFromJson(json);

  Map<String, dynamic> toJson() => _$DevicePermSearchToJson(this);
}
