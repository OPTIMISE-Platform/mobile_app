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

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/db_query.dart';
import 'auth.dart';

class DbQueryService {
  static final _client = http.Client();

  static Future<List<List<dynamic>>> query(DbQuery query) async {
    final url =
        (dotenv.env["API_URL"] ?? 'localhost') + '/db/v3/queries';
    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }
    final headers = await Auth.getHeaders();

    final resp = await _client.post(uri, headers: headers, body: json.encode([query]));
    if (resp.statusCode != 200) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    final decoded = (json.decode(resp.body) as List<dynamic>)[0];
    return List<List<dynamic>>.generate(decoded.length, (i) => decoded[i] as List<dynamic>);
  }
}
