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
import 'package:isar/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/mgw_deployment.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/mgw/core_manager.dart';
import 'package:mobile_app/services/mgw/endpoint.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/settings.dart';

import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

import '../shared/isar.dart';

const commandUrlPrefix = "/commands/batch?timeout=10s&prefer_event_value=";
const LOG_PREFIX = "DEVICE-COMMAND";

class DeviceCommandPath {
  late MgwCoreService mgwCoreService;
  late MgwEndpointService mgwEndpointService;
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  DeviceCommandPath(String host) {
    mgwCoreService = MgwCoreService(host);
    mgwEndpointService = MgwEndpointService(host);
  }

  Future<List<Endpoint>> getEndpoints() async {
    // TODO change module
    _logger.d("$LOG_PREFIX: Get deployment endpoint");
    List<Endpoint> endpoints;
    const deviceManagerModuleName =
        "github.com/SENERGY-Platform/mgw-device-command";
    if (isar != null) {
      endpoints = await isar!.endpoints
          .where()
          .moduleNameEqualTo(deviceManagerModuleName)
          .findAll();
      if (endpoints.isNotEmpty) {
        return endpoints;
      }
    }
    endpoints =
        await mgwCoreService.getEndpointsOfModule(deviceManagerModuleName);
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.endpoints.putAll(endpoints);
      });
    }
    return endpoints;
  }

  Future<List<DeviceCommandResponse>> runCommands(
      commands, preferEventValue) async {
    _logger.d("$LOG_PREFIX: Run commands via exposed path");
    var endpoints = await getEndpoints();
    var endpoint = endpoints.first.location;
    var path = endpoint + commandUrlPrefix + preferEventValue.toString();
    var resp = await mgwEndpointService.PostToExposedPath(path, commands);
    List<DeviceCommandResponse> commandResponses = [];
    for (final response in resp.data) {
      commandResponses.add(DeviceCommandResponse.fromJson(response));
    }
    return commandResponses;
  }
}

class DeviceCommandPort {
  String host;
  DeviceCommandPort(this.host);
  var _logger = Logger(
    printer: SimplePrinter(),
  );

  final _dioH1 = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 1500),
    sendTimeout: const Duration(milliseconds: 5000),
    receiveTimeout: const Duration(milliseconds: 15000),
  ))
    ..interceptors.add(ApiAvailableInterceptor());

  Future<List<DeviceCommandResponse>> runCommands(
      commands, preferEventValue) async {
    // TODO service.port was used  but shoud be device command port ?????
    var url = "http://${host}:8002$commandUrlPrefix$preferEventValue";
    _logger.d("$LOG_PREFIX: Run commands via exposed port at: $url");

    final Response<List<dynamic>> resp;

    resp = await _dioH1.post<List<dynamic>>(url, data: json.encode(commands));

    return List<DeviceCommandResponse>.generate(resp.data!.length,
        (index) => DeviceCommandResponse.fromJson(resp.data![index]));
  }
}

class DeviceCommandCloud {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  static final _dio2H2 = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 1500),
    sendTimeout: const Duration(milliseconds: 5000),
    receiveTimeout: const Duration(milliseconds: 15000),
  ))
    ..interceptors.add(ApiAvailableInterceptor())
    ..httpClientAdapter = AppHttpClientAdapter();

  Future<List<DeviceCommandResponse>> runCommands(
      commands, preferEventValue) async {
    var url = "${Settings.getApiUrl() ?? 'localhost'}/device-command" +
        commandUrlPrefix +
        preferEventValue.toString();
    _logger.d(LOG_PREFIX + ": Run commands via platform at: " + url);
    final headers = await Auth().getHeaders();

    final Response<dynamic> resp;

    resp = await _dio2H2.post(url,
        options: Options(headers: headers), data: json.encode(commands));

    List<DeviceCommandResponse> commandResponses = [];
    for (final response in resp.data) {
      commandResponses.add(DeviceCommandResponse.fromJson(response));
    }
    return commandResponses;
  }
}

class DeviceCommandsService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static Future<List<DeviceCommandResponse>> runCommands(
      List<DeviceCommand> commands,
      [bool preferEventValue = true]) async {
    final Map<Network?, List<DeviceCommand>> map = {};
    commands.forEach((e) {
      if (e.deviceInstance != null || e.device_id != null) {
        _insert(map, e.deviceInstance?.network, e, <DeviceCommand>[]);
      } else if (e.deviceGroup != null || e.group_id != null) {
        _insert(map, e.deviceGroup?.network, e, <DeviceCommand>[]);
      }
    });

    final List<Future> futures = [];
    final List<DeviceCommandResponse?> resp =
        List.generate(commands.length, (index) => null);

    final List<DeviceCommand> cloudRetries = [];

    map.entries.forEach((network) {
      final service = network.key?.localService?.first;
      futures.add(_runCommands(network.value, service == null,
              service?.host ?? "", preferEventValue)
          .onError((_, __) {
        cloudRetries.addAll(network.value);
        return [];
      }).then((value) {
        if (value.isEmpty) {
          return;
        }
        for (int i = 0; i < network.value.length; i++) {
          if (value[i].status_code != 513) {
            resp[commands.indexOf(network.value[i])] = value[i];
          } else {
            cloudRetries.add(network.value[i]);
          }
        }
      }));
    });
    final DateTime start = DateTime.now();
    await Future.wait(futures);
    if (cloudRetries.isNotEmpty) {
      List<DeviceCommandResponse> retryRes;
      try {
        retryRes = await _runCommands(cloudRetries, true, "", preferEventValue);
      } on DioException catch (e) {
        _logger.e("Cant run cloud commands :${e.message}");
        retryRes = List<DeviceCommandResponse>.generate(cloudRetries.length,
            (index) => DeviceCommandResponse(502, e.toString()));
      }
      for (int i = 0; i < retryRes.length; i++) {
        resp[commands.indexOf(cloudRetries[i])] = retryRes[i];
      }
    }
    _logger.d("runCommands ${DateTime.now().difference(start)}");
    return resp
        .map((e) => e ?? DeviceCommandResponse(502, "upstream reply null"))
        .toList();
  }

  static Future<bool> checkPathBasedCommandServiceAvailable(String host) async {
    _logger.d(
        "Find out which device command service to use by checking endpoints");
    var endpoints = [];
    try {
      endpoints = await DeviceCommandPath(host).getEndpoints();
    } on Failure catch (e) {
      _logger.e("Cant check device command endpoints: " + e.detailedMessage);
      return false;
    } catch (e) {
      _logger.e("Cant check device command endpoints: " + e.toString());
      return false;
    }

    if (endpoints.isEmpty) {
      _logger.d(
          "No endpoints found for device command -> use port based device command");
      return false;
    }
    _logger.d(
        "Endpoints found for device command -> use new path based device command");
    return true;
  }

  static Future<List<DeviceCommandResponse>> _runCommands(
      List<DeviceCommand> commands,
      bool sendToCloud,
      String host,
      bool preferEventValue) async {
    if (sendToCloud) {
      return DeviceCommandCloud().runCommands(commands, preferEventValue);
    }

    var usePathBasedCommandService =
        await checkPathBasedCommandServiceAvailable(host);
    _logger.d("Load devices from new path based device command: " +
        usePathBasedCommandService.toString());
    if (usePathBasedCommandService) {
      return DeviceCommandPath(host).runCommands(commands, preferEventValue);
    } else {
      return DeviceCommandPort(host).runCommands(commands, preferEventValue);
    }
  }

  /// Fills the responses list and returns success as boolean. A Toast is shown and an error is logged if success is false
  static Future<bool> runCommandsSecurely(BuildContext context,
      List<DeviceCommand> commands, List<DeviceCommandResponse> responses,
      [bool preferEventValue = true]) async {
    try {
      responses.addAll(
          await DeviceCommandsService.runCommands(commands, preferEventValue));
    } on ApiUnavailableException {
      const err = "Currently unavailable";
      Toast.showToastNoContext(err);
      _logger.e(err);
      return false;
    } catch (e) {
      const err = "Couldn't run command";
      Toast.showToastNoContext(err);
      _logger.e(err);
      return false;
    }
    return true;
  }

  static void _insert(Map<dynamic, List<dynamic>> m, dynamic key, dynamic value,
      List<dynamic> ifNotExisting) {
    if (!m.containsKey(key)) {
      m[key] = ifNotExisting;
    }
    m[key]!.add(value);
  }

  static bool isAvailable() {
    final uri = "${Settings.getApiUrl() ?? 'localhost'}/device-command";
    return ApiAvailableService().isAvailable(uri);
  }
}
