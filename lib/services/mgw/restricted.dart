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

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/auth.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';

const LOG_PREFIX = "MGW-RESTRICTED-API-SERVICE";

enum MgwSessionProblem {
  /// The phone holds no device credentials, so there is nothing to log in with.
  noCredentials,

  /// The gateway's identity provider did not issue a session.
  loginFailed,

  /// The stored session could not be read or written on this phone.
  storageFailed,
}

/// Why no session token could be attached to a request.
class MgwSessionException implements Exception {
  final MgwSessionProblem problem;
  final String message;

  /// The login's own failure, when the identity provider answered or the
  /// request to it failed.
  final Failure? failure;

  MgwSessionException(this.problem, this.message, {this.failure});

  @override
  String toString() => "MgwSessionException($problem: $message)";
}

class MgwService {
  // Use this service to perform request with automatically added session tokens

  String baseUrl = "";
  MgwAuth mgwAuthService = MgwAuth("");
  DeviceUserCredentials deviceCredentials = DeviceUserCredentials("", "", "");

  /// When true, a request for which no session can be obtained fails with
  /// [MgwSessionException] instead of going out without a token.
  final bool requireSession;

  /// Whether the last request carried a stored session rather than one from a
  /// new login; null when it carried none.
  bool? lastSessionReused;

  /// Whether the last GET was sent a second time with a new login because the
  /// gateway rejected the stored session.
  bool retriedWithFreshSession = false;

  static const _storage = FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
        resetOnError: true,
  ));
  static const sessionStorageKey = "mgw-session";
  static const sessionExpirationStorageKey = "mgw-session-expiration";

  // Request extras: set by the caller to skip the stored session, and by the
  // interceptor to record whether the stored one was used.
  static const _freshSessionKey = "mgw-fresh-session";
  static const _reusedSessionKey = "mgw-reused-session";

  /// Never throws: it runs while handling another failure, and a throw would
  /// replace that one.
  static Future<void> ResetSessionData() async {
    try {
      await _storage.delete(key: sessionStorageKey);
      await _storage.delete(key: sessionExpirationStorageKey);
    } catch (e) {
      Logger(printer: SimplePrinter())
          .e("$LOG_PREFIX: Could not drop the stored session: $e");
    }
  }

  final _logger = Logger(
    printer: SimplePrinter(),
  );

  //TODO: switch to dio
  final dio = Dio(
    BaseOptions(
    connectTimeout: const Duration(milliseconds: 5000),
    sendTimeout: const Duration(milliseconds: 5000),
    receiveTimeout: const Duration(milliseconds: 5000),
    ),
  )..httpClientAdapter = AppHttpClientAdapter.plain();


  MgwService(String host, bool authenticate, {this.requireSession = false}) {
    baseUrl = "http://${gatewayAuthority(host)}";
    mgwAuthService = MgwAuth(host);

    if (authenticate) {
      dio.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) async {
        options.headers['X-No-Auth-Redirect'] = 'true';
        try {
          final session =
              await obtainSession(fresh: options.extra[_freshSessionKey] == true);
          options.headers['X-Session-Token'] = session.token;
          options.extra[_reusedSessionKey] = session.reused;
          lastSessionReused = session.reused;
        } catch (e) {
          // Every error ends here, a throwing secure storage too: dio drops an
          // async onRequest that throws, and the request never returns.
          final problem = e is MgwSessionException
              ? e
              : MgwSessionException(MgwSessionProblem.storageFailed,
                  "Could not use the stored session ($e)");
          _logger.d("$LOG_PREFIX: No session: $problem");
          lastSessionReused = null;
          if (requireSession) {
            return handler
                .reject(DioException(requestOptions: options, error: problem));
          }
          // Sent without a token: the gateway answers 401, which callers
          // without requireSession already handle.
        }
        return handler.next(options);
      }));
    }
  }

  Future<String> GetSessionToken() async => (await obtainSession()).token;

  /// A session token, the stored one unless [fresh] or it expires within
  /// three hours. Throws [MgwSessionException] when none can be had.
  Future<({String token, bool reused})> obtainSession(
      {bool fresh = false}) async {
    try {
      await LoadCredentialsFromStorage();
    } on MgwCredentialsMissing {
      throw MgwSessionException(
          MgwSessionProblem.noCredentials, "No pairing credentials on this phone");
    } catch (e) {
      // A store that fails to read says nothing about whether a pairing exists;
      // calling it missing would send the user to pair a second device.
      throw MgwSessionException(MgwSessionProblem.storageFailed,
          "Could not read the pairing credentials ($e)");
    }
    if (!fresh) {
      final session = await _storage.read(key: sessionStorageKey);
      final expiration = DateTime.tryParse(
          await _storage.read(key: sessionExpirationStorageKey) ?? "");
      if (session != null &&
          expiration != null &&
          expiration.isAfter(DateTime.now().add(const Duration(hours: 3)))) {
        _logger.d("$LOG_PREFIX: Use stored session");
        return (token: session, reused: true);
      }
    }
    _logger.d("$LOG_PREFIX: Get new Session");
    final LoginResponse loginResponse;
    try {
      loginResponse = await mgwAuthService.Login(
          deviceCredentials.login, deviceCredentials.secret);
    } on Failure catch (f) {
      throw MgwSessionException(MgwSessionProblem.loginFailed, f.detailedMessage,
          failure: f);
    } catch (e) {
      throw MgwSessionException(MgwSessionProblem.loginFailed, e.toString());
    }
    try {
      await _storage.write(key: sessionStorageKey, value: loginResponse.token);
      await _storage.write(
          key: sessionExpirationStorageKey, value: loginResponse.expires_at);
    } catch (e, s) {
      // The token is valid all the same; the next request logs in again.
      ErrorReporter.log("Could not store the gateway session", e, s);
    }
    return (token: loginResponse.token, reused: false);
  }

  LoadCredentialsFromStorage() async {
    _logger.d("$LOG_PREFIX: Load device credentials from storage");
    deviceCredentials = await MgwStorage.LoadCredentials();
  }

  Future<Response<dynamic>> Post(String path, dynamic data, Options options) async {
    var url = baseUrl + path;
    _logger.d("$LOG_PREFIX: POST to: $url");
    try {
      return await dio.post(url, data: data, options: options);
    } on DioException catch (e) {
      _logger.e("$LOG_PREFIX: Request error: type=${e.type} message=${e.message} status=${e.response?.statusCode}");
      final sessionProblem = e.error;
      if (sessionProblem is MgwSessionException) throw sessionProblem;
      throw handleDioException(e);
    }
  }

  /// GETs [path]. A stored session the gateway answers with 401 is dropped and
  /// the request sent once more with a new login; a 403 rejects this device,
  /// not the session, and POST is never repeated, as a command must not run
  /// twice.
  Future<Response<dynamic>> Get(String path, Options options) async {
    var url = baseUrl + path;
    _logger.d("$LOG_PREFIX: GET from: $url");
    retriedWithFreshSession = false;
    try {
      return await dio.get(url, options: options);
    } on DioException catch (e) {
      if (!_rejectedStoredSession(e)) throw await _failureOf(e);
      _logger.d("$LOG_PREFIX: Stored session rejected, logging in again");
      await ResetSessionData();
      retriedWithFreshSession = true;
      try {
        return await dio.get(url,
            options: options.copyWith(
                extra: {...?options.extra, _freshSessionKey: true}));
      } on DioException catch (retry) {
        throw await _failureOf(retry);
      }
    }
  }

  static bool _rejectedStoredSession(DioException e) {
    return e.response?.statusCode == 401 &&
        e.requestOptions.extra[_reusedSessionKey] == true;
  }

  Future<Object> _failureOf(DioException e) async {
    _logger.e("$LOG_PREFIX: Get error: ${e.type} - ${e.message} - status: ${e.response?.statusCode}");
    final sessionProblem = e.error;
    if (sessionProblem is MgwSessionException) return sessionProblem;
    if (e.response?.statusCode == 401) {
      await ResetSessionData();
    }
    return handleDioException(e);
  }
}
