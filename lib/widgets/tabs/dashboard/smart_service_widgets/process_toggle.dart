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

import 'package:flutter/material.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../../services/auth.dart';

class SmSeProcessToggle extends SmartServiceModuleWidget {
  static final _client = http.Client();

  String _deploymentId = "";
  final List<String> _instanceIds = [];
  late BuildContext _context;

  @override
  double height = 1;

  @override
  double width = 1;

  @override
  Widget buildInternal(BuildContext context, bool _, bool __) {
    _context = context;
    return ElevatedButton(
      onPressed: _instanceIds.isEmpty ? _start : _stop,
      child: Icon(_instanceIds.isEmpty ? Icons.play_arrow : Icons.stop),
    );
  }

  @override
  void configure(data) {
    if (data is! Map<String, dynamic> || data["deploymentId"] == null) return;
    _deploymentId = data["deploymentId"] as String;
  }

  @override
  Future<void> refreshInternal() async {
    final url = "${dotenv.env["API_URL"] ?? 'localhost'}/process/engine/v2/deployments/$_deploymentId/instances";
    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }

    final headers = await Auth().getHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      return;
    }
    final List l = json.decode(resp.body);
    _instanceIds.clear();
    _instanceIds.addAll(l.map((e) => e["id"]));
  }

  Future<void> _start() async {
    final url = "${dotenv.env["API_URL"] ?? 'localhost'}/process/engine/v2/deployments/$_deploymentId/start";
    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }

    final headers = await Auth().getHeaders();
    await _client.get(uri, headers: headers);
    await refresh();
    redrawDashboard(_context);
  }

  Future<void> _stop() async {
    final List<Future> futures = _instanceIds.map((e) {
      final url = "${dotenv.env["API_URL"] ?? 'localhost'}/process/engine/v2/process-instances/$e";
      var uri = Uri.parse(url);
      if (url.startsWith("https://")) {
        uri = uri.replace(scheme: "https");
      }

      return Auth().getHeaders().then((headers) => _client.delete(uri, headers: headers));
    }).toList(growable: false);

    await Future.wait(futures);
    await refresh();
    redrawDashboard(_context);
  }
}
