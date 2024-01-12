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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/widgets/shared/favorize_button.dart';

class GroupListItem extends StatelessWidget {
  final DeviceGroup _group;
  final FutureOr<dynamic> Function(dynamic)? _poppedCallback;

  const GroupListItem(this._group, this._poppedCallback, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      return ListTile(
          title: SizedBox(
              width: MediaQuery.of(context).size.width - 192,
              child: Text(_group.name),
          ),
          subtitle: Text("${_group.device_ids.length} Device${_group.device_ids.length > 1 || _group.device_ids.isEmpty ? "s" : ""}"),
          /*
          trailing: Container(
            height: MediaQuery.of(context).textScaleFactor * 48,
            width: MediaQuery.of(context).textScaleFactor * 48,
            decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
            child: Padding(
                padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
                child: state.deviceGroups[_stateGroupIndex].imageWidget ?? const Icon(Icons.devices_other, color: Colors.white)),
          ),
           */
          leading: FavorizeButton(null, _group),
          onTap: () {
            state.searchDevices(DeviceSearchFilter("", null, null, null, [_group.id]), context);
            final future = Navigator.push(
                context,
                platformPageRoute(
                  context: context,
                  builder: (context) {
                    final target = DetailPage(null, _group);
                    return target;
                  },
                ));
            if (_poppedCallback != null) {
              future.then(_poppedCallback!);
            }
          });
    });
  }
}
