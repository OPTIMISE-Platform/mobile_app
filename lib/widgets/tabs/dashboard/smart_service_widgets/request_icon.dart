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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/material_icons.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';

class SmSeRequestIcon extends SmSeRequest {
  int codePoint = 0xe30b;

  @override
  double height = 1;

  @override
  double width = 1;

  @override
  Widget buildInternal(BuildContext context, bool _, bool __) {
    return Icon(IconData(codePoint, fontFamily: 'MaterialIcons'));
  }

  @override
  Future<void> refreshInternal() async {
    final resp = await request.perform();
    codePoint = iconNameToCodePoints[resp.body.endsWith("\n") ? resp.body.substring(0, resp.body.length - 1) : resp.body] ?? 0xe30b;
  }
}
