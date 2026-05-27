// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NotificationResponse _$NotificationResponseFromJson(
  Map<String, dynamic> json,
) => NotificationResponse(
  (json['notifications'] as List<dynamic>)
      .map((e) => Notification.fromJson(e as Map<String, dynamic>))
      .toList(),
  (json['offset'] as num).toInt(),
  (json['limit'] as num).toInt(),
  (json['total'] as num).toInt(),
);

Map<String, dynamic> _$NotificationResponseToJson(
  NotificationResponse instance,
) => <String, dynamic>{
  'notifications': instance.notifications,
  'offset': instance.offset,
  'limit': instance.limit,
  'total': instance.total,
};
