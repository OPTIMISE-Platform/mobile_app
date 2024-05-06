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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/theme.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/services/devices.dart';

import 'package:mobile_app/shared/isar.dart';

class FavorizeButton extends StatelessWidget {
  final DeviceInstance? _device;
  DeviceGroup? _group;

  FavorizeButton(this._device, this._group, {super.key}) {
    if ((_device == null && _group == null) ||
        (_device != null && _group != null)) {
      throw ArgumentException("Must set ONE of device or group");
    }
  }

  bool get _border {
    return !(MyTheme.isDarkMode && MyTheme.currentTheme == themeMaterial);
  }

  click() async {
    if (_device != null) {
        _device!.favorite = !_device!.favorite ;
        await isar?.writeTxn(() async {
          await isar!.deviceInstances.put(_device!);
        });
    } else {
      _group!.toggleFavorite();
      _group = await DeviceGroupsService.saveDeviceGroup(_group!);
    }
    AppState().notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, widget) {
      final disabled = _device != null
          ? !DevicesService.isSaveAvailable()
          : !DeviceGroupsService.isCreateEditDeleteAvailable();
      final List<Widget> children = [];
      if (_device != null ? _device!.favorite : _group!.favorite) {
        children.add(Icon(
          Icons.star,
          color: disabled ? Theme.of(context).disabledColor : Colors.yellow,
          size: _border && !disabled
              ? MediaQuery.textScaleFactorOf(context) * 15
              : null,
        ));
      }
      if ((_device != null ? !_device!.favorite : !_group!.favorite) ||
          (_border && !disabled)) {
        children.add(Icon(Icons.star_border,
            color: disabled ? Theme.of(context).disabledColor : Colors.grey));
      }
      return PlatformIconButton(
          cupertino: (_, __) =>
              CupertinoIconButtonData(padding: EdgeInsets.zero),
          icon: Stack(
            alignment: AlignmentDirectional.center,
            children: children,
          ),
          onPressed: disabled ? null : click);
    });
  }
}
