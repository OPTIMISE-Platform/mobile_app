/*
 * Copyright 2026 InfAI (CC SES)
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

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/firebase_options.dart';

/// Owns all Firebase and Firebase Cloud Messaging (FCM) setup.
class FirebaseService {
  FirebaseService._(); // static-only class

  /// Initialises Firebase and registers the background message handler.
  /// Call this once during app startup, after [WidgetsFlutterBinding] is ready.
  static Future<void> init() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
  }
}

/// Top-level function required by [FirebaseMessaging.onBackgroundMessage].
/// Must be a top-level (non-anonymous) function.
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  // Firebase must be re-initialised in the background isolate.
  await Firebase.initializeApp();
  await AppState.queueRemoteMessage(message);
}