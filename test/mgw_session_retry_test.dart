/*
 * Copyright 2026 InfAI (CC SES)
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
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/mgw/auth.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';

import 'golden_helper.dart';

const _host = "192.0.2.10:8081";
const _endpoints = "/core/api/core-manager/endpoints";
const _pairing = "pairing-a";

final _gateway = MGW(_host, _host, "", _host, pairingId: _pairing);

Future<String?> _storedSession() => const FlutterSecureStorage()
    .read(key: MgwService.sessionKeyOf(_pairing));

/// A gateway whose answers a test decides per request.
class _Gateway implements HttpClientAdapter {
  _Gateway(this.answer);

  /// Null throws a refused connection.
  final ResponseBody? Function(RequestOptions options) answer;
  final List<RequestOptions> requests = [];

  List<RequestOptions> to(String path) =>
      requests.where((r) => r.uri.path == path).toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final body = answer(options);
    if (body == null) {
      throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException("Connection refused"));
    }
    return body;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

ResponseBody _text(int status, String body) =>
    ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: ["text/plain"]
    });

/// The gateway's login flow, issuing [token].
ResponseBody? _login(RequestOptions o, {String token = "fresh"}) {
  if (o.uri.path == "/core/auth/login/api") return _json(200, {"id": "flow-1"});
  if (o.uri.path == "/core/auth/login") {
    return _json(200, {
      "session_token": token,
      "session": {"expires_at": "2099-01-01T00:00:00Z"}
    });
  }
  return null;
}

Future<void> _pairedWith({String? storedSession}) async {
  FlutterSecureStorage.setMockInitialValues({
    if (storedSession != null) ...{
      MgwService.sessionKeyOf(_pairing): storedSession,
      MgwService.sessionExpirationKeyOf(_pairing): "2099-01-01T00:00:00Z",
    }
  });
  await MgwStorage.StoreCredentials(
      _pairing, DeviceUserCredentials("id", "login", "s"));
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
    await MgwStorage.init();
  });

  tearDown(() async {
    AppHttpClientAdapter.testOverride = null;
    MgwReachability.forget();
    await MgwStorage.ReplacePairedMGWs([]);
  });

  group("classify", () {
    test("a refused or reset connection is out of reach", () {
      expect(MgwReachability.classify(ErrorCode.CONNECTION_ERROR),
          MgwStatus.unreachable);
    });

    test("a connection error is not mapped to the catch-all code", () {
      final options = RequestOptions(path: "http://$_host/");
      expect(
          handleDioException(DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                  error: const SocketException("Connection refused")))
              .errorCode,
          ErrorCode.CONNECTION_ERROR);
      expect(
          handleDioException(DioException(
                  requestOptions: options,
                  error: const SocketException("Connection reset by peer")))
              .errorCode,
          ErrorCode.CONNECTION_ERROR);
    });

    test("an error answer keeps its status even without a reason phrase", () {
      final options = RequestOptions(path: "http://$_host/");
      final failure = handleDioException(DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: options, statusCode: 401, data: "no session")));
      expect(failure.errorCode, ErrorCode.UNAUTHORIZED);
      expect(failure.statusCode, 401);
      expect(failure.detailedMessage, "no session");
    });

    test("a gateway refusing the authenticated request is unreachable",
        () async {
      await _pairedWith(storedSession: "stored");
      final gateway = _Gateway((o) => o.uri.path == "/" ? _text(200, "") : null);
      AppHttpClientAdapter.testOverride = gateway;

      final report = await MgwReachability.check(_gateway, force: true);

      expect(report.status, MgwStatus.unreachable);
      expect(report.failedCheck, MgwFailedCheck.notAnswering);
    });
  });

  group("stored session", () {
    test("rejected: dropped, and a new login is tried once", () async {
      await _pairedWith(storedSession: "stored");
      final gateway = _Gateway((o) {
        if (o.uri.path == "/") return _text(200, "");
        if (o.uri.path == _endpoints) {
          return o.headers["X-Session-Token"] == "fresh"
              ? _json(200, {})
              : _text(401, "unknown session");
        }
        return _login(o);
      });
      AppHttpClientAdapter.testOverride = gateway;

      final report = await MgwReachability.check(_gateway, force: true);

      expect(report.status, MgwStatus.ok);
      expect(report.sessionReused, isTrue);
      expect(report.retriedWithFreshLogin, isTrue);
      expect(gateway.to(_endpoints).map((r) => r.headers["X-Session-Token"]),
          ["stored", "fresh"]);
      expect(await _storedSession(), "fresh");
    });

    test("rejected again after the new login: unauthorized, with details",
        () async {
      await _pairedWith(storedSession: "stored");
      final gateway = _Gateway((o) {
        if (o.uri.path == "/") return _text(200, "");
        if (o.uri.path == _endpoints) return _text(401, "unknown session");
        return _login(o);
      });
      AppHttpClientAdapter.testOverride = gateway;

      final report = await MgwReachability.check(_gateway, force: true);

      expect(report.status, MgwStatus.unauthorized);
      expect(report.failedCheck, MgwFailedCheck.rejected);
      expect(report.httpStatus, 401);
      expect(report.gatewayMessage, "unknown session");
      expect(report.address, _host);
      expect(report.retriedWithFreshLogin, isTrue);
      expect(gateway.to(_endpoints), hasLength(2));
    });

    test("a 403 rejects the device: no new login, the session is kept",
        () async {
      await _pairedWith(storedSession: "stored");
      final gateway = _Gateway((o) {
        if (o.uri.path == "/") return _text(200, "");
        if (o.uri.path == _endpoints) return _text(403, "device not allowed");
        return _login(o);
      });
      AppHttpClientAdapter.testOverride = gateway;

      final report = await MgwReachability.check(_gateway, force: true);

      expect(report.status, MgwStatus.unauthorized);
      expect(report.failedCheck, MgwFailedCheck.rejected);
      expect(report.httpStatus, 403);
      expect(report.gatewayMessage, "device not allowed");
      expect(report.retriedWithFreshLogin, isFalse);
      expect(gateway.to(_endpoints), hasLength(1));
      expect(gateway.to("/core/auth/login"), isEmpty);
      expect(await _storedSession(), "stored");
    });

    for (final status in [401, 403]) {
      test("a POST rejected with $status is sent once", () async {
        await _pairedWith(storedSession: "stored");
        final gateway = _Gateway((o) {
          if (o.uri.path == "/mgw-dc/commands/batch") {
            return _text(status, "rejected");
          }
          return _login(o);
        });
        AppHttpClientAdapter.testOverride = gateway;

        await expectLater(
            MgwService.forGateway(_gateway)
                .Post("/mgw-dc/commands/batch", "[]", Options()),
            throwsA(isA<Failure>()));

        expect(gateway.to("/mgw-dc/commands/batch"), hasLength(1));
      });
    }

    test("a new session that is rejected is not retried", () async {
      await _pairedWith();
      final gateway = _Gateway((o) {
        if (o.uri.path == "/") return _text(200, "");
        if (o.uri.path == _endpoints) return _text(401, "unknown session");
        return _login(o);
      });
      AppHttpClientAdapter.testOverride = gateway;

      final report = await MgwReachability.check(_gateway, force: true);

      expect(report.status, MgwStatus.unauthorized);
      expect(report.sessionReused, isFalse);
      expect(report.retriedWithFreshLogin, isFalse);
      expect(gateway.to(_endpoints), hasLength(1));
    });
  });

  group("no session to send", () {
    test("without credentials: reported as such, nothing sent", () async {
      FlutterSecureStorage.setMockInitialValues({});
      final gateway = _Gateway((o) => o.uri.path == "/" ? _text(200, "") : null);
      AppHttpClientAdapter.testOverride = gateway;

      final report = await MgwReachability.check(_gateway, force: true);

      expect(report.status, MgwStatus.unauthorized);
      expect(report.failedCheck, MgwFailedCheck.noCredentials);
      expect(gateway.to(_endpoints), isEmpty);
    });

    test("a failed login is told apart from a rejection", () async {
      await _pairedWith();
      final gateway = _Gateway((o) {
        if (o.uri.path == "/") return _text(200, "");
        if (o.uri.path == "/core/auth/login/api") {
          return _json(200, {"id": "flow-1"});
        }
        if (o.uri.path == "/core/auth/login") {
          return _json(400, {
            "error": {"code": 400, "reason": "the provided credentials are invalid"}
          });
        }
        return _json(200, {});
      });
      AppHttpClientAdapter.testOverride = gateway;

      final report = await MgwReachability.check(_gateway, force: true);

      expect(report.status, MgwStatus.unauthorized);
      expect(report.failedCheck, MgwFailedCheck.loginFailed);
      expect(report.httpStatus, 400);
      expect(report.gatewayMessage, "the provided credentials are invalid");
      expect(gateway.to(_endpoints), isEmpty);
    });
  });

  test("pairing drops the session of the replaced credentials", () async {
    await _pairedWith(storedSession: "stored");
    await MgwStorage.ReplacePairedMGWs([_gateway]);
    AppHttpClientAdapter.testOverride = _Gateway((o) =>
        o.uri.path == "/core/api/auth-service/pairing/request"
            ? _json(200, {"id": "id-2", "login": "login-2", "secret": "s-2"})
            : null);

    final stored = await PairWithGateway(MGW(_host, _host, "", _host),
        replacing: _gateway);

    expect(stored.pairingId, _pairing);
    expect(await _storedSession(), isNull);
    expect((await MgwStorage.LoadCredentials(_pairing)).login, "login-2");
  });

  test("the gateway login is not held back by local mode", () async {
    // In local mode a host counts as available only once a probe has marked
    // it local - and the probe needs this login to do so.
    await Settings.setLocalMode(true);
    addTearDown(() => Settings.setLocalMode(false));
    final gateway = _Gateway((o) => _login(o));
    AppHttpClientAdapter.testOverride = gateway;

    final login = await MgwAuth(_host).Login("login", "s");

    expect(login.token, "fresh");
  });
}
