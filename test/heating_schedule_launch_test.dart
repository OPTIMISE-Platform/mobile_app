/*
 * Copyright (c) 2026 InfAI (CC SES)
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
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_edit_launch.dart';

import 'golden_helper.dart';

SmartServiceRelease _release() => SmartServiceRelease(0, "", "d", "rel-1", heatingReleaseName, null, true);

SmartServiceInstance _instance() => SmartServiceInstance("", "d", "inst-1", "Heating", "rel-1", "u", null, true, [], false, null);

// An empty stored value; the default is "{...}" so a fall back to it would be visible.
SmartServiceExtendedParameter _schedule() => SmartServiceExtendedParameter("schedule", "Schedule", "", "", '{"windows":[]}', false, null,
    ContentVariable.string, null, null, null, false);

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  testWidgets("the default plan is offered only when launching, not for an existing instance", (tester) async {
    Future<void> show({SmartServiceInstance? instance}) async {
      await pumpGolden(tester, SmartServicesReleaseLaunch(_release(), instance: instance, parameters: [_schedule()]), dark: false);
      await tester.pump();
      await tester.pump();
    }

    await show();
    expect(find.text("Add time window"), findsOneWidget);

    await show(instance: _instance());
    expect(find.text("Add time window"), findsNothing);
    expect(find.textContaining("The stored plan cannot be read"), findsOneWidget);
  });
}
