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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/material_icons.dart';

/// Resolves a stored Material icon name to an [IconData].
///
/// Icons are persisted by name and built at runtime from the code point, the
/// same approach the smart-service icon widgets use. This relies on the app
/// being built with `--no-tree-shake-icons` (as CI does), because the glyphs
/// aren't statically referenced anywhere.
IconData? sensorIcon(String? iconName) {
  if (iconName == null) return null;
  final codePoint = iconNameToCodePoints[iconName];
  if (codePoint == null) return null;
  return IconData(codePoint, fontFamily: 'MaterialIcons');
}

/// Icon names without the style suffixes, so the unfiltered picker shows one
/// entry per icon instead of four near-identical ones.
final List<String> _baseIconNames = () {
  const suffixes = ['_sharp', '_rounded', '_outlined'];
  final names =
      iconNameToCodePoints.keys.where((n) => !suffixes.any(n.endsWith)).toList()
        ..sort();
  return names;
}();

final List<String> _allIconNames = iconNameToCodePoints.keys.toList()..sort();

/// Lets the user pick a Material icon.
///
/// Returns the chosen icon name, an empty string when the icon was cleared, or
/// null when cancelled.
Future<String?> pickIcon(BuildContext context, {String? current}) =>
    Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _IconPicker(current: current),
      ),
    );

class _IconPicker extends StatefulWidget {
  final String? current;

  const _IconPicker({this.current});

  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _results {
    final query = _query.trim().toLowerCase().replaceAll(' ', '_');
    if (query.isEmpty) return _baseIconNames;
    // Search the full set so style variants stay reachable by name.
    return _allIconNames.where((n) => n.contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Icon'),
        actions: [
          if (widget.current != null)
            TextButton(
              onPressed: () => Navigator.pop(context, ''), // clear
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: MyTheme.inset,
            child: TextFormField(
              controller: _searchController,
              decoration: InputDecoration(hintText: 'Search icons'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('No icons found'))
                : Scrollbar(
                    child: GridView.builder(
                      padding: MyTheme.inset,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final name = results[i];
                        final selected = name == widget.current;
                        return InkWell(
                          onTap: () => Navigator.pop(context, name),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: selected
                                  ? Border.all(
                                      color: MyTheme.appColor,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: Tooltip(
                              message: name,
                              child: Icon(sensorIcon(name)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
