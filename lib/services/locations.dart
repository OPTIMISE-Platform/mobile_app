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


import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/services/cache_helper.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import 'auth.dart';

class LocationService {
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
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
  }

  static Future<List<Future<Location>>> getLocations() async {
    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/permissions/query/v3/resources/locations';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = "9999";

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.get<List<dynamic>?>(uri,
        queryParameters: queryParameters, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device locations");
    }

    final l = resp.data ?? [];
    final locations = List<Location>.generate(
        l.length, (index) => Location.fromJson(l[index]));
    return locations.map((e) => e.initImage()).toList(growable: false);
  }

  static Future<Location> saveLocation(Location location) async {
    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/device-manager/locations/${location.id}';

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.put<dynamic>(uri, options: Options(headers: headers), data: location.toJson());
    if (resp.statusCode == null || resp.statusCode! > 299) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return Location.fromJson(resp.data).initImage();
  }

  static Future<Location> createLocation(String name) async {
    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/device-manager/locations/';

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.post<dynamic>(uri, options: Options(headers: headers), data: Location("", name, "", "", [], []).toJson());
    if (resp.statusCode == null || resp.statusCode! > 299) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return Location.fromJson(resp.data).initImage();
  }

  static Future<void> deleteLocation(String id) async {
    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/device-manager/locations/$id';

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.delete(uri, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 299) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return;
  }
}
