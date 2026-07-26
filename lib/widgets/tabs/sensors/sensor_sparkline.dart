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

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/db_query.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/db_query.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/semaphore.dart';

final _logger = Logger(printer: SimplePrinter());

/// Bounds concurrent history queries — a sensors tab can hold many cards and
/// each one would otherwise fire its own request at once.
final Semaphore _sparklineLimiter = Semaphore(4);

/// Whether a history sparkline can be drawn for [state].
///
/// Controls have no measurement series, and the query addresses a value by its
/// service and path.
bool canShowSparkline(DeviceState state) =>
    !state.isControlling &&
    state.serviceId != null &&
    state.path != null &&
    state.deviceId != null;

/// One measurement in a [SparkSeries].
class SparkPoint {
  final double timeMs;
  final double value;

  const SparkPoint(this.timeMs, this.value);
}

/// A history series plus the window it is drawn in.
///
/// The window is fixed to the requested two hours rather than to the extent of
/// the data: a device that only reported for ten minutes must show a short
/// line, not a full-width one, or the card would misrepresent its history.
class SparkSeries {
  /// Ascending by time.
  final List<SparkPoint> points;
  final double startMs;
  final double endMs;

  const SparkSeries(this.points, this.startMs, this.endMs);
}

/// The window the sparkline covers.
const sparklineWindow = Duration(hours: 2);

/// Loads the last two hours of [state].
///
/// Uses the same query the detail page's chart issues for its 2h range (5m
/// buckets, mean aggregation), so a card and the chart behind it agree. Returns
/// null when there is nothing usable to draw.
Future<SparkSeries?> loadSparklineValues(DeviceState state) async {
  if (!canShowSparkline(state)) return null;
  final end = DateTime.now();
  try {
    final data = await _sparklineLimiter.withResource(
      () => DbQueryService.query(
        DbQuery(
          null,
          state.deviceId,
          state.serviceId,
          '5m',
          null,
          null,
          null,
          QueriesRequestElementTime('2h', null, null),
          [
            QueriesRequestElementColumn(
              state.path!,
              'mean',
              null,
              null,
              Settings.getFunctionPreferredCharacteristicId(state.functionId),
              AppState().platformFunctions[state.functionId]?.concept_id,
            ),
          ],
          null,
        ),
      ),
    );
    final points = <SparkPoint>[];
    for (final point in data) {
      if (point.length != 2 || point[1] is! num || point[0] == null) continue;
      final value = (point[1] as num).toDouble();
      if (value.isNaN) continue;
      final time = DateTime.tryParse(point[0].toString());
      if (time == null) continue;
      points.add(SparkPoint(time.millisecondsSinceEpoch.toDouble(), value));
    }
    // The query's order is left to the server (orderDirection is unset), which
    // for a time series is commonly newest first — sort so the line always runs
    // left to right in time.
    points.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    // A single point has no shape to show.
    if (points.length < 2) return null;
    return SparkSeries(
      points,
      end.subtract(sparklineWindow).millisecondsSinceEpoch.toDouble(),
      end.millisecondsSinceEpoch.toDouble(),
    );
  } catch (e) {
    // A missing history is not worth surfacing — the card still shows its value.
    _logger.d('Could not load sparkline: $e');
    return null;
  }
}

/// A minimal filled line chart, meant to sit behind a card's content.
///
/// Hand-painted rather than built with fl_chart: it needs no axes, labels or
/// interaction, and a card grid may hold many of them.
class Sparkline extends StatelessWidget {
  final SparkSeries series;
  final Color color;

  const Sparkline(this.series, {required this.color, super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _SparklinePainter(series, color),
      size: Size.infinite,
    ),
  );
}

class _SparklinePainter extends CustomPainter {
  final SparkSeries series;
  final Color color;

  _SparklinePainter(this.series, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final points = series.points;
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;

    var min = points.first.value;
    var max = points.first.value;
    for (final p in points) {
      if (p.value < min) min = p.value;
      if (p.value > max) max = p.value;
    }
    final span = max - min;

    // Flat series would divide by zero — draw it as a centred line instead.
    double yFor(double v) => span == 0
        ? size.height / 2
        : size.height - ((v - min) / span) * size.height;

    // x follows real time inside the requested window, so a stretch without
    // data stays visibly empty instead of being squeezed away, and a series
    // covering only part of the window stays short.
    final timeSpan = series.endMs - series.startMs;
    double xFor(double timeMs) => timeSpan <= 0
        ? 0
        : size.width * ((timeMs - series.startMs) / timeSpan).clamp(0.0, 1.0);

    final line = Path()
      ..moveTo(xFor(points.first.timeMs), yFor(points.first.value));
    for (var i = 1; i < points.length; i++) {
      line.lineTo(xFor(points[i].timeMs), yFor(points[i].value));
    }

    final fill = Path.from(line)
      ..lineTo(xFor(points.last.timeMs), size.height)
      ..lineTo(xFor(points.first.timeMs), size.height)
      ..close();

    canvas.drawPath(fill, Paint()..color = color.withAlpha(38));
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withAlpha(140)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.series, series);
}
