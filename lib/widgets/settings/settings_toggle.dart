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

import 'package:flutter/material.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';

/// A settings row with a switch.
///
/// Five rows on the settings page differed only in their label and in which
/// pair of Settings accessors they used, and each repeated the haptic tick.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final bool value;

  /// Persist the new value and notify. The haptic tick is added here.
  final Future<void> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        trailing: Switch.adaptive(
          value: value,
          onChanged: (v) async {
            await onChanged(v);
            HapticFeedbackProxy.lightImpact();
          },
        ),
      );
}
