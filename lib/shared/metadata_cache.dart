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

import 'dart:async';
import 'dart:convert';

import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/shared/chunked_parse.dart';
import 'package:mobile_app/shared/isar.dart';

/// Local persistence for large, stable reference metadata (device types,
/// functions, aspects, concepts, characteristics), stored as UTF-8 JSON bytes
/// in Isar.
///
/// These used to be served from the dio HTTP cache backed by Hive. Profiling
/// showed Hive verifies a CRC32 over every cached value on read, and for these
/// multi-megabyte bodies that CRC dominated the UI isolate for seconds on every
/// startup. Isar reads via a memory-mapped store with no per-value checksum.
///
/// The body is kept as bytes rather than a String: a login-moment profile then
/// showed the remaining block came from reading a String value back (Isar
/// UTF-8-decodes the whole blob into a Dart String, ~844ms) and re-parsing it
/// with jsonDecode (~811ms). Bytes make the read a memcpy and let the fused
/// UTF-8+JSON decoder build the objects in a single pass. See [loadMetadataCached].
class MetadataCache {
  MetadataCache._();

  /// Returns the cached UTF-8 JSON bytes for [key] if present and younger than
  /// [maxAge], otherwise null.
  static Future<List<int>?> read(String key, Duration maxAge) async {
    final db = isar;
    if (db == null) return null;
    try {
      final entry = await db.cachedMetadatas.getByKey(key);
      if (entry == null) return null;
      if (DateTime.now().difference(entry.updatedAt) > maxAge) return null;
      return entry.bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, List<int> bytes) async {
    final db = isar;
    if (db == null) return;
    try {
      final entry = CachedMetadata()
        ..key = key
        ..bytes = bytes
        ..updatedAt = DateTime.now();
      await db.writeTxn(() => db.cachedMetadatas.putByKey(entry));
    } catch (_) {
      // best-effort cache; ignore write failures
    }
  }
}

/// `Utf8Decoder.fuse(JsonDecoder)` resolves to the SDK's `_JsonUtf8Decoder`
/// fast path, which parses objects straight from UTF-8 bytes without ever
/// building the (multi-MB) intermediate Dart String.
final _jsonFromUtf8 = const Utf8Decoder().fuse(const JsonDecoder());

/// Returns metadata for [key]: decoded from the Isar byte cache when it is
/// younger than [maxAge], otherwise fetched fresh via [fetchRaw], persisted,
/// and parsed. The `fromJson` build is chunked so it never blocks the UI
/// isolate in one go.
Future<List<T>> loadMetadataCached<T>(
  String key,
  Future<List<dynamic>> Function() fetchRaw,
  T Function(Map<String, dynamic>) fromJson, {
  Duration maxAge = const Duration(days: 7),
}) async {
  final bytes = await MetadataCache.read(key, maxAge);
  if (bytes != null) {
    try {
      final decoded = _jsonFromUtf8.convert(bytes) as List<dynamic>;
      return await parseListChunked(decoded, fromJson);
    } catch (_) {
      // corrupt/incompatible cache — fall through to a fresh fetch
    }
  }
  final raw = await fetchRaw();
  // JsonUtf8Encoder emits bytes directly (no giant intermediate String).
  unawaited(MetadataCache.write(key, JsonUtf8Encoder().convert(raw)));
  return parseListChunked(raw, fromJson);
}
