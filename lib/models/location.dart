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
import 'package:flutter/widgets.dart';
import 'package:isar_community/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';

import 'package:mobile_app/shared/base64_response_decoder.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/shared/semaphore.dart';

part 'location.g.dart';

@JsonSerializable()
@collection
class Location {
  @Index(type: IndexType.hash)
  String id;
  @Index(caseSensitive: false)
  String name;
  String description, image;
  List<String> device_ids, device_group_ids;

  @JsonKey(ignore: true)
  @ignore
  Widget? imageWidget;

  @JsonKey(ignore: true)
  Id isarId = -1;

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  Future<Location> initImage() async {
    if (image.isEmpty) {
      return this;
    }
    try {
      final dio = await DioFactory.create(DioConfig.cached365);
      // Throttled so a batch of locations doesn't hammer the image host (429).
      final resp = await imageDownloadLimiter.withResource(
        () => dio.get<String?>(image,
            options: Options(responseDecoder: DecodeIntoBase64())),
      );
      if (!isReadableStatus(resp.statusCode)) {
        _logger.e("Could not load Location image: Response code was: ${resp.statusCode}. ID: $id, URL: $image");
        return this;
      }
      if (resp.data == null) {
        _logger.e("Could not load Location image: response was null. ID: $id, URL: $image");
        return this;
      }
      final b64 = const Base64Decoder().convert(resp.data!);
      imageWidget = Image.memory(b64);
    } catch (e) {
      // Isolate the failure so one bad image doesn't fail the whole batch.
      _logger.e("Could not load Location image. ID: $id, URL: $image. Error: $e");
    }
    return this;
  }


  Location(this.id, this.name, this.description, this.image, this.device_ids, this.device_group_ids) {
    isarId = fastHash(id);
  }
  factory Location.fromJson(Map<String, dynamic> json) => _$LocationFromJson(json);
  Map<String, dynamic> toJson() => _$LocationToJson(this);
}
