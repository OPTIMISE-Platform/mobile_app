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

import 'dart:convert';

import 'package:flutter/material.dart';
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

  testWidgets("the zone editor offers the thermostats the form holds now", (tester) async {
    String option(String id, String label) =>
        json.encode({"device_selection": {"device_id": id, "service_id": null, "path": null}, "label": label});
    final options = [option("urn:infai:ses:device:a", "Living room"), option("urn:infai:ses:device:b", "Bathroom")];
    final thermostats = SmartServiceExtendedParameter("thermostats", "Thermostats", "", [options[0]], null, true,
        [for (final o in options) SmartServiceParameterOption("device", json.decode(o)["label"], o, null, null)], ContentVariable.string, null, null, null, false);
    final schedule = SmartServiceExtendedParameter("schedule", "Schedule", "", '{"zones":[{"name":"Bad","devices":["urn:infai:ses:device:a"],"windows":[]}]}',
        null, false, null, ContentVariable.string, null, null, null, false);

    await pumpGolden(tester, SmartServicesReleaseLaunch(_release(), instance: _instance(), parameters: [thermostats, schedule]), dark: false);
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(CheckboxListTile, "Living room"), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, "Bathroom"), findsNothing);

    // selecting the second thermostat in the form shows it in the zone editor
    thermostats.characteristic!.value = [options[0], options[1]];
    await pumpGolden(tester, SmartServicesReleaseLaunch(_release(), instance: _instance(), parameters: [thermostats, schedule]), dark: false);
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithText(CheckboxListTile, "Bathroom"), findsOneWidget);
  });

  testWidgets("an own setback of a zone starts at the setback of the form, not at 0", (tester) async {
    final schedule = SmartServiceExtendedParameter("schedule", "Schedule", "", '{"windows":[]}', null, false, null, ContentVariable.string, null, null, null, false);
    final option = json.encode({"device_selection": {"device_id": "urn:infai:ses:device:a", "service_id": null, "path": null}, "label": "A"});
    final thermostats = SmartServiceExtendedParameter("thermostats", "Thermostats", "", [option], null, true,
        [SmartServiceParameterOption("device", "A", option, null, null)], ContentVariable.string, null, null, null, false);
    final setback = SmartServiceExtendedParameter("setback", "Setback", "", 17, null, false, null, ContentVariable.integer, null, null, null, false);

    await pumpGolden(tester, SmartServicesReleaseLaunch(_release(), instance: _instance(), parameters: [thermostats, schedule, setback]), dark: false);
    await tester.pump();
    await tester.pump();
    final own = find.byType(Switch).last; // no window, so the last switch is the own setback
    await tester.ensureVisible(own);
    await tester.tap(own);
    await tester.pump();
    expect(schedule.value, '{"zones":[{"name":"Alle","windows":[],"setback":17}]}');
  });
}
