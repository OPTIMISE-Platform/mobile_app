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
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/mgw_deployment.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/mgw/core_manager.dart';
import 'package:mobile_app/services/mgw/endpoint.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/settings.dart';

import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

import '../shared/isar.dart';

/// How long device-command waits for the devices of a batch. Both clients
/// wait a second longer, so the endpoint's own timeout answer arrives instead
/// of a client-side 502 for a slow device.
const commandTimeoutSeconds = 10;
const commandUrlPrefix =
    "/commands/batch?timeout=${commandTimeoutSeconds}s&prefer_event_value=";
const batchReceiveTimeout = Duration(seconds: commandTimeoutSeconds + 1);
const LOG_PREFIX = "DEVICE-COMMAND";

/// device-command's status for a command the gateway leaves to the platform.
const leftToPlatformStatus = 513;

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
      List<DeviceCommand> commands, bool preferEventValue) async {
    _logger.d("$LOG_PREFIX: Run commands via exposed path");
    var endpoints = await getEndpoints();
    var endpoint = endpoints.first.location;
    var path = endpoint + commandUrlPrefix + preferEventValue.toString();
    final Response<dynamic> resp;
    try {
      resp = await mgwEndpointService.PostToExposedPath(path, commands,
          receiveTimeout: batchReceiveTimeout);
    } catch (e) {
      // No retry here: a command is not idempotent, and the caller already
      // falls back to the cloud. Dropping the cached location makes the next
      // command look it up again in case the module has moved.
      await _clearCachedEndpoints();
      // A receive timeout means the gateway may still run the batch. A control
      // is not idempotent, so it is answered here rather than handed to the
      // platform; a read is, so it goes on like a 513.
      if (e is Failure && e.errorCode == ErrorCode.RECEIVE_TIMEOUT) {
        return [
          for (final command in commands)
            command.function_id.startsWith(controllingFunctionPrefix)
                ? DeviceCommandResponse(
                    502, "gateway took the command but did not answer")
                : DeviceCommandResponse(
                    leftToPlatformStatus, "gateway did not answer")
        ];
      }
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
        options: Options(headers: headers, receiveTimeout: batchReceiveTimeout),
        data: json.encode(commands));

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
    // Groups hold indices into [commands], so every answer lands at the index
    // of the command it belongs to, even if the same command is listed twice.
    final Map<Network?, List<int>> map = {};
    for (int i = 0; i < commands.length; i++) {
      final e = commands[i];
      if (e.deviceInstance != null || e.device_id != null) {
        _insert(map, e.deviceInstance?.network, i, <int>[]);
      } else if (e.deviceGroup != null || e.group_id != null) {
        _insert(map, e.deviceGroup?.network, i, <int>[]);
      }
    }

    final List<Future> futures = [];
    final List<DeviceCommandResponse?> resp =
        List.generate(commands.length, (index) => null);

    // Indices of gateway commands the platform answers instead.
    final List<int> cloudRetries = [];

    map.entries.forEach((network) {
      final indices = network.value;
      final group = [for (final i in indices) commands[i]];
      final host = network.key?.localGatewayHosts?.firstOrNull;
      if (host == null) {
        // A platform answer is final, 513 included: a command is never sent
        // twice.
        futures.add(_runOnPlatform(group, preferEventValue)
            .then((value) => _assign(resp, indices, value)));
        return;
      }
      futures.add(DeviceCommandPath(host)
          .runCommands(group, preferEventValue)
          .onError((_, __) {
        cloudRetries.addAll(indices);
        return <DeviceCommandResponse>[];
      }).then((value) {
        for (int i = 0; i < indices.length && i < value.length; i++) {
          if (value[i].status_code != leftToPlatformStatus) {
            resp[indices[i]] = value[i];
          } else {
            cloudRetries.add(indices[i]);
          }
        }
      }));
    });
    final DateTime start = DateTime.now();
    await Future.wait(futures);
    if (cloudRetries.isNotEmpty) {
      final retryRes = await _runOnPlatform(
          [for (final i in cloudRetries) commands[i]], preferEventValue);
      _assign(resp, cloudRetries, retryRes);
    }
    _logger.d("runCommands ${DateTime.now().difference(start)}");
    return resp
        .map((e) => e ?? DeviceCommandResponse(502, "upstream reply null"))
        .toList();
  }

  /// Sends [commands] to the platform in one batch. A failed request answers
  /// 502 for each command rather than being repeated: a command is not
  /// idempotent.
  static Future<List<DeviceCommandResponse>> _runOnPlatform(
      List<DeviceCommand> commands, bool preferEventValue) async {
    try {
      return await DeviceCommandCloud().runCommands(commands, preferEventValue);
    } on DioException catch (e) {
      _logger.e("Cant run cloud commands :${e.message}");
      final message = _platformFailureMessage(e);
      return List<DeviceCommandResponse>.generate(
          commands.length, (index) => DeviceCommandResponse(502, message));
    }
  }

  /// A short reason for the widgets' toast: the shared offline message when
  /// the platform could not be reached, else what it answered.
  static String _platformFailureMessage(DioException e) {
    if (ErrorReporter.isOffline(e)) return ErrorReporter.offlineMessage;
    final status = e.response?.statusCode;
    if (status != null) return "platform answered $status";
    return e.message ?? e.type.name;
  }

  /// Writes [value] to the [indices] it answers. A reply shorter than the
  /// batch leaves the rest null, which [runCommands] reports as 502.
  static void _assign(List<DeviceCommandResponse?> resp, List<int> indices,
      List<DeviceCommandResponse> value) {
    for (int i = 0; i < indices.length && i < value.length; i++) {
      resp[indices[i]] = value[i];
    }
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
