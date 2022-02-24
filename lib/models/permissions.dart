import 'package:json_annotation/json_annotation.dart';

part  'permissions.g.dart';

@JsonSerializable()
class Permissions {
  bool a, r, w, x;

  Permissions(this.a, this.r, this.w, this.x);
  factory Permissions.fromJson(Map<String, dynamic> json) => _$PermissionsFromJson(json);
  Map<String, dynamic> toJson() => _$PermissionsToJson(this);
}
