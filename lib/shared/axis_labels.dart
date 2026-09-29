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

import 'dart:math';

import 'package:fl_chart/fl_chart.dart';

/// Longest fraction part [axisFractionDigits] returns.
const _maxAxisFractionDigits = 6;

/// Fraction digits needed to tell ticks [interval] apart (0.05 gives 2, 0.5
/// gives 1, 5 gives 0), or null when [interval] is not a step fl_chart
/// rounds to. Those are 1, 2 or 5 times a power of ten (float noise such as
/// 0.05000000001 is tolerated); narrow axes get an unrounded step instead.
int? axisFractionDigits(double interval) {
  if (!interval.isFinite || interval <= 0) return null;
  final exponent = (log(interval) / ln10 + 1e-9).floor();
  final mantissa = interval / pow(10, exponent);
  final rounded = mantissa.round();
  if (![1, 2, 5].contains(rounded) || (mantissa - rounded).abs() > 1e-6) {
    return null;
  }
  final digits = max(-exponent, 0);
  return digits > _maxAxisFractionDigits ? null : digits;
}

/// Label for the tick at [value] of an axis with [meta]. fl_chart's own
/// [TitleMeta.formattedValue] takes its digits from the axis span rather than
/// the tick step, so steps finer than that repeat (20.5, 20.5, 20.4); this
/// takes them from [TitleMeta.appliedInterval]. Values from 1000 up, and
/// steps [axisFractionDigits] does not recognise, keep fl_chart's own form.
String formatAxisValue(double value, TitleMeta meta) {
  if (value.abs() >= 1000) return meta.formattedValue;
  final digits = axisFractionDigits(meta.appliedInterval);
  if (digits == null) return meta.formattedValue;
  var text = value.toStringAsFixed(digits);
  if (double.parse(text) == 0) text = (0.0).toStringAsFixed(digits);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return text;
}
