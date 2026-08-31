/*
 * Copyright 2022 InfAI (CC SES)
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

num minList(List<dynamic> l) {
  num m = l[0];
  for (var i = 0; i < l.length; i++) {
    if (l[i] is! num) {
      continue;
    }
    if (l[i] < m) {
      m = l[i];
    }
  }
  return m;
}

num maxList(List<dynamic> l) {
  num m = l[0];
  for (var i = 0; i < l.length; i++) {
    if (l[i] is! num) {
      continue;
    }
    if (l[i] > m) {
      m = l[i];
    }
  }
  return m;
}

/// Population standard deviation (divides by n), using the same Welford
/// recurrence the removed `stats` package used for its default (non-Bessel)
/// case. Two documented differences: that package sorted its input first (it
/// needed the order for the median), so the floating-point summation order can
/// differ in the last digits, and it threw on an empty input where this
/// returns 0. Callers that must distinguish "no data" check for that
/// themselves.
double populationStandardDeviation(Iterable<num> values) {
  var count = 0;
  var mean = 0.0;
  var m2 = 0.0;
  for (final value in values) {
    count++;
    final delta = value - mean;
    mean += delta / count;
    m2 += delta * (value - mean);
  }
  if (count == 0) return 0;
  return sqrt(m2 / count);
}

/// Maximum precision `toStringAsFixed` accepts.
const _maxFractionDigits = 20;

/// How many fraction digits it takes for [value] to reach the first non-zero
/// digit: 0 for values at or above 1 (and for non-positive or non-finite
/// ones), capped at what `toStringAsFixed` allows.
int fractionDigitsBelowOne(num value) {
  if (!value.isFinite || value <= 0 || value >= 1) return 0;
  var scaled = value;
  var digits = 0;
  while (scaled < 1 && digits < _maxFractionDigits) {
    scaled *= 10;
    digits++;
  }
  return digits;
}
