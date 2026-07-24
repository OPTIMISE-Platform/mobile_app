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

/// Parses [raw] into a `List<T>` via [fromJson], yielding to the event loop
/// every [chunkSize] items so a large parse never blocks the UI isolate in one
/// long stretch.
///
/// Preferred over `compute()` for big payloads: an isolate would parse on
/// another core, but copying the input in and the parsed objects back out both
/// happen on the calling (UI) isolate and, for thousands of nested objects, can
/// themselves block frames for a second or more. Chunked parsing keeps the work
/// on the UI isolate but spreads it across frames — bounded, predictable jank
/// instead of one long freeze, and no copy overhead.
Future<List<T>> parseListChunked<T>(
  List<dynamic> raw,
  T Function(Map<String, dynamic>) fromJson, {
  int chunkSize = 250,
}) async {
  final result = <T>[];
  for (var i = 0; i < raw.length; i++) {
    result.add(fromJson(raw[i] as Map<String, dynamic>));
    if (i > 0 && i % chunkSize == 0) {
      await Future<void>.delayed(Duration.zero); // let a frame render
    }
  }
  return result;
}
