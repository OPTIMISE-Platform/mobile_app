/*
 * Copyright 2023 InfAI (CC SES)
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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/error_reporter.dart';

class ApiAvailableService {
  static final _instance = ApiAvailableService._internal();

  factory ApiAvailableService() => _instance;

  ApiAvailableService._internal();

  static final _logger = Logger(printer: SimplePrinter());

  /// How often a probe looks for the platform again while it is unreachable.
  @visibleForTesting
  static Duration recheckInterval = const Duration(seconds: 60);

  /// Replaces the network probe of [recheckPlatform]; true means reachable.
  @visibleForTesting
  static Future<bool> Function()? probeOverride;

  /// Request extra marking a probe: it passes the interceptor while the
  /// platform is unreachable and its failure is not recorded.
  static const probeExtra = "platform_probe";

  /// Request extra holding [reachabilityEpoch] at the time the request left.
  static const epochExtra = "platform_epoch";

  static final _unreachable = ValueNotifier<bool>(false);

  /// True while the platform is known not to answer: a platform request failed
  /// without a response, or the auth server could not be reached. Cleared only
  /// by a successful probe.
  static ValueListenable<bool> get platformUnreachable => _unreachable;

  static bool get isPlatformUnreachable => _unreachable.value;

  /// Platform calls are refused as a matter of course: the platform is
  /// unreachable or the user chose the local mode.
  static bool get platformCallsOff =>
      isPlatformUnreachable ||
      (Settings.isInitialized && Settings.getLocalMode());

  static final _found = StreamController<void>.broadcast();

  /// Fires each time a probe finds the platform again after it was marked
  /// unreachable, which is the only way the mark is cleared outside tests.
  static Stream<void> get platformFound => _found.stream;

  static int _epoch = 0;

  /// Advances each time the platform is found reachable again. An observation
  /// made under an older value predates that probe and is dropped.
  static int get reachabilityEpoch => _epoch;

  static Timer? _recheckTimer;
  static Future<bool>? _probing;

  // performance evaluated, adds less than 2 ms to each request
  bool isAvailable(String uri) {
    // TODO request from backend, cache, match against routes
    if (servedLocally(AppState().networks, uri)) {
      return true;
    }
    if (isPlatformUnreachable) {
      return false;
    }
    return !Settings.getLocalMode();
  }

  /// Records that the platform did not answer. [observedAt] is the
  /// [reachabilityEpoch] the observation was made under.
  void markPlatformUnreachable({int? observedAt}) {
    if (observedAt != null && observedAt != _epoch) return;
    if (_unreachable.value) return;
    _logger.w("Platform not reachable");
    _unreachable.value = true;
    _startRechecks();
  }

  /// Marks the platform unreachable only if a probe fails as well: one slow
  /// or broken endpoint must not cut the app off. No probe in the local mode.
  Future<void> confirmUnreachable({int? observedAt}) async {
    if (_unreachable.value || _localMode) return;
    if (!await _probe()) markPlatformUnreachable(observedAt: observedAt);
  }

  /// Probes the platform while it is marked unreachable and clears the mark
  /// when it answers. In the local mode, which asks nothing of the platform,
  /// it only stops the rechecks.
  Future<void> recheckPlatform() async {
    if (!_unreachable.value) return;
    if (_localMode) {
      _stopRechecks();
      return;
    }
    _startRechecks();
    if (await _probe()) _markReachable();
  }

  /// Called for every failed request of the app's Dio instances.
  void recordFailure(DioException e) {
    final options = e.requestOptions;
    if (options.extra[probeExtra] == true) return;
    if (e.error is ApiUnavailableException) return;
    if (!isPlatformUri(options.uri)) return;
    final observedAt = options.extra[epochExtra] as int?;
    final status = e.response?.statusCode;
    // The ingress answers so for a single dead service too.
    if (status == 502 || status == 503 || status == 504) {
      unawaited(confirmUnreachable(observedAt: observedAt));
      return;
    }
    if (!ErrorReporter.isOffline(e)) return;
    switch (e.type) {
      // The platform took the connection, so only a failed probe confirms
      // the outage.
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        unawaited(confirmUnreachable(observedAt: observedAt));
      default:
        markPlatformUnreachable(observedAt: observedAt);
    }
  }

  static bool get _localMode =>
      Settings.isInitialized && Settings.getLocalMode();

  /// The periodic recheck runs only while the platform is marked unreachable
  /// outside the local mode.
  static void _startRechecks() {
    if (_localMode) return;
    _recheckTimer ??= Timer.periodic(
        recheckInterval, (_) => unawaited(ApiAvailableService().recheckPlatform()));
  }

  static void _stopRechecks() {
    _recheckTimer?.cancel();
    _recheckTimer = null;
  }

  void _markReachable() {
    _stopRechecks();
    if (!_unreachable.value) return;
    _epoch++;
    _logger.i("Platform reachable again");
    _unreachable.value = false;
    _found.add(null);
  }

  /// One probe at a time; concurrent callers share its result.
  Future<bool> _probe() => _probing ??= _runProbe().whenComplete(() {
        _probing = null;
      });

  /// The platform is reachable when the auth server serves its discovery
  /// document and the API host answers with anything but a gateway error.
  Future<bool> _runProbe() async {
    try {
      if (probeOverride != null) return await probeOverride!();
      final dio = await DioFactory.create(DioConfig.standard);
      final options =
          Options(extra: {probeExtra: true}, validateStatus: (_) => true);
      final api = Settings.getApiUrl();
      final answers = await Future.wait([
        dio
            .get(Auth().discoveryUrl, options: options)
            .then((r) => r.statusCode == 200),
        if (api != null)
          dio.get(api, options: options).then((r) =>
              r.statusCode != 502 && r.statusCode != 503 && r.statusCode != 504),
      ]);
      return answers.every((ok) => ok);
    } catch (e) {
      _logger.d("Platform probe failed: $e");
      return false;
    }
  }

  /// Whether [uri] addresses the platform's API or auth server.
  static bool isPlatformUri(Uri uri) {
    if (!Settings.isInitialized) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return [Settings.getApiUrl(), Settings.getKeycloakUrl()].any((url) =>
        url != null && Uri.tryParse(url)?.host.toLowerCase() == host);
  }

  /// Whether the recheck timer runs.
  @visibleForTesting
  static bool get rechecking => _recheckTimer != null;

  /// Sets the state without starting the recheck timer.
  @visibleForTesting
  static void setUnreachableForTest(bool value) {
    if (!value) _epoch++;
    _unreachable.value = value;
  }

  /// Clears the state, the timer and the probe seam.
  @visibleForTesting
  static void resetForTest() {
    _stopRechecks();
    _probing = null;
    probeOverride = null;
    recheckInterval = const Duration(seconds: 60);
    if (_unreachable.value) _epoch++;
    _unreachable.value = false;
  }

  /// Whether [uri] addresses a gateway that serves one of [networks].
  ///
  /// Such a request stays inside the local network and is reachable even when
  /// the cloud is not, which is what makes it available regardless of the local
  /// mode setting.
  @visibleForTesting
  static bool servedLocally(Iterable<Network> networks, String uri) {
    final host = Uri.parse(uri).host.toLowerCase();
    if (host.isEmpty) return false;
    return networks.any((network) =>
        network.localGateways?.any(
            (gateway) => gatewayHostOnly(gateway.ip).toLowerCase() == host) ??
        false);
  }
}
