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
import 'package:mobile_app/widgets/tabs/sensors/sensor_icons.dart';

/// The name and icon the user confirmed in a [showNameIconDialog].
class NameIconResult {
  final String name;
  final String? iconName;

  /// The second line, empty when it should fall back to its default. Only
  /// meaningful when the dialog was opened with `withSubtitle`.
  final String subtitle;

  /// Whether the second line should be left off entirely.
  final bool subtitleHidden;

  const NameIconResult(
    this.name,
    this.iconName, {
    this.subtitle = '',
    this.subtitleHidden = false,
  });
}

/// Asks for a name and an optional Material icon, plus an optional second line.
///
/// Used both for sensor tabs (name required) and for a card's title (name
/// optional — empty clears it and falls back to the function name). With
/// [withSubtitle] the card's second line can be retyped or switched off.
/// Returns null when cancelled.
Future<NameIconResult?> showNameIconDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String? initialIconName,
  String nameHint = 'Name',
  bool nameRequired = true,
  String confirmLabel = 'Save',
  bool withSubtitle = false,
  String initialSubtitle = '',
  String subtitleHint = 'Subtitle',
  bool initialSubtitleHidden = false,
}) => showAdaptiveDialog<NameIconResult>(
  context: context,
  builder: (_) => _NameIconDialog(
    title: title,
    initialName: initialName,
    initialIconName: initialIconName,
    nameHint: nameHint,
    nameRequired: nameRequired,
    confirmLabel: confirmLabel,
    withSubtitle: withSubtitle,
    initialSubtitle: initialSubtitle,
    subtitleHint: subtitleHint,
    initialSubtitleHidden: initialSubtitleHidden,
  ),
);

class _NameIconDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String? initialIconName;
  final String nameHint;
  final bool nameRequired;
  final String confirmLabel;
  final bool withSubtitle;
  final String initialSubtitle;
  final String subtitleHint;
  final bool initialSubtitleHidden;

  const _NameIconDialog({
    required this.title,
    required this.initialName,
    required this.initialIconName,
    required this.nameHint,
    required this.nameRequired,
    required this.confirmLabel,
    required this.withSubtitle,
    required this.initialSubtitle,
    required this.subtitleHint,
    required this.initialSubtitleHidden,
  });

  @override
  State<_NameIconDialog> createState() => _NameIconDialogState();
}

class _NameIconDialogState extends State<_NameIconDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _subtitleController = TextEditingController(
    text: widget.initialSubtitle,
  );
  late String? _iconName = widget.initialIconName;
  late bool _subtitleHidden = widget.initialSubtitleHidden;
  bool _empty = false;

  @override
  void initState() {
    super.initState();
    _empty = widget.initialName.isEmpty;
    _controller.addListener(() {
      final empty = _controller.text.trim().isEmpty;
      if (empty != _empty) setState(() => _empty = empty);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  Widget _buildCaption(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: Theme.of(context).textTheme.labelMedium),
  );

  Future<void> _chooseIcon() async {
    final picked = await pickIcon(context, current: _iconName);
    if (picked == null || !mounted) return;
    setState(() => _iconName = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final icon = sensorIcon(_iconName);
    return AlertDialog.adaptive(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Two bare fields would be indistinguishable, so they get captions
            // as soon as there is more than one.
            if (widget.withSubtitle) _buildCaption('Title'),
            TextFormField(
              controller: _controller,
              decoration: InputDecoration(hintText: widget.nameHint),
              autofocus: true,
            ),
            if (widget.withSubtitle) ...[
              const SizedBox(height: 10),
              _buildCaption('Subtitle'),
              // Greyed out rather than removed while switched off, so it stays
              // visible what would come back.
              Opacity(
                opacity: _subtitleHidden ? 0.4 : 1,
                child: TextFormField(
                  controller: _subtitleController,
                  decoration: InputDecoration(hintText: widget.subtitleHint),
                  enabled: !_subtitleHidden,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(child: Text('Show on card')),
                  Switch.adaptive(
                    value: !_subtitleHidden,
                    onChanged: (show) =>
                        setState(() => _subtitleHidden = !show),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon ?? Icons.image_not_supported_outlined),
                TextButton(
                  onPressed: _chooseIcon,
                  child: Text(icon == null ? 'Choose icon' : 'Change icon'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          onPressed: widget.nameRequired && _empty
              ? null
              : () => Navigator.pop(
                  context,
                  NameIconResult(
                    _controller.text.trim(),
                    _iconName,
                    subtitle: _subtitleController.text.trim(),
                    subtitleHidden: _subtitleHidden,
                  ),
                ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
