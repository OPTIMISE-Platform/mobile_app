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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/services/cache_helper.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../shared/keyed_list.dart';
import 'auth.dart';

class SmartServiceService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;

  static late final Dio? _dio;

  static String baseUrl = '${dotenv.env["API_URL"] ?? 'localhost'}/smart-services/repository';

  static initOptions() async {
    if (_options != null && _dio != null) {
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
    _dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
  }

  static Future<SmartServiceInstance> getInstance(String id) async {
    final String url = "$baseUrl/instances/$id";

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<dynamic> resp;
    try {
      resp = await _dio!.get<dynamic>(url, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceInstance");
    }

    return SmartServiceInstance.fromJson(resp.data);
  }

  static Future<List<SmartServiceInstance>> getInstances(int limit, int offset) async {
    final String url = "$baseUrl/instances";
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = limit.toString();
    queryParameters["offset"] = offset.toString();

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<List<dynamic>?> resp;
    try {
      resp = await _dio!.get<List<dynamic>?>(url, queryParameters: queryParameters, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceInstance");
    }

    final l = (resp.data ?? []) as List;
    return List<SmartServiceInstance>.generate(l.length, (index) => SmartServiceInstance.fromJson(l[index]));
  }

  static Future<void> deleteInstance(String id) async {
    final String url = "$baseUrl/instances/$id";

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    try {
      await dio.delete(url, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    return;
  }

  static Future<SmartServiceInstance> createInstance(
      String releaseId, List<SmartServiceParameter>? parameters, String name, String description) async {
    final String url = "$baseUrl/releases/$releaseId/instances";

    final Map<String, dynamic> body = {
      "name": name,
      "description": description,
      "parameters": parameters,
    };

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final Response<dynamic> resp;
    try {
      resp = await dio.post<dynamic>(url, options: Options(headers: headers), data: json.encode(body));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    return SmartServiceInstance.fromJson(resp.data);
  }

  static Future<SmartServiceInstance> updateInstanceParameters(String instanceId, List<SmartServiceParameter>? parameters,
      {String? releaseId}) async {
    final String url = "$baseUrl/instances/$instanceId/parameters";

    final Map<String, String> queryParameters = {};
    if (releaseId != null) {
      queryParameters["release_id"] = releaseId;
    }

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final Response<dynamic> resp;
    try {
      resp = await dio.put<dynamic>(url, queryParameters: queryParameters, options: Options(headers: headers), data: json.encode(parameters));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    return SmartServiceInstance.fromJson(resp.data);
  }

  static Future<SmartServiceInstance> updateInstanceInfo(String instanceId, String name, String description) async {
    final String url = "$baseUrl/instances/$instanceId/info";
    final Map<String, dynamic> body = {
      "name": name,
      "description": description,
    };

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final Response<dynamic> resp;
    try {
      resp = await dio.put<dynamic>(url, options: Options(headers: headers), data: json.encode(body));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    return SmartServiceInstance.fromJson(resp.data);
  }

  static Future<List<SmartServiceExtendedParameter>> getReleaseParameters(String releaseId) async {
    final String url = "$baseUrl/releases/$releaseId/parameters";

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<List<dynamic>?> resp;
    try {
      resp = await _dio!.get<List<dynamic>?>(url, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceExtendedParameter");
    }

    final l = resp.data ?? [];
    return List<SmartServiceExtendedParameter>.generate(l.length, (index) => SmartServiceExtendedParameter.fromJson(l[index]));
  }

  static Future<List<SmartServiceRelease>> getReleases(int limit, int offset, {bool addUsableFlag = true}) async {
    final String url = "$baseUrl/releases";
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = limit.toString();
    queryParameters["offset"] = offset.toString();
    queryParameters["latest"] = "true";
    if (addUsableFlag) {
      queryParameters["add-usable-flag"] = "true";
    }
    queryParameters["rights"] = "x";

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<List<dynamic>?> resp;
    try {
      resp = await _dio!.get<List<dynamic>?>(url, queryParameters: queryParameters, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceRelease");
    }

    final l = resp.data ?? [];
    return List<SmartServiceRelease>.generate(l.length, (index) => SmartServiceRelease.fromJson(l[index]));
  }

  static Future<SmartServiceRelease> getRelease(String id) async {
    final String url = "$baseUrl/releases/$id";

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<dynamic> resp;
    try {
      resp = await _dio!.get<dynamic>(url, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceRelease");
    }

    return SmartServiceRelease.fromJson(resp.data);
  }

  static Future<List<SmartServiceModule>> getModules({SmartServiceModuleType? type, String? instanceId}) async {
    final String url = "$baseUrl/modules";
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = "0";
    if (type != null) {
      queryParameters["module_type"] = type;
    }
    if (instanceId != null) {
      queryParameters["instance_id"] = instanceId;
    }

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<List<dynamic>?> resp;
    try {
      resp = await _dio!.get<List<dynamic>?>(url, queryParameters: queryParameters, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceModules");
    }

    final l = resp.data ?? [];
    return List<SmartServiceModule>.generate(l.length, (index) => SmartServiceModule.fromJson(l[index]));
  }

  static Future<Pair<List<SmartServiceExtendedParameter>, bool>> prepareUpgrade(SmartServiceInstance oldInstance) async {
    if (oldInstance.new_release_id == null) throw ArgumentError("No Update available");
    final params = await getReleaseParameters(oldInstance.new_release_id!);
    bool newParamsAdded = false;
    for (final param in params) {
      final i = oldInstance.parameters?.indexWhere((e) => e.id == param.id) ?? -1;
      if (i != -1) {
        param.value = oldInstance.parameters![i].value;
        param.value_label = oldInstance.parameters![i].value_label;
      } else {
        newParamsAdded = true;
      }
    }
    return Pair(params, newParamsAdded);
  }
}
