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

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/shared/chunked_parse.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/shared/semaphore.dart';

final _logger = Logger(printer: SimplePrinter());

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
    final entry = await readEntry(key);
    if (entry == null || isStale(entry.storedAt, maxAge)) return null;
    return entry.bytes;
  }

  /// Returns the cached bytes for [key] whatever their age, with the time they
  /// were stored, or null when nothing usable is stored.
  static Future<({List<int> bytes, DateTime storedAt})?> readEntry(
      String key) async {
    final db = isar;
    if (db == null) return null;
    try {
      final entry = await db.cachedMetadatas.getByKey(key);
      if (entry == null) return null;
      return (bytes: entry.bytes, storedAt: entry.updatedAt);
    } catch (_) {
      return null;
    }
  }

  /// Whether data stored at [storedAt] is older than [maxAge]. A time in the
  /// future counts as stale: it was written under a clock that ran ahead and
  /// would otherwise count as current even for maxAge zero.
  static bool isStale(DateTime storedAt, Duration maxAge, [DateTime? now]) {
    final age = (now ?? DateTime.now()).difference(storedAt);
    return age > maxAge || age.isNegative;
  }

  /// Drops every cached entry so the next [read] misses and the caller
  /// fetches fresh from the backend.
  static Future<void> clear() async {
    final db = isar;
    if (db == null) return;
    try {
      await db.writeTxn(() => db.cachedMetadatas.clear());
    } catch (_) {
      // best-effort cache; ignore clear failures
    }
  }

  static Future<void> delete(String key) async {
    final db = isar;
    if (db == null) return;
    try {
      await db.writeTxn(() => db.cachedMetadatas.deleteByKey(key));
    } catch (_) {
      // best-effort cache; ignore delete failures
    }
  }

  /// Skipped when the account changed since [epoch], taken before the fetch.
  /// Checked inside the transaction, so a clear queued after the change always
  /// runs after the check. [storedAt] defaults to now.
  static Future<void> write(String key, List<int> bytes, int epoch,
      {DateTime? storedAt}) async {
    final db = isar;
    if (db == null) return;
    try {
      final entry = CachedMetadata()
        ..key = key
        ..bytes = bytes
        ..updatedAt = storedAt ?? DateTime.now();
      await db.writeTxn(() async {
        if (epoch == AccountEpoch.current) {
          await db.cachedMetadatas.putByKey(entry);
        }
      });
    } catch (_) {
      // best-effort cache; ignore write failures
    }
  }
}

/// `Utf8Decoder.fuse(JsonDecoder)` resolves to the SDK's `_JsonUtf8Decoder`
/// fast path, which parses objects straight from UTF-8 bytes without ever
/// building the (multi-MB) intermediate Dart String.
final _jsonFromUtf8 = const Utf8Decoder().fuse(const JsonDecoder());

/// Decodes UTF-8 JSON bytes into a list. Top-level so [compute] can run it in
/// a background isolate.
List<dynamic> _decodeJsonListFromUtf8(Uint8List bytes) =>
    _jsonFromUtf8.convert(bytes) as List<dynamic>;

/// Bounds how many decode isolates exist at once. All six metadata blobs load
/// in parallel at startup, and each isolate holds a copy of its multi-MB input
/// plus the decoded tree — six at once is a memory spike on a weak device for
/// no gain, since the decodes are CPU-bound anyway.
final _decodeLimiter = Semaphore(2);

/// How long cached reference metadata counts as current. These sets change
/// rarely, so a week of staleness is cheaper than refetching megabytes.
const metadataMaxAge = Duration(days: 7);

/// Returns metadata for [key]: decoded from the Isar byte cache when it is
/// younger than [maxAge], otherwise fetched fresh via [fetchRaw], persisted,
/// and parsed. The JSON decode of the cached bytes runs in a background
/// isolate, the `fromJson` build is chunked — neither blocks the UI isolate
/// in one go.
///
/// With [serveStale] set, a stored entry of any age is returned instead of
/// fetched, so only an empty cache blocks; [serveStale] then receives when the
/// returned data was stored (the entry's time, or now after a fetch) so the
/// caller can revalidate what is older than [maxAge].
///
/// `Duration.zero` always fetches, with or without [serveStale]. That keeps
/// the stored copy intact if the fetch fails, which clearing the cache
/// beforehand would not.
Future<List<T>> loadMetadataCached<T>(
  String key,
  Future<List<dynamic>> Function() fetchRaw,
  T Function(Map<String, dynamic>) fromJson, {
  Duration maxAge = metadataMaxAge,
  void Function(DateTime storedAt)? serveStale,
}) async {
  final entry =
      maxAge > Duration.zero ? await MetadataCache.readEntry(key) : null;
  if (entry != null &&
      (serveStale != null || !MetadataCache.isStale(entry.storedAt, maxAge))) {
    try {
      // convert() is one synchronous multi-MB parse and froze the UI for its
      // whole duration when it ran here (~800ms per blob, six blobs at every
      // app start). compute() sends the bytes as typed data (a memcpy) and
      // returns the decoded tree via Isolate.exit, i.e. without copying it
      // back — the copy-out concern in parseListChunked's doc applies to
      // constructed model objects, not to this plain JSON tree.
      final bytes = entry.bytes;
      final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final decoded = await _decodeLimiter
          .withResource(() => compute(_decodeJsonListFromUtf8, data));
      final parsed = await parseListChunked(decoded, fromJson);
      serveStale?.call(entry.storedAt);
      return parsed;
    } catch (e) {
      // Corrupt cache, an incompatible shape, or a failed isolate spawn — all
      // recoverable by fetching, but logged rather than swallowed: a spawn
      // failure otherwise looks like six corrupt blobs.
      _logger.w("Cached metadata for $key unusable, fetching: $e");
    }
  }
  final epoch = AccountEpoch.current;
  final raw = await fetchRaw();
  final fetchedAt = DateTime.now();
  // JsonUtf8Encoder emits bytes directly (no giant intermediate String).
  unawaited(MetadataCache.write(key, JsonUtf8Encoder().convert(raw), epoch));
  final parsed = await parseListChunked(raw, fromJson);
  serveStale?.call(fetchedAt);
  return parsed;
}
