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
import 'package:flutter/widgets.dart';
import 'package:isar_community/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/aspect_ids.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/shared/entity_image.dart';
import 'package:mobile_app/shared/entity_notifier.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';

part 'device_group.g.dart';

@JsonSerializable()
@collection
class DeviceGroup {
  @Index(type: IndexType.hash)
  String id;
  @Index(caseSensitive: false)
  String name;
  String image;
  List<DeviceGroupCriteria>? criteria;
  List<String> device_ids;
  List<Attribute>? attributes;
  String? auto_generated_by_device;

  @JsonKey(includeFromJson: false, includeToJson: false)
  @ignore
  Widget? imageWidget;

  @JsonKey(includeFromJson: false, includeToJson: false)
  @ignore
  final List<DeviceState> states = [];

  // Per-group change signal — see DeviceInstance.stateNotifier.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @ignore
  final EntityNotifier stateNotifier = EntityNotifier();

  void notifyStateChanged() => stateNotifier.notifyChanged();

  @JsonKey(includeFromJson: false, includeToJson: false)
  @ignore
  Network? network;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Id isarId = -1;

  /// Set on a row served from a cache that an app version without aspect lists
  /// may have written: its criteria can show a combination as its first aspect.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @ignore
  bool criteriaMayPredateAspectLists = false;

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  Future<DeviceGroup> initImage() async {
    // Only on success, so a later failed reload does not blank an image that
    // is already on screen.
    final loaded = await loadEntityImage(image, "deviceGroup", id);
    if (loaded != null) imageWidget = loaded;
    return this;
  }

  DeviceGroup(this.id, this.name, this.criteria, this.image, this.device_ids, this.attributes) {
    isarId = fastHash(id);
    final networkIndex = AppState()
        .networks
        .indexWhere((n) => device_ids.every((String groupDeviceId) => (n.device_ids ?? <String>[]).contains(groupDeviceId.substring(0, 57))));
    if (networkIndex != -1) {
      network = AppState().networks[networkIndex];
    }
  }

  factory DeviceGroup.fromJson(Map<String, dynamic> json) {
    final c = _$DeviceGroupFromJson(json);
    return c;
  }

  Map<String, dynamic> toJson() => _$DeviceGroupToJson(this);

  prepareStates([bool? force]) {
    if (states.isNotEmpty && force != true) {
      // only once
      return;
    }
    states.clear();
    for (final criterion in criteria ?? []) {
      final f = AppState().platformFunctions[criterion.function_id];
      if (f == null) {
        _logger.e("Function is unknown: ${criterion.function_id}");
        continue;
      }
      // A combination row [a, b] demands one variable carrying both aspects, so
      // it is its own value next to the single rows [a] and [b].
      final aspectIds = criterion.effectiveAspects;
      final aspectKey = aspectIdsKey(aspectIds);
      if (states.indexWhere((element) =>
              element.functionId == criterion.function_id &&
              element.aspectKey == aspectKey &&
              element.deviceClassId == criterion.device_class_id) ==
          -1) {
        final state = DeviceState(null, null, null, criterion.function_id, null,
            criterion.function_id.startsWith(controllingFunctionPrefix), id, criterion.device_class_id, null, null, null,
            aspectIds: aspectIds);
        state.deviceGroup = this;
        states.add(state);
      }
    }
  }

  /// [states] without those a more specific state of the same function, kind
  /// and device class covers. device-repository adds every subset and ancestor
  /// of a variable's aspects as a criterion of its own, so a group of lamps on
  /// [device, lighting] also gets [device] and [lighting], which read the same
  /// variable. A state without aspects is kept, except a control on a device
  /// class next to controls of its function on aspects: it acts on all of them
  /// at once.
  List<DeviceState> get shownStates {
    final aspects = AppState().aspects.values;
    bool coveredClassControl(DeviceState s) =>
        s.isControlling &&
        (s.deviceClassId ?? "").isNotEmpty &&
        states.any((o) => o.isControlling && o.functionId == s.functionId && o.aspectIds.isNotEmpty);
    bool covers(DeviceState specific, DeviceState general) =>
        specific.functionId == general.functionId &&
        specific.isControlling == general.isControlling &&
        specific.deviceClassId == general.deviceClassId &&
        specific.aspectKey != general.aspectKey &&
        aspectsCover(aspects, general.aspectIds, specific.aspectIds) &&
        !aspectsCover(aspects, specific.aspectIds, general.aspectIds);
    return states
        .where((s) => s.aspectIds.isEmpty ? !coveredClassControl(s) : !states.any((o) => covers(o, s)))
        .toList(growable: false);
  }

  List<CommandCallback> getStateFillFunctions([List<String>? limitToFunctionIds]) {
    final List<CommandCallback> result = [];
    for (var i = 0; i < states.length; i++) {
      if (limitToFunctionIds != null && !limitToFunctionIds.contains(states[i].functionId)) {
        continue;
      }
      if (states[i].isControlling) {
        continue;
      }
      result.add(CommandCallback(states[i].toCommand(null, this), (value) {
        if (value is List && value.length == 1) {
          states[i].value = value[0];
        } else {
          states[i].value = value;
        }
        states[i].transitioning = false;
      }));
    }
    return result;
  }

  // Mirror of the per-account favorite list (Settings.getFavoriteGroupIds) -
  // see DeviceInstance.favorite.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @Index()
  bool favorite = false;
}

@JsonSerializable()
@embedded
class DeviceGroupCriteria {
  String aspect_id = "", device_class_id = "", function_id = "", interaction = "";

  /// Replaces the deprecated [aspect_id]; several aspects demand one variable
  /// carrying all of them. Sent back exactly as read, absent when it was.
  @JsonKey(includeIfNull: false)
  List<String>? aspect_ids;

  DeviceGroupCriteria();

  /// The aspects this criterion demands, sorted; see [effectiveAspectIds].
  @ignore
  List<String> get effectiveAspects => effectiveAspectIds(aspect_id, aspect_ids);

  factory DeviceGroupCriteria.fromJson(Map<String, dynamic> json) => _$DeviceGroupCriteriaFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceGroupCriteriaToJson(this);
}

class DeviceInstanceWithRemovesCriteria {
  bool removesCriteria;
  DeviceInstance device;

  DeviceInstanceWithRemovesCriteria(this.device, this.removesCriteria);
}

class DeviceGroupHelperResponse {
  List<DeviceGroupCriteria> criteria;
  List<DeviceInstanceWithRemovesCriteria> devices;

  DeviceGroupHelperResponse(this.criteria, this.devices);
}
