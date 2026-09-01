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
import 'package:flutter/cupertino.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/shared/base64_response_decoder.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:mobile_app/shared/semaphore.dart';

part 'device_class.g.dart';

const cachSubdir = "/img";

@JsonSerializable()
class DeviceClass {
  String id, image, name;

  @JsonKey(ignore: true)
  Widget? imageWidget;

  @JsonKey(ignore: true)
  List<String> deviceIds = [];

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  Future<void> _initImage() async {
    if (image.isEmpty) {
      return;
    }
    try {
      final dio = await DioFactory.create(DioConfig.cached365);
      // Throttled so a batch of device classes doesn't hammer the image host
      // (imgur returns HTTP 429 when too many requests arrive at once).
      final resp = await imageDownloadLimiter.withResource(
        () => dio.get<String?>(image,
            options: Options(responseDecoder: DecodeIntoBase64())),
      );
      if (!isReadableStatus(resp.statusCode)) {
        _logger.e("Could not load deviceClass image: Response code was: ${resp.statusCode}. ID: $id, URL: $image");
        return;
      }
      if (resp.data == null) {
        _logger.e("Could not load deviceClass image: response was null. ID: $id, URL: $image");
        return;
      }
      final b64 = const Base64Decoder().convert(resp.data!);
      imageWidget = Image.memory(b64);
    } catch (e) {
      // Fire-and-forget from fromJson — swallow so it never surfaces as an
      // unhandled async exception (e.g. a 429 from the image host).
      _logger.e("Could not load deviceClass image. ID: $id, URL: $image. Error: $e");
    }
  }

  DeviceClass(this.id, this.name, this.image);

  factory DeviceClass.fromJson(Map<String, dynamic> json) {
    final c = _$DeviceClassFromJson(json);
    c._initImage();
    return c;
  }

  Map<String, dynamic> toJson() => _$DeviceClassToJson(this);
}
