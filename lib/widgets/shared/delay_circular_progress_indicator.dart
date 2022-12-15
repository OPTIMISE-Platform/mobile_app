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

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

class DelayedCircularProgressIndicator extends StatefulWidget {
  const DelayedCircularProgressIndicator({super.key});

  @override
  State<StatefulWidget> createState() => _DelayedCircularProgressIndicatorState();
}

class _DelayedCircularProgressIndicatorState extends State<DelayedCircularProgressIndicator> {
  bool _show = false;
  Future? _f;

  @override
  void initState() {
    super.initState();
    _f = Future.delayed(const Duration(milliseconds: 200)).then((_) => setState(() => _show=true));
  }

  @override
  void dispose() {
    super.dispose();
    _f?.ignore();
  }

  @override
  Widget build(BuildContext context) => _show ? PlatformCircularProgressIndicator() : const SizedBox.shrink();
}
