/*
 * Copyright 2022 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import 'package:json_annotation/json_annotation.dart';

part 'notification.g.dart';

//@JsonSerializable() EDIT CHANGES MANUALLY!
class Notification {
  String created_at, message, userId, id, title;
  bool isRead;

  DateTime createdAt() {
    return DateTime.parse(created_at).toLocal();
  }

  Notification(this.created_at, this.message, this.userId, this.id, this.isRead, this.title);
  factory Notification.fromJson(Map<String, dynamic> json) => _$NotificationFromJson(json);
  Map<String, dynamic> toJson() => _$NotificationToJson(this);
}

Notification _$NotificationFromJson(
    Map<String, dynamic> json) =>
    Notification(
      json['created_at'] as String,
      json['message'] as String,
      json['userId'] as String,
      json['_id'] as String,
      json['isRead'] as bool,
      json['title'] as String,
    );

Map<String, dynamic> _$NotificationToJson(
    Notification instance) =>
    <String, dynamic>{
      'created_at': instance.created_at,
      'message': instance.message,
      'userId': instance.userId,
      '_id': instance.id,
      'isRead': instance.isRead,
      'title': instance.title,
    };


@JsonSerializable()
class NotificationResponse {
  List<Notification> notifications;
  int offset, limit, total;

  NotificationResponse(this.notifications, this.offset, this.limit, this.total);
  factory NotificationResponse.fromJson(Map<String, dynamic> json) => _$NotificationResponseFromJson(json);
  Map<String, dynamic> toJson() => _$NotificationResponseToJson(this);
}
