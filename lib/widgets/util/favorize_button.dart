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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/theme.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../exceptions/argument_exception.dart';
import '../../services/devices.dart';

class FavorizeButton extends StatelessWidget {
  final int? _stateDeviceIndex;
  final int? _stateDeviceGroupIndex;

  FavorizeButton(this._stateDeviceIndex, this._stateDeviceGroupIndex, {Key? key}) : super(key: key) {
    if ((_stateDeviceIndex == null && _stateDeviceGroupIndex == null) || (_stateDeviceIndex != null && _stateDeviceGroupIndex != null)) {
      throw ArgumentException("Must set ONE of _stateDeviceIndex or _stateDeviceGroupIndex");
    }
  }

  bool get _border {
    return !(MyTheme.isDarkMode && MyTheme.currentTheme == themeMaterial);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, widget) {
      final List<Widget> children = [];
      if (_stateDeviceIndex != null ? state.devices[_stateDeviceIndex!].favorite : state.deviceGroups[_stateDeviceGroupIndex!].favorite) {
        children.add(Icon(
          Icons.star,
          color: Colors.yellow,
          size: _border ? MediaQuery.textScaleFactorOf(context) * 15 : null,
        ));
      }
      if ((_stateDeviceIndex != null ? !state.devices[_stateDeviceIndex!].favorite : !state.deviceGroups[_stateDeviceGroupIndex!].favorite) ||
          _border) {
        children.add(const Icon(Icons.star_border, color: Colors.grey));
      }
      return PlatformIconButton(
        cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        icon: Stack(
          alignment: AlignmentDirectional.center,
          children: children,
        ),
        onPressed: () async {
          if (_stateDeviceIndex != null) {
            state.devices[_stateDeviceIndex!].toggleFavorite();
            await DevicesService.saveDevice(state.devices[_stateDeviceIndex!]);
          } else {
            state.deviceGroups[_stateDeviceGroupIndex!].toggleFavorite();
            state.deviceGroups[_stateDeviceGroupIndex!] = await DeviceGroupsService.saveDeviceGroup(state.deviceGroups[_stateDeviceGroupIndex!]);
          }
          state.notifyListeners();
        },
      );
    });
  }
}
