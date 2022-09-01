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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/icon.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';

class SmSeButton extends SmSeRequest {
  SmartServiceModuleWidget? child;

  @override
  double height = 2;

  @override
  double width = 1;

  @override
  Widget buildInternal(BuildContext context, bool onlyPreview, bool _) {
    final w = child?.buildInternal(context, onlyPreview, false) ?? const SizedBox.shrink();
    final onPressed = onlyPreview ? null : () async => await request.perform();

    return (child is SmSeIcon
        ? IconButton(icon: w, onPressed: onPressed)
        : TextButton(
            child: w,
            onPressed: onPressed,
          ));
  }

  @override
  Future<void> configure(data) async {
    super.configure(data);
    if (data is! Map<String, dynamic> || data["child"] == null) return;
    child = await SmartServiceModuleWidget.fromWidgetInfo("${id}_child", WidgetInfo.fromJson(data["child"]));
  }

  @override
  Future<void> refreshInternal() async {
    return await child?.refresh();
  }
}
