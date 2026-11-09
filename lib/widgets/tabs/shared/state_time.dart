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

import 'package:flutter/material.dart';
import 'package:mobile_app/shared/relative_time.dart';
import 'package:mobile_app/theme.dart';

/// The clock the captions measure against; fixed by tests so the phrasing does
/// not depend on when they run.
@visibleForTesting
DateTime Function() stateTimeClock = DateTime.now;

DateTime stateTimeNow() => stateTimeClock();

/// Rebuilds [builder] whenever the [relativeTime] phrasing of [time] changes
/// while it is on screen: at 30 s, every second up to the minute, then every
/// minute. A relative time so keeps up with the clock on a page that stays
/// open without a reload.
class RelativeTimeTicker extends StatefulWidget {
  final DateTime time;
  final WidgetBuilder builder;

  const RelativeTimeTicker({super.key, required this.time, required this.builder});

  @override
  State<RelativeTimeTicker> createState() => _RelativeTimeTickerState();
}

class _RelativeTimeTickerState extends State<RelativeTimeTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(RelativeTimeTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new message restarts the count at "< 30 seconds ago".
    if (oldWidget.time != widget.time) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(untilRelativeTimeChanges(widget.time, now: stateTimeNow()), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

final _countedPhrase = RegExp(r'^(< )?(\d{1,2}) (seconds|min|h)( ago)$');

/// [phrase], a [relativeTime], after [prefix], set so its words keep their
/// place while the count changes: digits are of equal width, the count takes
/// the room of two digits, and a count of seconds also the room of the "< "
/// of "< 30 seconds ago". Only a change of unit moves the text. Screen readers
/// read [prefix] and [phrase] as they are; the reserved room is transparent.
Text relativeTimeText(
  String phrase, {
  String prefix = '',
  Key? key,
  TextStyle? style,
  TextAlign? textAlign,
  int? maxLines,
  TextOverflow? overflow,
}) {
  final match = _countedPhrase.firstMatch(phrase);
  if (match == null) {
    return Text(prefix + phrase,
        key: key, style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow);
  }
  final below = match.group(1), count = match.group(2)!, unit = match.group(3)!;
  const hidden = TextStyle(color: Colors.transparent);
  return Text.rich(
    TextSpan(children: [
      if (prefix.isNotEmpty) TextSpan(text: prefix),
      if (unit == 'seconds') TextSpan(text: '< ', style: below == null ? hidden : null),
      if (count.length < 2) const TextSpan(text: '0', style: hidden),
      TextSpan(text: '$count $unit'),
      TextSpan(text: match.group(4)),
    ]),
    key: key,
    semanticsLabel: prefix + phrase,
    style: (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );
}

/// "12 min ago" for the time a reading was received. With [tappable], a tap
/// switches to the absolute time and back.
class StateTimeCaption extends StatefulWidget {
  final DateTime time;
  final bool tappable;
  final TextAlign textAlign;

  const StateTimeCaption(
    this.time, {
    super.key,
    this.tappable = false,
    this.textAlign = TextAlign.end,
  });

  @override
  State<StateTimeCaption> createState() => _StateTimeCaptionState();
}

class _StateTimeCaptionState extends State<StateTimeCaption> {
  bool _absolute = false;

  @override
  Widget build(BuildContext context) =>
      RelativeTimeTicker(time: widget.time, builder: _build);

  Widget _build(BuildContext context) {
    final now = stateTimeNow();
    final text = relativeTimeText(
      _absolute
          ? clockOrDate(widget.time, now: now)
          : relativeTime(widget.time, now: now),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (!widget.tappable) return text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _absolute = !_absolute),
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.xxs),
        child: text,
      ),
    );
  }
}

/// The newest of the reading times in [times], null when there is none.
DateTime? newestTime(Iterable<DateTime?> times) {
  DateTime? newest;
  for (final t in times) {
    if (t != null && (newest == null || t.isAfter(newest))) newest = t;
  }
  return newest;
}
