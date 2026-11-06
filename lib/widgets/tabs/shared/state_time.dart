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

/// Rebuilds [builder] once a minute while it is on screen, so a relative time
/// keeps up with the clock on a page that stays open without a reload.
class MinuteTicker extends StatefulWidget {
  final WidgetBuilder builder;

  const MinuteTicker({super.key, required this.builder});

  @override
  State<MinuteTicker> createState() => _MinuteTickerState();
}

class _MinuteTickerState extends State<MinuteTicker> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
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
  Widget build(BuildContext context) => MinuteTicker(builder: _build);

  Widget _build(BuildContext context) {
    final now = stateTimeNow();
    final text = Text(
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
