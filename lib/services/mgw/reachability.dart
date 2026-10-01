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

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/advertisements.dart';
import 'package:mobile_app/services/mgw/api.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';

const LOG_PREFIX = "MGW-REACHABILITY";

/// What a paired gateway is currently good for.
enum MgwStatus {
  /// Nothing answers at its address - a different local network, or the gateway
  /// is down.
  unreachable,

  /// Something answers, but it serves a different cloud network than the one
  /// this gateway was bound to - so it is not the gateway we mean, just a
  /// device at the same private address.
  foreign,

  /// It answers, but rejects this device. The pairing is stored and no longer
  /// valid, which is what a reinstalled gateway looks like: it serves its
  /// unauthenticated endpoints and knows nothing of the identity behind the
  /// stored credentials.
  unauthorized,

  /// Reachable and authenticated - the local path can be used.
  ok,

  /// The check failed on this phone (its secure storage), so nothing is known
  /// about the gateway.
  unknown,
}

/// The step of a status check that failed.
enum MgwFailedCheck {
  /// Nothing answered, either the liveness request or a later one.
  notAnswering,

  /// The gateway advertises a different cloud network than the expected one.
  foreignNetwork,

  /// The phone holds no device credentials.
  noCredentials,

  /// The gateway's identity provider issued no session.
  loginFailed,

  /// This phone could not read or write its stored session.
  sessionStorage,

  /// The gateway answered the authenticated request with an error.
  rejected,
}

/// Result of one status check, with what is needed to explain it.
@immutable
class MgwReport {
  const MgwReport({
    required this.status,
    required this.address,
    required this.checkedAt,
    this.failedCheck,
    this.error,
    this.httpStatus,
    this.gatewayMessage,
    this.expectedNetworkId,
    this.advertisedNetworkId,
    this.sessionReused,
    this.retriedWithFreshLogin = false,
  });

  final MgwStatus status;

  /// Null when every check passed.
  final MgwFailedCheck? failedCheck;

  /// Authority the probe addressed, with the port.
  final String address;

  final DateTime checkedAt;

  /// Message of a failure that carried no answer from the gateway.
  final String? error;

  /// Status of the gateway's error answer.
  final int? httpStatus;

  /// What the gateway said with its error answer.
  final String? gatewayMessage;

  final String? expectedNetworkId;

  /// Null when the advertisement was not read, empty when it names none.
  final String? advertisedNetworkId;

  /// Whether the authenticated request used the stored session; null when it
  /// did not carry one.
  final bool? sessionReused;

  /// Whether the stored session was rejected and a new login tried.
  final bool retriedWithFreshLogin;

  @override
  String toString() => "MgwReport($status, $failedCheck, $address, "
      "http: $httpStatus, gateway: $gatewayMessage, error: $error, "
      "reused: $sessionReused, retried: $retriedWithFreshLogin)";
}

/// Tells what a paired gateway is currently good for.
///
/// Being paired is a stored fact, not a live one, so it says nothing about the
/// network the device is on right now, and nothing about whether the gateway
/// still knows this device. Both are checked here, because a request that
/// assumes either runs into its timeout first and only then falls back to the
/// cloud.
///
/// Identity is settled before the session is: the gateway advertises the cloud
/// network it serves without needing one, so a device answering at the same
/// private address is told apart from the real gateway even while the pairing
/// is broken. A gateway whose cloud proxy is not signed in advertises nothing,
/// and then only the authenticated call can vouch for identity.
class MgwReachability {
  static const probeTimeout = Duration(milliseconds: 1500);

  /// Kept short: the result only has to survive one round of merging, and a
  /// device that changes networks has to notice quickly.
  static const cacheTtl = Duration(seconds: 20);

  // Own client on purpose: the shared factory installs ApiAvailableInterceptor,
  // which decides availability from the very gateway list this probe fills.
  static final _dio = Dio(BaseOptions(
    connectTimeout: probeTimeout,
    sendTimeout: probeTimeout,
    receiveTimeout: probeTimeout,
    followRedirects: false,
    validateStatus: (_) => true,
  ))
    ..httpClientAdapter = AppHttpClientAdapter.plain();

  static final _logger = Logger(printer: SimplePrinter());

  /// Replaces the network probe in tests.
  @visibleForTesting
  static Future<MgwReport> Function(String host, String? expectNetworkId)?
      probeOverride;

  /// Bumped when a report is cached or the cache is dropped, so a widget
  /// showing one can read it again or check again.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  // Cache age is measured on a monotonic clock: a wall clock set back would
  // keep an answer alive for as long as it was moved.
  static final Stopwatch _age = Stopwatch()..start();

  static final Map<String, _Entry> _cache = {};

  /// Probes that are running right now, so a rebuild joins the request in
  /// flight instead of starting another one.
  static final Map<String, _Pending> _pending = {};

  /// Moved by [forget]: a probe started before it neither fills the cache nor
  /// is joined by a later check.
  static int _epoch = 0;

  /// Order in which probes started, so one that finishes late does not replace
  /// the answer of one started after it.
  static int _sequence = 0;

  /// Drops the cached results, so the next check probes again. Probes already
  /// in flight still answer their own callers - for the network they started
  /// in - but no longer reach the cache.
  static void forget() {
    _epoch++;
    _cache.clear();
    revision.value++;
  }

  // The expectation belongs in the key: an answer found without one says
  // nothing about identity, and reusing it for a call that carries one would
  // skip the very check that call asked for.
  @visibleForTesting
  static String cacheKeyFor(String host, String? expectNetworkId) =>
      "$host|${expectNetworkId ?? ''}";

  /// Report on the gateway at [host], cached for [cacheTtl]. [force] probes
  /// again even when a fresh answer or a running probe exists.
  ///
  /// [expectNetworkId] is the network the gateway was bound to; when it
  /// advertises a different one, the answer is [MgwStatus.foreign].
  static Future<MgwReport> check(String host,
      {String? expectNetworkId, bool force = false}) {
    final key = cacheKeyFor(host, expectNetworkId);
    if (!force) {
      final cached = cachedReportOf(host, expectNetworkId: expectNetworkId);
      if (cached != null) return Future.value(cached);
      final running = _pending[key];
      if (running != null && running.epoch == _epoch) {
        return running.completer.future;
      }
    }
    final pending = _Pending(_epoch, ++_sequence);
    _pending[key] = pending;
    () async {
      try {
        final probe = probeOverride ?? _probe;
        final report = await probe(host, expectNetworkId);
        if (pending.epoch == _epoch) _store(key, pending.sequence, report);
        pending.completer.complete(report);
      } catch (e, s) {
        pending.completer.completeError(e, s);
      } finally {
        if (identical(_pending[key], pending)) _pending.remove(key);
      }
    }();
    return pending.completer.future;
  }

  static void _store(String key, int sequence, MgwReport report) {
    final previous = _cache[key];
    if (previous != null && previous.sequence > sequence) return;
    _cache[key] = _Entry(report, sequence, _age.elapsed);
    revision.value++;
  }

  /// Status of the gateway at [host]. Cached for [cacheTtl].
  static Future<MgwStatus> statusOf(String host,
          {String? expectNetworkId}) async =>
      (await check(host, expectNetworkId: expectNetworkId)).status;

  /// The cached report, or null when nothing fresh is cached. For a widget
  /// that must not start a request while building.
  static MgwReport? cachedReportOf(String host, {String? expectNetworkId}) {
    final cached = _cache[cacheKeyFor(host, expectNetworkId)];
    if (cached == null) return null;
    if (_age.elapsed - cached.storedAt >= cacheTtl) return null;
    return cached.report;
  }

  /// The cached status, or null when nothing was probed yet.
  static MgwStatus? cachedStatusOf(String host, {String? expectNetworkId}) =>
      cachedReportOf(host, expectNetworkId: expectNetworkId)?.status;

  /// Whether the gateway at [host] can be used right now.
  static Future<bool> isUsable(String host, {String? expectNetworkId}) async =>
      await statusOf(host, expectNetworkId: expectNetworkId) == MgwStatus.ok;

  /// Checks several gateways at once and returns the (host, network) pairs
  /// that can be used.
  ///
  /// Keyed by both: two gateways can share an address while serving different
  /// networks, and only the one whose own network answers may be used.
  static Future<Set<(String, String)>> usableAmong(
      Iterable<(String, String)> hostsWithNetwork) async {
    final checked = await Future.wait(hostsWithNetwork.map((e) async =>
        (e, await isUsable(e.$1, expectNetworkId: e.$2))));
    return {for (final (pair, usable) in checked) if (usable) pair};
  }

  static Future<MgwReport> _probe(String host, String? expectNetworkId) async {
    final address = gatewayAuthority(host);
    final expected = (expectNetworkId == null || expectNetworkId.isEmpty)
        ? null
        : expectNetworkId;
    MgwReport report(MgwStatus status,
            {MgwFailedCheck? failedCheck,
            String? error,
            String? advertised}) =>
        MgwReport(
            status: status,
            failedCheck: failedCheck,
            address: address,
            checkedAt: DateTime.now(),
            error: error,
            expectedNetworkId: expected,
            advertisedNetworkId: advertised);

    final silence = await _answers(host);
    if (silence != null) {
      _logger.d("$LOG_PREFIX: $host is out of reach: $silence");
      return report(MgwStatus.unreachable,
          failedCheck: MgwFailedCheck.notAnswering, error: silence);
    }
    String? advertised;
    if (expected != null) {
      advertised =
          await MgwAdvertisements.networkIdOf(host, budget: probeTimeout);
      if (advertised.isNotEmpty && advertised != expected) {
        _logger.d("$LOG_PREFIX: $host serves $advertised, not $expected");
        return report(MgwStatus.foreign,
            failedCheck: MgwFailedCheck.foreignNetwork, advertised: advertised);
      }
    }
    final result = await _authenticates(host, address, expected, advertised);
    _logger.d("$LOG_PREFIX: $host is ${result.status}");
    return result;
  }

  /// Unauthenticated liveness check: the gateway answers "/" with a redirect to
  /// its web ui, so any answer at all shows it is in reach. Returns why nothing
  /// answered, or null.
  static Future<String?> _answers(String host) async {
    try {
      await _dio.get("http://${gatewayAuthority(host)}/");
      return null;
    } on DioException catch (e) {
      return describeDioException(e);
    } catch (e) {
      return e.toString();
    }
  }

  /// Short reason for a request that got no answer.
  @visibleForTesting
  static String describeDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return "No answer within ${probeTimeout.inMilliseconds} ms";
      default:
        return e.error?.toString() ?? e.message ?? e.type.name;
    }
  }

  /// Sends one request that needs the session token the pairing produced. It is
  /// the same path every local device call takes, so nothing is spent here that
  /// the first real call would not spend anyway.
  static Future<MgwReport> _authenticates(String host, String address,
      String? expected, String? advertised) async {
    final api = MgwApiService(host, true, requireSession: true);
    final service = api.mgwService;
    MgwReport report(MgwStatus status,
            {MgwFailedCheck? failedCheck,
            Failure? failure,
            String? error}) =>
        MgwReport(
          status: status,
          failedCheck: failedCheck,
          address: address,
          checkedAt: DateTime.now(),
          error: error ??
              (failure != null && failure.statusCode == null
                  ? failure.detailedMessage
                  : null),
          httpStatus: failure?.statusCode,
          gatewayMessage:
              failure?.statusCode != null ? failure!.detailedMessage : null,
          expectedNetworkId: expected,
          advertisedNetworkId: advertised,
          sessionReused: service.retriedWithFreshSession
              ? true
              : service.lastSessionReused,
          retriedWithFreshLogin: service.retriedWithFreshSession,
        );

    try {
      await api.Get("/core-manager/endpoints", Options());
      return report(MgwStatus.ok);
    } on MgwSessionException catch (e) {
      switch (e.problem) {
        case MgwSessionProblem.noCredentials:
          return report(MgwStatus.unauthorized,
              failedCheck: MgwFailedCheck.noCredentials, error: e.message);
        case MgwSessionProblem.storageFailed:
          return report(MgwStatus.unknown,
              failedCheck: MgwFailedCheck.sessionStorage, error: e.message);
        case MgwSessionProblem.loginFailed:
          break;
      }
      final failure = e.failure;
      return report(
          failure == null ? MgwStatus.unauthorized : classify(failure.errorCode),
          failedCheck: MgwFailedCheck.loginFailed,
          failure: failure,
          error: failure == null ? e.message : null);
    } on Failure catch (e) {
      final status = classify(e.errorCode);
      return report(status,
          failedCheck: status == MgwStatus.unreachable
              ? MgwFailedCheck.notAnswering
              : MgwFailedCheck.rejected,
          failure: e);
    } catch (e) {
      _logger.d("$LOG_PREFIX: $host failed the authenticated check: $e");
      return report(MgwStatus.unauthorized,
          failedCheck: MgwFailedCheck.rejected, error: e.toString());
    }
  }

  /// A gateway that answered the liveness check but failed the authenticated
  /// one is only unreachable when the second request did not get through
  /// either; anything the gateway itself answered means it rejected us.
  static MgwStatus classify(ErrorCode code) {
    switch (code) {
      case ErrorCode.CONNECT_TIMEOUT:
      case ErrorCode.RECEIVE_TIMEOUT:
      case ErrorCode.SEND_TIMEOUT:
      case ErrorCode.NO_INTERNET_CONNECTION:
      case ErrorCode.CONNECTION_ERROR:
        return MgwStatus.unreachable;
      default:
        return MgwStatus.unauthorized;
    }
  }
}

class _Entry {
  final MgwReport report;
  final int sequence;

  /// Reading of [MgwReachability._age] when stored.
  final Duration storedAt;

  _Entry(this.report, this.sequence, this.storedAt);
}

class _Pending {
  final int epoch;
  final int sequence;
  final completer = Completer<MgwReport>();

  _Pending(this.epoch, this.sequence);
}
