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

import "dart:io";

import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile_app/exceptions/api_unavailable_exception.dart";
import "package:mobile_app/exceptions/unexpected_status_code_exception.dart";
import "package:mobile_app/shared/error_reporter.dart";

void main() {
  late List<String> shown;
  late DateTime now;

  setUp(() {
    shown = [];
    now = DateTime(2026, 1, 1, 12);
    ErrorReporter.clock = () => now;
    ErrorReporter.present = shown.add;
  });

  tearDown(ErrorReporter.resetForTest);

  DioException connectionFailure() => DioException(
      requestOptions: RequestOptions(path: "/x"),
      type: DioExceptionType.connectionError);

  group("offline detection", () {
    test("a request that never got a response counts as offline", () {
      expect(ErrorReporter.isOffline(connectionFailure()), isTrue);
      expect(ErrorReporter.isOffline(UnexpectedStatusCodeException(null, "x")),
          isTrue);
      expect(ErrorReporter.isOffline(ApiUnavailableException()), isTrue);
      expect(
          ErrorReporter.isOffline(const SocketException("no route")), isTrue);
    });

    test("a socket failure wrapped by dio is still offline", () {
      final wrapped = DioException(
          requestOptions: RequestOptions(path: "/x"),
          type: DioExceptionType.unknown,
          error: const SocketException("no route"));
      expect(ErrorReporter.isOffline(wrapped), isTrue);
    });

    test("a refusal from the backend is not offline", () {
      expect(ErrorReporter.isOffline(UnexpectedStatusCodeException(403, "x")),
          isFalse);
      expect(ErrorReporter.isOffline(Exception("something else")), isFalse);
      expect(ErrorReporter.isOffline(null), isFalse);
    });
  });

  group("reporting", () {
    test("a failure with no connection is named by its cause, not its endpoint",
        () {
      ErrorReporter.report("Could not get devices", connectionFailure());
      expect(shown, [ErrorReporter.offlineMessage]);
    });

    test("one offline start does not stack a toast per endpoint", () {
      // This is what the state layer does on a start without a connection: each
      // loader reports its own failure, all with the same cause.
      for (final what in const [
        "Could not get devices",
        "Could not get deviceGroups",
        "Could not get networks",
        "Could not get locations",
        "Could not load aspects",
      ]) {
        ErrorReporter.report(what, connectionFailure());
      }
      expect(shown, [ErrorReporter.offlineMessage]);
    });

    test("the same message shows again once the first is off screen", () {
      ErrorReporter.report("Could not get devices", connectionFailure());
      now = now.add(const Duration(seconds: 30));
      ErrorReporter.report("Could not get devices", connectionFailure());
      expect(shown,
          [ErrorReporter.offlineMessage, ErrorReporter.offlineMessage]);
    });

    test("different failures are not collapsed into each other", () {
      ErrorReporter.report("Could not delete notifications",
          UnexpectedStatusCodeException(500, "x"));
      ErrorReporter.report(
          "Could not update notification", UnexpectedStatusCodeException(500, "x"));
      expect(shown,
          ["Could not delete notifications", "Could not update notification"]);
    });

    test("a failure the backend answered keeps its own message", () {
      ErrorReporter.report(
          "Could not load devices", UnexpectedStatusCodeException(500, "x"));
      expect(shown, ["Could not load devices"]);
    });

    test("reportOffline needs no exception to inspect", () {
      ErrorReporter.reportOffline();
      expect(shown, [ErrorReporter.offlineMessage]);
    });
  });
}
