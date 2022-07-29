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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';

const Duration animationDuration = Duration(milliseconds: 100);

class SmSeFlip extends SmartServiceModuleWidget {
  SmartServiceModuleWidget? front;
  SmartServiceModuleWidget? back;

  bool _showFront = true;

  @override
  double get height => ((_showFront ? front?.height : back?.height) ?? 0) + 1;

  @override
  double get width => (_showFront ? front?.width : back?.width) ?? 0;

  @override
  Widget buildInternal(BuildContext context, bool onlyPreview, bool _) {
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: (_showFront ? front : back)?.buildInternal(context, onlyPreview, false),
        onTap: onlyPreview
            ? null
            : () async {
                _showFront = !_showFront;
                redrawDashboard(context);
                await refresh();
                redrawDashboard(context);
              });
  }

  @override
  void configure(data) {
    if (data is! Map<String, dynamic> || data["front"] == null || data["back"] == null) return;

    front = SmartServiceModuleWidget.fromWidgetInfo(id + "_front", WidgetInfo.fromJson(data["front"]));
    back = SmartServiceModuleWidget.fromWidgetInfo(id + "_back", WidgetInfo.fromJson(data["back"]));
  }

  @override
  Future<void> refreshInternal() async {
    return await (_showFront ? front?.refresh() : back?.refresh());
  }
}
