/*
 * Copyright 2022 InfAI (CC SES)
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

import 'package:json_annotation/json_annotation.dart';

@JsonSerializable()
class MGW {
  String hostname, mDNSServiceName, coreId, ip;

  /// Id of the cloud network this gateway serves.
  ///
  /// Kept separately from [coreId] because the gateway does not publish it: the
  /// core advertises its own 8 character core id, which is never a network id,
  /// so the binding is set when the gateway is added.
  String networkId;

  MGW(this.hostname, this.mDNSServiceName, this.coreId, this.ip,
      {this.networkId = ""});

  // Entries written before the split carried the network id in coreId, so fall
  // back to it rather than dropping an existing binding.
  MGW.fromJson(Map<String, dynamic> json)
      : hostname = json['hostname'],
        mDNSServiceName = json['mDNSServiceName'],
        coreId = json['coreId'] ?? "",
        ip = json['ip'],
        networkId = json['networkId'] ?? json['coreId'] ?? "";

  Map<String, dynamic> toJson() => <String, dynamic>{
        "hostname": hostname,
        "mDNSServiceName": mDNSServiceName,
        "coreId": coreId,
        "ip": ip,
        "networkId": networkId
      };
}

