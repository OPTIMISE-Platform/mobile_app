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

  MGW(this.hostname, this.mDNSServiceName, this.coreId, this.ip);
  MGW.fromJson(Map<String, dynamic> json): hostname=json['hostname'], mDNSServiceName=json['mDNSServiceName'], coreId=json['coreId'], ip=json['ip'];
  Map<String, dynamic> toJson() => <String, dynamic> {
      "hostname": this.hostname,
      "mDNSServiceName": this.mDNSServiceName,
      "coreId": this.coreId,
      "ip": this.ip
  };
}

