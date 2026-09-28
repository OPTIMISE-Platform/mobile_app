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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/entity_leading_icon.dart';
import 'package:mobile_app/widgets/shared/favorize_button.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

class DeviceListItem extends StatefulWidget {
  final DeviceInstance _device;
  final FutureOr<dynamic> Function(dynamic)? _poppedCallback;
  final SlicePosition _position;

  /// The location page's own location, omitted from the subtitle there - a
  /// row would otherwise repeat the location the whole page is already
  /// filtered to.
  final String? _currentLocationId;

  const DeviceListItem(this._device, this._poppedCallback,
      {required SlicePosition position, String? currentLocationId, super.key})
      : _position = position,
        _currentLocationId = currentLocationId;

  @override
  State<StatefulWidget> createState() => _DeviceListItemState();
}

class _DeviceListItemState extends State<DeviceListItem> {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  // Lives on the State, where it survives widget rebuilds by itself. On the
  // widget it needed a didUpdateWidget copy to carry it across, and made the
  // widget mutable.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: widget._device.stateNotifier,
        builder: (context, child) {
      final device = widget._device;
      final List<Widget> trailingWidgets = [];
      final filteredStates = device.states.where((element) =>
          !element.isControlling &&
          element.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE']);
      filteredStates.forEach((element) {
        trailingWidgets.add(Container(
          width: MediaQuery.textScalerOf(context).scale(50),
          margin:
              EdgeInsets.only(left: MediaQuery.textScalerOf(context).scale(4)),
          child: element.transitioning
              ? const Center(child: DelayedCircularProgressIndicator())
              : element.value == null
                  ? const Center(
                      child: Tooltip(
                          message: "Status unknown",
                          triggerMode: TooltipTriggerMode.tap,
                          child: Icon(
                            Icons.remove,
                          )))
                  : IconButton(
                      splashRadius: 25,
                      tooltip: AppState()
                          .platformFunctions[functionConfigs[
                                  dotenv.env['FUNCTION_GET_ON_OFF_STATE']]
                              ?.getRelatedControllingFunction(element.value)]
                          ?.display_name,
                      icon: functionConfigs[
                                  dotenv.env['FUNCTION_GET_ON_OFF_STATE']]
                              ?.displayValue(element.value, context) ??
                          const Icon(Icons.help_outline),
                      onPressed: device.connection_state ==
                              DeviceConnectionStatus.offline
                          ? null
                          : () async {
                              if (device.connection_state ==
                                  DeviceConnectionStatus.offline) {
                                Toast.showToastNoContext("Device is offline");
                                return;
                              }
                              if (element.transitioning) {
                                return; // avoid double presses
                              }
                              final controllingFunction = functionConfigs[
                                      dotenv.env['FUNCTION_GET_ON_OFF_STATE']]
                                  ?.getRelatedControllingFunction(
                                      element.value);
                              if (controllingFunction == null) {
                                const err =
                                    "Could not find related controlling function";
                                Toast.showToastNoContext(err);
                                _logger.e(err);
                                return;
                              }
                              final controllingStates = device.states.where(
                                  (state) =>
                                      state.isControlling &&
                                      state.functionId == controllingFunction &&
                                      state.serviceGroupKey ==
                                          element.serviceGroupKey &&
                                      state.aspectId == element.aspectId);
                              if (controllingStates.isEmpty) {
                                const err =
                                    "Found no controlling service, check device type!";
                                Toast.showToastNoContext(err);
                                _logger.e(err);
                                return;
                              }
                              if (controllingStates.length > 1) {
                                const err =
                                    "Found more than one controlling service, check device type!";
                                Toast.showToastNoContext(err);
                                _logger.e(err);
                                return;
                              }
                              element.transitioning = true;
                              widget._device.notifyStateChanged();
                              final List<DeviceCommandResponse> responses = [];
                              if (!await DeviceCommandsService
                                  .runCommandsSecurely(
                                      [controllingStates.first.toCommand()],
                                      responses)) {
                                element.transitioning = false;
                                widget._device.notifyStateChanged();
                                return;
                              }
                              assert(responses.length == 1);
                              if (responses[0].status_code != 200) {
                                final err =
                                    "Error running command: ${responses[0].message}";
                                Toast.showToastNoContext(err);
                                _logger.e(err);
                                return;
                              }
                              responses.clear();
                              if (!await DeviceCommandsService
                                  .runCommandsSecurely(
                                      [element.toCommand()],
                                      responses,
                                      false)) {
                                element.transitioning = false;
                                widget._device.notifyStateChanged();
                                return;
                              }
                              assert(responses.length == 1);
                              if (responses[0].status_code != 200) {
                                final err =
                                    "Error running command: ${responses[0].message}";
                                Toast.showToastNoContext(err);
                                element.transitioning = false;
                                widget._device.notifyStateChanged();
                                _logger.e(err);
                                return;
                              }
                              element.value = responses[0].message[0];
                              element.transitioning = false;
                              widget._device.notifyStateChanged();
                            },
                    ),
        ));
      });

      final connectionStatus = device.connection_state;
      final unavailable = connectionStatus == DeviceConnectionStatus.offline ||
          device.network?.localGatewayHosts?.isNotEmpty != true && Settings.getLocalMode();

      final deviceType = AppState().deviceTypes[device.device_type_id];
      final deviceClass = deviceType == null
          ? null
          : AppState().deviceClasses[deviceType.device_class_id];

      final locationNames = AppState()
          .locationsForDevice(device.id)
          .where((l) => l.id != widget._currentLocationId)
          .map((l) => l.name)
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final statusChipLabel = !unavailable
          ? null
          : connectionStatus == DeviceConnectionStatus.offline
              ? "Offline"
              : "Not local";
      Widget? subtitle;
      if (locationNames.isNotEmpty || statusChipLabel != null) {
        // Wrap, not Row: at a narrow width and a large text scale, a location
        // name plus the chip no longer fit on one line - this drops to a
        // second line instead of overflowing.
        subtitle = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Spacing.xxs,
          runSpacing: 2,
          children: [
            if (locationNames.isNotEmpty) Text(locationNames.join(", ")),
            if (locationNames.isNotEmpty && statusChipLabel != null)
              const Text("·"),
            if (statusChipLabel != null) _StatusChip(statusChipLabel),
          ],
        );
      }

      Widget? trailingContent;
      if (!unavailable) {
        if (trailingWidgets.length == 1) {
          trailingContent = trailingWidgets[0];
        } else if (trailingWidgets.isNotEmpty) {
          trailingContent = IconButton(
              splashRadius: 25,
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _expanded = !_expanded));
        }
      }

      final List<Widget> columnWidgets = [];
      columnWidgets.add(ListTile(
        title: Text.rich(
          key: const Key('deviceListItemTitle'),
          TextSpan(text: device.displayName, children: [
            if (device.favorite)
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
            size: 40, fallbackIcon: Icons.devices, image: deviceClass?.imageWidget),
        trailing: trailingContent,
        // Tighter than the default 16 on both counts: the title now competes
        // with a trailing toggle for a narrow row's width, and the left edge
        // has to stay Spacing.lg for the hairline (GroupedListTile.
        // insetIconLeading40) to still start under the title.
        contentPadding: const EdgeInsets.only(left: Spacing.lg, right: Spacing.sm),
        horizontalTitleGap: Spacing.sm,
        onTap: () => _onTap(context),
        onLongPress: () => _toggleFavorite(device),
      ));

      if (_expanded) {
        columnWidgets.add(
          ListTile(
              title: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            children: trailingWidgets,
          )),
        );
      }

      return GroupedListTile(
          position: widget._position,
          hairlineInset: GroupedListTile.insetIconLeading40,
          child: AnimatedSize(
              duration: const Duration(milliseconds: 75),
              alignment: Alignment.topLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: columnWidgets,
              )));
    });
  }

  _onTap(BuildContext context) {
    final future = Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) {
            final target = DetailPage(widget._device, null);
            return target;
          },
        ));
    if (widget._poppedCallback != null) {
      future.then(widget._poppedCallback!);
    }
  }

  /// Same code path as [FavorizeButton] itself (the mutex, the persistence,
  /// the Isar mirror), invoked without building the button widget - the star
  /// in the title is a display-only indicator now, the row's long-press is
  /// what toggles it.
  Future<void> _toggleFavorite(DeviceInstance device) async {
    if (!DevicesService.isSaveAvailable()) return; // matches the button's disabled state
    // click() itself toasts "Could not save favorite" and bails out without
    // an account - checked here too so that path doesn't also get our own
    // (wrong) success toast.
    final willSave = Settings.getAccount() != null;
    final adding = !device.favorite;
    await FavorizeButton(device, null).click();
    if (!willSave) return;
    HapticFeedbackProxy.mediumImpact();
    Toast.showToastNoContext(adding ? "Added to favorites" : "Removed from favorites");
  }
}

/// The device's unavailability reason, shown in the subtitle line instead of
/// the old trailing icon.
class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.warnInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 1),
      decoration:
          BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
    );
  }
}
