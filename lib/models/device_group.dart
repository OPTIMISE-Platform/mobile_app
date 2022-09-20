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
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/function.dart';

import '../services/cache_helper.dart';
import '../shared/base64_response_decoder.dart';
import 'attribute.dart';
import 'device_instance.dart';
import 'device_state.dart';

part 'device_group.g.dart';

@JsonSerializable()
class DeviceGroup {
  String id, name, image;
  List<DeviceGroupCriteria> criteria;
  List<String> device_ids;
  List<Attribute>? attributes;

  @JsonKey(ignore: true)
  Widget? imageWidget;

  @JsonKey(ignore: true)
  final List<DeviceState> states = [];

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
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!))..httpClientAdapter = Http2Adapter(AppState.connectionManager);
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

  DeviceGroup(this.id, this.name, this.criteria, this.image, this.device_ids, this.attributes);

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
    for (final criterion in criteria) {
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
        states.add(DeviceState(null, null, null, criterion.function_id, criterion.aspect_id,
            criterion.function_id.startsWith(controllingFunctionPrefix), id, criterion.device_class_id, null, null));
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
      result.add(CommandCallback(states[i].toCommand(), (value) {
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

  bool get favorite {
    final i = attributes?.indexWhere((element) => element.key == attributeFavorite && element.origin == appOrigin);
    return i != null && i != -1;
  }

  setFavorite(bool val) {
    if (val) {
      attributes ??= [];
      attributes!.add(Attribute(attributeFavorite, "true", appOrigin));
    } else {
      final i = attributes?.indexWhere((element) => element.key == attributeFavorite);
      if (i != null && i != -1) {
        attributes!.removeAt(i);
      }
    }
  }

  toggleFavorite() {
    setFavorite(!favorite);
  }
}

@JsonSerializable()
class DeviceGroupCriteria {
  String aspect_id, device_class_id, function_id, interaction;

  DeviceGroupCriteria(this.aspect_id, this.device_class_id, this.function_id, this.interaction);

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
