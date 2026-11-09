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

/// What a `…/db/v3/raw-value` request of a smart-service widget reads: one
/// value of one service of one device. Its query parameters are the ones the
/// platform's smart-service models build.
class RawValueSource {
  static const _path = '/db/v3/raw-value';

  final String deviceId;
  final String serviceId;

  /// Dotted path of the content variable.
  final String column;
  final String? targetCharacteristicId;
  final String? conceptId;

  const RawValueSource({
    required this.deviceId,
    required this.serviceId,
    required this.column,
    this.targetCharacteristicId,
    this.conceptId,
  });

  /// Null unless [url] is a raw-value URL with device, service and column. The
  /// host does not matter.
  static RawValueSource? fromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
    if (!path.endsWith(_path)) return null;
    final query = uri.queryParameters;
    final deviceId = query['device_id'];
    final serviceId = query['service_id'];
    final column = query['column'];
    if (deviceId == null || deviceId.isEmpty) return null;
    if (serviceId == null || serviceId.isEmpty) return null;
    if (column == null || column.isEmpty) return null;
    String? optional(String key) {
      final value = query[key];
      return value == null || value.isEmpty ? null : value;
    }

    return RawValueSource(
      deviceId: deviceId,
      serviceId: serviceId,
      column: column,
      targetCharacteristicId: optional('target_characteristic_id'),
      conceptId: optional('concept_id'),
    );
  }
}
