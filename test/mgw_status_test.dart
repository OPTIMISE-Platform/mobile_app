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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_dot.dart';

void main() {
  group("classify", () {
    test("a rejected request means the gateway forgot this device", () {
      // The gateway answered the liveness check, so anything it says about the
      // authenticated one is a rejection - a reinstalled gateway looks exactly
      // like this.
      expect(MgwReachability.classify(ErrorCode.UNAUTHORIZED),
          equals(MgwStatus.unauthorized));
      expect(MgwReachability.classify(ErrorCode.NOT_FOUND),
          equals(MgwStatus.unauthorized));
      expect(MgwReachability.classify(ErrorCode.SERVER_ERROR),
          equals(MgwStatus.unauthorized));
      expect(MgwReachability.classify(ErrorCode.BAD_REQUEST),
          equals(MgwStatus.unauthorized));
      expect(MgwReachability.classify(ErrorCode.DEFAULT),
          equals(MgwStatus.unauthorized));
    });

    test("a request that did not get through means out of reach", () {
      for (final code in [
        ErrorCode.CONNECT_TIMEOUT,
        ErrorCode.RECEIVE_TIMEOUT,
        ErrorCode.SEND_TIMEOUT,
        ErrorCode.NO_INTERNET_CONNECTION,
      ]) {
        expect(MgwReachability.classify(code), equals(MgwStatus.unreachable),
            reason: "$code");
      }
    });
  });

  group("cache key", () {
    test("carries the expected network", () {
      // An answer found without an expectation says nothing about identity, so
      // it must not be handed to a call that asked for one.
      expect(MgwReachability.cacheKeyFor("10.0.2.2", null),
          isNot(equals(MgwReachability.cacheKeyFor("10.0.2.2", "urn:hub:a"))));
      expect(MgwReachability.cacheKeyFor("10.0.2.2", "urn:hub:a"),
          isNot(equals(MgwReachability.cacheKeyFor("10.0.2.2", "urn:hub:b"))));
    });

    test("separates hosts", () {
      expect(MgwReachability.cacheKeyFor("a", "n"),
          isNot(equals(MgwReachability.cacheKeyFor("b", "n"))));
    });
  });

  group("status dot", () {
    test("every status has its own colour", () {
      final colours = {
        MgwStatusDot.colorOf(MgwStatus.ok),
        MgwStatusDot.colorOf(MgwStatus.unauthorized),
        MgwStatusDot.colorOf(MgwStatus.unreachable),
      };
      expect(colours, hasLength(3));
      // A stranger at the address is as unusable as a rejection, so it shares
      // the colour - the label is what tells them apart.
      expect(MgwStatusDot.colorOf(MgwStatus.foreign),
          equals(MgwStatusDot.colorOf(MgwStatus.unauthorized)));
      expect(MgwStatusDot.colorOf(MgwStatus.ok), equals(Colors.green));
      expect(MgwStatusDot.colorOf(MgwStatus.unauthorized), equals(Colors.red));
    });

    test("an unknown status is not shown as connected", () {
      // Before the first probe answers there is nothing to claim - showing
      // green there would assert exactly what has not been checked yet.
      expect(MgwStatusDot.colorOf(null), isNot(equals(Colors.green)));
      expect(MgwStatusDot.labelOf(null), equals("Checking"));
    });

    test("every status has its own label", () {
      final labels = {
        MgwStatusDot.labelOf(MgwStatus.ok),
        MgwStatusDot.labelOf(MgwStatus.unauthorized),
        MgwStatusDot.labelOf(MgwStatus.unreachable),
        MgwStatusDot.labelOf(MgwStatus.foreign),
        MgwStatusDot.labelOf(null),
      };
      expect(labels, hasLength(5));
    });
  });
}
