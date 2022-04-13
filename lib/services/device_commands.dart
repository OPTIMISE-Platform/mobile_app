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
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/no_network_exception.dart';
import 'package:mobile_app/models/device_command.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/device_command_response.dart';
import '../widgets/toast.dart';
import 'auth.dart';

class DeviceCommandsService {
  static final _client = http.Client();
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static Future<List<DeviceCommandResponse>> runCommands(List<DeviceCommand> commands, [bool preferEventValue = true]) async {
    ConnectivityResult connectivityResult = await (Connectivity().checkConnectivity());

    if (connectivityResult == ConnectivityResult.none) throw NoNetworkException();

    final url =
        (dotenv.env["API_URL"] ?? 'localhost') + '/device-command/commands/batch?timeout=25s&prefer_event_value=' + preferEventValue.toString();
    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }
    final headers = await Auth.getHeaders();

    final resp = await _client.post(uri, headers: headers, body: json.encode(commands));

    if (resp.statusCode > 200) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    final List<dynamic> l = json.decode(resp.body);

    return List<DeviceCommandResponse>.generate(l.length, (index) => DeviceCommandResponse.fromJson(l[index]));
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
}
