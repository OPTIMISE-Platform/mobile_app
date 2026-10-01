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

const defaultGatewayPort = 8080;

final _explicitPort = RegExp(r":\d+$");

/// `[literal]` with an optional `:port`.
final _bracketed = RegExp(r"^\[([^\]]*)\](:\d+)?$");

/// An IPv6 literal without brackets has at least two colons; a host with a
/// port has exactly one, so the two cannot be confused.
bool _isBareIpv6(String host) =>
    !host.startsWith("[") && ":".allMatches(host).length > 1;

/// An IPv6 literal with its zone id's `%` escaped as a URI writes it.
///
/// A zone that already starts with the escape `25` and has more after it is
/// read as escaped and decoded once first; a bare `%25` is the raw zone 25.
String _escapeZone(String literal) {
  final at = literal.indexOf("%");
  if (at < 0) return literal;
  var zone = literal.substring(at + 1);
  if (zone.startsWith("25") && zone.length > 2) zone = zone.substring(2);
  return "${literal.substring(0, at)}%25$zone";
}

/// Brackets an IPv6 literal for use in a URL.
String _bracket(String literal) => "[${_escapeZone(literal)}]";

/// Authority to address a gateway with.
///
/// [host] may already carry a port - the installer's gateway port is
/// configurable and mDNS reports it per core, so a gateway is not necessarily
/// on [defaultGatewayPort]. An IPv6 literal comes bare or bracketed; the last
/// group of a bare one is part of the address, never a port.
String gatewayAuthority(String host) {
  final h = host.trim();
  if (_isBareIpv6(h)) return "${_bracket(h)}:$defaultGatewayPort";
  final bracketed = _bracketed.firstMatch(h);
  if (bracketed != null) {
    return "${_bracket(bracketed.group(1)!)}"
        "${bracketed.group(2) ?? ":$defaultGatewayPort"}";
  }
  return _explicitPort.hasMatch(h) ? h : "$h:$defaultGatewayPort";
}

/// The host part of a stored gateway address, for comparing against the host of
/// a parsed URI, which never carries the port or the brackets.
String gatewayHostOnly(String host) {
  final h = host.trim();
  if (_isBareIpv6(h)) return _escapeZone(h);
  final bracketed = _bracketed.firstMatch(h);
  if (bracketed != null) return _escapeZone(bracketed.group(1)!);
  return h.replaceFirst(_explicitPort, "");
}

final _scheme = RegExp(r"^https?://", caseSensitive: false);
final _bracketedInput = RegExp(r"^\[([^\]]+)\](?::(\d+))?$");
final _hostInput = RegExp(r"^([^:]+)(?::(\d+))?$");
final _dottedDigits = RegExp(r"^[\d.]+$");
final _hostName = RegExp(r"^[A-Za-z0-9._-]+$");
final _alphanumeric = RegExp(r"[A-Za-z0-9]");

/// A gateway address typed by hand, as it is stored (see [gatewayAddress]):
/// without a scheme, path, query or fragment, with the port as a number and
/// the default one left out. Null when what remains is not a host name, an
/// IPv4 or IPv6 address, with an optional port.
String? parseGatewayInput(String input) {
  var h = input.trim().replaceFirst(_scheme, "");
  final end = h.indexOf(RegExp(r"[/?#]"));
  if (end >= 0) h = h.substring(0, end);
  if (h.isEmpty) return null;

  final String host;
  final String? port;
  final bracketed = _bracketedInput.firstMatch(h);
  if (bracketed != null) {
    host = bracketed.group(1)!;
    port = bracketed.group(2);
  } else if (_isBareIpv6(h)) {
    host = h;
    port = null;
  } else {
    final plain = _hostInput.firstMatch(h);
    if (plain == null) return null;
    host = plain.group(1)!;
    port = plain.group(2);
  }

  final String normalized;
  if (host.contains(":")) {
    try {
      Uri.parseIPv6Address(host.split("%").first);
    } on FormatException {
      return null;
    }
    normalized = host;
  } else if (_dottedDigits.hasMatch(host)) {
    final octets = host.split(".");
    if (octets.length != 4) return null;
    final values = octets.map(int.tryParse).toList();
    if (values.any((v) => v == null || v > 255)) return null;
    normalized = values.join(".");
  } else {
    if (!_hostName.hasMatch(host) || !_alphanumeric.hasMatch(host)) return null;
    normalized = host;
  }

  final number = port == null ? defaultGatewayPort : int.tryParse(port);
  if (number == null || number < 1 || number > 65535) return null;
  return gatewayAddress(normalized, number);
}

/// The address to store for a gateway found at [host] on [port]: the default
/// port is left out and an IPv6 literal is bracketed, so discovery and the
/// address refresh write the same string for the same gateway.
String gatewayAddress(String host, int port) {
  final h = host.trim();
  final base = _isBareIpv6(h) ? _bracket(h) : h;
  return port == defaultGatewayPort ? base : "$base:$port";
}

/// Whether two stored addresses reach the same authority, so `host` and
/// `host:8080` count as one.
bool sameGatewayAddress(String a, String b) =>
    a.trim().isNotEmpty &&
    gatewayAuthority(a).toLowerCase() == gatewayAuthority(b).toLowerCase();
