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

import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/models/aspect_ids.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/models/service_group.dart';

import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_type.dart';

part 'device_state.g.dart';

@JsonSerializable()
class DeviceState {
  dynamic value;
  String functionId;
  bool isControlling, transitioning = false;

  @JsonKey(includeFromJson: false, includeToJson: false)
  DeviceInstance? _deviceInstance;
  @JsonKey(includeFromJson: false, includeToJson: false)
  DeviceGroup? _deviceGroup;

  DeviceInstance? get deviceInstance {
    return _deviceInstance;
  }

  set deviceInstance(DeviceInstance? instance) {
    _deviceInstance = instance;
    name = deviceInstance?.display_name;
  }

  DeviceGroup? get deviceGroup {
    return _deviceGroup;
  }

  set deviceGroup(DeviceGroup? instance) {
    _deviceGroup = instance;
    name = deviceGroup?.name;
  }

  String? serviceId, serviceGroupKey, groupId, deviceClassId, deviceId, path, name, serviceGroupName;

  /// The aspects of the content variable or criterion, sorted; empty when it
  /// names none.
  final List<String> aspectIds;

  /// The alphabetically first of [aspectIds], what the deprecated single
  /// `aspect_id` carries.
  String? get aspectId => aspectIds.isEmpty ? null : aspectIds.first;

  /// Identifies [aspectIds] as a set.
  String get aspectKey => aspectIdsKey(aspectIds);

  /// [aspectId] is used only when [aspectIds] is null or empty, which is the
  /// case for entries written before aspect lists existed.
  DeviceState(this.value, this.serviceId, this.serviceGroupKey, this.functionId, String? aspectId, this.isControlling, this.groupId, this.deviceClassId,
      this.deviceId, this.path, this.serviceGroupName, {List<String>? aspectIds})
      : aspectIds = List.unmodifiable(effectiveAspectIds(aspectId, aspectIds)) {
    name = deviceInstance?.display_name ?? deviceGroup?.name;
  }

  factory DeviceState.fromJson(Map<String, dynamic> json) => _$DeviceStateFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceStateToJson(this);

  DeviceCommand toCommand([dynamic value, DeviceGroup? deviceGroup]) {
    final command = DeviceCommand(functionId, deviceId, serviceId, aspectId, groupId, deviceClassId, value,
        Settings.getFunctionPreferredCharacteristicId(functionId), aspectIds.isEmpty ? null : [...aspectIds]);
    command.deviceInstance = deviceInstance;
    command.deviceGroup = deviceGroup ?? this.deviceGroup;
    return command;
  }

  /// The controlling states of [controllingFunctionId] in [states] that act on
  /// this measurement: same service group, paired by [matchAspects].
  List<DeviceState> controlsFor(Iterable<DeviceState> states, String controllingFunctionId) => matchAspects(
      states.where((s) => s.isControlling && s.functionId == controllingFunctionId && s.serviceGroupKey == serviceGroupKey),
      aspectIds);

  /// The [candidates] that belong to a state on [aspectIds], in tiers: all with
  /// an equal aspect set; else the one whose non-empty set is a subset
  /// (output [a, b], input [a]) if it is unique; else the first with the same
  /// first aspect, the one state that first aspect stood for before aspect
  /// lists. Without aspects only candidates without aspects match.
  static List<DeviceState> matchAspects(Iterable<DeviceState> candidates, List<String> aspectIds) {
    final key = aspectIdsKey(aspectIds);
    final exact = candidates.where((s) => s.aspectKey == key).toList(growable: false);
    if (exact.isNotEmpty || aspectIds.isEmpty) return exact;
    final measured = aspectIds.toSet();
    final subsets =
        candidates.where((s) => s.aspectIds.isNotEmpty && measured.containsAll(s.aspectIds)).toList(growable: false);
    if (subsets.length == 1) return subsets;
    return candidates.where((s) => s.aspectId == aspectIds.first).take(1).toList(growable: false);
  }

  /// The state a persisted reference means among [candidates], which already
  /// agree with it on everything but the aspects. A reference with
  /// [aspectIds] needs the same set. One written before aspect lists carries
  /// only [aspectId]: it means the state on exactly that aspect if there is
  /// one, since that asks the backend what the old reference asked, and
  /// otherwise the single candidate whose aspects contain it; several such
  /// candidates are ambiguous and match nothing.
  static DeviceState? resolveAspects(Iterable<DeviceState> candidates, String? aspectId, List<String>? aspectIds) {
    final key = aspectIdsKey(aspectIds != null ? ([...aspectIds]..sort()) : effectiveAspectIds(aspectId, null));
    final exact = candidates.where((s) => s.aspectKey == key).toList(growable: false);
    if (exact.isNotEmpty || aspectIds != null) {
      return exact.length == 1 ? exact.first : null;
    }
    final containing = candidates.where((s) => s.aspectIds.contains(aspectId)).toList(growable: false);
    return containing.length == 1 ? containing.first : null;
  }
}

class StateHelper {
  static final Map<String, List<DeviceState>> _states = {};

  static List<DeviceState> getStates(DeviceType deviceType, DeviceInstance device) {
    var template = _states[deviceType.id];
    if (template == null) {
      final List<DeviceState> states = [];
      for (final service in deviceType.services) {
        final serviceGroupName =
            deviceType.service_groups?.firstWhere((e) => e.key == service.service_group_key, orElse: () => ServiceGroup("", "", "")).name;
        for (final output in service.outputs ?? []) {
          _addStateFromContentVariable(service, output.content_variable, false, "", states, device, serviceGroupName);
        }

        for (final input in service.inputs ?? []) {
          _addStateFromContentVariable(service, input.content_variable, true, "", states, device, serviceGroupName);
        }
      }
      _states[deviceType.id] = states;
      template = states;
    }
    // Always return copies, also on the miss path that just built the
    // template: returning the cached objects themselves let the first device's
    // live values and binding leak into every later device of the same type.
    final states = template;
    return List<DeviceState>.generate(states.length, (i) {
      final state = DeviceState(null, states[i].serviceId, states[i].serviceGroupKey, states[i].functionId, null,
          states[i].isControlling, null, null, device.id, states[i].path, states[i].serviceGroupName,
          aspectIds: states[i].aspectIds);
      state.deviceInstance = device;
      return state;
    });
  }

  static _addStateFromContentVariable(Service service, ContentVariable contentVariable, bool isInput, String parentPath, List<DeviceState> states,
      DeviceInstance device, String? serviceGroupName) async {
    final path = parentPath + (parentPath.isEmpty ? "" : ".") + (contentVariable.name ?? "");
    if (contentVariable.function_id != null) {
      final state = DeviceState(null, service.id, service.service_group_key, contentVariable.function_id!, null, isInput, null,
          null, device.id, path, serviceGroupName, aspectIds: contentVariable.effectiveAspects);
      state.deviceInstance = device;
      // Keyed on the whole aspect set: outputs [air, inside] and [air, outside]
      // share their first aspect and are still two values.
      final idx = states.indexWhere((element) => element.serviceGroupKey == service.service_group_key
          && element.functionId == contentVariable.function_id!
          && element.aspectKey == state.aspectKey
          && element.isControlling == isInput);
      if (idx == -1) {
        states.add(state);
      }
    }
    contentVariable.sub_content_variables
        ?.forEach((element) => _addStateFromContentVariable(service, element, isInput, path, states, device, serviceGroupName));
  }
}
