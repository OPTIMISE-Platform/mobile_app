import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CacheHelper {
  static String bodyCacheIDBuilder(RequestOptions request) {
    List<int> bytes = utf8.encode(request.uri.toString());
    if (request.data != null) {
      bytes = [...bytes, ...utf8.encode(request.data)];
    }
    return sha1.convert(bytes).toString();
  }

  static Future<String?> getCacheFile() async {
    final dir = await getCacheDir();
    if (dir == null) {
      return null;
    }
    return dir.path + "/cache.box";
  }

  static Future<Directory?> getCacheDir() async {
    if (kIsWeb) {
      return null;
    }
    if (Platform.isAndroid) {
      List<Directory>? cacheDirs = await getExternalCacheDirectories();
      if (cacheDirs != null && cacheDirs.isNotEmpty) {
        return cacheDirs[0];
      }
    }

    return await getApplicationDocumentsDirectory();
  }

  static clearCache() async {
    final cacheFile = (await getCacheFile());
    HiveCacheStore(cacheFile).clean();
  }
}
