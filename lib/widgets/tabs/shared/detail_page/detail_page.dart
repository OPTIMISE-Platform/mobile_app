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
import 'package:mobile_app/mixins/resume_refresh_mixin.dart';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/config/functions/get_timestamp.dart';
import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/live/live_values.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/widgets/tabs/groups/group_edit_devices.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/chart.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/control_cards.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_labels.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/inline_control.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';
import 'package:mobile_app/shared/device_controls.dart';
import 'package:mobile_app/shared/unavailability.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/entity_leading_icon.dart';
import 'package:mobile_app/widgets/shared/favorize_button.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/shared/state_time.dart';
import 'package:mobile_app/widgets/tabs/shared/value_change.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_tile.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/relative_time.dart';

class DetailPage extends StatefulWidget {
  final DeviceInstance? _device;
  final DeviceGroup? _group;

  const DetailPage(this._device, this._group, {super.key});

  @override
  State<StatefulWidget> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with ResumeRefreshMixin {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  StreamSubscription? _refreshSubscription;

  /// Keeps the values of a device page current while it is open; null for a group.
  LiveHandle? _live;

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

  /// Delegates to the shared implementation, which the sensors page reuses. A
  /// [value] is sent without asking in the dialog.
  _performAction(DeviceConnectionStatus? connectionStatus, BuildContext context, DeviceState element, List<DeviceState> states,
          [dynamic value]) =>
      performDeviceStateAction(
        context: context,
        connectionStatus: connectionStatus,
        element: element,
        states: states,
        isGroup: widget._group != null,
        setState: setState,
        notifyEntity: _notifyEntity,
        value: value,
      );

  _displayTimestamp(DeviceState element, List<DeviceState> states, BuildContext context) {
    try {
      final state = DeviceState.legacyMatchAspects(
          states.where((state) =>
              !state.isControlling &&
              state.serviceId == element.serviceId &&
              state.deviceClassId == element.deviceClassId &&
              state.functionId == dotenv.env["FUNCTION_GET_TIMESTAMP"]),
          element.aspectIds).first;
      Toast.showToastNoContext(FunctionConfigGetTimestamp().formatTimestamp(state.value));
    } catch (e) {
      _logger.w("Could not display timestamp: $e");
    }
  }

  /// The row's subtitle with the time the reading was received as its last
  /// line, when that is known. Under the title rather than next to the value,
  /// where a ListTile leaves no height for a second line.
  Widget? _subtitleWithTime(String subtitle, DeviceState element) {
    final time = element.transitioning ? null : element.lastMessageTime;
    if (time == null) return subtitle.isEmpty ? null : Text(subtitle);
    final caption = StateTimeCaption(time, tappable: true, textAlign: TextAlign.start);
    if (subtitle.isEmpty) return caption;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(subtitle), caption],
    );
  }

  /// Identifies a row across rebuilds, independent of its position in the
  /// (re-)sorted list. Both `prepareStates` implementations that build
  /// `states` (device_state.dart for a device, device_group.dart for a
  /// group) already refuse to add a state whose functionId, serviceGroupKey,
  /// aspect set, deviceClassId and isControlling all match an existing one, so
  /// that combination is exactly the invariant already unique per row here.
  String _rowKey(DeviceState element) => [
        element.functionId,
        element.serviceGroupKey,
        element.aspectKey,
        element.deviceClassId,
        element.isControlling,
      ].join("|");

  /// Orders rows with the on/off functions first, the rest by function id.
  List<Pair<String, ({Widget tile, String rowKey})>> _sorted(KeyedList<String, ({Widget tile, String rowKey})> rows) {
    final list = rows.list();
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
    return list;
  }

  ListSection<Pair<String, ({Widget tile, String rowKey})>> _section(
          String id, String title, List<Pair<String, ({Widget tile, String rowKey})>> items) =>
      ListSection<Pair<String, ({Widget tile, String rowKey})>>(
        id: id,
        title: title,
        items: items,
        keyOf: (row) => row.t.rowKey,
        itemBuilder: (_, row, position) => GroupedListTile(
          position: position,
          hairlineInset: GroupedListTile.insetNoLeading,
          child: row.t.tile,
        ),
      );

  /// The value of a row without a control. An on/off reading is text, not the
  /// power icon, which is for the switch that acts on it.
  Widget _readOnlyValue(DeviceState element, FunctionConfig config, String unit, BuildContext context, BinaryRole? role) {
    const style = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
    if (isOnOffReading(element.functionId)) return Text(binaryValueText(role, element.value), style: style);
    return config.displayValue(element.value, context) ?? Text(formatValueWithUnit(element.value, unit), style: style);
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
          !state.devicesListEnded) {
        if (!state.loadingDevices) {
          state.loadDevices(); //ensure all devices get loaded
        }
        return const Center(child: DelayedCircularProgressIndicator());
      }

      final device = widget._device;
      final deviceGroup = widget._group;
      // Rows are the shown states; pairing and actions need all of them, so a
      // control of a hidden reading stays with that reading.
      final List<DeviceState> states;
      final List<DeviceState> rows;
      if (device != null) {
        states = device.states;
        rows = states;
      } else {
        states = deviceGroup!.states;
        rows = deviceGroup.shownStates;
      }

      // Cards take what belongs together; the rows they cover are left out below.
      final isGroup = deviceGroup != null;
      final light = lightCardOf(rows, states, isGroup: isGroup);
      final climates = climateCardsOf(rows, states, isGroup: isGroup);
      final covered = <DeviceState>{...?light?.covered, for (final c in climates) ...c.covered};

      final connectionStatus = device?.connection_state;
      // Local mode without a local gateway locks the controls too, not only an
      // offline device.
      final unavailability = device != null
          ? deviceUnavailability(device)
          : groupUnavailability(deviceGroup!);
      final appBar = MyAppBar(device?.displayName ?? deviceGroup!.name);
      if (state.devices.isEmpty) {
        state.loadDevices();
      }
      List<Widget> appBarActions = [];

      if (device != null && DevicesService.isSaveAvailable()) {
        appBarActions.add(IconButton(
          onPressed: () async {
            final oldName = device.displayName;
            final newName = await showAdaptiveDialog(
                context: context,
                builder: (_) {
                  final controller = TextEditingController(text: device.displayName);
                  return AlertDialog.adaptive(
                    title: Text(
                      "Rename ${device.displayName}",
                      overflow: TextOverflow.ellipsis,
                    ),
                    content: TextFormField(controller: controller),
                    actions: <Widget>[
                      TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
                      TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context, controller.value.text)),
                    ],
                  );
                });
            if (newName == null) return;
            device.setNickname(newName);
            try {
              await DevicesService.saveDevice(device);
              _notifyEntity();
            } catch (e, s) {
              ErrorReporter.log("Could not save the device", e, s);
              Toast.showToastNoContext("Could not update device name");
              device.setNickname(oldName);
            }
          },
          icon: const Icon(Icons.edit),
        ));
      } else if (deviceGroup != null && DeviceGroupsService.isCreateEditDeleteAvailable()) {
        appBarActions.add(IconButton(
          onPressed: () async {
            final oldName = deviceGroup.name;
            final newName = await showAdaptiveDialog(
                context: context,
                builder: (_) {
                  final controller = TextEditingController(text: deviceGroup.name);
                  return AlertDialog.adaptive(
                    title: Text(
                      "Rename ${deviceGroup.name}",
                      overflow: TextOverflow.ellipsis,
                    ),
                    content: TextFormField(controller: controller),
                    actions: <Widget>[
                      TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
                      TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context, controller.value.text)),
                    ],
                  );
                });
            if (newName == null) return;
            try {
              await DeviceGroupsService.saveDeviceGroup(deviceGroup, (g) => g.name = newName);
              _notifyEntity();
            } catch (e, s) {
              ErrorReporter.log("Could not save the device group", e, s);
              Toast.showToastNoContext("Could not update device name");
              deviceGroup.name = oldName;
            }
          },
          icon: const Icon(Icons.edit),
        ));
        appBarActions.add(IconButton(
          onPressed: () async {
            final deleted = await showAdaptiveDialog(
                context: context,
                builder: (context) => AlertDialog.adaptive(
                      title: Text("Do you want to permanently delete group '${deviceGroup.name}'?"),
                      actions: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        TextButton(
                            child: const Text('Delete'),
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
          icon: const Icon(Icons.delete),
        ));
      }
      appBarActions.addAll(MyAppBar.getDefaultActions(context));

      // Rows with a control on top, read-only ones below.
      final KeyedList<String, ({Widget tile, String rowKey})> controlWidgets = KeyedList();
      final KeyedList<String, ({Widget tile, String rowKey})> readingWidgets = KeyedList();
      final List<DeviceState> markedControllingStates = [...covered.where((s) => s.isControlling)];

      for (var element in rows.where((element) => !element.isControlling)) {
        if (element.functionId == dotenv.env["FUNCTION_GET_TIMESTAMP"] || covered.contains(element)) {
          continue;
        }
        final label = detailLabel(element, rows, device, states: states, isGroup: isGroup);
        final role = binaryRoleOf(element, states, isGroup: isGroup);
        var functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);

        final controllingFunctions = functionConfig.getAllRelatedControllingFunctions();
        Iterable<DeviceState>? controllingStates;
        // The config guesses "on" for an unknown on/off state, so such a reading
        // keeps its controls as rows of their own instead of acting for them.
        final unknownSwitch =
            isOnOffReading(element.functionId) && onOffReadingOf(element.value) == OnOffReading.unknown;
        if (controllingFunctions != null &&
            !unknownSwitch &&
            functionConfig.getRelatedControllingFunction(element.value) != null) {
          controllingStates = controllingFunctions.expand((f) => element.controlsFor(states, f)).toList();
        }
        final unit = readingUnit(element.functionId);
        if (controllingFunctions == null || controllingFunctions.isEmpty || controllingStates == null || controllingStates.isEmpty) {
          readingWidgets.insert(
            element.functionId,
            (
              rowKey: _rowKey(element),
              tile: ListTile(
                onLongPress: () => _displayTimestamp(element, states, context),
                onTap: device == null || element.value is! num
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Chart(element),
                        )),
                title: Text(label.title),
                subtitle: _subtitleWithTime(label.subtitle, element),
                trailing: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .5 - 12),
                  padding: const EdgeInsets.only(right: 12),
                  child: element.transitioning
                      ? const DelayedCircularProgressIndicator()
                      : ValueChange(
                          value: element.value,
                          child: _readOnlyValue(element, functionConfig, unit, context, role),
                        ),
                ),
              ),
            ),
          );
        } else {
          markedControllingStates.addAll(controllingStates);
          // On/off is a switch; a value control with one control is set in
          // place when its characteristic allows, else it keeps the dialog.
          final switchReading = isOnOffReading(element.functionId) ? onOffReadingOf(element.value) : null;
          final control = switchReading == null && controllingStates.length == 1 ? controllingStates.first : null;
          // In the control's characteristic; no conversion keeps the dialog.
          final start = control == null ? null : inlineStartValue(control, states, isGroup: isGroup);
          final spec = start == null ? null : inlineControlSpec(control!, start.value, reading: element);
          ListTile tile(Widget? trailing) => ListTile(
                onLongPress: () => _displayTimestamp(element, states, context),
                onTap: device == null || element.value is! num
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Chart(element),
                        )),
                title: Text(label.title),
                subtitle: _subtitleWithTime(label.subtitle, element),
                trailing: trailing,
              );
          final Widget row;
          if (spec != null) {
            row = InlineControl(
              spec: spec,
              value: start!.value,
              unit: controlUnit(control!),
              busy: element.transitioning,
              enabled: unavailability == null,
              onSend: (value) => _performAction(connectionStatus, context, control, states, value),
              tile: tile,
            );
          } else {
            row = tile(element.transitioning
                ? Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .5 - 12),
                    padding: const EdgeInsets.only(right: 12),
                    child: const DelayedCircularProgressIndicator())
                : switchReading != null
                    ? Switch(
                        value: switchReading == OnOffReading.on,
                        // A group whose members disagree is neither on nor off.
                        thumbIcon: switchReading == OnOffReading.mixed ? const WidgetStatePropertyAll(Icon(Icons.remove)) : null,
                        onChanged: unavailability != null ? null : (_) => _performAction(connectionStatus, context, element, states),
                      )
                    : functionConfig.displayValue(element.value, context) != null
                        ? IconButton(
                            icon: functionConfig.displayValue(element.value, context)!,
                            onPressed: unavailability != null
                                ? null
                                : () => _performAction(
                                      connectionStatus,
                                      context,
                                      element,
                                      states,
                                    ),
                          )
                        : TextButton(
                            onPressed: unavailability != null
                                ? null
                                : () => _performAction(
                                      connectionStatus,
                                      context,
                                      element,
                                      states,
                                    ),
                            child: functionConfig.displayValue(element.value, context) ??
                                Text(formatValueWithUnit(element.value, unit)),
                          ));
          }
          controlWidgets.insert(element.functionId, (rowKey: _rowKey(element), tile: row));
        }
      }

      for (var element in rows.where((element) => element.isControlling && !markedControllingStates.contains(element))) {
        var functionConfig = functionConfigs[element.functionId];
        final label = detailLabel(element, rows, device, states: states, isGroup: isGroup);

        // An input with the role Reading steps from the measured value it feeds,
        // which no longer carries it as its control.
        final start = isReadingInput(element) ? inlineStartValue(element, states, isGroup: isGroup) : null;
        final fed = start == null ? const <DeviceState>[] : readingsOfControl(element, states, isGroup: isGroup);
        final spec = start == null || fed.length != 1 ? null : inlineControlSpec(element, start.value, reading: fed.single);
        if (spec != null) {
          controlWidgets.insert(
            element.functionId,
            (
              rowKey: _rowKey(element),
              tile: InlineControl(
                spec: spec,
                value: start!.value,
                unit: controlUnit(element),
                busy: fed.single.transitioning,
                enabled: unavailability == null,
                onSend: (value) => _performAction(connectionStatus, context, element, states, value),
                tile: (trailing) => ListTile(
                  title: Text(label.title),
                  subtitle: label.subtitle.isEmpty ? null : Text(label.subtitle),
                  trailing: trailing,
                ),
              ),
            ),
          );
          continue;
        }

        controlWidgets.insert(
          element.functionId,
          (
            rowKey: _rowKey(element),
            tile: ListTile(
              title: Text(label.title),
              onTap: device == null || element.value is! num
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Chart(element),
                      )),
              subtitle: label.subtitle.isEmpty ? null : Text(label.subtitle),
              trailing: element.transitioning
                  ? Container(padding: const EdgeInsets.only(right: 12), child: const DelayedCircularProgressIndicator())
                  : IconButton(
                      splashRadius: 25,
                      icon: functionConfig?.displayValue(element.value, context) ?? const Icon(Icons.input),
                      onPressed: unavailability != null
                          ? null
                          : () => _performAction(
                                connectionStatus,
                                context,
                                element,
                                states,
                              ),
                    ),
            ),
          ),
        );
      }

      final cards = <Pair<String, ({Widget tile, String rowKey})>>[
        if (light != null)
          Pair('', (
            rowKey: 'card|light',
            tile: LightCard(
              model: light,
              states: states,
              isGroup: isGroup,
              enabled: unavailability == null,
              onSend: (control, value) => _performAction(connectionStatus, context, control, states, value),
              onTogglePower: () => _performAction(connectionStatus, context, light.power!, states),
            ),
          )),
        for (final climate in climates)
          Pair('', (
            rowKey: 'card|climate|${_rowKey(climate.setpoint)}',
            tile: ClimateCard(
              model: climate,
              states: states,
              isGroup: isGroup,
              enabled: unavailability == null,
              setpointTitle: detailLabel(climate.setpoint, rows, device, states: states, isGroup: isGroup).title,
              thermostat: device != null ? deviceIsThermostat(device) : groupIsThermostats(deviceGroup!),
              onSend: (control, value) => _performAction(connectionStatus, context, control, states, value),
              onOpenMeasured: device == null || climate.measured == null
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (context) => Chart(climate.measured!))),
            ),
          )),
      ];
      final controlList = [...cards, ..._sorted(controlWidgets)];
      final readingList = _sorted(readingWidgets);

      final List<Widget> trailingHeader = [];

      if (connectionStatus == DeviceConnectionStatus.offline) {
        trailingHeader.add(Tooltip(
            message: "Device is offline", triggerMode: TooltipTriggerMode.tap, child: Icon(Icons.error, color: context.appColors.warnInk)));
      }
      if (unavailability == Unavailability.notLocal) {
        trailingHeader.add(Tooltip(
            message: "Not local", triggerMode: TooltipTriggerMode.tap, child: Icon(Icons.lan_outlined, color: context.appColors.warnInk)));
      }
      if (device != null) {
        if (device.network?.localGateways?.isNotEmpty == true) {
          trailingHeader.add(const Tooltip(message: "In local network", triggerMode: TooltipTriggerMode.tap, child: Icon(Icons.lan_outlined)));
        }
        trailingHeader.add(FavorizeButton(widget._device!, null));
      } else {
        if (deviceGroup?.network?.localGateways?.isNotEmpty == true) {
          trailingHeader.add(const Tooltip(message: "In local network", triggerMode: TooltipTriggerMode.tap, child: Icon(Icons.lan_outlined)));
        }
        trailingHeader.add(FavorizeButton(null, widget._group));
      }

      // The app bar already names the entity; the header says what it is.
      final deviceType = device != null ? state.deviceTypes[device.device_type_id] : null;
      final entityImage = device != null
          ? state.deviceClasses[deviceType?.device_class_id]?.imageWidget
          : deviceGroup!.imageWidget;
      final headerTitle = device != null
          ? state.deviceClasses[deviceType?.device_class_id]?.name ?? "Device"
          : devicesLabel(state.visibleDeviceCount(deviceGroup!.device_ids));
      final entitySecondLine = device != null
          ? [
              if (deviceType != null) deviceType.name,
              ...state.locationsForDevice(device.id).map((l) => l.name),
            ].join(" · ")
          : state.devices.map((e) => e.displayName).join(", ");

      final lastMessage = newestTime(rows.where((s) => !s.isControlling).map((s) => s.lastMessageTime));

      return Scaffold(
          floatingActionButton: deviceGroup == null || !DeviceGroupsService.isCreateEditDeleteAvailable()
              ? null
              : FloatingActionButton(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (context) => GroupEditDevices(widget._group!)));
                    await state.searchDevices(
                        DeviceSearchFilter("",
                            deviceGroupIds: [deviceGroup.id],
                            showInactive: state.showsInactiveDevices),
                        true);
                    deviceGroup.prepareStates(true);
                    if (!context.mounted) return;
                    _refresh(context);
                  },
                  backgroundColor: context.appColors.app,
                  child: const Icon(Icons.list),
                ),
          body: Scaffold(
            appBar: appBar.getAppBar(context, appBarActions),
            body: RefreshIndicator(
              onRefresh: () async {
                HapticFeedbackProxy.lightImpact();
                _refresh(context);
              },
              child: Scrollbar(
                child: SectionedListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  leading: [
                    ListTile(
                      // header
                      leading: EntityLeadingIcon(
                        size: 48,
                        fallbackIcon: device != null ? Icons.devices : Icons.devices_other,
                        image: entityImage,
                      ),
                      title: Text(
                        headerTitle,
                        key: const Key('detailPageHeaderTitle'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: entitySecondLine.isEmpty
                          ? null
                          : Text(
                              entitySecondLine,
                              key: const Key('detailPageHeaderSubtitle'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: trailingHeader),
                    ),
                    if (lastMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(left: Spacing.lg, right: Spacing.lg, top: Spacing.xs),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: RelativeTimeTicker(
                            time: lastMessage,
                            builder: (context) => relativeTimeText(
                              relativeTime(lastMessage, now: stateTimeNow()),
                              prefix: "Last message ",
                              key: const Key('detailPageLastMessage'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                    if (controlList.isNotEmpty || readingList.isNotEmpty || deviceGroup != null) const SizedBox(height: Spacing.lg),
                  ],
                  sections: [
                    _section("control", "Control", controlList),
                    _section("readings", "Readings", readingList),
                  ],
                  trailing: [
                    // Prevents FAB overlap; also drawn when
                    // isCreateEditDeleteAvailable() hides that FAB, same as
                    // before this became a grouped surface.
                    if (deviceGroup != null) const SizedBox(height: 72),
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
    final device = widget._device;
    if (device != null) _live = LiveValues.instance.watch(device);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(context));
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      if (!mounted) return;
      _refresh(context);
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    _live?.release();
    super.dispose();
  }

  @override
  void onResumed() => _refresh(context);
}
