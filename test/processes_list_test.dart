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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/shared/relative_time.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/section_list_header.dart';
import 'package:mobile_app/widgets/tabs/processes/processes_list.dart';

import 'golden_helper.dart';
import 'process_backend.dart';

const _hub = "urn:infai:ses:hub:known";
const _unknownHub = "urn:infai:ses:hub:unknown";

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // One testWidgets: Dio instances are memoized for the process, and a second
  // test would not get its answers (docs/testing.md).
  testWidgets(
      "rows are grouped into Cloud and gateway sections with state chips, "
      "next run and a detail page", (tester) async {
    AppState().networks.add(Network(_hub, "Basement Hub", false, [], [],
        DeviceConnectionStatus.online, "", "owner"));
    final now = DateTime.now();
    final due = now.add(const Duration(minutes: 17));
    String ago(int minutes) =>
        now.subtract(Duration(minutes: minutes)).toUtc().toIso8601String();

    final backend = ProcessBackend(
      deployments: [
        deploymentJson("d-cloud", "Heating", description: "Keeps the salon warm"),
        deploymentJson("d-old", "Old job"),
        deploymentJson("d-idle", "Idle process"),
        deploymentJson("d-broken", "Broken job"),
        deploymentJson("d-stopped", "Stopped job"),
        deploymentJson("d-gw", "Gateway job", networkId: _hub),
        deploymentJson("d-lost", "Lost job", networkId: _unknownHub),
      ],
      instances: [
        // An older run of the same deployment must not win.
        instanceJson("i-cloud-old", "d-cloud", "Heating",
            state: "completed", createdAt: ago(600), lastActivityAt: ago(500)),
        instanceJson("i-cloud", "d-cloud", "Heating",
            createdAt: ago(300), lastActivityAt: ago(12)),
        instanceJson("i-old", "d-old", "Old job",
            state: "completed", createdAt: ago(3000), lastActivityAt: ago(60 * 5)),
        instanceJson("i-broken", "d-broken", "Broken job",
            state: "incident", createdAt: ago(100), lastActivityAt: ago(90)),
        instanceJson("i-stopped", "d-stopped", "Stopped job",
            state: "terminated", createdAt: ago(100), lastActivityAt: ago(80)),
        instanceJson("i-gw", "d-gw", "Gateway job",
            createdAt: ago(200), lastActivityAt: ago(3), networkId: _hub),
      ],
      debugs: {
        "i-cloud": timerDebugJson("Timer_tick", "15 Minuten", due),
        "i-broken": {
          "active": [],
          "waits": [],
          "incidents": [
            {"error_message": "Device did not answer"}
          ],
        },
        "i-gw": {
          "active": [],
          "waits": [],
          "incidents": [
            {"error_message": "Script task failed"}
          ],
        },
      },
    );
    serveGoldenBackend(backend);

    await pumpGolden(
        tester, const Scaffold(body: ProcessesList()), dark: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Sections: Cloud first, then gateways by name; an unknown hub is
    // "Gateway".
    final headers = tester
        .widgetList<SectionListHeader>(find.byType(SectionListHeader))
        .map((h) => h.title)
        .toList();
    expect(headers, ["Cloud", "Basement Hub", "Gateway"]);

    Finder row(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(ListTile));
    Finder inRow(String name, Finder what) =>
        find.descendant(of: row(name), matching: what);

    // Cloud rows by name; the newest instance decides, not the older one.
    expect(inRow("Heating", find.text("Running")), findsOneWidget);
    expect(inRow("Idle process", find.text("Not running")), findsOneWidget);
    expect(inRow("Old job", find.text("Completed")), findsOneWidget);
    expect(inRow("Gateway job", find.text("Incident")), findsOneWidget);
    expect(inRow("Lost job", find.text("Not running")), findsOneWidget);
    // An instance the engine ended on an incident, and one that was stopped.
    expect(inRow("Broken job", find.text("Incident")), findsOneWidget);
    expect(inRow("Stopped job", find.text("Stopped")), findsOneWidget);

    expect(
        inRow("Heating",
            find.text("Last activity 12 min ago · Next run ${clockOrDate(due)}")),
        findsOneWidget);
    expect(inRow("Old job", find.text("Last activity 5 h ago")), findsOneWidget);

    final context = tester.element(find.text("Heating"));
    Color? chipColor(String name, String label) => tester
        .widget<Text>(inRow(name, find.text(label)))
        .style
        ?.color;
    expect(chipColor("Heating", "Running"), context.appColors.appInk);
    expect(chipColor("Gateway job", "Incident"), context.appColors.error);
    expect(chipColor("Broken job", "Incident"), context.appColors.error);

    // The debug requests ran for running and incident instances only.
    final debugPaths = backend.requests
        .map((r) => r.uri.path)
        .where((p) => p.endsWith("/debug"))
        .toSet();
    expect(debugPaths, {
      "$processesBase/instances/i-cloud/debug",
      "$processesBase/instances/i-broken/debug",
      "$processesBase/instances/i-gw/debug",
    });

    // Detail with a timer wait.
    await tester.tap(find.text("Heating"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Keeps the salon warm"), findsOneWidget);
    expect(find.text("Waiting for"), findsOneWidget);
    expect(find.text("Active steps"), findsOneWidget);
    expect(find.text("Incidents"), findsNothing);
    expect(find.text("Timer · PT15M"), findsOneWidget);
    expect(find.text("Due ${clockOrDate(due)}"), findsOneWidget);
    expect(find.text("15 Minuten"), findsNWidgets(2));
    expect(find.text("Cloud"), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 500));

    // Detail with an incident, in the error colour.
    await tester.tap(find.text("Gateway job"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("Incidents"), findsOneWidget);
    final message = tester.widget<Text>(find.text("Script task failed"));
    expect(message.style?.color, context.appColors.error);
    expect(find.text("Basement Hub"), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
  });
}
