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
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';

/// One settings section: a title and the rows it currently shows, each paired
/// with the hairline inset its own content wants (e.g.
/// [GroupedListTile.insetIconLeading] for a row with a leading icon). A
/// section builder computes [rows] after its own conditionals (debug mode,
/// logged in, ...), and [toListSection] slices exactly those into a surface,
/// so a row hidden this build never leaves a square corner on the one that
/// ends up last.
class SettingsSection {
  const SettingsSection(this.title, this.rows);

  factory SettingsSection.of(String title, List<(Widget, double)> rows) =>
      SettingsSection(title, rows);

  final String title;
  final List<(Widget, double)> rows;

  /// Rows are keyed by their place in the section: they carry no identity of
  /// their own, and the section's title keeps them apart from other sections.
  ListSection<(int, (Widget, double))> toListSection() =>
      ListSection<(int, (Widget, double))>(
        id: title,
        title: title,
        items: rows.indexed.toList(growable: false),
        keyOf: (row) => "${row.$1}",
        itemBuilder: (_, row, position) => GroupedListTile(
          position: position,
          hairlineInset: row.$2.$2,
          child: row.$2.$1,
        ),
      );
}
