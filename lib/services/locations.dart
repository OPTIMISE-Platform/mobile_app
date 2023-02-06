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
import 'package:isar/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../shared/http_client_adapter.dart';
import '../shared/isar.dart';
import 'auth.dart';

class LocationService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;
  static late Dio _dio;

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
    _dio = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..httpClientAdapter = AppHttpClientAdapter();
  }

  static Future<List<Future<Location>>> getLocations({bool forceBackend = false}) async {
    if (!forceBackend && isar != null) {
      return (await isar!.locations.where().sortByName().findAll()).map((e) => e.initImage()).toList();
    }

    String uri = '${Settings.getApiUrl() ?? 'localhost'}/permissions/query/v3/resources/locations';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = "9999";

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<List<dynamic>?> resp;
    try {
      resp = await _dio.get<List<dynamic>?>(uri, queryParameters: queryParameters, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device locations");
    }

    final l = resp.data ?? [];
    final locations = List<Location>.generate(l.length, (index) => Location.fromJson(l[index]));
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.putAll(locations);
      });
    }
    return locations.map((e) => e.initImage()).toList(growable: false);
  }

  static Future<Location> saveLocation(Location location) async {
    String uri = '${Settings.getApiUrl() ?? 'localhost'}/device-manager/locations/${location.id}';

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<dynamic> resp;
    try {
      resp = await _dio.put<dynamic>(uri, options: Options(headers: headers), data: location.toJson());
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }

    final savedLocation = Location.fromJson(resp.data);
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.put(savedLocation);
      });
    }
    return savedLocation.initImage();
  }

  static Future<Location> createLocation(String name) async {
    String uri = '${Settings.getApiUrl() ?? 'localhost'}/device-manager/locations/';

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>(uri, options: Options(headers: headers), data: Location("", name, "", "", [], []).toJson());
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    final savedLocation = Location.fromJson(resp.data);
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.put(savedLocation);
      });
    }
    return savedLocation.initImage();
  }

  static Future<void> deleteLocation(String id) async {
    String uri = '${Settings.getApiUrl() ?? 'localhost'}/device-manager/locations/$id';

    final headers = await Auth().getHeaders();
    await initOptions();
    try {
      await _dio.delete(uri, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.delete(fastHash(id));
      });
    }

    return;
  }
}
