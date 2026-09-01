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
import 'package:mobile_app/mixins/resume_refresh_mixin.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/config/functions/get_timestamp.dart';
import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/widgets/tabs/groups/group_edit_devices.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/chart.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/expandable_text.dart';
import 'package:mobile_app/widgets/shared/favorize_button.dart';
import 'package:mobile_app/widgets/shared/toast.dart';

class DetailPage extends StatefulWidget {
  final DeviceInstance? _device;
  final DeviceGroup? _group;

  const DetailPage(this._device, this._group, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with ResumeRefreshMixin {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  StreamSubscription? _refreshSubscription;

  _refresh(BuildContext context) async {
    late final List<DeviceState> states;
    if (widget._device != null) {
      states = widget._device!.states;
    } else {
      states = widget._group!.states;
    }
    for (var element in states) {
      if (!element.isControlling) {
        element.value = null;
        element.transitioning = true;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyEntity());
    AppState().loadStates(widget._device == null ? [] : [widget._device!], widget._group == null ? [] : [widget._group!]);
  }

  /// Signals only this page's device/group so its widgets rebuild without
  /// waking every other AppState consumer.
  void _notifyEntity() {
    widget._device?.notifyStateChanged();
    widget._group?.notifyStateChanged();
  }

  /// Delegates to the shared implementation, which the sensors page reuses.
  _performAction(DeviceConnectionStatus? connectionStatus, BuildContext context, DeviceState element, List<DeviceState> states) =>
      performDeviceStateAction(
        context: context,
        connectionStatus: connectionStatus,
        element: element,
        states: states,
        isGroup: widget._group != null,
        setState: setState,
        notifyEntity: _notifyEntity,
      );

  _displayTimestamp(DeviceState element, List<DeviceState> states, BuildContext context) {
    try {
      final state = states.firstWhere((state) =>
          !state.isControlling &&
          state.serviceId == element.serviceId &&
          state.aspectId == element.aspectId &&
          state.deviceClassId == element.deviceClassId &&
          state.functionId == dotenv.env["FUNCTION_GET_TIMESTAMP"]);
      Toast.showToastNoContext(FunctionConfigGetTimestamp().formatTimestamp(state.value));
    } catch (e) {
      _logger.w("Could not display timestamp: $e");
    }
  }

  String _getTitle(DeviceState element) {
    final function = AppState().platformFunctions[element.functionId];
    String title = function?.display_name ?? "MISSING_FUNCTION_NAME";
    if (title.isEmpty) title = function?.name ?? "MISSING_FUNCTION_NAME";
    return title;
  }

  String _getSubtitle(DeviceState element, List<DeviceState> states, DeviceInstance? device) {
    String subtitle = "";
    if (states.any((s) => s.functionId == element.functionId && s != element && s.aspectId != element.aspectId)) {
      subtitle += _findAspect(AppState().aspects.values, element.aspectId)?.name ?? "MISSING_ASPECT_NAME";
    }
    if (device != null &&
        element.serviceGroupKey != null &&
        element.serviceGroupKey != "" &&
        states.any((s) => s.functionId == element.functionId && s != element && s.aspectId == element.aspectId)) {
      if (subtitle.isNotEmpty) subtitle += ", ";
      subtitle += (AppState().deviceTypes[device.device_type_id]?.service_groups?.firstWhere((g) => g.key == element.serviceGroupKey).name ??
          "MISSING_SERVICE_GROUP_NAME");
    }
    return subtitle;
  }

  Aspect? _findAspect(Iterable<Aspect> aspects, String? id) {
    if (id == null) {
      return null;
    }
    for (final a in aspects) {
      if (a.id == id) {
        return a;
      }
      if (a.sub_aspects != null) {
        final sub = _findAspect(a.sub_aspects!, id);
        if (sub != null) {
          return sub;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on this entity's own changes (frequent) OR structural AppState
    // changes like the device list finishing loading (rare) — but not on other
    // devices' per-entity updates.
    final entityNotifier =
        widget._device?.stateNotifier ?? widget._group!.stateNotifier;
    return ListenableBuilder(
        listenable: Listenable.merge([AppState(), entityNotifier]),
        builder: (context, child) {
      final state = AppState();
      if ((state.loadingDevices || (widget._group != null && (state.devices.length != widget._group!.device_ids.length))) &&
          !state.allDevicesLoaded) {
        if (!state.loadingDevices) {
          state.loadDevices(); //ensure all devices get loaded
        }
        return Center(child: DelayedCircularProgressIndicator());
      }

      final device = widget._device;
      final deviceGroup = widget._group;
      late final List<DeviceState> states;
      if (device != null) {
        states = device.states;
      } else {
        states = deviceGroup!.states;
      }

      final connectionStatus = device?.connection_state;
      final appBar = MyAppBar(device?.displayName ?? deviceGroup!.name);
      if (state.devices.isEmpty) {
        state.loadDevices();
      }
      List<Widget> appBarActions = [];

      if (device != null && DevicesService.isSaveAvailable()) {
        appBarActions.add(PlatformIconButton(
          onPressed: () async {
            final oldName = device.displayName;
            final newName = await showPlatformDialog(
                context: context,
                builder: (_) {
                  final controller = TextEditingController(text: device.displayName);
                  return PlatformAlertDialog(
                    title: Text(
                      "Rename ${device.displayName}",
                      overflow: TextOverflow.ellipsis,
                    ),
                    content: PlatformTextFormField(controller: controller),
                    actions: <Widget>[
                      PlatformDialogAction(child: PlatformText('Cancel'), onPressed: () => Navigator.pop(context)),
                      PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, controller.value.text)),
                    ],
                  );
                });
            if (newName == null) return;
            device.setNickname(newName);
            try {
              await DevicesService.saveDevice(device);
              _notifyEntity();
            } catch (e) {
              Toast.showToastNoContext("Could not update device name");
              device.setNickname(oldName);
            }
          },
          icon: Icon(PlatformIcons(context).edit),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
      } else if (deviceGroup != null && DeviceGroupsService.isCreateEditDeleteAvailable()) {
        appBarActions.add(PlatformIconButton(
          onPressed: () async {
            final oldName = deviceGroup.name;
            final newName = await showPlatformDialog(
                context: context,
                builder: (_) {
                  final controller = TextEditingController(text: deviceGroup.name);
                  return PlatformAlertDialog(
                    title: Text(
                      "Rename ${deviceGroup.name}",
                      overflow: TextOverflow.ellipsis,
                    ),
                    content: PlatformTextFormField(controller: controller),
                    actions: <Widget>[
                      PlatformDialogAction(child: PlatformText('Cancel'), onPressed: () => Navigator.pop(context)),
                      PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, controller.value.text)),
                    ],
                  );
                });
            if (newName == null) return;
            deviceGroup.name = newName;
            try {
              await DeviceGroupsService.saveDeviceGroup(deviceGroup);
              _notifyEntity();
            } catch (e) {
              Toast.showToastNoContext("Could not update device name");
              deviceGroup.name = oldName;
            }
          },
          icon: Icon(PlatformIcons(context).edit),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
        appBarActions.add(PlatformIconButton(
          onPressed: () async {
            final deleted = await showPlatformDialog(
                context: context,
                builder: (context) => PlatformAlertDialog(
                      title: Text("Do you want to permanently delete group '${deviceGroup.name}'?"),
                      actions: [
                        PlatformDialogAction(
                          child: PlatformText('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        PlatformDialogAction(
                            child: PlatformText('Delete'),
                            cupertino: (_, __) => CupertinoDialogActionData(isDestructiveAction: true),
                            onPressed: () async {
                              await DeviceGroupsService.deleteDeviceGroup(deviceGroup.id);
                              state.deviceGroups.remove(deviceGroup);
                              if (!context.mounted) return;
                              Navigator.pop(context, true);
                            })
                      ],
                    ));
            if (deleted == true) {
              // Only the pop needs a live context; the notify has to happen
              // either way, otherwise the list keeps showing the deleted group.
              if (context.mounted) Navigator.pop(context);
              state.notifyListeners();
            }
          },
          icon: Icon(PlatformIcons(context).delete),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
      }
      if (kIsWeb) {
        appBarActions.add(PlatformIconButton(
          onPressed: () => _refresh(context),
          icon: const Icon(Icons.refresh),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
      }
      appBarActions.addAll(MyAppBar.getDefaultActions(context));

      KeyedList<String, Widget> functionWidgets = KeyedList();
      final List<DeviceState> markedControllingStates = [];

      for (var element in states.where((element) => !element.isControlling)) {
        if (element.functionId == dotenv.env["FUNCTION_GET_TIMESTAMP"]) {
          continue;
        }
        final subtitle = _getSubtitle(element, states, device);
        var functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);

        final controllingFunctions = functionConfig.getAllRelatedControllingFunctions();
        Iterable<DeviceState>? controllingStates;
        if (controllingFunctions != null) {
          controllingStates = states.where((state) =>
              state.isControlling &&
              controllingFunctions.contains(state.functionId) &&
              state.serviceGroupKey == element.serviceGroupKey &&
              state.aspectId == element.aspectId &&
              functionConfig.getRelatedControllingFunction(element.value) != null);
        }
        String? preferred = Settings.getFunctionPreferredCharacteristicId(element.functionId);
        String? unit;
        if (preferred != null) {
          unit = state.characteristics[preferred]?.display_unit;
        } else {
          unit = state.concepts[state.platformFunctions[element.functionId]?.concept_id]?.getBaseCharacteristic().display_unit ?? "";
        }
        if (controllingFunctions == null || controllingFunctions.isEmpty || controllingStates == null || controllingStates.isEmpty) {
          functionWidgets.insert(
            element.functionId,
            ListTile(
                onLongPress: () => _displayTimestamp(element, states, context),
                onTap: device == null || element.value is! num
                    ? null
                    : () => Navigator.push(
                        context,
                        platformPageRoute(
                          context: context,
                          builder: (context) => Chart(element),
                        )),
                title: Text(_getTitle(element)),
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
                trailing: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .5 - 12),
                  padding: const EdgeInsets.only(right: 12),
                  child: element.transitioning
                      ? DelayedCircularProgressIndicator()
                      : functionConfig.displayValue(element.value, context) ??
                          Text("${formatValue(element.value)} ${unit}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                )),
          );
        } else {
          markedControllingStates.addAll(controllingStates);
          functionWidgets.insert(
            element.functionId,
            ListTile(
                onLongPress: () => _displayTimestamp(element, states, context),
                onTap: device == null || element.value is! num
                    ? null
                    : () => Navigator.push(
                        context,
                        platformPageRoute(
                          context: context,
                          builder: (context) => Chart(element),
                        )),
                title: Text(_getTitle(element)),
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
                trailing: element.transitioning
                    ? Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .5 - 12),
                        padding: const EdgeInsets.only(right: 12),
                        child: DelayedCircularProgressIndicator())
                    : functionConfig.displayValue(element.value, context) != null
                        ? PlatformIconButton(
                            cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
                            icon: functionConfig.displayValue(element.value, context)!,
                            onPressed: connectionStatus == DeviceConnectionStatus.offline
                                ? null
                                : () => _performAction(
                                      connectionStatus,
                                      context,
                                      element,
                                      states,
                                    ),
                          )
                        : PlatformTextButton(
                            onPressed: connectionStatus == DeviceConnectionStatus.offline
                                ? null
                                : () => _performAction(
                                      connectionStatus,
                                      context,
                                      element,
                                      states,
                                    ),
                            child: functionConfig.displayValue(element.value, context) ??
                                Text(
                                    "${formatValue(element.value)}${unit != "" ? " $unit" : ""}"),
                          )),
          );
        }
      }

      for (var element in states.where((element) => element.isControlling && !markedControllingStates.contains(element))) {
        var functionConfig = functionConfigs[element.functionId];
        final subtitle = _getSubtitle(element, states, device);

        functionWidgets.insert(
          element.functionId,
          ListTile(
            title: Text(_getTitle(element)),
            onTap: device == null || element.value is! num
                ? null
                : () => Navigator.push(
                    context,
                    platformPageRoute(
                      context: context,
                      builder: (context) => Chart(element),
                    )),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: element.transitioning
                ? Container(padding: const EdgeInsets.only(right: 12), child: DelayedCircularProgressIndicator())
                : PlatformIconButton(
                    cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
                    material: (_, __) => MaterialIconButtonData(splashRadius: 25),
                    icon: functionConfig?.displayValue(element.value, context) ?? const Icon(Icons.input),
                    onPressed: connectionStatus == DeviceConnectionStatus.offline
                        ? null
                        : () => _performAction(
                              connectionStatus,
                              context,
                              element,
                              states,
                            ),
                  ),
          ),
        );
      }

      final List<Widget> widgets = [];
      final list = functionWidgets.list();
      list.sort((a, b) {
        if (a.k == b.k) {
          return 0;
        }
        if (a.k == dotenv.env['FUNCTION_SET_ON_STATE'] || a.k == dotenv.env['FUNCTION_SET_OFF_STATE']) {
          return -2;
        }
        if (b.k == dotenv.env['FUNCTION_SET_ON_STATE'] || b.k == dotenv.env['FUNCTION_SET_OFF_STATE']) {
          return 2;
        }
        if (a.k == dotenv.env['FUNCTION_GET_ON_OFF_STATE']) {
          return -1;
        }
        if (b.k == dotenv.env['FUNCTION_GET_ON_OFF_STATE']) {
          return 1;
        }
        return a.k.compareTo(b.k);
      });
      for (var element in list) {
        widgets.add(const Divider());
        widgets.add(element.t);
      }
      if (deviceGroup != null) {
        // prevent fab overlap
        widgets.add(Column(
          children: const [Divider(), ListTile()],
        ));
      }

      final List<Widget> trailingHeader = [];

      if (connectionStatus == DeviceConnectionStatus.offline) {
        trailingHeader.add(Tooltip(
            message: "Device is offline", triggerMode: TooltipTriggerMode.tap, child: Icon(PlatformIcons(context).error, color: MyTheme.warnColor)));
      }
      if (device != null) {
        if (device.network?.localService != null) {
          trailingHeader.add(const Tooltip(message: "In local network", triggerMode: TooltipTriggerMode.tap, child: Icon(Icons.lan_outlined)));
        }
        trailingHeader.add(FavorizeButton(widget._device!, null));
      } else {
        if (deviceGroup?.network?.localService != null) {
          trailingHeader.add(const Tooltip(message: "In local network", triggerMode: TooltipTriggerMode.tap, child: Icon(Icons.lan_outlined)));
        }
        trailingHeader.add(FavorizeButton(null, widget._group));
      }

      return Scaffold(
          floatingActionButton: deviceGroup == null || !DeviceGroupsService.isCreateEditDeleteAvailable()
              ? null
              : FloatingActionButton(
                  onPressed: () async {
                    await Navigator.push(context, platformPageRoute(context: context, builder: (context) => GroupEditDevices(widget._group!)));
                    await state.searchDevices(DeviceSearchFilter("", null, null, null, [deviceGroup.id], null, null), true);
                    deviceGroup.prepareStates(true);
                    if (!context.mounted) return;
                    _refresh(context);
                  },
                  backgroundColor: MyTheme.appColor,
                  child: Icon(Icons.list, color: MyTheme.textColor),
                ),
          body: PlatformScaffold(
            appBar: appBar.getAppBar(context, appBarActions),
            body: RefreshIndicator(
              onRefresh: () async {
                HapticFeedbackProxy.lightImpact();
                _refresh(context);
              },
              child: Scrollbar(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: MyTheme.inset,
                  children: [
                    ListTile(
                      // header
                      leading: Container(
                        height: MediaQuery.of(context).textScaleFactor * 48,
                        width: MediaQuery.of(context).textScaleFactor * 48,
                        decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
                        child: Padding(
                          padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
                          child: device != null
                              ? state.deviceClasses[state.deviceTypes[device.device_type_id]?.device_class_id]?.imageWidget
                              : deviceGroup!.imageWidget ?? const Icon(Icons.devices_other, color: Colors.white),
                        ),
                      ),
                      title: Text(
                        device != null
                            ? state.deviceClasses[state.deviceTypes[device.device_type_id]?.device_class_id]?.name ?? "MISSING_DEVICE_CLASS_NAME"
                            : "Device Group",
                      ),
                      subtitle: device != null
                          ? ExpandableText(state.deviceTypes[device.device_type_id]?.name ?? "MISSING_DEVICE_TYPE_NAME", 2)
                          : ExpandableText(state.devices.map((e) => e.displayName).join("\n"), 3),
                      trailing: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: trailingHeader),
                    ),
                    Container(
                      padding: const EdgeInsets.only(left: 6, right: 6),
                      child: const Divider(thickness: 2),
                    ),
                    ...widgets.skip(1), // skip first divider
                  ],
                ),
              ),
            ),
          ));
    });
  }

  @override
  void initState() {
    super.initState();
    if ((widget._device == null && widget._group == null) || (widget._device != null && widget._group != null)) {
      throw ArgumentException("Must set ONE of device or group");
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(context));
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      if (!mounted) return;
      _refresh(context);
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void onResumed() => _refresh(context);
}
