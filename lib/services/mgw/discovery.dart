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

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:nsd/nsd.dart';

const LOG_PREFIX = "MGW-DISCOVERY-SERVICE";

/// A gateway found on the local link.
class DiscoveredGateway {
  /// The gateway's own core id, from the `core_id` TXT record. This is not a
  /// cloud network id; the gateway does not publish which network it serves.
  final String coreId;

  /// mDNS instance name.
  final String name;

  final String hostname;

  /// Resolved address, empty if none was reported.
  final String ip;

  /// Never zero: a service resolved without a port falls back to the default,
  /// because an address built from port 0 is unreachable and says nothing about
  /// why.
  final int port;

  DiscoveredGateway({
    required this.coreId,
    required this.name,
    required this.hostname,
    required this.ip,
    required this.port,
  });

  @override
  String toString() =>
      "DiscoveredGateway($name, coreId: $coreId, $hostname/$ip:$port)";
}

/// Finds MGW cores via mDNS.
///
/// Browsing needs a fixed service type, and the core does not have one yet: it
/// advertises `_mgwcore_<core id>._tcp`, so the type carries the id nobody knows
/// in advance. Until the core publishes [coreServiceType], this finds nothing
/// and a gateway is added by address instead (SNRGY ticket for the core side).
///
/// Enumerating the types instead, via a raw mDNS client, was tried and reverted:
/// it works, but `RawDatagramSocket.joinMulticast` is synchronous and was
/// measured blocking the calling isolate for over a minute, which Android ends
/// as an ANR. The platform's own discovery does that work off the Dart isolate.
class MgwDiscoveryService {
  /// Service type the core is meant to advertise under.
  ///
  /// It has to be the same for every core: a type carrying the core id cannot be
  /// browsed, and it also breaks RFC 6335, which allows no underscore inside the
  /// label and at most 15 characters - `nsd` rejects such a type outright.
  static const coreServiceType = "_mgwcore._tcp";

  /// TXT key holding the core id.
  static const coreIdRecord = "core_id";

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  /// Browses for [timeout] and returns what answered.
  static Future<List<DiscoveredGateway>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Discovery discovery;
    try {
      discovery = await startDiscovery(coreServiceType,
          ipLookupType: IpLookupType.any);
    } catch (e) {
      // Discovery is opportunistic - a gateway can always be added by address.
      _logger.e("$LOG_PREFIX: Could not start discovery: $e");
      return [];
    }

    try {
      await Future.delayed(timeout);
      final found = <String, DiscoveredGateway>{};
      for (final service in discovery.services) {
        final gateway = fromService(
          name: service.name,
          host: service.host,
          port: service.port,
          address: service.addresses?.isNotEmpty == true
              ? service.addresses!.first.address
              : null,
          txt: service.txt,
        );
        if (gateway == null) continue;
        // Keyed by host: the same core answers once per interface it is seen on.
        found[gateway.hostname] = gateway;
      }
      _logger.d("$LOG_PREFIX: Found ${found.length} gateways");
      return found.values.toList();
    } finally {
      try {
        await stopDiscovery(discovery);
      } catch (e) {
        _logger.e("$LOG_PREFIX: Could not stop discovery: $e");
      }
    }
  }

  /// Builds a gateway from one resolved service, or null if it carries no host.
  @visibleForTesting
  static DiscoveredGateway? fromService({
    String? name,
    String? host,
    int? port,
    String? address,
    Map<String, Uint8List?>? txt,
  }) {
    final hostname = host ?? "";
    if (hostname.isEmpty) return null;
    return DiscoveredGateway(
      coreId: readTxt(txt, coreIdRecord),
      name: (name ?? "").isEmpty ? hostname : name!,
      hostname: hostname,
      ip: address ?? "",
      port: (port == null || port == 0) ? defaultGatewayPort : port,
    );
  }

  /// Reads a TXT record; `nsd` hands them over as raw bytes.
  @visibleForTesting
  static String readTxt(Map<String, Uint8List?>? txt, String key) {
    final value = txt?[key];
    if (value == null || value.isEmpty) return "";
    try {
      return utf8.decode(value).trim();
    } on FormatException {
      return "";
    }
  }
}
