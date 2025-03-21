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
import 'package:mobile_app/shared/api_available_interceptor.dart';

const LOG_PREFIX = "MGW-RESTRICTED-API-SERVICE";
class MgwService {
  // Use this service to perform request with automatically added session tokens

  String baseUrl = "";
  MgwAuth mgwAuthService = MgwAuth("");
  DeviceUserCredentials deviceCredentials = DeviceUserCredentials("", "", "");

  static const  _storage = FlutterSecureStorage(aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ));
  static const sessionStorageKey = "mgw-session";
  static const sessionExpirationStorageKey = "mgw-session-expiration";

  static ResetSessionData () async{
    await _storage.delete(key: sessionStorageKey);
    await _storage.delete(key: sessionExpirationStorageKey);
  }

  final _logger = Logger(
    printer: SimplePrinter(),
  );

  final dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 1500),
      sendTimeout: const Duration(milliseconds: 5000),
      receiveTimeout: const Duration(milliseconds: 5000),))
    ..interceptors.add(ApiAvailableInterceptor());

  MgwService(String host, bool authenticate) {
    baseUrl = "http://$host:8080";
    mgwAuthService = MgwAuth(host);

    if(authenticate) {
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
        _logger.d("$LOG_PREFIX: Set auth headers");
        options.headers['X-No-Auth-Redirect'] = 'true';
        try {
          _logger.d("Try to get session token");
          options.headers['X-Session-Token'] = await GetSessionToken();
        } catch (e) {
          try {
            _logger.d("Try to get basic auth");
            options.headers['Authorization'] = await GetBasicAuthValue();
          } catch (e) {
            _logger.d(e);
          }
        }
        _logger.d("$LOG_PREFIX: End interceptor");
        return handler.next(options);
      }));
    }
  }

  Future<String> GetSessionToken() async {
    _logger.d("$LOG_PREFIX: Get Session Token");
    await LoadCredentialsFromStorage();
    final now = DateTime.now();
    String? session = await _storage.read(key: sessionStorageKey);
    String? sessionExpiration = await _storage.read(key: sessionExpirationStorageKey);
    if (sessionExpiration != null) {
      final sessionExpirationDate = DateTime.parse(sessionExpiration);
      if (sessionExpirationDate.isAfter(now.add(const Duration(hours:3))) && session != null) {
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
      String basicAuth =
          'Basic ${base64.encode(utf8.encode('admin:$password'))}';
      return basicAuth;
    } catch (e) {
      rethrow;
    }
  }

  LoadCredentialsFromStorage() async {
    _logger.d("$LOG_PREFIX: Load device credentials from storage");
    deviceCredentials = await MgwStorage.LoadCredentials();
  }

  Future<Response<dynamic>> Post(String path, dynamic data, Options options) async {
    var url = baseUrl + path;
    _logger.d("$LOG_PREFIX: POST to: $url");
    Response resp;
    try {
      resp = await dio.post(url, data: data, options: options);
      return resp;
    } on DioException catch (e) {
      _logger.e("$LOG_PREFIX: Request error: $e");
      var failure = handleDioException(e);
      throw(failure);
    }
  }

  Future<Response<dynamic>> Get(String path, Options options) async {
    var url = baseUrl + path;
    _logger.d("$LOG_PREFIX: GET from: $url");
    Response resp;
    try {
      resp = await dio.get(url, options: options);
      return resp;
    } on DioException catch (e) {
      _logger.e("$LOG_PREFIX: Get: Request error");
      if (e.response?.statusCode == 401){
        ResetSessionData();
      }
      var failure = handleDioException(e);
      throw(failure);
    }
  }
}
