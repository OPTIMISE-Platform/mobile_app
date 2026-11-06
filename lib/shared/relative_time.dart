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

import 'package:mobile_app/shared/display_time.dart';
import 'package:mobile_app/shared/formats.dart';

/// Short, human phrasing of [t] relative to [now] (default: the current time):
/// "just now", "5 min ago", "3 h ago", "yesterday 14:02", else a date.
///
/// Calendar days are compared in display time. A [t] more than a minute in
/// the future is not phrased relatively but shown as a clock time, with the
/// date when it is not today.
String relativeTime(DateTime t, {DateTime? now}) {
  final at = toDisplayTime(t);
  final ref = toDisplayTime(now ?? DateTime.now());
  final diff = ref.difference(at);
  if (diff.isNegative && diff.inSeconds < -60) return clockOrDate(t, now: now);
  if (diff.inSeconds < 60) return "just now";
  if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
  // Calendar dates in UTC: a local midnight difference is 23 h on the day the
  // clocks go forward, which would round yesterday down to today.
  final today = DateTime.utc(ref.year, ref.month, ref.day);
  final day = DateTime.utc(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days == 0) return "${diff.inHours} h ago";
  if (days == 1) return "yesterday ${Formats.hhmm.format(at)}";
  return Formats.eddmmy.format(at);
}

/// The clock time of [t] when it falls on the same calendar day as [now],
/// otherwise day and month in front of it.
String clockOrDate(DateTime t, {DateTime? now}) {
  final at = toDisplayTime(t);
  final ref = toDisplayTime(now ?? DateTime.now());
  final sameDay =
      at.year == ref.year && at.month == ref.month && at.day == ref.day;
  final time = Formats.hhmm.format(at);
  return sameDay ? time : "${Formats.ddmm.format(at)} $time";
}
