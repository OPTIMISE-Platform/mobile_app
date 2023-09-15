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
import 'package:flutter/material.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';

import '../../../../services/auth.dart';

class SmSeProcessToggle extends SmartServiceModuleWidget {
  @override
  setPreview(bool enabled) => null;

  static final _dio = Dio()
    ..interceptors.add(ApiAvailableInterceptor())
    ..httpClientAdapter = AppHttpClientAdapter();



  String _deploymentId = "";
  final List<String> _instanceIds = [];
  late BuildContext _context;
  late final Map<String, dynamic>? inputs;

  @override
  double height = 1;

  @override
  double width = 1;

  @override
  Widget buildInternal(BuildContext context, bool __) {
    _context = context;
    return ElevatedButton(
      onPressed: _instanceIds.isEmpty ? _start : _stop,
      child: Icon(_instanceIds.isEmpty ? Icons.play_arrow : Icons.stop),
    );
  }

  @override
  Future<void> configure(data) async {
    if (data is! Map<String, dynamic> || data["deploymentId"] == null) return;
    _deploymentId = data["deploymentId"] as String;
    inputs = data["inputs"] as Map<String, dynamic>;
  }

  @override
  Future<void> refreshInternal() async {
    final url = "${Settings.getApiUrl() ?? 'localhost'}/process/engine/v2/deployments/$_deploymentId/instances";

    final headers = await Auth().getHeaders();
    final resp = await _dio.get<List<dynamic>>(url, options: Options(headers: headers));
    if (resp.statusCode == null || resp.data == null || resp.statusCode != 200) {
      return;
    }
    _instanceIds.clear();
    _instanceIds.addAll(resp.data!.map((e) => e["id"]));
  }

  Future<void> _start() async {
    String url = "${Settings.getApiUrl() ?? 'localhost'}/process/engine/v2/deployments/$_deploymentId/start";
    String queryParameters = "?";
    inputs?.forEach((key, value) {
      if (queryParameters.length > 1) {
        queryParameters += "&";
      }
      queryParameters += "$key=${json.encode(value)}";
    });
    if (queryParameters.length > 1) {
      url += queryParameters;
      url = Uri.encodeFull(url);
    }

    final headers = await Auth().getHeaders();
    await _dio.get(url, options: Options(headers: headers));
    await refresh();
    redrawDashboard(_context);
  }

  Future<void> _stop() async {
    final List<Future> futures = _instanceIds.map((e) {
      final url = "${Settings.getApiUrl() ?? 'localhost'}/process/engine/v2/process-instances/$e";


      return Auth().getHeaders().then((headers) => _dio.delete(url, options: Options(headers: headers)));
    }).toList(growable: false);

    await Future.wait(futures);
    await refresh();
    redrawDashboard(_context);
  }
}
