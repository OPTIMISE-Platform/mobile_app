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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/shared/display_time.dart';
import 'package:mobile_app/shared/relative_time.dart';

void main() {
  setUp(() => useUtcForDisplayTime = true);
  tearDown(() => useUtcForDisplayTime = false);

  final now = DateTime.utc(2026, 11, 6, 15, 30);

  test("under 30 seconds is < 30 seconds ago, including up to a minute ahead", () {
    expect(relativeTime(now, now: now), "< 30 seconds ago");
    expect(
        relativeTime(now.subtract(const Duration(seconds: 29, milliseconds: 999)), now: now),
        "< 30 seconds ago");
    expect(relativeTime(now.add(const Duration(seconds: 30)), now: now),
        "< 30 seconds ago");
    expect(relativeTime(now.add(const Duration(seconds: 60)), now: now),
        "< 30 seconds ago");
  });

  test("seconds from 30 up to the minute", () {
    expect(relativeTime(now.subtract(const Duration(seconds: 30)), now: now),
        "30 seconds ago");
    expect(
        relativeTime(now.subtract(const Duration(seconds: 59, milliseconds: 999)),
            now: now),
        "59 seconds ago");
  });

  test("minutes up to the hour", () {
    expect(relativeTime(now.subtract(const Duration(minutes: 1)), now: now),
        "1 min ago");
    expect(relativeTime(now.subtract(const Duration(minutes: 2)), now: now),
        "2 min ago");
    expect(relativeTime(now.subtract(const Duration(minutes: 59, seconds: 59)),
            now: now),
        "59 min ago");
  });

  test("hours within the same calendar day", () {
    expect(relativeTime(DateTime.utc(2026, 11, 6, 14, 30), now: now), "1 h ago");
    expect(relativeTime(DateTime.utc(2026, 11, 6, 0, 0), now: now), "15 h ago");
  });

  test("the previous calendar day is yesterday with the time, even under 24 h",
      () {
    expect(relativeTime(DateTime.utc(2026, 11, 5, 14, 2), now: now),
        "yesterday 14:02");
    expect(
        relativeTime(DateTime.utc(2026, 11, 5, 23, 50),
            now: DateTime.utc(2026, 11, 6, 1, 10)),
        "yesterday 23:50");
  });

  test("older than yesterday is a date", () {
    expect(relativeTime(DateTime.utc(2026, 11, 4, 9, 0), now: now),
        "Wed, 04.11.2026");
  });

  test("a time more than a minute ahead is a clock time, with the date when "
      "not today", () {
    expect(relativeTime(DateTime.utc(2026, 11, 6, 17, 13), now: now), "17:13");
    expect(relativeTime(DateTime.utc(2026, 11, 7, 8, 0), now: now), "07.11 08:00");
  });

  test("the phrasing next changes at 30 s, then at every whole second of the "
      "age up to the minute, then at a whole minute", () {
    Duration until(Duration age) =>
        untilRelativeTimeChanges(now.subtract(age), now: now);
    expect(until(Duration.zero), const Duration(seconds: 30));
    expect(until(const Duration(milliseconds: 2400)),
        const Duration(milliseconds: 27600));
    expect(until(const Duration(seconds: 30)), const Duration(seconds: 1));
    expect(until(const Duration(milliseconds: 31400)),
        const Duration(milliseconds: 600));
    expect(until(const Duration(seconds: 59, milliseconds: 500)),
        const Duration(milliseconds: 500));
    expect(until(const Duration(minutes: 1)), const Duration(minutes: 1));
    expect(until(const Duration(minutes: 12, seconds: 20)),
        const Duration(seconds: 40));
    expect(until(const Duration(hours: 3, seconds: 5)),
        const Duration(seconds: 55));
    // A time just ahead of now stays "< 30 seconds ago" until it is 30 s old.
    expect(until(const Duration(milliseconds: -300)),
        const Duration(milliseconds: 30300));
  });

  test("each change of the phrasing in the first minutes is a wake-up", () {
    // Stepping from wake-up to wake-up reads every phrasing once, in order,
    // without skipping a second.
    final t = now;
    var at = t;
    var wakeUps = 0;
    final seen = <String>[relativeTime(t, now: at)];
    while (at.difference(t) < const Duration(minutes: 3)) {
      at = at.add(untilRelativeTimeChanges(t, now: at));
      wakeUps++;
      final phrase = relativeTime(t, now: at);
      if (phrase != seen.last) seen.add(phrase);
    }
    expect(seen, [
      "< 30 seconds ago",
      for (var i = 30; i < 60; i++) "$i seconds ago",
      "1 min ago",
      "2 min ago",
      "3 min ago",
    ]);
    // No wake-up while the phrasing stands still: one to reach 30 s, one per
    // second up to the minute, one per minute.
    expect(wakeUps, 1 + 30 + 2);
  });

  test("clockOrDate", () {
    expect(clockOrDate(DateTime.utc(2026, 11, 6, 9, 5), now: now), "09:05");
    expect(clockOrDate(DateTime.utc(2026, 11, 8, 9, 5), now: now), "08.11 09:05");
  });
}
