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
import 'package:mobile_app/widgets/shared/section_list_header.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

void main() {
  Widget host(Widget list) => MaterialApp(home: Scaffold(body: list));

  ListSection<String> section(String id, List<String> items,
          {String? title, Map<String, SlicePosition>? positions}) =>
      ListSection<String>(
        id: id,
        title: title,
        items: items,
        keyOf: (item) => item,
        itemBuilder: (_, item, position) {
          positions?["$id/$item"] = position;
          return _ToggleRow("$id/$item");
        },
      );

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  SliverChildBuilderDelegate delegate(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).childrenDelegate
          as SliverChildBuilderDelegate;

  group("SectionedListView", () {
    testWidgets("computes each row's position within its own section",
        (tester) async {
      final positions = <String, SlicePosition>{};
      await tester.pumpWidget(host(SectionedListView(
        leading: const [Text("lead")],
        trailing: const [Text("trail")],
        sections: [
          section("a", ["1", "2", "3"], title: "A", positions: positions),
          section("b", ["1"], title: "B", positions: positions),
          section("c", ["1", "2"], positions: positions),
        ],
      )));

      expect(positions, {
        "a/1": SlicePosition.first,
        "a/2": SlicePosition.middle,
        "a/3": SlicePosition.last,
        "b/1": SlicePosition.only,
        "c/1": SlicePosition.first,
        "c/2": SlicePosition.last,
      });
      // leading, header A, a/1..3, header B, b/1, c/1..2, trailing
      expect(top(tester, "lead"), lessThan(top(tester, "A")));
      expect(top(tester, "A"), lessThan(top(tester, "a/1 off")));
      expect(top(tester, "a/3 off"), lessThan(top(tester, "B")));
      expect(top(tester, "B"), lessThan(top(tester, "b/1 off")));
      expect(top(tester, "b/1 off"), lessThan(top(tester, "c/1 off")));
      expect(top(tester, "c/2 off"), lessThan(top(tester, "trail")));
      expect(tester.widget<ListView>(find.byType(ListView)).semanticChildCount,
          10);
    });

    testWidgets("shows a header only for a titled section with rows",
        (tester) async {
      await tester.pumpWidget(host(SectionedListView(sections: [
        section("empty", [], title: "Empty"),
        section("untitled", ["1"]),
        section("titled", ["1"], title: "Titled"),
      ])));

      expect(find.text("Empty"), findsNothing);
      expect(find.byType(SectionListHeader), findsOneWidget);
      expect(find.text("Titled"), findsOneWidget);
      expect(find.text("untitled/1 off"), findsOneWidget);
    });

    testWidgets(
        "keeps a row's State with its item when a section before it "
        "appears or disappears", (tester) async {
      Widget build(List<String> groups) => host(SectionedListView(sections: [
            section("groups", groups, title: "Groups"),
            section("devices", ["d1", "d2"], title: "Devices"),
          ]));

      await tester.pumpWidget(build(["g1"]));
      await tester.tap(find.text("devices/d1 off"));
      await tester.pump();
      expect(find.text("devices/d1 on"), findsOneWidget);
      expect(delegate(tester).findChildIndexCallback!(
              const ValueKey(("devices", "d1"))),
          3);

      // Header and row of "groups" go: every device row moves two slots up.
      await tester.pumpWidget(build([]));
      expect(find.text("Groups"), findsNothing);
      expect(find.text("devices/d1 on"), findsOneWidget);
      expect(find.text("devices/d2 off"), findsOneWidget);
      expect(delegate(tester).findChildIndexCallback!(
              const ValueKey(("devices", "d1"))),
          1);
      expect(delegate(tester).findChildIndexCallback!(
              const ValueKey(("groups", "g1"))),
          isNull);

      // And back: two slots down again.
      await tester.pumpWidget(build(["g1", "g2"]));
      expect(find.text("devices/d1 on"), findsOneWidget);
      expect(find.text("devices/d2 off"), findsOneWidget);
      expect(find.text("groups/g1 off"), findsOneWidget);
      expect(delegate(tester).findChildIndexCallback!(
              const ValueKey(("devices", "d2"))),
          5);
    });

    testWidgets("keeps equal item keys in two sections apart",
        (tester) async {
      Widget build(bool withSecond) => host(SectionedListView(sections: [
            section("first", ["same"]),
            section("second", withSecond ? ["same"] : []),
          ]));

      await tester.pumpWidget(build(true));
      await tester.tap(find.text("first/same off"));
      await tester.pump();
      expect(find.text("first/same on"), findsOneWidget);
      expect(find.text("second/same off"), findsOneWidget);

      // With one shared key, the second row's State would take over the
      // first row's slot here.
      await tester.pumpWidget(build(false));
      expect(find.text("first/same on"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("renders rows that share a key instead of failing",
        (tester) async {
      await tester.pumpWidget(host(SectionedListView(sections: [
        section("devices", ["d1", "d2", "d1"]),
      ])));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey(("devices", "d1"))), findsOneWidget);
      expect(find.byKey(const ValueKey(("devices", "d1#1"))), findsOneWidget);
    });

    testWidgets("builds an empty row when the list shrank since the build",
        (tester) async {
      final items = List.generate(40, (i) => "d$i");
      await tester.pumpWidget(host(SectionedListView(sections: [
        section("devices", items),
      ])));
      items.clear();
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets("rejects two sections with the same id", (tester) async {
      await tester.pumpWidget(host(SectionedListView(sections: [
        section("devices", ["d1"]),
        section("devices", ["d2"]),
      ])));

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains('share the id "devices"'));
    });
  });
}

class _ToggleRow extends StatefulWidget {
  const _ToggleRow(this.label);

  final String label;

  @override
  State<_ToggleRow> createState() => _ToggleRowState();
}

class _ToggleRowState extends State<_ToggleRow> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text("${widget.label} ${_on ? "on" : "off"}"),
        onTap: () => setState(() => _on = !_on),
      );
}
