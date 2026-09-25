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
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

/// Drag-and-drop reordering of [items] on a dedicated page.
///
/// Returns the reordered list, or null if cancelled. A separate page (rather
/// than dragging the tab strip / value grid in place) keeps this dependency
/// free: Flutter ships reordering for lists, not for grids or chip rows.
Future<List<T>?> reorderItems<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T item) label,
  IconData? Function(T item)? icon,
  String Function(T item)? subtitle,
}) => Navigator.push<List<T>>(
  context,
  MaterialPageRoute(
    builder: (_) => _ReorderPage<T>(
      title: title,
      items: items,
      label: label,
      icon: icon,
      subtitle: subtitle,
    ),
  ),
);

class _ReorderPage<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T item) label;
  final IconData? Function(T item)? icon;
  final String Function(T item)? subtitle;

  const _ReorderPage({
    required this.title,
    required this.items,
    required this.label,
    this.icon,
    this.subtitle,
  });

  @override
  State<_ReorderPage<T>> createState() => _ReorderPageState<T>();
}

class _ReorderPageState<T> extends State<_ReorderPage<T>> {
  late final List<T> _items = [...widget.items];

  // theme.dart's CardThemeData - matches GroupedListTile's own corner radius,
  // so the dragged row's shadow follows the same rounded shape it draws in.
  static const _cardRadius = BorderRadius.all(Radius.circular(14));

  /// One row, keyed by item rather than index so an index key does not make
  /// the list rebuild in place and defeat the reorder animation. [position]
  /// is passed separately from the row's own index so the row being dragged
  /// can be forced to [SlicePosition.only] regardless of where it rests.
  /// [horizontalMargin] is 0 for the proxy decorator, which draws its own
  /// margin outside the elevated Material instead (see [_proxyDecorator]).
  Widget _buildRow(int i, SlicePosition position,
      {double horizontalMargin = Spacing.lg}) {
    final item = _items[i];
    final iconData = widget.icon?.call(item);
    final sub = widget.subtitle?.call(item);
    return GroupedListTile(
      key: ObjectKey(item),
      position: position,
      horizontalMargin: horizontalMargin,
      hairlineInset: iconData == null
          ? GroupedListTile.insetNoLeading
          : GroupedListTile.insetIconLeading,
      child: ListTile(
        leading: iconData == null ? null : Icon(iconData),
        title: Text(widget.label(item)),
        subtitle: (sub == null || sub.isEmpty) ? null : Text(sub),
        trailing: ReorderableDragStartListener(
          index: i,
          child: const Icon(Icons.drag_handle),
        ),
      ),
    );
  }

  /// The row being dragged detaches from its neighbours, so it always shows
  /// as a complete, fully rounded card - not whatever slice its resting
  /// position happens to be - with the lift/shadow Flutter's own default
  /// decorator would otherwise draw as a plain rectangle around it.
  ///
  /// The margin sits outside the elevated Material, not inside it: giving it
  /// to the row itself (like every resting row draws its own) would elevate
  /// the margin's width too, casting the shadow around a rectangle wider
  /// than - and offset from - the visible card.
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final elevation = Tween<double>(begin: 0, end: 6).evaluate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut));
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Material(
            elevation: elevation,
            color: Colors.transparent,
            shadowColor: Theme.of(context).shadowColor,
            borderRadius: _cardRadius,
            child: _buildRow(index, SlicePosition.only, horizontalMargin: 0),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _items),
            child: const Text('Done'),
          ),
        ],
      ),
      body: _items.length < 2
          ? const Center(child: Text('Nothing to reorder'))
          : ReorderableListView.builder(
              padding: Spacing.listPadding(context),
              itemCount: _items.length,
              proxyDecorator: _proxyDecorator,
              onReorderItem: (oldIndex, newIndex) {
                // Unlike onReorder, onReorderItem's newIndex is already
                // adjusted for the removal at oldIndex.
                setState(() {
                  _items.insert(newIndex, _items.removeAt(oldIndex));
                });
              },
              itemBuilder: (_, i) =>
                  _buildRow(i, SlicePosition.forIndex(i, _items.length)),
            ),
    );
  }
}
