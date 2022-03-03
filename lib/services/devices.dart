import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_permsearch.dart';
import 'package:mobile_app/services/cache_helper.dart';

import 'auth.dart';

class DevicesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );



  static CacheOptions? options;

  static initOptions() async {
    if (options != null) {
      return;
    }

    String? dir = await CacheHelper.getCacheDir();

    options = CacheOptions(
      store: HiveCacheStore(dir != null ? dir + '/cache.box' : null),
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      allowPostMethod: true,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
  }

  static Future<List<DevicePermSearch>> getDevices(BuildContext context,
      int limit, int offset, String search, List<String>? byDeviceTypes) async {
    _logger.v("Devices '" +
        search +
        "' " +
        offset.toString() +
        "-" +
        (offset + limit).toString());

    final uri = (dotenv.env["API_URL"] ?? 'localhost') + '/permissions/query/v3/query';
    final body = <String, dynamic>{
      "resource": "devices",
      "find": {
        "limit": limit,
        "offset": offset,
        "sortBy": "name.asc",
        "search": search,
      }
    };
    if (byDeviceTypes != null && byDeviceTypes.length > 0) {
      body["filter"] = {
        "condition": {
          "feature": "features.device_type_id",
          "operation": "any_value_in_feature",
          "value": byDeviceTypes,
        }
      };
    }

    final encoded = json.encode(body);

    final headers = await Auth.getHeaders(context);
    await initOptions();
    final dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: options!));
    final resp = await dio.post<List<dynamic>?>(uri, options: Options(headers: headers), data: encoded);


    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw "Unexpected status code " + resp.statusCode.toString();
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached devices");
    }

    final l = resp.data ?? [];
    return List<DevicePermSearch>.generate(
        l.length, (index) => DevicePermSearch.fromJson(l[index]));
  }

  static Future<int> getTotalDevices(
      BuildContext context, String search) async {
    String uri = (dotenv.env["API_URL"] ?? 'localhost') +
        '/permissions/query/v3/total/devices';

    final Map<String, String> queryParameters = {};
    if (search.isNotEmpty) {
      queryParameters["search"] = search;
    }
    final headers = await Auth.getHeaders(context);
    await initOptions();
    final dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: options!));
    final resp = await dio.get<int>(uri, options: Options(headers: headers), queryParameters: queryParameters);

    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw "Unexpected status code " + resp.statusCode.toString();
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached total devices");
    }

    return resp.data ?? 0;
  }
}
