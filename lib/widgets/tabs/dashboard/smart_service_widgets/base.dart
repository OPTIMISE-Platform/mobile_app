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

import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/example.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/text.dart';

import '../../../../exceptions/argument_exception.dart';
import '../../../../models/smart_service.dart';
import '../dashboard.dart';
import 'button.dart';

typedef SmSeWidgetType = String;

// DEFINE NEW WIDGET TYPES BELOW
const SmSeWidgetType SmSeExampleType = "example";
const SmSeWidgetType SmSeTextType = "text";
const SmSeWidgetType SmSeButtonType = "button";

/// EXTEND THIS CLASS TO ADD NEW WIDGETS
abstract class SmartServiceModuleWidget {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  abstract int height;

  /// Currently without effect
  abstract int width;

  void configure(dynamic data);

  Widget build(BuildContext context, bool onlyPreview);

  late String id;

  Future<void> refresh();

  static SmartServiceModuleWidget? fromModule(SmartServiceModule module) {
    if (module.module_type != smartServiceModuleTypeWidget) {
      throw ArgumentException("wrong module type");
    }
    if (module.module_data is! Map<String, dynamic>) {
      throw ArgumentException("invalid module data");
    }
    final data = module.module_data as Map<String, dynamic>;
    if (!data.containsKey("widget_type") || !data.containsKey("widget_data") || data["widget_type"] is! String) {
      throw ArgumentException("invalid module data");
    }
    return fromWidgetInfo(module.id, WidgetInfo(data["widget_type"], data["widget_data"]));
  }

  static SmartServiceModuleWidget? fromWidgetInfo(String id, WidgetInfo data) {
    SmartServiceModuleWidget? w;

    switch (data.widget_type) {
      // ADD NEW WIDGETS BELOW

      case SmSeExampleType:
        w = SmSeExample();
        break;
      case SmSeTextType:
        w = SmSeText();
        break;
      case SmSeButtonType:
        w = SmSeButton();
        break;

      // ADD NEW WIDGETS ABOVE
      default:
        _logger.e("unimplemented widget type " + data.widget_type);
        return null;
    }
    w.id = id;
    w.configure(data.widget_data);

    return w;
  }

  redrawDashboard(BuildContext context) {
    (context.findAncestorStateOfType<State<Dashboard>>() as DashboardState?)?.setState(() {});
  }
}
