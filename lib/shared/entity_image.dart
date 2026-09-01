/*
 * Copyright 2026 InfAI (CC SES)
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
import 'package:logger/logger.dart';
import 'package:mobile_app/shared/base64_response_decoder.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:mobile_app/shared/semaphore.dart';

final _logger = Logger(printer: SimplePrinter());

/// Downloads the image at [url] and decodes it into a widget, or returns null
/// if that did not work.
///
/// Device classes, device groups and locations each carried their own copy of
/// this, identical down to the throttling and the swallowed failure. [entity]
/// and [id] only name the subject in the log.
///
/// Never throws. These run fire-and-forget off a fromJson path, so an
/// unreachable image host must not take down the batch it belongs to, and an
/// escaping exception there would surface as an unhandled async error.
Future<Widget?> loadEntityImage(String url, String entity, String id) async {
  if (url.isEmpty) return null;
  try {
    final dio = await DioFactory.create(DioConfig.cached365);
    // Throttled so a batch does not hammer the image host, which answers 429
    // when too many requests arrive at once.
    final resp = await imageDownloadLimiter.withResource(
      () => dio.get<String?>(url,
          options: Options(responseDecoder: DecodeIntoBase64())),
    );
    if (!isReadableStatus(resp.statusCode)) {
      _logger.e(
          "Could not load $entity image: response code was ${resp.statusCode}. ID: $id, URL: $url");
      return null;
    }
    if (resp.data == null) {
      _logger.e(
          "Could not load $entity image: response was null. ID: $id, URL: $url");
      return null;
    }
    return Image.memory(const Base64Decoder().convert(resp.data!));
  } catch (e) {
    _logger.e("Could not load $entity image. ID: $id, URL: $url. Error: $e");
    return null;
  }
}
