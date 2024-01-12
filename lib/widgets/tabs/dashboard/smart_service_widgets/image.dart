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
import 'package:mobile_app/shared/api_available_interceptor.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';

import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/shared/base64_response_decoder.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';

class SmSeImage extends SmSeRequest {
  @override
  setPreview(bool enabled) => null;

  bool _cachable = false;
  Widget imageWidget = const SizedBox.shrink();
  CacheOptions? _options;

  @override
  double height = 1;

  @override
  double width = 1;

  @override
  Future<void> configure(data) async {
    super.configure(data);
    if (data is! Map<String, dynamic> || data["cachable"] == null || data["height"] == null || data["width"] == null) return;
    _cachable = data["cachable"] as bool;
    height = data["height"] is int ? (data["height"] as int).toDouble() :  data["height"] as double;
    width = data["width"] is int ? (data["width"] as int).toDouble() :  data["width"] as double;
    await _loadImage();
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    return imageWidget;
  }

  @override
  Future<void> refreshInternal() async {
    if (_cachable) return;
    await _loadImage();
  }

  initOptions() async {
    if (_options != null) {
      return;
    }

    _options = CacheOptions(
      store: HiveCacheStore(await CacheHelper.getCacheFile()),
      policy: _cachable ? CachePolicy.forceCache : CachePolicy.request,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 365),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
  }

  _loadImage() async {
    await initOptions();
    final dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();

    Map<String, String> headers = {};
    if (request.need_token) {
      headers = await Auth().getHeaders();
    }

    final resp = await dio.request(request.url,
        data: request.body, options: Options(method: request.method, headers: headers, responseDecoder: DecodeIntoBase64()));

    if (resp.statusCode == null || resp.statusCode! > 304) {
      return;
    }
    if (resp.data == null) {
      return;
    }
    final b64 = const Base64Decoder().convert(resp.data!);
    imageWidget = Image.memory(b64);
  }
}
