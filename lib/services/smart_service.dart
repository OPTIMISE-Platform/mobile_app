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
import '../models/content_variable.dart';
import 'auth.dart';

class SmartServiceService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;

  static late final Dio? _dio;

  static String baseUrl = (dotenv.env["API_URL"] ?? 'localhost') + '/smart-services/repository';

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

  static Future<List<SmartServiceInstance>> getInstances(int limit, int offset) async {
    /* TODO return [
      SmartServiceInstance(
          "dummy desc",
          // TODO
          "design_id",
          "id-0",
          "complete",
          "release_id",
          "user_id",
          null,
          true,
          [
            SmartServiceParameter("id-0", "differen"),
            SmartServiceParameter(
              "id-1",
              3,
            ),
            SmartServiceParameter("id-2", 1337),
            SmartServiceParameter("id-3", 0.4),
            SmartServiceParameter("id-4", <dynamic>[0, 1]),
            SmartServiceParameter("id-5", <dynamic>[0, 1]),
            SmartServiceParameter(
              "id-6",
              null,
            ),
            SmartServiceParameter("id-7", <dynamic>[true, false]),
            SmartServiceParameter(
              "id-8",
              false,
            ),
            SmartServiceParameter(
              "id-9",
              "value-a",
            ),
            SmartServiceParameter("id-10", "value-b")
          ]),
      SmartServiceInstance("dummy desc", "design_id", "id-0", "not ready", "release_id", "user_id", null, false, null),
      SmartServiceInstance("dummy desc", "design_id", "id-0", "incomplete delete", "release_id", "user_id", "incomplete delete", false, null)
    ]; */

    final String url = baseUrl + "/instances";
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = limit.toString();
    queryParameters["offset"] = offset.toString();

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.get<List<dynamic>?>(url, queryParameters: queryParameters, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceInstance");
    }

    final l = (resp.data ?? []) as List;
    return List<SmartServiceInstance>.generate(l.length, (index) => SmartServiceInstance.fromJson(l[index]));
  }

  static Future<void> deleteInstance(String id) async {
    final String url = baseUrl + "/instances/" + id;

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.delete(url, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 299) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return;
  }

  static Future<void> createInstance(String releaseId, List<SmartServiceParameter>? parameters, String name, String description) async {
    final String url = baseUrl + "/releases/" + releaseId + "/instances";

    final Map<String, dynamic> body = {
      "name": name,
      "description": description,
      "parameters": parameters,
    };

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.post<dynamic>(url, options: Options(headers: headers), data: json.encode(body));
    if (resp.statusCode == null || resp.statusCode! > 299) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return;
  }

  static Future<SmartServiceInstance> updateInstanceParameters(String instanceId, List<SmartServiceParameter>? parameters) async {
    final String url = baseUrl + "/instances/" + instanceId + "/parameters";

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.put<dynamic>(url, options: Options(headers: headers), data: json.encode(parameters));
    if (resp.statusCode == null || resp.statusCode! > 299) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return SmartServiceInstance.fromJson(resp.data);
  }

  static Future<SmartServiceInstance> updateInstanceInfo(String instanceId, String name, String description) async {
    final String url = baseUrl + "/instances/" + instanceId + "/info";
    final Map<String, dynamic> body = {
      "name": name,
      "description": description,
    };

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.put<dynamic>(url, options: Options(headers: headers), data: json.encode(body));
    if (resp.statusCode == null || resp.statusCode! > 299) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return SmartServiceInstance.fromJson(resp.data);
  }

  static Future<List<SmartServiceExtendedParameter>> getReleaseParameters(String releaseId) async {
    /* TODO return [

      SmartServiceExtendedParameter("id-0", "label", "str-free", "default_value", "default_value", false, null, ContentVariable.STRING),
      SmartServiceExtendedParameter("id-1", "label", "int-free", 1, 1, false, null, ContentVariable.INTEGER),
      SmartServiceExtendedParameter(
          "id-2",
          "super long label i have no idea why anyone would need that much space for a label",
          "description which is just very long and contains a lot of very important information like what this actually does and how you should configure all these awesome options which you really need to do right? no, because this service isnt just a smart service its actualöly a super smart service. its the result of 100 year long deep learning models that will improve your life and totally will get you laid daily",
          null,
          null,
          false,
          null,
          ContentVariable.INTEGER),
      SmartServiceExtendedParameter("id-3", "label", "float-free", 0.4, 0.4, false, null, ContentVariable.FLOAT),
      SmartServiceExtendedParameter(
          "id-4",
          "super long label i have no idea why anyone would need that much space for a label",
          "description which is just very long and contains a lot of very important information like what this actually does and how you should configure all these awesome options which you really need to do right? no, because this service isnt just a smart service its actualöly a super smart service. its the result of 100 year long deep learning models that will improve your life and totally will get you laid daily",
          <dynamic>[0, 1],
          <dynamic>[0, 1],
          true,
          null,
          ContentVariable.INTEGER),
      SmartServiceExtendedParameter("id-5", "label", "float-free-many", <dynamic>[0, 1], <dynamic>[0, 1], true, null, ContentVariable.FLOAT),
      SmartServiceExtendedParameter(
          "id-6",
          "label",
          "str-choose many",
          null,
          "1",
          true,
          [
            SmartServiceParameterOption("", "a", "value-a"),
            SmartServiceParameterOption("", "b", "value-b"),
            SmartServiceParameterOption("", "c", "value-c"),
          ],
          ContentVariable.STRING),
      SmartServiceExtendedParameter(
          "id-7", "label", "bool-free-many", <dynamic>[false, true, false], <dynamic>[false, true, false], true, null, ContentVariable.BOOLEAN),
      SmartServiceExtendedParameter("id-8", "label", "bool-free", false, false, false, null, ContentVariable.BOOLEAN),
      SmartServiceExtendedParameter(
          "id-9",
          "label",
          "str-choose one",
          null,
          null,
          false,
          [
            SmartServiceParameterOption("", "a", "value-a"),
            SmartServiceParameterOption("", "b", "value-b"),
            SmartServiceParameterOption("", "c", "value-c"),
          ],
          ContentVariable.STRING),
      SmartServiceExtendedParameter(
          "id-10",
          "label",
          "str-choose one, default a",
          "value-a",
          "value-a",
          false,
          [
            SmartServiceParameterOption("", "a", "value-a"),
            SmartServiceParameterOption("", "b", "value-b"),
            SmartServiceParameterOption("", "c", "value-c"),
          ],
          ContentVariable.STRING),
    ]; */
    final String url = baseUrl + "/releases/" + releaseId + "/parameters";

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.get<List<dynamic>?>(url, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceExtendedParameter");
    }

    final l = resp.data ?? [];
    return List<SmartServiceExtendedParameter>.generate(l.length, (index) => SmartServiceExtendedParameter.fromJson(l[index]));
  }

  static Future<List<SmartServiceRelease>> getReleases(int limit, int offset) async {
    /* TODO return [
      SmartServiceRelease("1970-01-01T00:00:00Z", "daily", "design_id", "id", "kaputt release", "error"),
      SmartServiceRelease(
          "2223-01-01T00:00:00Z",
          "description which is just very long and contains a lot of very important information like what this actually does and how you should configure all these awesome options which you really need to do right? no, because this service isnt just a smart service its actualöly a super smart service. its the result of 100 year long deep learning models that will improve your life and totally will get you laid daily",
          "design_id",
          "id",
          "release name",
          null)
    ]; */

    final String url = baseUrl + "/releases";
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = limit.toString();
    queryParameters["offset"] = offset.toString();

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.get<List<dynamic>?>(url, queryParameters: queryParameters, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceRelease");
    }

    final l = resp.data ?? [];
    return List<SmartServiceRelease>.generate(l.length, (index) => SmartServiceRelease.fromJson(l[index]));
  }

  static Future<SmartServiceRelease> getRelease(String id) async {
    /* TODO return SmartServiceRelease(
        "2223-01-01T00:00:00Z",
        "description which is just very long and contains a lot of very important information like what this actually does and how you should configure all these awesome options which you really need to do right? no, because this service isnt just a smart service its actualöly a super smart service. its the result of 100 year long deep learning models that will improve your life and totally will get you laid daily",
        "design_id",
        "id",
        "release name",
        null); */

    final String url = baseUrl + "/releases/" + id;

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.get<dynamic>(url, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached SmartServiceRelease");
    }

    return SmartServiceRelease.fromJson(resp.data);
  }
}
