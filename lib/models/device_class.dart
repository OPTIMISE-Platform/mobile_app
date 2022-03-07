import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/util/base64_response_decoder.dart';

part 'device_class.g.dart';

const cachSubdir = "/img";

@JsonSerializable()
class DeviceClass {
  String id, image, name;

  Widget? imageWidget;

  static CacheOptions? _options;

  static initOptions() async {
    if (_options != null) {
      return;
    }

    _options = CacheOptions(
      store: HiveCacheStore(await CacheHelper.getCacheFile()),
      policy: CachePolicy.forceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 365),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
  }

  _initImage() async {
    if (image.isEmpty) {
      return;
    }
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.get<String?>(image, options: Options(responseDecoder: DecodeIntoBase64()));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw "Unexpected status code " + resp.statusCode.toString();
    }
    if (resp.data == null) {
      throw "Unexpected null data";
    }
    final b64 = const Base64Decoder().convert(resp.data!);
    imageWidget = Image.memory(b64);
  }

  DeviceClass(this.id, this.name, this.image);

  factory DeviceClass.fromJson(Map<String, dynamic> json) {
    final c = _$DeviceClassFromJson(json);
    c._initImage();
    return c;
  }

  Map<String, dynamic> toJson() => _$DeviceClassToJson(this);
}
