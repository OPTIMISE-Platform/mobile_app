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

/// A raw JSON blob of a large, stable reference-metadata response (device
/// types, functions, aspects, concepts, characteristics), persisted in Isar.
///
/// Isar reads values via a memory-mapped store without the per-value CRC32 that
/// Hive (the dio HTTP cache backend) computes — that CRC was dominating the UI
/// isolate for seconds on startup. Reading the blob here is cheap; the only
/// remaining cost is a normal jsonDecode plus the (chunked) object build.
@collection
class CachedMetadata {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String key;

  late String json;

  late DateTime updatedAt;
}
