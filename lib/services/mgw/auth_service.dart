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
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/api.dart';
import 'package:device_info_plus/device_info_plus.dart';

class User {
  String id;
  String username;
  String password;
  User(this.id, this.username, this.password);
}

@JsonSerializable()
class DeviceUserCredentials {
  String id;
  String login;
  String secret;

  DeviceUserCredentials(this.id, this.login, this.secret);
  DeviceUserCredentials.fromJson(Map<String, dynamic> json): id=json['id'], login=json['login'], secret=json['secret'];
  Map<String, dynamic> toJson() => <String, dynamic> {
  'id': this.id,
  'login': this.login,
  'secret': this.secret,
  };
}


Future<String> getDeviceName() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    return androidInfo.model;
  }

  if(Platform.isIOS) {
    IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
    return iosInfo.utsname.machine ?? "unknown";
  }

  return "unknown";
}

Future<String> getManufacturer() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    return androidInfo.manufacturer;
  }

  if(Platform.isIOS) {
    return "Apple";
  }

  return "unknown";
}

const LOG_PREFIX = "MGW-USER-SERVICE";

class MgwAuthService {
  MgwAuthService._(this.mgwApiService);

  static const basePath = "/auth-service";
  final MgwApiService mgwApiService;

  final _logger = Logger(printer: SimplePrinter());

  static Future<MgwAuthService> create(String host) async {
    final mgwApiService = await MgwApiService.create(host, false);
    return MgwAuthService._(mgwApiService);
  }

  Future<DeviceUserCredentials> RegisterDevice() async {
    _logger.d("$LOG_PREFIX: Register device");
    const path = "$basePath/pairing/request";
    final payload = jsonEncode({
      "manufacturer": await getManufacturer(),
      "model": await getDeviceName(),
    });
    final resp = await mgwApiService.Post(path, payload, Options());
    final user = DeviceUserCredentials.fromJson(resp.data);
    _logger.d("$LOG_PREFIX: Registration successful - Device username: ${user.login}");
    return user;
  }
}
