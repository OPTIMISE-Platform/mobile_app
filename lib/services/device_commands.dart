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

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/no_network_exception.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/settings.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/device_command_response.dart';
import '../shared/http_client_adapter.dart';
import '../widgets/shared/toast.dart';
import 'auth.dart';

class DeviceCommandsService {
  static final _dioH1 = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000));
  static final _dio2H2 = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
    ..httpClientAdapter = AppHttpClientAdapter();
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static Future<List<DeviceCommandResponse>> runCommands(List<DeviceCommand> commands, [bool preferEventValue = true]) async {
    ConnectivityResult connectivityResult = await (Connectivity().checkConnectivity());

    if (connectivityResult == ConnectivityResult.none) throw NoNetworkException();

    final Map<Network?, List<DeviceCommand>> map = {};
    commands.forEach((e) {
      if (e.deviceInstance != null || e.device_id != null) {
        _insert(map, e.deviceInstance?.network, e, <DeviceCommand>[]);
      } else if (e.deviceGroup != null || e.group_id != null) {
        _insert(map, e.deviceGroup?.network, e, <DeviceCommand>[]);
      }
    });

    final List<Future> futures = [];
    final List<DeviceCommandResponse?> resp = List.generate(commands.length, (index) => null);

    final List<DeviceCommand> cloudRetries = [];

    map.entries.forEach((network) {
      final service = network.key?.localService;
      Dio dio;
      String url;
      if (service != null) {
        url = "http://${service.host!}:${service.port!}";
        dio = _dioH1;
      } else {
        url = "${Settings.getApiUrl() ?? 'localhost'}/device-command";
        dio = _dio2H2;
      }
      url += "/commands/batch?timeout=10s&prefer_event_value=$preferEventValue";
      futures.add(_runCommands(network.value, url, service == null, dio).then((value) {
        for (int i = 0; i < network.value.length; i++) {
          if (value[i].status_code != 513) {
            resp[commands.indexOf(network.value[i])] = value[i];
          } else {
            cloudRetries.add(network.value[i]);
          }
        }
      }).onError((_, __) {
        cloudRetries.addAll(network.value);
      }));
    });
    final DateTime start = DateTime.now();
    await Future.wait(futures);
    if (cloudRetries.isNotEmpty) {
      final url = "${Settings.getApiUrl() ?? 'localhost'}/device-command/commands/batch?timeout=25s&prefer_event_value=$preferEventValue";
      List<DeviceCommandResponse> retryRes;
      try {
        retryRes = await _runCommands(cloudRetries, url, true, _dio2H2);
      } catch (e) {
        retryRes = List<DeviceCommandResponse>.generate(cloudRetries.length, (index) => DeviceCommandResponse(502, e.toString()));
      }
      for (int i = 0; i < retryRes.length; i++) {
        resp[commands.indexOf(cloudRetries[i])] = retryRes[i];
      }
    }
    _logger.d("runCommands ${DateTime.now().difference(start)}");
    return resp.map((e) => e ?? DeviceCommandResponse(502, "upstream reply null")).toList();
  }

  static Future<List<DeviceCommandResponse>> _runCommands(List<DeviceCommand> commands, String url, bool sendToken, Dio dio) async {
    final headers = await Auth().getHeaders();

    final Response<List<dynamic>> resp;

    try {
      resp = await dio.post<List<dynamic>>(url, options: Options(headers: sendToken ? headers : null), data: json.encode(commands));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    return List<DeviceCommandResponse>.generate(resp.data!.length, (index) => DeviceCommandResponse.fromJson(resp.data![index]));
  }

  /// Fills the responses list and returns success as boolean. A Toast is shown and an error is logged if success is false
  static Future<bool> runCommandsSecurely(BuildContext context, List<DeviceCommand> commands, List<DeviceCommandResponse> responses,
      [bool preferEventValue = true]) async {
    try {
      responses.addAll(await DeviceCommandsService.runCommands(commands, preferEventValue));
    } on NoNetworkException {
      const err = "You are offline";
      Toast.showErrorToast(context, err);
      _logger.e(err);
      return false;
    } catch (e) {
      const err = "Couldn't run command";
      Toast.showErrorToast(context, err);
      _logger.e(err);
      return false;
    }
    return true;
  }

  static void _insert(Map<dynamic, List<dynamic>> m, dynamic key, dynamic value, List<dynamic> ifNotExisting) {
    if (!m.containsKey(key)) {
      m[key] = ifNotExisting;
    }
    m[key]!.add(value);
  }
}
