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
import 'package:flutter/cupertino.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/util/base64_response_decoder.dart';

part 'device_class.g.dart';

const cachSubdir = "/img";

@JsonSerializable()
class DeviceClass {
  String id, image, name;

  @JsonKey(ignore: true)
  Widget? imageWidget;

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

  _initImage() async {
    if (image.isEmpty) {
      return;
    }
    await initOptions();
    final dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.get<String?>(image,
        options: Options(responseDecoder: DecodeIntoBase64()));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      _logger.e("Could not load deviceClass image: Response code was: " +
          resp.statusCode.toString() +
          ". ID: " +
          id +
          ", URL: " +
          image);
      return;
    }
    if (resp.data == null) {
      _logger.e("Could not load deviceClass image: response was null. ID: " +
          id +
          ", URL: " +
          image);
      return;
    }
    final b64 = const Base64Decoder().convert(resp.data!);
    imageWidget = Image.memory(b64);
  }

  DeviceClass(this.id, this.name, this.image);

  factory DeviceClass.fromJson(Map<String, dynamic> json) {
    final c = _$DeviceClassFromJson(json);
    c._initImage();
    return c;
  }

  Map<String, dynamic> toJson() => _$DeviceClassToJson(this);
}
