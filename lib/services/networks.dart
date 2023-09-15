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
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/network.dart';
import '../shared/http_client_adapter.dart';
import '../shared/isar.dart';
import 'api_available.dart';
import 'auth.dart';

class NetworksService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;
  static     String uri = '${Settings.getApiUrl() ?? 'localhost'}/permissions/query/v3/resources/hubs?limit=9999';


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

  static Future<List<Network>> getNetworks([List<String>? ids, bool forceBackend = false]) async {
    if (!forceBackend && isar != null) {
      return isar!.networks.where().sortByName().findAll();
    }


    final Map<String, String> queryParameters = {};
    if (ids != null && ids.isNotEmpty) {
      queryParameters["ids"] = ids.join(",");
    }

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();
    final Response<List<dynamic>?> resp;
    try {
      resp = await dio.get<List<dynamic>?>(uri, queryParameters: queryParameters, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device classes");
    }

    final l = resp.data ?? [];
    final networks = List<Network>.generate(l.length, (index) => Network.fromJson(l[index]));
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.networks.putAll(networks);
      });
    }
    return networks;
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);

}
