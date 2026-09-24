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

void main() {
  tearDown(() {
    useUtcForDisplayTime = false;
  });

  test("production path returns toLocal", () {
    final t = DateTime.utc(2026, 1, 1, 12);
    expect(toDisplayTime(t), t.toLocal());
  });

  test("test path returns toUtc when switched on", () {
    useUtcForDisplayTime = true;
    final t = DateTime.utc(2026, 1, 1, 12);
    expect(toDisplayTime(t), t.toUtc());
  });
}
