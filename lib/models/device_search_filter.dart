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

import 'package:mobile_app/app_state.dart';

import '../exceptions/argument_exception.dart';

class DeviceSearchFilter {
  final String query;
  final List<String>? deviceTypeIds;
  final List<String>? deviceIds;
  final String? networkId;

  DeviceSearchFilter(this.query, [this.deviceTypeIds, this.deviceIds, this.networkId]) {
    if (deviceTypeIds != null && deviceIds != null) {
      throw ArgumentException("May only use one of deviceTypeIds or deviceIds");
    }
    if (networkId != null && (query.isNotEmpty || deviceTypeIds != null || deviceIds != null)) {
      throw ArgumentException("May not use networkId with other filters");
    }
  }

  static DeviceSearchFilter fromClassIds(String query, List<String> deviceClassIds, AppState state) {
    final deviceTypeIds = state.deviceTypes.values.where((element) => deviceClassIds.contains(element.device_class_id)).map((e) => e.id).toList(
        growable: false);
    return DeviceSearchFilter(query, deviceTypeIds);
  }

  static DeviceSearchFilter empty() {
    return DeviceSearchFilter("");
  }

  Map<String, dynamic> toBody(int limit, int offset) {
    final body = <String, dynamic>{
      "resource": "devices",
      "find": {
        "limit": limit,
        "offset": offset,
        "sortBy": "name.asc",
        "search": query,
      }
    };
    if (deviceTypeIds != null) {
      body["find"]["filter"] = {
        "condition": {
          "feature": "features.device_type_id",
          "operation": "any_value_in_feature",
          "value": deviceTypeIds!.join(","),
        }
      };
    }
    if (deviceIds != null) {
      body["list_ids"] = {
        "ids": deviceIds,
      };
    }

    return body;
  }

  @override
  int get hashCode {
    return (toBody(0, 0)
        .toString() + networkId.toString())
        .hashCode;
  }

  @override
  bool operator ==(Object other) {
    if (other is! DeviceSearchFilter) {
      return false;
    }
    return hashCode == other.hashCode;
  }

}
