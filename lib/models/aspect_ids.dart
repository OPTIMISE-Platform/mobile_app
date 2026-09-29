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

/// The aspects named by a pair of the deprecated single `aspect_id` and the
/// `aspect_ids` list, sorted: the list if it is non-empty, else the single id,
/// else none. The list wins because a device-repository read fills both.
List<String> effectiveAspectIds(String? aspectId, List<String>? aspectIds) {
  if (aspectIds != null && aspectIds.isNotEmpty) return [...aspectIds]..sort();
  if (aspectId != null && aspectId.isNotEmpty) return [aspectId];
  return [];
}

/// Renders a sorted aspect list the way models' `AspectIdsShort` does, so equal
/// sets give equal keys.
String aspectIdsKey(List<String> sortedAspectIds) => sortedAspectIds.join(",");
