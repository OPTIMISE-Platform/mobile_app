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

/// Authority to address a gateway with.
///
/// [host] may already carry a port - the installer's gateway port is
/// configurable and mDNS reports it per core, so a gateway is not necessarily
/// on [defaultGatewayPort].
String gatewayAuthority(String host) =>
    _explicitPort.hasMatch(host) ? host : "$host:$defaultGatewayPort";

/// The host part of a stored gateway address, for comparing against the host of
/// a parsed URI, which never carries the port.
String gatewayHostOnly(String host) =>
    host.replaceFirst(_explicitPort, "");
