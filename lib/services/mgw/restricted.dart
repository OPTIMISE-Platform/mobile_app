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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/auth.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/dio_factory.dart';

const LOG_PREFIX = "MGW-RESTRICTED-API-SERVICE";

class MgwService {
  MgwService._(this.baseUrl, this.mgwAuthService, this._dio);

  final String baseUrl;
  final MgwAuth mgwAuthService;
  final Dio _dio;

  DeviceUserCredentials deviceCredentials = DeviceUserCredentials("", "", "");

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  static const sessionStorageKey = "mgw-session";
  static const sessionExpirationStorageKey = "mgw-session-expiration";

  final _logger = Logger(printer: SimplePrinter());

  static Future<MgwService> create(String host, bool authenticate) async {
    final dio = await DioFactory.create(DioConfig.standard);
    final service = MgwService._(
      "http://$host:8080",
      MgwAuth(host),
      dio,
    );

    if (authenticate) {
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) async {
          service._logger.d("$LOG_PREFIX: Set auth headers");
          options.headers['X-No-Auth-Redirect'] = 'true';
          try {
            service._logger.d("Try to get session token");
            options.headers['X-Session-Token'] = await service.GetSessionToken();
          } catch (e) {
            try {
              service._logger.d("Try to get basic auth");
              options.headers['Authorization'] = await service.GetBasicAuthValue();
            } catch (e) {
              service._logger.d(e);
            }
          }
          service._logger.d("$LOG_PREFIX: End interceptor");
          return handler.next(options);
        },
      ));
    }

    return service;
  }

  static ResetSessionData() async {
    await _storage.delete(key: sessionStorageKey);
    await _storage.delete(key: sessionExpirationStorageKey);
  }

  Future<String> GetSessionToken() async {
    _logger.d("$LOG_PREFIX: Get Session Token");
    await LoadCredentialsFromStorage();
    final now = DateTime.now();
    String? session = await _storage.read(key: sessionStorageKey);
    String? sessionExpiration = await _storage.read(key: sessionExpirationStorageKey);
    if (sessionExpiration != null) {
      final sessionExpirationDate = DateTime.parse(sessionExpiration);
      if (sessionExpirationDate.isAfter(now.add(const Duration(hours: 3))) && session != null) {
        _logger.d("$LOG_PREFIX: Use stored session");
        return session;
      }
    }
    _logger.d("$LOG_PREFIX: Get new Session");
    var loginResponse = await mgwAuthService.Login(deviceCredentials.login, deviceCredentials.secret);
    await _storage.write(key: sessionStorageKey, value: loginResponse.token);
    await _storage.write(key: sessionExpirationStorageKey, value: loginResponse.expires_at);
    return loginResponse.token;
  }

  Future<String> GetBasicAuthValue() async {
    _logger.d("$LOG_PREFIX: Load basic auth credentials from storage");
    try {
      var password = await MgwStorage.LoadBasicAuthCredentials();
      return 'Basic ${base64.encode(utf8.encode('admin:$password'))}';
    } catch (e) {
      rethrow;
    }
  }

  LoadCredentialsFromStorage() async {
    _logger.d("$LOG_PREFIX: Load device credentials from storage");
    deviceCredentials = await MgwStorage.LoadCredentials();
  }

  Future<Response<dynamic>> Post(String path, dynamic data, Options options) async {
    final url = baseUrl + path;
    _logger.d("$LOG_PREFIX: POST to: $url");
    try {
      return await _dio.post(url, data: data, options: options);
    } on DioException catch (e) {
      _logger.e("$LOG_PREFIX: Request error: type=${e.type} message=${e.message} status=${e.response?.statusCode}");
      throw handleDioException(e);
    }
  }

  Future<Response<dynamic>> Get(String path, Options options) async {
    final url = baseUrl + path;
    _logger.d("$LOG_PREFIX: GET from: $url");
    try {
      return await _dio.get(url, options: options);
    } on DioException catch (e) {
      _logger.e("$LOG_PREFIX: Get error: ${e.type} - ${e.message} - status: ${e.response?.statusCode}");
      if (e.response?.statusCode == 401) {
        await ResetSessionData();
      }
      throw handleDioException(e);
    }
  }
}
