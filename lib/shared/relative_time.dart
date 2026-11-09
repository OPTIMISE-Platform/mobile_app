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
/// "< 30 seconds ago", "45 seconds ago", "5 min ago", "3 h ago",
/// "yesterday 14:02", else a date.
///
/// Calendar days are compared in display time. A [t] up to a minute in the
/// future is "< 30 seconds ago", since clocks of phone and platform differ by
/// a few seconds. A [t] further ahead is not phrased relatively but shown as a
/// clock time, with the date when it is not today.
String relativeTime(DateTime t, {DateTime? now}) {
  final at = toDisplayTime(t);
  final ref = toDisplayTime(now ?? DateTime.now());
  final diff = ref.difference(at);
  if (diff.isNegative && diff.inSeconds < -60) return clockOrDate(t, now: now);
  if (diff.inSeconds < 30) return "< 30 seconds ago";
  if (diff.inSeconds < 60) return "${diff.inSeconds} seconds ago";
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

/// How long after [now] the phrasing of [relativeTime] for [t] can next
/// change: when the age reaches 30 s while it is "< 30 seconds ago", at the
/// next whole second of the age while that is counted in seconds, else at the
/// next whole minute.
///
/// An hour count changes at a whole minute of the age as well. A calendar
/// day changes at midnight, which this shows at most a minute late.
Duration untilRelativeTimeChanges(DateTime t, {required DateTime now}) {
  const second = Duration.microsecondsPerSecond, minute = Duration.microsecondsPerMinute;
  final age = now.difference(t).inMicroseconds;
  if (age > -minute && age < 30 * second) return Duration(microseconds: 30 * second - age);
  final step = age > -minute && age < minute ? second : minute;
  // Dart's % is never negative for a positive divisor, which also aligns an
  // age just ahead of now.
  return Duration(microseconds: step - age % step);
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
