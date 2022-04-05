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
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/widgets/device_page.dart';
import 'package:mobile_app/widgets/util/favorize_button.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';

class GroupListItem extends StatelessWidget {
  final int _stateGroupIndex;
  final FutureOr<dynamic> Function(dynamic)? _poppedCallback;

  const GroupListItem(this._stateGroupIndex, this._poppedCallback, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      return ListTile(
          title: Text(state.deviceGroups[_stateGroupIndex].name),
          subtitle: Text(state.deviceGroups[_stateGroupIndex].device_ids.length.toString() +
              " Device" +
              (state.deviceGroups[_stateGroupIndex].device_ids.length > 1 || state.deviceGroups[_stateGroupIndex].device_ids.isEmpty ? "s" : "")),
          leading: Container(
            height: MediaQuery.of(context).textScaleFactor * 48,
            width: MediaQuery.of(context).textScaleFactor * 48,
            decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
            child: Padding(
                padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
                child: state.deviceGroups[_stateGroupIndex].imageWidget ?? const Icon(Icons.devices_other, color: Colors.white)),
          ),
          trailing: FavorizeButton(null, _stateGroupIndex),
          onTap: () {
            state.searchDevices(DeviceSearchFilter("", null, null, null, [state.deviceGroups[_stateGroupIndex].id]), context);
            final future = Navigator.push(
                context,
                platformPageRoute(
                  context: context,
                  builder: (context) {
                    final target = DevicePage(null, _stateGroupIndex);
                    target.refresh(context, state);
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
