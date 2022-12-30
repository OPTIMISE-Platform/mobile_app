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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/row.dart';

class SmSeColumn extends SmSeRow {
  @override
  double get height => children.map((e) => e?.height ?? 0).reduce((a, b) => a + b) + 1;

  @override
  double get width => children.map((e) => e?.width ?? 0).reduce((a, b) => a > b ? a : b) + 1;

  @override
  Widget buildInternal(BuildContext context, bool _) {
    children.forEach((e) => e?.setPreview(preview));
    return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: children.map((e) => e?.buildInternal(context, true) ?? const SizedBox.shrink()).toList());
  }
}
