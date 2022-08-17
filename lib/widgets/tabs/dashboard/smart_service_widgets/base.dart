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

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/column.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/flip.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/icon.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/line_chart.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/request_icon.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/row.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/single_value.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/text.dart';
import 'package:mutex/mutex.dart';

import '../../../../models/smart_service.dart';
import '../dashboard.dart';
import 'button.dart';

typedef SmSeWidgetType = String;

// DEFINE NEW WIDGET TYPES BELOW
const SmSeWidgetType smSeTextType = "text";
const SmSeWidgetType smSeButtonType = "button";
const SmSeWidgetType smSeFlipType = "flip";
const SmSeWidgetType smSeRowType = "row";
const SmSeWidgetType smSeColumnType = "column";
const SmSeWidgetType smSeIconType = "icon";
const SmSeWidgetType smSeSingleValueType = "single_value";
const SmSeWidgetType smSeRequestIconType = "request_icon";
const SmSeWidgetType smSeLineChartType = "line_chart";

/// EXTEND THIS CLASS TO ADD NEW WIDGETS
abstract class SmartServiceModuleWidget {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  double get height;

  /// Currently without effect
  double get width;

  late WidgetInfo widgetInfo;
  late String instance_id;

  void configure(dynamic data);

  @nonVirtual
  Widget build(BuildContext context, bool onlyPreview) => SizedBox(
      height: height * heightUnit,
      child: _refreshing.isLocked ? Center(child: PlatformCircularProgressIndicator()) : buildInternal(context, onlyPreview, false));

  @protected
  Widget buildInternal(BuildContext context, bool onlyPreview, bool parentFlexible);

  late String id;

  final Mutex _refreshing = Mutex();

  @nonVirtual
  Future<void> refresh() async {
    await _refreshing.protect(refreshInternal);
  }

  @protected
  Future<void> refreshInternal() async {
    return;
  }

  static SmartServiceModuleWidget? fromModule(SmartServiceModule module) {
    if (module.module_type != smartServiceModuleTypeWidget) {
     _logger.w("wrong module type");
     return null;
    }
    if (module.module_data is! Map<String, dynamic>) {
      _logger.w("invalid module data");
      return null;
    }
    final data = module.module_data as Map<String, dynamic>;
    if (!data.containsKey("widget_type") || !data.containsKey("widget_data") || data["widget_type"] is! String) {
      _logger.w("invalid module data");
      return null;
    }
    final widgetInfo = WidgetInfo.fromJson(data);
    final id = widgetInfo.widget_key != null ?  (module.instance_id + "_" + widgetInfo.widget_key!) : module.id;
    final w = fromWidgetInfo(id, widgetInfo);
    if (w != null) {
      w.instance_id = module.instance_id;
    }
    return w;
  }

  static SmartServiceModuleWidget? fromWidgetInfo(String id, WidgetInfo data) {
    SmartServiceModuleWidget? w;

    switch (data.widget_type) {
      // ADD NEW WIDGETS BELOW
      case smSeTextType:
        w = SmSeText();
        break;
      case smSeButtonType:
        w = SmSeButton();
        break;
      case smSeFlipType:
        w = SmSeFlip();
        break;
      case smSeRowType:
        w = SmSeRow();
        break;
      case smSeColumnType:
        w = SmSeColumn();
        break;
      case smSeIconType:
        w = SmSeIcon();
        break;
      case smSeSingleValueType:
        w = SmSeSingleValue();
        break;
      case smSeRequestIconType:
        w = SmSeRequestIcon();
        break;
      case smSeLineChartType:
        w = SmSeLineChart();
        break;

      // ADD NEW WIDGETS ABOVE
      default:
        _logger.w("unimplemented widget type '" + data.widget_type + "'");
        return null;
    }
    w.id = id;
    w.widgetInfo = data;
    w.configure(data.widget_data);

    return w;
  }

  redrawDashboard(BuildContext context) {
    final state = (context.findAncestorStateOfType<State<Dashboard>>() as DashboardState?);
    if (state?.mounted == true) state!.setState(() {});
  }
}