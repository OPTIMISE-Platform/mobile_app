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
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: _group.stateNotifier,
        builder: (context, child) {
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
              subtitle: Text(devicesLabel(AppState().visibleDeviceCount(_group.device_ids))),
              leading: EntityLeadingIcon(
                  size: 40,
                  fallbackIcon: Icons.devices_other,
                  image: _group.imageWidget),
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
