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
import 'package:flutter/widgets.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';

import '../services/cache_helper.dart';
import '../shared/base64_response_decoder.dart';
import '../shared/http_client_adapter.dart';

part 'location.g.dart';

@JsonSerializable()
class Location {
  String id, name, description, image;
  List<String> device_ids, device_group_ids;

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

  Future<Location> initImage() async {
    if (image.isEmpty) {
      return this;
    }
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!))..httpClientAdapter = AppHttpClientAdapter();
    final resp = await dio.get<String?>(image, options: Options(responseDecoder: DecodeIntoBase64()));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      _logger.e("Could not load Location image: Response code was: ${resp.statusCode}. ID: $id, URL: $image");
      return this;
    }
    if (resp.data == null) {
      _logger.e("Could not load Location image: response was null. ID: $id, URL: $image");
      return this;
    }
    final b64 = const Base64Decoder().convert(resp.data!);
    imageWidget = Image.memory(b64);
    return this;
  }


  Location(this.id, this.name, this.description, this.image, this.device_ids, this.device_group_ids);
  factory Location.fromJson(Map<String, dynamic> json) => _$LocationFromJson(json);
  Map<String, dynamic> toJson() => _$LocationToJson(this);
}
