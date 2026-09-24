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

class MultiSelectOption {
  const MultiSelectOption(this.label, {this.group});

  final String label;

  /// Options sharing a group are listed together under it as a header.
  final String? group;
}

/// Asks the user to tick any number of [options].
///
/// Selections are indices into [options], never labels: two options may carry
/// the same label, for example the same device offered in two groups.
/// Returns the selected indices, or null when cancelled — an empty list means
/// the user deliberately deselected everything.
Future<List<int>?> showMultiSelectDialog(
  BuildContext context, {
  required String title,
  required List<MultiSelectOption> options,
  required List<int> selected,
}) =>
    showAdaptiveDialog<List<int>>(
      context: context,
      builder: (_) =>
          _MultiSelectDialog(title: title, options: options, selected: selected),
    );

class _MultiSelectDialog extends StatefulWidget {
  const _MultiSelectDialog({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<MultiSelectOption> options;
  final List<int> selected;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  // Owned by the State, not by the dialog builder closure: a route rebuild
  // (theme or text-scale change while the dialog is open) re-runs the builder
  // and would reset a selection held there.
  late final List<int> _current = widget.selected.toList();

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final MapEntry(key: group, value: indices)
        in groupOptionIndices(widget.options).entries) {
      if (group != null) {
        children.add(ListTile(
          dense: true,
          title: Text(group, style: Theme.of(context).textTheme.titleSmall),
        ));
      }
      for (final i in indices) {
        children.add(CheckboxListTile(
          value: _current.contains(i),
          title: Text(widget.options[i].label),
          onChanged: (checked) => setState(
              () => checked == true ? _current.add(i) : _current.remove(i)),
        ));
      }
    }
    return AlertDialog.adaptive(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: children),
      ),
      actions: [
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: const Text("OK"),
          onPressed: () => Navigator.pop(context, _current),
        ),
      ],
    );
  }
}

/// Indices of [options] by group, groups in order of first appearance.
Map<String?, List<int>> groupOptionIndices(List<MultiSelectOption> options) {
  final groups = <String?, List<int>>{};
  for (var i = 0; i < options.length; i++) {
    groups.putIfAbsent(options[i].group, () => []).add(i);
  }
  return groups;
}

/// Form-field-shaped control that opens [showMultiSelectDialog] and reports the
/// selected indices. [onChanged] only fires when the selection actually changed.
class MultiSelectField extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.options,
    required this.selected,
    required this.emptyLabel,
    required this.onChanged,
  });

  final List<MultiSelectOption> options;
  final List<int> selected;

  /// Shown while nothing is selected, and used as the dialog title.
  final String emptyLabel;

  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final result = await showMultiSelectDialog(
          context,
          title: emptyLabel,
          options: options,
          selected: selected,
        );
        if (result == null) return;
        if (!context.mounted) return;
        // Unchanged selections must not trigger a rebuild of the host form.
        if (result.length == selected.length &&
            result.every(selected.contains)) {
          return;
        }
        onChanged(result);
      },
      child: InputDecorator(
        // isDense keeps the field inside the caller's row height at the
        // default text scale; the row itself may still grow when scaled up.
        decoration: const InputDecoration(isDense: true),
        child: Text(
          selected.isEmpty
              ? emptyLabel
              : selected.map((i) => options[i].label).join(", "),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
