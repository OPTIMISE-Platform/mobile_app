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
import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';

class Request {
  static final _dio = Dio()..interceptors.add(ApiAvailableInterceptor());

  final String method, url;
  dynamic body;
  final bool need_token;

  Request(this.method, this.url, dynamic body, this.need_token) {
    this.body = json.encode(body);
  }

  factory Request.fromJson(Map<String, dynamic> json) => Request(
      json["method"] as String,
      json["url"] as String,
      json["body"],
      json["need_token"] as bool);

  factory Request.from(Request r) =>
      Request(r.method, r.url, json.decode(json.encode(r.body)), r.need_token);

  Future<Response<T>> perform<T>() async {
    Map<String, String> headers = {};
    if (need_token) {
      headers = await Auth().getHeaders();
    }

    switch (method.toUpperCase()) {
      case "GET":
        return await _dio.get(url, options: Options(headers: headers));
      case "POST":
        return await _dio.post(url,
            options: Options(headers: headers), data: body);
      case "PUT":
        return await _dio.put(url,
            options: Options(headers: headers), data: body);
      case "HEAD":
        return await _dio.head(url, options: Options(headers: headers));
      case "PATCH":
        return await _dio.patch(url,
            options: Options(headers: headers), data: body);
      case "DELETE":
        return await _dio.delete(url,
            options: Options(headers: headers), data: body);

      default:
        throw ArgumentException("Unsupported method $method");
    }
  }
}

abstract class SmSeRequest extends SmartServiceModuleWidget {
  late Request request;

  @override
  @mustCallSuper
  Future<void> configure(dynamic data) async {
    if (data is! Map<String, dynamic> || data["request"] == null) return;
    request = Request.fromJson(data["request"]);
  }
}
