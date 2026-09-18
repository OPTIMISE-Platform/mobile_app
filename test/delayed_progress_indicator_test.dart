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
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';

void main() {
  // No test for the setState-after-dispose case: the widget's own _f.ignore()
  // swallows that error, so it cannot be observed from a test - and for the
  // same reason it was never visible in the app either. The guard stays
  // because marking a defunct element dirty is wrong regardless.
  testWidgets("shows itself once the delay is over", (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: DelayedCircularProgressIndicator()));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
