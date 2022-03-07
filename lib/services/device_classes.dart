import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/services/cache_helper.dart';

import 'auth.dart';

class DeviceClassesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? options;

  static initOptions() async {
    if (options != null) {
      return;
    }

    options = CacheOptions(
      store: HiveCacheStore(await CacheHelper.getCacheFile()),
      policy: CachePolicy.forceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
  }

  static Future<List<DeviceClass>> getDeviceClasses(BuildContext context,
      [List<String>? ids]) async {
    String uri = (dotenv.env["API_URL"] ?? 'localhost') +
        '/permissions/query/v3/resources/device-classes';
    final Map<String, String> queryParameters = {};
    if (ids != null && ids.isNotEmpty) {
      queryParameters["ids"] = ids.join(",");
    }

    final headers = await Auth.getHeaders(context);
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: options!));
    final resp = await dio.get<List<dynamic>?>(uri,
        queryParameters: queryParameters, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw "Unexpected status code " + resp.statusCode.toString();
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device classes");
    }

    final l = resp.data ?? [];
    return List<DeviceClass>.generate(
        l.length, (index) => DeviceClass.fromJson(l[index]));
  }
}
