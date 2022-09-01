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

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/exceptions/argument_exception.dart';

import '../../../../../services/auth.dart';
import '../base.dart';

class Request {
  static final _client = http.Client();

  final String method, url;
  dynamic body;
  final bool need_token;

  Request(this.method, this.url, dynamic body, this.need_token) {
      this.body = json.encode(body);
  }

  factory Request.fromJson(Map<String, dynamic> json) =>
      Request(json["method"] as String, json["url"] as String, json["body"], json["need_token"] as bool);

  Future<http.Response> perform() async {
    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }
    Map<String, String> headers = {};
    if (need_token) {
      headers = await Auth().getHeaders();
    }

    switch (method.toUpperCase()) {
      case "GET":
        return await _client.get(uri, headers: headers);
      case "POST":
        return await _client.post(uri, headers: headers, body: body);
      case "PUT":
        return await _client.put(uri, headers: headers, body: body);
      case "HEAD":
        return await _client.head(uri, headers: headers);
      case "PATCH":
        return await _client.patch(uri, headers: headers, body: body);
      case "DELETE":
        return await _client.delete(uri, headers: headers, body: body);

      default:
        throw ArgumentException("Unsupported method " + method);
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
