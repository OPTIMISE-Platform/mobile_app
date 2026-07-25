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

import 'package:isar_community/isar.dart';

part 'cached_metadata.g.dart';

/// A UTF-8 encoded JSON body of a large, stable reference-metadata response
/// (device types, functions, aspects, concepts, characteristics), persisted in
/// Isar.
///
/// Isar reads values via a memory-mapped store without the per-value CRC32 that
/// Hive (the dio HTTP cache backend) computes — that CRC was dominating the UI
/// isolate for seconds on startup.
///
/// The body is stored as raw bytes, not a `String`: a login-moment CPU profile
/// showed that reading it back as a `String` made Isar UTF-8-decode the whole
/// multi-MB blob into a Dart String (~844ms for device-types) on the UI isolate
/// *before* jsonDecode even ran (another ~811ms) — two full passes over the
/// same data. Storing bytes makes the Isar read a plain memcpy, and decoding
/// straight from these bytes with the fused UTF-8+JSON decoder builds the
/// objects in a single pass without ever materialising the intermediate String.
@collection
class CachedMetadata {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String key;

  late List<byte> bytes;

  late DateTime updatedAt;
}
