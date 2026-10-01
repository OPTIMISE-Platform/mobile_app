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

  /// The address to pair with and to store, with the port kept. Pairing and
  /// the address refresh both read this, so a stored address and a refreshed
  /// one compare equal when nothing moved.
  String get address => gatewayAddress(ip.isEmpty ? hostname : ip, port);

  @override
  String toString() =>
      "DiscoveredGateway($name, coreId: $coreId, $hostname/$ip:$port)";
}

/// Called with everything found so far, each time the platform reports a
/// change.
typedef DiscoveryUpdate = void Function(List<DiscoveredGateway> found);

/// Finds MGW cores via mDNS.
///
/// Browsing needs a fixed service type. The core advertised `_mgwcore_<core
/// id>._tcp` until SNRGY-4733, a type carrying the id nobody knows in advance,
/// so nothing could browse for it; a gateway had to be added by address. Cores
/// installed from that release on publish [coreServiceType], older ones still
/// do not, which is why adding by address stays.
///
/// Enumerating the types instead, via a raw mDNS client, was tried and reverted:
/// it works, but `RawDatagramSocket.joinMulticast` is synchronous and was
/// measured blocking the calling isolate for over a minute, which Android ends
/// as an ANR. The platform's own discovery does that work off the Dart isolate.
class MgwDiscoveryService {
  /// Service type the core advertises under, from mgw-core-installer.
  ///
  /// The same for every core, because a type carrying the core id cannot be
  /// browsed. The name is also bounded by RFC 6335, which allows no underscore
  /// inside the label and at most 15 characters - `nsd` rejects such a type
  /// outright, which is why the installer shortened it.
  static const coreServiceType = "_snrgy-mgwcore._tcp";

  /// TXT key holding the core id.
  static const coreIdRecord = "core_id";

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  /// Replaces [discover] in tests, which have no platform discovery.
  @visibleForTesting
  static Future<List<DiscoveredGateway>> Function(DiscoveryUpdate? onUpdate)?
      discoverOverride;

  /// Browses for [timeout] and returns what answered. [onUpdate] gets the
  /// gateways as they come in.
  ///
  /// Throws when discovery cannot start; a caller that treats discovery as
  /// optional catches that itself.
  static Future<List<DiscoveredGateway>> discover({
    Duration timeout = const Duration(seconds: 5),
    DiscoveryUpdate? onUpdate,
  }) async {
    final override = discoverOverride;
    if (override != null) return override(onUpdate);

    final Discovery discovery;
    try {
      discovery = await startDiscovery(coreServiceType,
          ipLookupType: IpLookupType.any);
    } catch (e) {
      _logger.e("$LOG_PREFIX: Could not start discovery: $e");
      rethrow;
    }

    void notify() => onUpdate?.call(_collect(discovery.services));
    if (onUpdate != null) discovery.addListener(notify);
    try {
      await Future.delayed(timeout);
      final found = _collect(discovery.services);
      _logger.d("$LOG_PREFIX: Found ${found.length} gateways");
      return found;
    } finally {
      if (onUpdate != null) discovery.removeListener(notify);
      try {
        await stopDiscovery(discovery);
      } catch (e) {
        _logger.e("$LOG_PREFIX: Could not stop discovery: $e");
      }
    }
  }

  static List<DiscoveredGateway> _collect(List<Service> services) {
    final found = <String, DiscoveredGateway>{};
    for (final service in services) {
      final gateway = fromService(
        name: service.name,
        host: service.host,
        port: service.port,
        address: pickAddress(service.addresses),
        txt: service.txt,
      );
      if (gateway == null) continue;
      // Keyed by host: the same core answers once per interface it is seen on.
      found[gateway.hostname] = gateway;
    }
    return found.values.toList();
  }

  /// The address to reach a gateway at: IPv4 first, because a lookup of any
  /// type may list an IPv6 one first and a link-local one is not routable
  /// without its zone, then a routable IPv6 address, then whatever is left.
  @visibleForTesting
  static String? pickAddress(List<InternetAddress>? addresses) {
    if (addresses == null || addresses.isEmpty) return null;
    final ipv4 =
        addresses.where((a) => a.type == InternetAddressType.IPv4).firstOrNull;
    if (ipv4 != null) return ipv4.address;
    final routable = addresses
        .where((a) => a.type == InternetAddressType.IPv6 && !a.isLinkLocal)
        .firstOrNull;
    return (routable ?? addresses.first).address;
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
