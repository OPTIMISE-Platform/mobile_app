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
/// functions, aspects, concepts, characteristics), stored as raw JSON blobs in
/// Isar.
///
/// These used to be served from the dio HTTP cache backed by Hive. Profiling
/// showed Hive verifies a CRC32 over every cached value on read, and for these
/// multi-megabyte bodies that CRC dominated the UI isolate for seconds on every
/// startup. Isar reads via a memory-mapped store with no per-value checksum, so
/// the only remaining cost is a normal jsonDecode plus the (chunked) build.
class MetadataCache {
  MetadataCache._();

  /// Returns the cached JSON string for [key] if present and younger than
  /// [maxAge], otherwise null.
  static Future<String?> read(String key, Duration maxAge) async {
    final db = isar;
    if (db == null) return null;
    try {
      final entry = await db.cachedMetadatas.getByKey(key);
      if (entry == null) return null;
      if (DateTime.now().difference(entry.updatedAt) > maxAge) return null;
      return entry.json;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, String json) async {
    final db = isar;
    if (db == null) return;
    try {
      final entry = CachedMetadata()
        ..key = key
        ..json = json
        ..updatedAt = DateTime.now();
      await db.writeTxn(() => db.cachedMetadatas.putByKey(entry));
    } catch (_) {
      // best-effort cache; ignore write failures
    }
  }
}

/// Returns metadata for [key]: parsed from the Isar blob cache when it is
/// younger than [maxAge], otherwise fetched fresh via [fetchRaw], persisted,
/// and parsed. Parsing is chunked so it never blocks the UI isolate in one go.
Future<List<T>> loadMetadataCached<T>(
  String key,
  Future<List<dynamic>> Function() fetchRaw,
  T Function(Map<String, dynamic>) fromJson, {
  Duration maxAge = const Duration(days: 7),
}) async {
  final blob = await MetadataCache.read(key, maxAge);
  if (blob != null) {
    try {
      return await parseListChunked(jsonDecode(blob) as List<dynamic>, fromJson);
    } catch (_) {
      // corrupt/incompatible cache — fall through to a fresh fetch
    }
  }
  final raw = await fetchRaw();
  unawaited(MetadataCache.write(key, jsonEncode(raw)));
  return parseListChunked(raw, fromJson);
}
