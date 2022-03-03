import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
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

  static Future<String?> getCacheDir() async {
    if (kIsWeb) {
      return null;
    }
    if (Platform.isAndroid) {
      List<Directory>? cacheDirs = await getExternalCacheDirectories();
      if (cacheDirs != null && cacheDirs.isNotEmpty) {
        return cacheDirs[0].path;
      }
    }

    return (await getApplicationDocumentsDirectory()).path;
  }
}
