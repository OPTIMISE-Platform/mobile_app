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
    // Guarded rather than cancelled: ignore() below only suppresses error
    // reporting, it does not stop the callback. This widget is shown while
    // something loads, so a load that finishes inside the delay disposes it
    // before the timer fires - which used to be a setState after dispose.
    _f = Future.delayed(const Duration(milliseconds: 200)).then((_) {
      if (!mounted) return;
      setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _f?.ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _show ? const CircularProgressIndicator.adaptive() : const SizedBox.shrink();
}
