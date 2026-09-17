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
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';

const LOG_PREFIX = "MGW-REACHABILITY";

/// Tells whether a paired gateway can be reached from the network the device is
/// on right now.
///
/// A gateway sits in one local network and the device is not always in it, so a
/// paired gateway is not a usable one. Without this check every local request
/// would run into its timeout first and only then fall back to the cloud.
///
/// This answers reachability, not identity: something else answering on the same
/// private address in a foreign network counts as reachable. Telling the two
/// apart would need an unauthenticated endpoint that names the core, and the
/// gateway has none.
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

  /// Drops the cached results, so the next check probes again.
  static void forget() => _cache.clear();

  /// Whether the gateway at [host] answers. Cached for [cacheTtl].
  static Future<bool> isReachable(String host) async {
    final cached = _cache[host];
    if (cached != null && DateTime.now().difference(cached.at) < cacheTtl) {
      return cached.reachable;
    }
    final reachable = await _probe(host);
    _cache[host] = _Probe(reachable, DateTime.now());
    return reachable;
  }

  /// Probes several gateways at once and returns those that answered.
  static Future<List<String>> reachableAmong(Iterable<String> hosts) async {
    final checked = await Future.wait(hosts.map((host) async =>
        MapEntry(host, await isReachable(host))));
    return checked.where((e) => e.value).map((e) => e.key).toList();
  }

  static Future<bool> _probe(String host) async {
    // The gateway answers "/" with a redirect to its web ui, which needs no
    // session - any answer at all is enough to show it is in reach.
    final url = "http://${gatewayAuthority(host)}/";
    try {
      final response = await _dio.get(url);
      _logger.d("$LOG_PREFIX: $host answered ${response.statusCode}");
      return true;
    } catch (e) {
      _logger.d("$LOG_PREFIX: $host is out of reach: $e");
      return false;
    }
  }
}

class _Probe {
  final bool reachable;
  final DateTime at;
  _Probe(this.reachable, this.at);
}
