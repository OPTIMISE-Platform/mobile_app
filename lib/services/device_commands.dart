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
import 'package:isar_community/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/mgw_deployment.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/mgw/core_manager.dart';
import 'package:mobile_app/services/mgw/endpoint.dart';
import 'package:mobile_app/services/settings.dart';

import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/error_reporter.dart';
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

  static const deviceManagerModuleName =
      "github.com/SENERGY-Platform/mgw-device-command";

  Future<void> _clearCachedEndpoints() async {
    if (isar == null) {
      return;
    }
    await isar!.writeTxn(() async {
      await isar!.endpoints
          .where()
          .moduleNameEqualTo(deviceManagerModuleName)
          .deleteAll();
    });
  }

  Future<List<Endpoint>> getEndpoints() async {
    // TODO change module
    _logger.d("$LOG_PREFIX: Get deployment endpoint");
    List<Endpoint> endpoints;
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
    final Response<dynamic> resp;
    try {
      resp = await mgwEndpointService.PostToExposedPath(path, commands);
    } catch (_) {
      // No retry here: a command is not idempotent, and the caller already
      // falls back to the cloud. Dropping the cached location makes the next
      // command look it up again in case the module has moved.
      await _clearCachedEndpoints();
      rethrow;
    }
    List<DeviceCommandResponse> commandResponses = [];
    for (final response in resp.data) {
      commandResponses.add(DeviceCommandResponse.fromJson(response));
    }
    return commandResponses;
  }
}

class DeviceCommandCloud {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  Future<List<DeviceCommandResponse>> runCommands(
      commands, preferEventValue) async {
    var url = "${Settings.getApiUrl() ?? 'localhost'}/device-command$commandUrlPrefix$preferEventValue";
    _logger.d("$LOG_PREFIX: Run commands via platform at: $url");
    final headers = await Auth().getHeaders();

    final Response<dynamic> resp;
    final dio2H2 = await DioFactory.create(DioConfig.standard);
    resp = await dio2H2.post(url,
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
      final host = network.key?.localGatewayHosts?.first;
      futures.add(_runCommands(network.value, host == null,
              host ?? "", preferEventValue)
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

  static Future<List<DeviceCommandResponse>> _runCommands(
      List<DeviceCommand> commands,
      bool sendToCloud,
      String host,
      bool preferEventValue) async {
    if (sendToCloud) {
      return DeviceCommandCloud().runCommands(commands, preferEventValue);
    }

    return DeviceCommandPath(host).runCommands(commands, preferEventValue);
  }

  /// Fills the responses list and returns whether that succeeded. A failure is
  /// logged and reported to the user.
  static Future<bool> runCommandsSecurely(
      List<DeviceCommand> commands, List<DeviceCommandResponse> responses,
      [bool preferEventValue = true]) async {
    try {
      responses.addAll(
          await DeviceCommandsService.runCommands(commands, preferEventValue));
    } catch (e, s) {
      // One catch: ApiUnavailableException never arrives on its own, it is
      // always wrapped in the DioException the interceptor rejects with, so a
      // clause on it never ran. ErrorReporter recognises the wrapped one and
      // names the missing connection instead of this message.
      ErrorReporter.report("Couldn't run command", e, s);
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
