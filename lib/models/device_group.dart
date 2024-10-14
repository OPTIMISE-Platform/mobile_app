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

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/shared/base64_response_decoder.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
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

  @JsonKey(ignore: true)
  @ignore
  Widget? imageWidget;

  @JsonKey(ignore: true)
  @ignore
  final List<DeviceState> states = [];

  @JsonKey(ignore: true)
  @ignore
  Network? network;

  @JsonKey(ignore: true)
  Id isarId = -1;

  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  static CacheOptions? _options;

  static initOptions() async {
    if (_options != null) {
      return;
    }

    _options = CacheOptions(
      store: HiveCacheStore(await CacheHelper.getCacheFile()),
      policy: CachePolicy.forceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 365),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
  }

  Future<DeviceGroup> initImage() async {
    if (image.isEmpty) {
      return this;
    }
    await initOptions();
    final dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();
    final resp = await dio.get<String?>(image, options: Options(responseDecoder: DecodeIntoBase64()));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      _logger.e("Could not load deviceGroup image: Response code was: ${resp.statusCode}. ID: $id, URL: $image");
      return this;
    }
    if (resp.data == null) {
      _logger.e("Could not load deviceGroup image: response was null. ID: $id, URL: $image");
      return this;
    }
    final b64 = const Base64Decoder().convert(resp.data!);
    imageWidget = Image.memory(b64);
    return this;
  }

  DeviceGroup(this.id, this.name, this.criteria, this.image, this.device_ids, this.attributes) {
    isarId = fastHash(id);
    final networkIndex = AppState()
        .networks
        .indexWhere((n) => device_ids.every((String groupDeviceId) => (n.device_ids ?? <String>[]).contains(groupDeviceId.substring(0, 57)) as bool));
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
      final f = AppState().nestedFunctions[criterion.function_id];
      if (f == null) {
        _logger.e("Function is unknown: ${criterion.function_id}");
        continue;
      }
      if (states.indexWhere((element) =>
              element.functionId == criterion.function_id &&
              element.aspectId == criterion.aspect_id &&
              element.deviceClassId == criterion.device_class_id) ==
          -1) {
        final state = DeviceState(null, null, null, criterion.function_id, criterion.aspect_id,
            criterion.function_id.startsWith(controllingFunctionPrefix), id, criterion.device_class_id, null, null, null);
        state.deviceGroup = this;
        states.add(state);
      }
    }
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

  Future<bool> isFavorite() async {
    final group =
    await isar!.deviceGroups.where().idEqualTo(id).findFirst();
    return group?.favorite ?? false;
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @Index()
  bool favorite = false;

  /*
  bool get favorite {
    final i = attributes?.indexWhere((element) => element.key == attributeFavorite && element.origin == appOrigin);
    return i != null && i != -1;
  }*/

  setFavorite(bool val) {
    if (val) {
      attributes ??= [];
      try {
        attributes!.add(Attribute.New(attributeFavorite, "true", appOrigin));
      } on UnsupportedError {
        final List<Attribute> tmp = [];
        tmp.addAll(attributes!);
        tmp.add(Attribute.New(attributeFavorite, "true", appOrigin));
        attributes = tmp;
      }
    } else {
      final i = attributes?.indexWhere((element) => element.key == attributeFavorite);
      if (i != null && i != -1) {
        try {
          attributes!.removeAt(i);
        } on UnsupportedError {
          final List<Attribute> tmp = [];
          tmp.addAll(attributes!);
          tmp.removeAt(i);
          attributes = tmp;
        }
      }
    }
  }

  toggleFavorite() {
    setFavorite(!favorite);
  }
}

@JsonSerializable()
@embedded
class DeviceGroupCriteria {
  String aspect_id = "", device_class_id = "", function_id = "", interaction = "";

  DeviceGroupCriteria();

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
