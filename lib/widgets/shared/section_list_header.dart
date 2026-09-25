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
import 'package:mobile_app/theme.dart';

/// Small title above a grouped-list section's surface.
///
/// Left/right-aligned with the surface below it, not with its hairline
/// inset, and carries the vertical gap between two sections' surfaces above
/// its text.
class SectionListHeader extends StatelessWidget {
  const SectionListHeader(this.title, {this.horizontalMargin = Spacing.lg, super.key});

  final String title;
  final double horizontalMargin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          horizontalMargin, Spacing.lg, horizontalMargin, Spacing.xs),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
