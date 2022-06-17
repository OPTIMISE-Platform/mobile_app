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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/config/function_config.dart';
import 'package:mobile_app/config/get_timestamp.dart';
import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/chart.dart';
import 'package:mobile_app/widgets/tabs/groups/group_edit_devices.dart';
import 'package:provider/provider.dart';

import '../../../../app_state.dart';
import '../../../../models/aspect.dart';
import '../../../../models/device_command_response.dart';
import '../../../../models/device_instance.dart';
import '../../../../services/device_commands.dart';
import '../../../../services/devices.dart';
import '../../../../shared/keyed_list.dart';
import '../../../../theme.dart';
import '../../../shared/app_bar.dart';
import '../../../shared/expandable_text.dart';
import '../../../shared/favorize_button.dart';
import '../../../shared/toast.dart';

class DetailPage extends StatefulWidget {
  final int? _stateDeviceIndex;
  final int? _stateDeviceGroupIndex;

  const DetailPage(this._stateDeviceIndex, this._stateDeviceGroupIndex, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with WidgetsBindingObserver {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  _refresh(BuildContext context) async {
    late final List<DeviceState> states;
    if (widget._stateDeviceIndex != null) {
      states = AppState().devices[widget._stateDeviceIndex!].states;
    } else {
      states = AppState().deviceGroups[widget._stateDeviceGroupIndex!].states;
    }
    for (var element in states) {
      if (!element.isControlling) {
        element.value = null;
        element.transitioning = true;
      }
    }
    WidgetsBinding.instance?.addPostFrameCallback((_) => AppState().notifyListeners());
    AppState().loadStates(context, widget._stateDeviceIndex == null ? [] : [AppState().devices[widget._stateDeviceIndex!]],
        widget._stateDeviceGroupIndex == null ? [] : [AppState().deviceGroups[widget._stateDeviceGroupIndex!]]);
  }

  _performAction(DeviceConnectionStatus? connectionStatus, BuildContext context, DeviceState element, List<DeviceState> states) async {
    if (connectionStatus == DeviceConnectionStatus.offline) {
      Toast.showWarningToast(context, "Device is offline", const Duration(milliseconds: 750));
      return;
    }
    FunctionConfig? functionConfig;
    NestedFunction? function;
    if (!element.isControlling) {
      functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);
      function = AppState().nestedFunctions[functionConfig.getRelatedControllingFunction(element.value)];

      final controllingFunction = functionConfig.getRelatedControllingFunction(element.value);
      if (controllingFunction == null) {
        const err = "Could not find related controlling function";
        Toast.showErrorToast(context, err);
        _logger.e(err);
        return;
      }
      final controllingStates = states.where((state) =>
          state.isControlling &&
          state.functionId == controllingFunction &&
          state.serviceGroupKey == element.serviceGroupKey &&
          state.aspectId == element.aspectId);
      if (controllingStates.isEmpty) {
        const err = "Found no controlling service, check device type!";
        Toast.showErrorToast(context, err);
        _logger.e(err);
        return;
      }
      if (controllingStates.length > 1) {
        const err = "Found more than one controlling service, check device type!";
        Toast.showErrorToast(context, err);
        _logger.e(err);
        return;
      }
      element = controllingStates.first;
      functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);
    } else {
      functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);
      function = AppState().nestedFunctions[element.functionId];
    }

    if (function == null) {
      const err = "Function not found";
      Toast.showWarningToast(context, err, const Duration(milliseconds: 750));
      _logger.e(err + ": " + element.functionId);
      return;
    }

    if (element.transitioning) {
      return; // avoid double presses
    }
    final List<CommandCallback> commandCallbacks = [];
    final List<int> transitioningStates = [];
    for (var i = 0; i < states.length; i++) {
      if (states[i].isControlling) {
        continue;
      }
      var measuringFunctionConfig = functionConfigs[states[i].functionId];
      measuringFunctionConfig ??= FunctionConfigDefault(states[i].functionId);

      List<String>? refreshingMeasurementFunctionIds;
      if (widget._stateDeviceGroupIndex != null) {
        refreshingMeasurementFunctionIds = measuringFunctionConfig.getAllRelatedControllingFunctions();
      } else {
        refreshingMeasurementFunctionIds = [measuringFunctionConfig.getRelatedControllingFunction(states[i].value) ?? ''];
      }
      refreshingMeasurementFunctionIds ??= [];

      if (element.serviceGroupKey == states[i].serviceGroupKey && refreshingMeasurementFunctionIds.contains(element.functionId)) {
        transitioningStates.add(i);
        commandCallbacks.add(CommandCallback(states[i].toCommand(), (value) {
          states[i].transitioning = false;
          value = value as DeviceCommandResponse;
          if (value.status_code != 200) {
            _logger.e(value.status_code.toString() + ": " + value.message);
            return;
          }
          if (value.message is List && value.message.length == 1) {
            states[i].value = value.message[0];
          } else {
            states[i].value = value.message;
          }
        }));
      }
    }

    dynamic input;
    if (function.hasInput()) {
      Widget? content = functionConfig.build(context, transitioningStates.length == 1 ? states[transitioningStates[0]].value : null);
      if (content == null) {
        const err = "Function Config missing build()";
        Toast.showErrorToast(context, err, const Duration(milliseconds: 750));
        _logger.e(err + ": " + element.functionId);
        return;
      }
      input = await showPlatformDialog(
        context: context,
        builder: (_) => PlatformAlertDialog(
          title: const Text('Configure'),
          content: content,
          actions: <Widget>[
            PlatformDialogAction(
              child: PlatformText('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, functionConfig!.getConfiguredValue())),
          ],
        ),
      );
      if (input == null) {
        return; // canceled
      }
    }
    element.transitioning = true;
    for (var i in transitioningStates) {
      states[i].transitioning = true;
    }
    AppState().notifyListeners();
    final List<DeviceCommandResponse> responses = [];
    if (!await DeviceCommandsService.runCommandsSecurely(context, [element.toCommand(input)], responses)) {
      element.transitioning = false;
      for (var i in transitioningStates) {
        states[i].transitioning = false;
      }
      AppState().notifyListeners();
      return;
    }
    assert(responses.length == 1);
    if (responses[0].status_code != 200) {
      element.transitioning = false;
      for (var i in transitioningStates) {
        states[i].transitioning = false;
      }
      AppState().notifyListeners();
      const err = "Error running command";
      Toast.showErrorToast(context, err);
      _logger.e(err + ": " + responses[0].message.toString());
      return;
    }
    element.transitioning = false;
    AppState().notifyListeners();

    // refresh changed measurements
    AppState().notifyListeners();
    responses.clear();
    if (!await DeviceCommandsService.runCommandsSecurely(context, commandCallbacks.map((e) => e.command).toList(growable: false), responses, false)) {
      for (var i in transitioningStates) {
        states[i].transitioning = false;
      }
      AppState().notifyListeners();
      return;
    }
    assert(responses.length == commandCallbacks.length);
    for (var i = 0; i < responses.length; i++) {
      commandCallbacks[i].callback(responses[i]);
    }
    AppState().notifyListeners();
  }

  _displayTimestamp(DeviceState element, List<DeviceState> states, BuildContext context) {
    try {
      final state = states.firstWhere((state) =>
          !state.isControlling &&
          state.serviceId == element.serviceId &&
          state.aspectId == element.aspectId &&
          state.deviceClassId == element.deviceClassId &&
          state.functionId == dotenv.env["FUNCTION_GET_TIMESTAMP"]);
      Toast.showInformationToast(context, FunctionConfigGetTimestamp().formatTimestamp(state.value), const Duration(milliseconds: 1000));
    } catch (e) {
      _logger.w("Could not display timestamp: " + e.toString());
    }
  }

  String _getTitle(DeviceState element) {
    final function = AppState().nestedFunctions[element.functionId];
    String title = function?.display_name ?? "MISSING_FUNCTION_NAME";
    if (title.isEmpty) title = function?.name ?? "MISSING_FUNCTION_NAME";
    return title;
  }

  String _getSubtitle(DeviceState element, List<DeviceState> states, DeviceInstance? device) {
    String subtitle = "";
    if (states.any((s) => !s.isControlling && s.functionId == element.functionId && s != element && s.aspectId != element.aspectId)) {
      subtitle += _findAspect(AppState().aspects.values, element.aspectId)?.name ?? "MISSING_ASPECT_NAME";
    }
    if (device != null &&
        element.serviceGroupKey != null &&
        element.serviceGroupKey != "" &&
        states.any((s) => !s.isControlling && s.functionId == element.functionId && s != element && s.aspectId == element.aspectId)) {
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
    return Consumer<AppState>(builder: (context, state, child) {
      if ((state.loadingDevices ||
              (widget._stateDeviceGroupIndex != null &&
                  (state.deviceGroups.length <= widget._stateDeviceGroupIndex! ||
                      state.devices.length != state.deviceGroups[widget._stateDeviceGroupIndex!].device_ids.length))) &&
          !state.allDevicesLoaded) {
        if (!state.loadingDevices) {
          state.loadDevices(context); //ensure all devices get loaded
        }
        return Center(child: PlatformCircularProgressIndicator());
      }

      if (widget._stateDeviceIndex != null && state.devices.length - 1 < widget._stateDeviceIndex!) {
        _logger.w("Device Page requested for device index that is not in AppState");
        return Center(child: PlatformCircularProgressIndicator());
      }
      if (widget._stateDeviceGroupIndex != null && state.deviceGroups.length - 1 < widget._stateDeviceGroupIndex!) {
        _logger.w("Device Page requested for device group index that is not in AppState");
        return Center(child: PlatformCircularProgressIndicator());
      }
      final device = widget._stateDeviceIndex == null ? null : state.devices[widget._stateDeviceIndex!];
      final deviceGroup = widget._stateDeviceGroupIndex == null ? null : state.deviceGroups[widget._stateDeviceGroupIndex!];
      late final List<DeviceState> states;
      if (widget._stateDeviceIndex != null) {
        states = state.devices[widget._stateDeviceIndex!].states;
      } else {
        states = state.deviceGroups[widget._stateDeviceGroupIndex!].states;
      }

      final connectionStatus = device?.getConnectionStatus();
      final _appBar = MyAppBar(device?.displayName ?? deviceGroup!.name);
      if (state.devices.isEmpty) {
        state.loadDevices(context);
      }
      List<Widget> appBarActions = [];

      if (device != null) {
        appBarActions.add(PlatformIconButton(
          onPressed: () async {
            final oldName = device.displayName;
            final newName = await showPlatformDialog(
                context: context,
                builder: (_) {
                  final controller = TextEditingController(text: device.displayName);
                  return PlatformAlertDialog(
                    title: Text(
                      "Rename " + device.displayName,
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
              await DevicesService.saveDevice(state.devices[widget._stateDeviceIndex!]);
              state.notifyListeners();
            } catch (e) {
              Toast.showErrorToast(context, "Could not update device name");
              device.setNickname(oldName);
            }
          },
          icon: Icon(PlatformIcons(context).edit),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
      } else if (deviceGroup != null) {
        appBarActions.add(PlatformIconButton(
          onPressed: () async {
            final oldName = deviceGroup.name;
            final newName = await showPlatformDialog(
                context: context,
                builder: (_) {
                  final controller = TextEditingController(text: deviceGroup.name);
                  return PlatformAlertDialog(
                    title: Text(
                      "Rename " + deviceGroup.name,
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
              await DeviceGroupsService.saveDeviceGroup(state.deviceGroups[widget._stateDeviceGroupIndex!]);
              state.notifyListeners();
            } catch (e) {
              Toast.showErrorToast(context, "Could not update device name");
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
                      title: Text("Do you want to permanently delete group '" + deviceGroup.name + "'?"),
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
                              state.deviceGroups.removeAt(widget._stateDeviceGroupIndex!);
                              Navigator.pop(context, true);
                            })
                      ],
                    ));
            if (deleted == true) {
              Navigator.pop(context);
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
              state.aspectId == element.aspectId);
        }
        if (controllingFunctions == null || controllingFunctions.isEmpty || controllingStates == null || controllingStates.isEmpty) {
          functionWidgets.insert(
            element.functionId,
            ListTile(
                onTap: () => _displayTimestamp(element, states, context),
                onLongPress: device == null || element.value is! num
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
                      ? PlatformCircularProgressIndicator()
                      : functionConfig.displayValue(element.value, context) ??
                          Text(
                              formatValue(element.value) +
                                  " " +
                                  (state.nestedFunctions[element.functionId]?.concept.base_characteristic?.display_unit ?? ""),
                              style: const TextStyle(fontStyle: FontStyle.italic)),
                )),
          );
        } else {
          markedControllingStates.addAll(controllingStates);
          functionWidgets.insert(
            element.functionId,
            ListTile(
                onTap: () => _displayTimestamp(element, states, context),
                onLongPress: device == null || element.value is! num
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
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .5 -12),
                        padding: const EdgeInsets.only(right: 12),
                        child: PlatformCircularProgressIndicator())
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
                            child: functionConfig.displayValue(element.value, context) ??
                                Text(formatValue(element.value) +
                                    " " +
                                    (state.nestedFunctions[element.functionId]?.concept.base_characteristic?.display_unit ?? "")),
                            onPressed: connectionStatus == DeviceConnectionStatus.offline
                                ? null
                                : () => _performAction(
                                      connectionStatus,
                                      context,
                                      element,
                                      states,
                                    ),
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
            onLongPress: device == null || element.value is! num
                ? null
                : () => Navigator.push(
                    context,
                    platformPageRoute(
                      context: context,
                      builder: (context) => Chart(element),
                    )),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: element.transitioning
                ? Container(padding: const EdgeInsets.only(right: 12), child: PlatformCircularProgressIndicator())
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
        trailingHeader.add(FavorizeButton(widget._stateDeviceIndex!, null));
      } else {
        trailingHeader.add(FavorizeButton(null, widget._stateDeviceGroupIndex));
      }

      return Scaffold(
          floatingActionButton: deviceGroup == null
              ? null
              : FloatingActionButton(
                  onPressed: () async {
                    await Navigator.push(
                        context, platformPageRoute(context: context, builder: (context) => GroupEditDevices(widget._stateDeviceGroupIndex!)));
                    await state.searchDevices(DeviceSearchFilter("", null, null, null, [deviceGroup.id], null, null), context, true);
                    deviceGroup.prepareStates(true);
                    _refresh(context);
                  },
                  backgroundColor: MyTheme.appColor,
                  child: Icon(Icons.list, color: MyTheme.textColor),
                ),
          body: PlatformScaffold(
            appBar: _appBar.getAppBar(context, appBarActions),
            body: RefreshIndicator(
              onRefresh: () => _refresh(context),
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
                      trailing: Row(children: trailingHeader, mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end),
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
    if ((widget._stateDeviceIndex == null && widget._stateDeviceGroupIndex == null) ||
        (widget._stateDeviceIndex != null && widget._stateDeviceGroupIndex != null)) {
      throw ArgumentException("Must set ONE of _stateDeviceIndex or _stateDeviceGroupIndex");
    }
    WidgetsBinding.instance!.addObserver(this);
    WidgetsBinding.instance?.addPostFrameCallback((_) => _refresh(context));
  }

  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) _refresh(context);
  }
}
