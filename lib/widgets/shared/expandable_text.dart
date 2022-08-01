/*
 * Copyright 2022 InfAI (CC SES)
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

import 'package:flutter/cupertino.dart';

class ExpandableText extends StatefulWidget {
  final String _text;
  final int _collapsed_lines;

  const ExpandableText(this._text, this._collapsed_lines, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;
  int _collapsed_lines = 1;
  String _text = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _text = widget._text;
        _collapsed_lines = widget._collapsed_lines;
      });
    });
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _text = widget._text;
          _collapsed_lines = widget._collapsed_lines;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: AnimatedSize(
          duration: const Duration(milliseconds: 75),
          child: Text(_text, maxLines: _expanded ? null : _collapsed_lines, overflow: TextOverflow.fade)),
      onTap: () => setState(() {
        _expanded = !_expanded;
      }),
    );
  }
}
