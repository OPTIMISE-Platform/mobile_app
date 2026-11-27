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
import 'package:mobile_app/shared/conditional_get.dart';
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
  /// were stored and the validator they came with, or null when nothing usable
  /// is stored.
  static Future<
      ({
        List<int> bytes,
        DateTime storedAt,
        MetadataValidator? validator
      })?> readEntry(String key) async {
    final db = isar;
    if (db == null) return null;
    try {
      final entry = await db.cachedMetadatas.getByKey(key);
      if (entry == null) return null;
      final etag = entry.etag;
      final etagUri = entry.etagUri;
      return (
        bytes: entry.bytes,
        storedAt: entry.updatedAt,
        validator: etag != null && etagUri != null
            ? MetadataValidator(etag, etagUri)
            : null,
      );
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
  /// runs after the check. [storedAt] defaults to now. [validator] is stored
  /// with the bytes; without one, a validator already stored under [key] is
  /// dropped, since it no longer belongs to the new bytes.
  static Future<void> write(String key, List<int> bytes, int epoch,
      {DateTime? storedAt, MetadataValidator? validator}) async {
    final db = isar;
    if (db == null) return;
    try {
      final entry = CachedMetadata()
        ..key = key
        ..bytes = bytes
        ..updatedAt = storedAt ?? DateTime.now()
        ..etag = validator?.etag
        ..etagUri = validator?.uri;
      await db.writeTxn(() async {
        if (epoch == AccountEpoch.current) {
          await db.cachedMetadatas.putByKey(entry);
        }
      });
    } catch (_) {
      // best-effort cache; ignore write failures
    }
  }

  /// Sets the stored time of [key] to now after the backend confirmed the
  /// stored copy with `304`; bytes and validator stay. Skipped, like [write],
  /// when the account changed since [epoch], checked inside the transaction.
  static Future<void> touch(String key, int epoch) async {
    final db = isar;
    if (db == null) return;
    try {
      await db.writeTxn(() async {
        if (epoch != AccountEpoch.current) return;
        final entry = await db.cachedMetadatas.getByKey(key);
        if (entry == null) return;
        entry.updatedAt = DateTime.now();
        await db.cachedMetadatas.putByKey(entry);
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

/// Decodes stored bytes and builds the list. See the notes on the isolate in
/// [loadMetadataCached].
Future<List<T>> _parseStored<T>(
    List<int> stored, T Function(Map<String, dynamic>) fromJson) async {
  // convert() is one synchronous multi-MB parse and froze the UI for its
  // whole duration when it ran here (~800ms per blob, six blobs at every
  // app start). compute() sends the bytes as typed data (a memcpy) and
  // returns the decoded tree via Isolate.exit, i.e. without copying it
  // back - the copy-out concern in parseListChunked's doc applies to
  // constructed model objects, not to this plain JSON tree.
  final data = stored is Uint8List ? stored : Uint8List.fromList(stored);
  final decoded = await _decodeLimiter
      .withResource(() => compute(_decodeJsonListFromUtf8, data));
  return parseListChunked(decoded, fromJson);
}

/// Returns metadata for [key]: decoded from the Isar byte cache when it is
/// younger than [maxAge], otherwise fetched via [fetchRaw], persisted, and
/// parsed. The JSON decode of the cached bytes runs in a background isolate,
/// the `fromJson` build is chunked - neither blocks the UI isolate in one go.
///
/// When a fetch is due, the validator of the stored entry goes to [fetchRaw],
/// which answers [NotModified] when the backend confirms it. The stored bytes are
/// then parsed as for a cache hit and their time is renewed. [Fetched] is
/// stored with its validator, if it has one. An entry that cannot be used
/// never sends its validator.
///
/// With [serveStale] set, a stored entry of any age is returned instead of
/// fetched, so only an empty cache blocks; [serveStale] then receives when the
/// returned data was stored (the entry's time, or now after a fetch or a 304)
/// so the caller can revalidate what is older than [maxAge].
///
/// `Duration.zero` always fetches, with or without [serveStale], and sends the
/// stored validator. That keeps the stored copy intact if the fetch fails,
/// which clearing the cache beforehand would not.
Future<List<T>> loadMetadataCached<T>(
  String key,
  Future<MetadataFetch> Function(MetadataValidator? validator) fetchRaw,
  T Function(Map<String, dynamic>) fromJson, {
  Duration maxAge = metadataMaxAge,
  void Function(DateTime storedAt)? serveStale,
}) async {
  // Taken before the entry is read, so a validator of a gone account never
  // renews or replaces anything of the next one.
  final epoch = AccountEpoch.current;
  final entry = await MetadataCache.readEntry(key);
  var validator = entry?.validator;
  if (entry != null &&
      maxAge > Duration.zero &&
      (serveStale != null ||
          !MetadataCache.isStale(entry.storedAt, maxAge))) {
    try {
      final parsed = await _parseStored(entry.bytes, fromJson);
      serveStale?.call(entry.storedAt);
      return parsed;
    } catch (e) {
      // Corrupt cache, an incompatible shape, or a failed isolate spawn - all
      // recoverable by fetching, but logged rather than swallowed: a spawn
      // failure otherwise looks like six corrupt blobs. Its validator must not
      // go along: a 304 would leave nothing to use.
      _logger.w("Cached metadata for $key unusable, fetching: $e");
      validator = null;
    }
  }
  var result = await fetchRaw(validator);
  if (result is NotModified) {
    try {
      // entry is not null: without a validator no If-None-Match is sent.
      final parsed = await _parseStored(entry!.bytes, fromJson);
      await MetadataCache.touch(key, epoch);
      serveStale?.call(DateTime.now());
      return parsed;
    } catch (e) {
      // Only reached with Duration.zero, where the entry was not tried before.
      _logger.w("Cached metadata for $key unusable after 304, fetching: $e");
      result = await fetchRaw(null);
    }
  }
  final fetched = result as Fetched;
  final fetchedAt = DateTime.now();
  // JsonUtf8Encoder emits bytes directly (no giant intermediate String).
  unawaited(MetadataCache.write(key, JsonUtf8Encoder().convert(fetched.raw), epoch,
      validator: fetched.validator));
  final parsed = await parseListChunked(fetched.raw, fromJson);
  serveStale?.call(fetchedAt);
  return parsed;
}
