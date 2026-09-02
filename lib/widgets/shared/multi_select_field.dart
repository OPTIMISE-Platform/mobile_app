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

/// Asks the user to tick any number of [options].
///
/// Returns the selected entries, or null when cancelled — an empty list means
/// the user deliberately deselected everything.
Future<List<String>?> showMultiSelectDialog(
  BuildContext context, {
  required String title,
  required List<String> options,
  required List<String> selected,
}) =>
    showAdaptiveDialog<List<String>>(
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
  final List<String> options;
  final List<String> selected;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  // Owned by the State, not by the dialog builder closure: a route rebuild
  // (theme or text-scale change while the dialog is open) re-runs the builder
  // and would reset a selection held there.
  late final List<String> _current = widget.selected.toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: widget.options
              .map((option) => CheckboxListTile(
                    value: _current.contains(option),
                    title: Text(option),
                    onChanged: (checked) => setState(() => checked == true
                        ? _current.add(option)
                        : _current.remove(option)),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          child: Text("Cancel"),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () => Navigator.pop(context, _current),
        ),
      ],
    );
  }
}

/// Form-field-shaped control that opens [showMultiSelectDialog] and reports the
/// selected labels. [onChanged] only fires when the selection actually changed.
class MultiSelectField extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.options,
    required this.selected,
    required this.emptyLabel,
    required this.onChanged,
  });

  final List<String> options;
  final List<String> selected;

  /// Shown while nothing is selected, and used as the dialog title.
  final String emptyLabel;

  final ValueChanged<List<String>> onChanged;

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
          selected.isEmpty ? emptyLabel : selected.join(", "),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
