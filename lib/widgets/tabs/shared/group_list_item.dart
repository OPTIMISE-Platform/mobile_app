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

import 'package:mobile_app/shared/devices_label.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_tile.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_labels.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';
import 'package:mobile_app/shared/unavailability.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/widgets/shared/entity_leading_icon.dart';
import 'package:mobile_app/widgets/shared/favorize_button.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

class GroupListItem extends StatelessWidget {
  final DeviceGroup _group;
  final FutureOr<dynamic> Function(dynamic)? _poppedCallback;
  final SlicePosition _position;

  const GroupListItem(this._group, this._poppedCallback,
      {required SlicePosition position, super.key})
      : _position = position;

  /// Same code path as [FavorizeButton] itself (the mutex, the persistence,
  /// the Isar mirror), invoked without building the button widget - the star
  /// in the title is a display-only indicator now, the row's long-press is
  /// what toggles it.
  Future<void> _toggleFavorite() async {
    if (!DeviceGroupsService.isCreateEditDeleteAvailable()) return; // matches the button's disabled state
    final willSave = Settings.getAccount() != null;
    final adding = !_group.favorite;
    await FavorizeButton(null, _group).click();
    if (!willSave) return;
    HapticFeedbackProxy.mediumImpact();
    Toast.showToastNoContext(adding ? "Added to favorites" : "Removed from favorites");
  }

  /// The reading the row switches and the control it switches through, or
  /// null when the row has no switch: the group is unavailable, or no single
  /// shown reading and control go with each other.
  ({DeviceState reading, DeviceState control})? _switchOf() {
    if (groupUnavailability(_group) != null) return null;
    final readings = _group.shownStates
        .where((s) => isSwitchableOnOff(s, _group.states, isGroup: true))
        .toList(growable: false);
    if (readings.length != 1) return null;
    final reading = readings.first;
    final control = resolveGroupControl(reading, _group.states,
        onOffTargetFunction(onOffReadingOf(reading.value)));
    if (control == null) return null;
    return (reading: reading, control: control);
  }

  /// The row's switch. Passive while a command runs, and for a reading that
  /// is unknown, which never switches.
  Widget _switchButton(BuildContext context, DeviceState reading, DeviceState control) {
    final textScaler = MediaQuery.textScalerOf(context);
    final Widget button;
    if (reading.transitioning || SwitchCommands.isRunning(reading)) {
      button = const Center(child: DelayedCircularProgressIndicator());
    } else if (onOffReadingOf(reading.value) == OnOffReading.unknown) {
      button = const Center(
          child: Tooltip(
              message: "Status unknown",
              triggerMode: TooltipTriggerMode.tap,
              child: Icon(Icons.remove)));
    } else {
      button = IconButton(
        splashRadius: 25,
        tooltip: toggleTooltipOf(reading, AppState().platformFunctions[control.functionId]?.display_name),
        icon: toggleIconOf(reading, context) ?? const Icon(Icons.help_outline),
        onPressed: () => SwitchCommands.run(
          reading,
          () => toggleThroughControl(
            measurement: reading,
            control: control,
            notifyEntity: _group.notifyStateChanged,
          ),
        ),
      );
    }
    return Container(
      width: textScaler.scale(50),
      margin: EdgeInsets.only(left: textScaler.scale(4)),
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: _group.stateNotifier,
        builder: (context, child) {
      final unavailability = groupUnavailability(_group);
      final switchOf = _switchOf();

      Widget subtitle = Text(devicesLabel(AppState().visibleDeviceCount(_group.device_ids)));
      if (unavailability != null) {
        // Wrap, not Row, for the same reason as the device row's subtitle.
        subtitle = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Spacing.xxs,
          runSpacing: 2,
          children: [
            subtitle,
            const Text("·"),
            const StatusChip("Not local"),
          ],
        );
      }

      return GroupedListTile(
          position: _position,
          hairlineInset: GroupedListTile.insetIconLeading40,
          child: ListTile(
              title: Text.rich(
                TextSpan(text: _group.name, children: [
                  if (_group.favorite)
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: EdgeInsets.only(left: Spacing.xxs),
                        child: Icon(Icons.star,
                            size: 16, color: Colors.yellow, semanticLabel: "Favorite"),
                      ),
                    ),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitle,
              leading: EntityLeadingIcon(
                  size: 40,
                  fallbackIcon: Icons.devices_other,
                  image: _group.imageWidget),
              trailing: switchOf == null
                  ? null
                  : _switchButton(context, switchOf.reading, switchOf.control),
              contentPadding: const EdgeInsets.only(left: Spacing.lg, right: Spacing.sm),
              horizontalTitleGap: Spacing.sm,
              onLongPress: _toggleFavorite,
              onTap: () {
                // The list this row sits in was searched with the parent
                // filter, so its toggle carries over to the group's members.
                AppState().searchDevices(
                    DeviceSearchFilter("",
                        deviceGroupIds: [_group.id],
                        showInactive: AppState().showsInactiveDevices));
                final future = Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) {
                        final target = DetailPage(null, _group);
                        return target;
                      },
                    ));
                if (_poppedCallback != null) {
                  future.then(_poppedCallback);
                }
              }));
    });
  }
}
