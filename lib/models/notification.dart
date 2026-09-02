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

import 'package:flutter/material.dart';
import 'package:isar_community/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/shared/isar.dart';

part 'notification.g.dart';

/// Persisted so the list survives a start without a reachable backend. The
/// server stays the source of truth: a successful fetch replaces the stored
/// set, and a delete removes the rows as well.
@JsonSerializable()
@collection
class Notification {
  String created_at, message, userId, title;

  @JsonKey(name: '_id')
  @Index(unique: true, replace: true)
  String id;

  bool isRead;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Id isarId = -1;

  DateTime createdAt() {
    return DateTime.parse(created_at).toLocal();
  }

  show(BuildContext context) {
    Future.delayed(const Duration(milliseconds: 100),
      () {
        if (!context.mounted) return;
        showAdaptiveDialog(
          context: context,
          builder: (_) => AlertDialog.adaptive(
            title: Text(title, overflow: TextOverflow.ellipsis,),
            content: Text(message),
            actions: <Widget>[
              TextButton(child: Text('OK'), onPressed: () => Navigator.pop(context)),
            ],
          ),
        );
      });
  }

  Notification(this.created_at, this.message, this.userId, this.id, this.isRead, this.title) {
    isarId = fastHash(id);
  }

  factory Notification.fromJson(Map<String, dynamic> json) => _$NotificationFromJson(json);
  Map<String, dynamic> toJson() => _$NotificationToJson(this);
}

@JsonSerializable()
class NotificationResponse {
  List<Notification> notifications;
  int offset, limit, total;

  NotificationResponse(this.notifications, this.offset, this.limit, this.total);
  factory NotificationResponse.fromJson(Map<String, dynamic> json) => _$NotificationResponseFromJson(json);
  Map<String, dynamic> toJson() => _$NotificationResponseToJson(this);
}
