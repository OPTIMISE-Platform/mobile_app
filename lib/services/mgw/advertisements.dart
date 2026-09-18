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
import 'package:mobile_app/services/mgw/gateway_host.dart';

const LOG_PREFIX = "MGW-ADVERTISEMENTS";

/// Reads what a gateway publishes about itself.
///
/// Deployments advertise key/value records under a reference; the cloud proxy
/// puts the id of the cloud network the gateway serves under `network`. The
/// route needs no session, so this answers before a gateway is paired.
class MgwAdvertisements {
  /// Reference the cloud proxy publishes the network id under.
  static const networkReference = "network";

  static const timeout = Duration(milliseconds: 2500);

  // Own client for the same reason as the status probe: the shared factory
  // installs ApiAvailableInterceptor, which asks about the very gateway that is
  // being examined here.
  static final _dio = Dio(BaseOptions(
    connectTimeout: timeout,
    sendTimeout: timeout,
    receiveTimeout: timeout,
  ));

  static final _logger = Logger(printer: SimplePrinter());

  /// Id of the cloud network the gateway at [host] serves, empty when it
  /// advertises none.
  ///
  /// A gateway whose cloud proxy has not been signed in to the platform yet
  /// advertises nothing - that is an empty answer, not an error.
  /// [budget] shortens the wait for a caller that already knows the host
  /// answers - the status check has just proven that and must not double its
  /// own budget here.
  static Future<String> networkIdOf(String host, {Duration? budget}) async {
    final url =
        "http://${gatewayAuthority(host)}/core/discovery?reference=$networkReference";
    try {
      final response = await _dio.get(url,
          options: budget == null
              ? null
              : Options(receiveTimeout: budget, sendTimeout: budget));
      final id = networkIdFrom(response.data);
      _logger.d("$LOG_PREFIX: $host serves network '${id.isEmpty ? '-' : id}'");
      return id;
    } catch (e) {
      _logger.d("$LOG_PREFIX: $host published no network: $e");
      return "";
    }
  }

  /// Picks the network id out of an advertisement list.
  @visibleForTesting
  static String networkIdFrom(dynamic body) {
    if (body is! List) return "";
    for (final entry in body) {
      if (entry is! Map) continue;
      if (entry["reference"] != networkReference) continue;
      final items = entry["items"];
      if (items is! Map) continue;
      final id = items["id"];
      if (id is String && id.isNotEmpty) return id;
    }
    return "";
  }
}
