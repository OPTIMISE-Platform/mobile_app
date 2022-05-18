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

import 'package:firebase_messaging/firebase_messaging.dart';

Map<String, dynamic> remoteMessageToMap(RemoteMessage message) {
  return {
    'senderId': message.senderId,
    'category': message.category,
    'collapseKey': message.collapseKey,
    'contentAvailable': message.contentAvailable,
    'data': message.data,
    'from': message.from,
    'messageId': message.messageId,
    'messageType': message.messageType,
    'mutableContent': message.mutableContent,
    'notification': message.notification == null
        ? null
        : {
            'title': message.notification!.title,
            'body': message.notification!.body,
          },
    'sentTime': message.sentTime?.millisecondsSinceEpoch,
    'threadId': message.threadId,
    'ttl': message.ttl,
  };
}
