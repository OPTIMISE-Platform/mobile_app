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
              itemCount: _items.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  // ReorderableListView reports the target index before removal.
                  if (newIndex > oldIndex) newIndex -= 1;
                  _items.insert(newIndex, _items.removeAt(oldIndex));
                });
              },
              itemBuilder: (_, i) {
                final item = _items[i];
                final iconData = widget.icon?.call(item);
                final sub = widget.subtitle?.call(item);
                return ListTile(
                  // Keyed by item, not index — an index key would make the
                  // list rebuild in place and defeat the reorder animation.
                  key: ObjectKey(item),
                  leading: iconData == null ? null : Icon(iconData),
                  title: Text(widget.label(item)),
                  subtitle: (sub == null || sub.isEmpty) ? null : Text(sub),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                );
              },
            ),
    );
  }
}
