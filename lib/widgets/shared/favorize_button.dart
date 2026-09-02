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
import 'package:mutex/mutex.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/theme.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/toast.dart';

import 'package:mobile_app/shared/isar.dart';

class FavorizeButton extends StatelessWidget {
  final DeviceInstance? _device;
  final DeviceGroup? _group;

  FavorizeButton(this._device, this._group, {super.key}) {
    if ((_device == null && _group == null) ||
        (_device != null && _group != null)) {
      throw ArgumentException("Must set ONE of device or group");
    }
  }

  bool get _border {
    return !(MyTheme.isDarkMode && MyTheme.currentTheme == themeMaterial);
  }

  // One shared id list per kind, so an unsynchronised read-modify-write would
  // drop a toggle whose write overlaps the next one. Static because the widget
  // instance is recreated on every rebuild.
  static final _m = Mutex();

  click() async {
    if (Settings.getAccount() == null) {
      // The lists are keyed by account; without one the toggle would light the
      // star up and be gone again on the next fetch.
      Toast.showToastNoContext("Could not save favorite");
      return;
    }
    await _m.protect(() async {
      // The id list is what a favorite actually is; the flag on the cached row
      // is only the mirror the Isar favorites query filters on. The next state
      // comes from that mirror, because it is what build() drew and therefore
      // what the tap was aimed at - the two can disagree while a cache from a
      // previous account is still around.
      if (_device != null) {
        final next = !_device.favorite;
        final ids = Settings.getFavoriteDeviceIds();
        if (next) {
          ids.add(_device.id);
        } else {
          ids.remove(_device.id);
        }
        await Settings.setFavoriteDeviceIds(ids);
        _device.favorite = next;
        await isar?.writeTxn(() async {
          await isar!.deviceInstances.put(_device);
        });
        _device.notifyStateChanged();
      } else {
        final next = !_group!.favorite;
        final ids = Settings.getFavoriteGroupIds();
        if (next) {
          ids.add(_group.id);
        } else {
          ids.remove(_group.id);
        }
        await Settings.setFavoriteGroupIds(ids);
        _group.favorite = next;
        await isar?.writeTxn(() async {
          await isar!.deviceGroups.put(_group);
        });
        _group.notifyStateChanged();
      }
    });
    // Favorite membership is structural for the favorites screen, so also
    // signal AppState. Favorite toggles are rare (a user tap), not a hot path.
    AppState().notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: _device?.stateNotifier ?? _group!.stateNotifier,
        builder: (context, child) {
      final disabled = _device != null
          ? !DevicesService.isSaveAvailable()
          : !DeviceGroupsService.isCreateEditDeleteAvailable();
      final List<Widget> children = [];
      if (_device != null ? _device.favorite : _group!.favorite) {
        children.add(Icon(
          Icons.star,
          color: disabled ? Theme.of(context).disabledColor : Colors.yellow,
          size: _border && !disabled
              ? MediaQuery.textScaleFactorOf(context) * 15
              : null,
        ));
      }
      if ((_device != null ? !_device.favorite : !_group!.favorite) ||
          (_border && !disabled)) {
        children.add(Icon(Icons.star_border,
            color: disabled ? Theme.of(context).disabledColor : Colors.grey));
      }
      return IconButton(
          icon: Stack(
            alignment: AlignmentDirectional.center,
            children: children,
          ),
          onPressed: disabled ? null : click);
    });
  }
}
