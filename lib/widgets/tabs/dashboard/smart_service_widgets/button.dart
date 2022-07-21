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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/material_icons.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';

import '../../../../theme.dart';

class SmSeButton extends SmartServiceModuleWidget {
  _DataModel? data;
  bool _inDetailView = false;

  @override
  int height = 1;

  @override
  int width = 1;

  @override
  Widget build(BuildContext context, bool onlyPreview) {
    if (_inDetailView) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: data!.detail_widgets!.map((e) => e?.build(context, onlyPreview) ?? const SizedBox.shrink()).toList()),
        onTap: !onlyPreview && data?.detail_widgets != null && data!.detail_widgets!.isNotEmpty
            ? () {
                _inDetailView = false;
                height = 1;
                redrawDashboard(context);
              }
            : null,
      );
    }
    List<Widget> elems = [];
    if (data?.prefix != null) {
      elems.add(Text(data!.prefix!));
    }

    elems.add(IconButton(
      iconSize: 42,
      icon: Icon(IconData(iconNameToCodePoints[data?.icon] ?? 0xe237, fontFamily: 'MaterialIcons')),
      onPressed: onlyPreview ? null : () async => data?.request.perform(),
    ));
    if (data?.suffix != null) {
      elems.add(Text(data!.suffix!));
    }
    return Container(
        padding: const EdgeInsets.only(left: MyTheme.insetSize, right: MyTheme.insetSize),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: elems),
          onTap: !onlyPreview && data?.detail_widgets != null && data!.detail_widgets!.isNotEmpty
              ? () {
                  _inDetailView = true;
                  height = data!.detail_widgets!.map((e) => e?.height ?? 0).reduce((e1, e2) => e1 + e2);
                  redrawDashboard(context);
                }
              : null,
        ));
  }

  @override
  void configure(data) {
    this.data = _DataModel.fromJson(id, data);
  }

  @override
  Future<void> refresh() async {
    return;
  }
}

class _DataModel {
  String? prefix, suffix;
  String icon;
  Request request;
  List<SmartServiceModuleWidget?>? detail_widgets;

  _DataModel(this.prefix, this.suffix, this.icon, this.request, this.detail_widgets);

  factory _DataModel.fromJson(String parentId, Map<String, dynamic> json) {
    List<SmartServiceModuleWidget?> detail_widgets = [];
    if (json["detail_widgets"] is List<dynamic>) {
      (json["detail_widgets"] as List<dynamic>).asMap().forEach((key, value) {
        detail_widgets
            .add(SmartServiceModuleWidget.fromWidgetInfo(parentId + "_" + key.toString(), WidgetInfo.fromJson(value as Map<String, dynamic>)));
      });
      detail_widgets = detail_widgets.where((e) => e != null).toList();
    }

    return _DataModel(json["prefix"] as String?, json["suffix"] as String?, json["icon"] as String,
        Request.fromJson(json["request"] as Map<String, dynamic>), detail_widgets);
  }
}
