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

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/advertisements.dart';
import 'package:mobile_app/services/mgw/api.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';

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
  ));

  static final _logger = Logger(printer: SimplePrinter());

  static final Map<String, _Probe> _cache = {};

  /// Probes that are running right now, so a rebuild joins the request in
  /// flight instead of starting another one.
  static final Map<String, Future<MgwStatus>> _pending = {};

  /// Drops the cached results, so the next check probes again. Probes already
  /// in flight are left alone - they answer for the network they started in.
  static void forget() => _cache.clear();

  // The expectation belongs in the key: an answer found without one says
  // nothing about identity, and reusing it for a call that carries one would
  // skip the very check that call asked for.
  @visibleForTesting
  static String cacheKeyFor(String host, String? expectNetworkId) =>
      "$host|${expectNetworkId ?? ''}";

  /// Status of the gateway at [host]. Cached for [cacheTtl].
  ///
  /// [expectNetworkId] is the network the gateway was bound to; when it
  /// advertises a different one, the answer is [MgwStatus.foreign].
  static Future<MgwStatus> statusOf(String host,
      {String? expectNetworkId}) async {
    final key = cacheKeyFor(host, expectNetworkId);
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at) < cacheTtl) {
      return cached.status;
    }
    return _pending.putIfAbsent(key, () async {
      try {
        final status = await _probe(host, expectNetworkId);
        _cache[key] = _Probe(status, DateTime.now());
        return status;
      } finally {
        _pending.remove(key);
      }
    });
  }

  /// The cached status, or null when nothing was probed yet. For a widget that
  /// must not start a request while building.
  static MgwStatus? cachedStatusOf(String host, {String? expectNetworkId}) {
    final cached = _cache[cacheKeyFor(host, expectNetworkId)];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.at) >= cacheTtl) return null;
    return cached.status;
  }

  /// Whether the gateway at [host] can be used right now.
  static Future<bool> isUsable(String host, {String? expectNetworkId}) async =>
      await statusOf(host, expectNetworkId: expectNetworkId) == MgwStatus.ok;

  /// Checks several gateways at once and returns the hosts that can be used.
  ///
  /// Takes pairs rather than a map: two gateways can share an address while
  /// serving different networks, and a map would silently keep only one.
  static Future<List<String>> usableAmong(
      Iterable<MapEntry<String, String>> hostsWithNetwork) async {
    final checked = await Future.wait(hostsWithNetwork.map((e) async =>
        MapEntry(e.key, await isUsable(e.key, expectNetworkId: e.value))));
    return checked.where((e) => e.value).map((e) => e.key).toList();
  }

  static Future<MgwStatus> _probe(String host, String? expectNetworkId) async {
    if (!await _answers(host)) {
      _logger.d("$LOG_PREFIX: $host is out of reach");
      return MgwStatus.unreachable;
    }
    if (expectNetworkId != null && expectNetworkId.isNotEmpty) {
      final advertised =
          await MgwAdvertisements.networkIdOf(host, budget: probeTimeout);
      if (advertised.isNotEmpty && advertised != expectNetworkId) {
        _logger.d("$LOG_PREFIX: $host serves $advertised, not $expectNetworkId");
        return MgwStatus.foreign;
      }
    }
    final status = await _authenticates(host);
    _logger.d("$LOG_PREFIX: $host is $status");
    return status;
  }

  /// Unauthenticated liveness check: the gateway answers "/" with a redirect to
  /// its web ui, so any answer at all shows it is in reach.
  static Future<bool> _answers(String host) async {
    try {
      await _dio.get("http://${gatewayAuthority(host)}/");
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sends one request that needs the session token the pairing produced. It is
  /// the same path every local device call takes, so nothing is spent here that
  /// the first real call would not spend anyway.
  static Future<MgwStatus> _authenticates(String host) async {
    try {
      await MgwApiService(host, true).Get("/core-manager/endpoints", Options());
      return MgwStatus.ok;
    } on Failure catch (e) {
      return classify(e.errorCode);
    } catch (e) {
      _logger.d("$LOG_PREFIX: $host failed the authenticated check: $e");
      return MgwStatus.unauthorized;
    }
  }

  /// A gateway that answered the liveness check but failed the authenticated
  /// one is only unreachable when the second request did not get through
  /// either; anything the gateway itself answered means it rejected us.
  @visibleForTesting
  static MgwStatus classify(ErrorCode code) {
    switch (code) {
      case ErrorCode.CONNECT_TIMEOUT:
      case ErrorCode.RECEIVE_TIMEOUT:
      case ErrorCode.SEND_TIMEOUT:
      case ErrorCode.NO_INTERNET_CONNECTION:
        return MgwStatus.unreachable;
      default:
        return MgwStatus.unauthorized;
    }
  }
}

class _Probe {
  final MgwStatus status;
  final DateTime at;
  _Probe(this.status, this.at);
}
