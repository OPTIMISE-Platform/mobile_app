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
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

/// One settings section: a title and the rows it currently shows. A section
/// builder computes [rows] after its own conditionals (debug mode, logged
/// in, ...), so its length is always what will actually be on screen -
/// [Settings] slices rows into a surface from that, never from a fixed count
/// that could include a row that ends up hidden.
class SettingsSection {
  const SettingsSection(this.title, this.rows);

  /// Builds a section from its rows, each paired with the hairline inset its
  /// own content wants (e.g. [GroupedListTile.insetIconLeading] for a row
  /// with a leading icon). Wraps every row in a [GroupedListTile] whose
  /// slice position comes from how many rows are passed here - after the
  /// caller's own conditionals - so a row hidden this build never leaves a
  /// square corner on the one that ends up last.
  factory SettingsSection.of(String title, List<(Widget, double)> rows) {
    return SettingsSection(title, [
      for (var i = 0; i < rows.length; i++)
        GroupedListTile(
          position: SlicePosition.forIndex(i, rows.length),
          hairlineInset: rows[i].$2,
          child: rows[i].$1,
        ),
    ]);
  }

  final String title;
  final List<Widget> rows;
}
