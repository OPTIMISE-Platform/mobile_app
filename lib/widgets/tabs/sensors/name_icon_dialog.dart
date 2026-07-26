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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_icons.dart';

/// The name and icon the user confirmed in a [showNameIconDialog].
class NameIconResult {
  final String name;
  final String? iconName;

  const NameIconResult(this.name, this.iconName);
}

/// Asks for a name and an optional Material icon.
///
/// Used both for sensor tabs (name required) and for a card's alias (name
/// optional — empty clears the alias). Returns null when cancelled.
Future<NameIconResult?> showNameIconDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String? initialIconName,
  String nameHint = 'Name',
  bool nameRequired = true,
  String confirmLabel = 'Save',
}) => showPlatformDialog<NameIconResult>(
  context: context,
  builder: (_) => _NameIconDialog(
    title: title,
    initialName: initialName,
    initialIconName: initialIconName,
    nameHint: nameHint,
    nameRequired: nameRequired,
    confirmLabel: confirmLabel,
  ),
);

class _NameIconDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String? initialIconName;
  final String nameHint;
  final bool nameRequired;
  final String confirmLabel;

  const _NameIconDialog({
    required this.title,
    required this.initialName,
    required this.initialIconName,
    required this.nameHint,
    required this.nameRequired,
    required this.confirmLabel,
  });

  @override
  State<_NameIconDialog> createState() => _NameIconDialogState();
}

class _NameIconDialogState extends State<_NameIconDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  late String? _iconName = widget.initialIconName;
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
    super.dispose();
  }

  Future<void> _chooseIcon() async {
    final picked = await pickIcon(context, current: _iconName);
    if (picked == null || !mounted) return;
    setState(() => _iconName = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final icon = sensorIcon(_iconName);
    return PlatformAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlatformTextFormField(
            controller: _controller,
            hintText: widget.nameHint,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon ?? Icons.image_not_supported_outlined),
              PlatformTextButton(
                onPressed: _chooseIcon,
                child: Text(icon == null ? 'Choose icon' : 'Change icon'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        PlatformDialogAction(
          child: PlatformText('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        PlatformDialogAction(
          onPressed: widget.nameRequired && _empty
              ? null
              : () => Navigator.pop(
                  context,
                  NameIconResult(_controller.text.trim(), _iconName),
                ),
          child: PlatformText(widget.confirmLabel),
        ),
      ],
    );
  }
}
