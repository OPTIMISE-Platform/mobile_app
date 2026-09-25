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

/// Where a row sits in a lazily built list section, so it can draw its own
/// slice of the section's surface (rounded outer corners, hairline) without
/// the section itself being one widget that wraps every row.
enum SlicePosition {
  first,
  middle,
  last,
  only;

  /// The position of the row at [index] among [count] rows in one section.
  static SlicePosition forIndex(int index, int count) {
    assert(count > 0, "a section needs at least one row");
    assert(index >= 0 && index < count, "index out of range for count");
    if (count == 1) return SlicePosition.only;
    if (index == 0) return SlicePosition.first;
    if (index == count - 1) return SlicePosition.last;
    return SlicePosition.middle;
  }

  /// Whether this row rounds its top corners.
  bool get roundsTop => this == SlicePosition.first || this == SlicePosition.only;

  /// Whether this row rounds its bottom corners.
  bool get roundsBottom => this == SlicePosition.last || this == SlicePosition.only;

  /// Whether a hairline is drawn below this row (every row but the last).
  bool get drawsHairline => this == SlicePosition.first || this == SlicePosition.middle;
}
