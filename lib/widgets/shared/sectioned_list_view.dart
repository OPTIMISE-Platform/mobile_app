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
import 'package:mobile_app/widgets/shared/section_list_header.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

/// Builds one row of a [ListSection] at its slice [position].
typedef SectionRowBuilder<T> = Widget Function(
    BuildContext context, T item, SlicePosition position);

/// Rows of a [SectionedListView] that share one surface, optionally under a
/// [SectionListHeader].
class ListSection<T> {
  const ListSection({
    required this.id,
    required this.items,
    required this.keyOf,
    required this.itemBuilder,
    this.title,
  });

  /// Prefixes every row key of this section. Must be unique among the
  /// sections and stable across builds - not the title, which may come and
  /// go - so a row keeps its key when its header or an earlier section does.
  final String id;

  /// Header text; no header when null or when [items] is empty.
  final String? title;

  final List<T> items;

  /// The item's identity, unique within this section.
  final String Function(T item) keyOf;

  final SectionRowBuilder<T> itemBuilder;

  // Called through ListSection<Object?> by the list: methods, unlike a read of
  // keyOf or itemBuilder, get no covariance check against the caller's T.
  String _keyAt(int i) => keyOf(items[i]);

  Widget _buildAt(BuildContext context, int i, int count) =>
      itemBuilder(context, items[i], SlicePosition.forIndex(i, count));
}

/// A lazily built grouped list: [leading] widgets, then each non-empty
/// section (header, rows sliced into one surface), then [trailing] widgets.
///
/// Each row is keyed by its section's id and its item's key, and the list
/// maps those keys back to the current index, so a row's State follows its
/// item when rows, headers or sections before it appear or disappear.
/// [leading] and [trailing] stay unkeyed and are matched by position.
class SectionedListView extends StatelessWidget {
  const SectionedListView({
    required this.sections,
    this.leading = const [],
    this.trailing = const [],
    this.padding,
    this.physics,
    this.controller,
    super.key,
  });

  final List<ListSection<Object?>> sections;

  /// Above the first section, e.g. a detail page's header.
  final List<Widget> leading;

  /// Below the last section, e.g. FAB clearance or a loading row.
  final List<Widget> trailing;

  /// Defaults to [Spacing.listPadding].
  final EdgeInsetsGeometry? padding;

  final ScrollPhysics? physics;

  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final layout = _Layout(sections, leading.length);
    assert(layout.debugCheckUniqueKeys());
    final sectionsEnd = layout.end;
    // Built on first use per build: the list asks only while rows are keyed
    // and on screen, and the map is valid for this build's layout only.
    Map<(String, String), int>? indexByKey;

    return ListView.builder(
      controller: controller,
      physics: physics,
      padding: padding ?? Spacing.listPadding(context),
      itemCount: sectionsEnd + trailing.length,
      itemBuilder: (context, i) {
        if (i < leading.length) return leading[i];
        if (i >= sectionsEnd) return trailing[i - sectionsEnd];
        return layout.build(context, i);
      },
      findChildIndexCallback: (key) {
        if (key is! ValueKey<(String, String)>) return null;
        return (indexByKey ??= layout.indexByKey())[key.value];
      },
    );
  }
}

class _Placed {
  _Placed(this.section, this.start, this.count)
      : hasHeader = section.title != null;

  final ListSection<Object?> section;

  /// List index of this section's header, or of its first row without one.
  final int start;

  /// Rows as of this build, so positions and index ranges agree even if the
  /// caller's list changes before a row is built lazily.
  final int count;

  final bool hasHeader;

  int get firstRow => start + (hasHeader ? 1 : 0);

  int get end => firstRow + count;
}

class _Layout {
  _Layout(this.sections, int offset) {
    var index = offset;
    for (final section in sections) {
      final count = section.items.length;
      if (count == 0) continue;
      final p = _Placed(section, index, count);
      placed.add(p);
      index = p.end;
    }
    end = index;
  }

  final List<ListSection<Object?>> sections;
  final List<_Placed> placed = [];
  late final int end;

  Widget build(BuildContext context, int i) {
    for (final p in placed) {
      if (i >= p.end) continue;
      if (p.hasHeader && i == p.start) return SectionListHeader(p.section.title!);
      final row = i - p.firstRow;
      return KeyedSubtree(
        key: ValueKey((p.section.id, p.section._keyAt(row))),
        child: p.section._buildAt(context, row, p.count),
      );
    }
    throw RangeError.range(i, 0, end - 1, "index");
  }

  Map<(String, String), int> indexByKey() => {
        for (final p in placed)
          for (var row = 0; row < p.count; row++)
            (p.section.id, p.section._keyAt(row)): p.firstRow + row,
      };

  bool debugCheckUniqueKeys() {
    final ids = <String>{};
    for (final section in sections) {
      if (!ids.add(section.id)) {
        throw FlutterError(
            'SectionedListView: two sections share the id "${section.id}".');
      }
    }
    for (final p in placed) {
      final keys = <String>{};
      for (var row = 0; row < p.count; row++) {
        final key = p.section._keyAt(row);
        if (!keys.add(key)) {
          throw FlutterError('SectionedListView: section "${p.section.id}" '
              'has two rows keyed "$key". Rows are matched to their State by '
              'key, so a duplicate hands one row\'s State to the other.');
        }
      }
    }
    return true;
  }
}
