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

import 'package:flutter/services.dart';
import 'package:mobile_app/services/settings.dart';

class HapticFeedbackProxy {
  static bool get enabled => Settings.getHapticFeedBackEnabled();

  static Future<void> heavyImpact() async {
    if (enabled) {
      return HapticFeedback.heavyImpact();
    }
  }

  static Future<void> lightImpact() async {
    if (enabled) {
      return HapticFeedback.lightImpact();
    }
  }

  static Future<void> mediumImpact() async {
    if (enabled) {
      return HapticFeedback.mediumImpact();
    }
  }

  static Future<void> selectionClick() async {
    if (enabled) {
      return HapticFeedback.selectionClick();
    }
  }

  static Future<void> vibrate() async {
    if (enabled) {
      return HapticFeedback.vibrate();
    }
  }
}
