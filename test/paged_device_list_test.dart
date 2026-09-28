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
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/paged_device_list.dart';
import 'package:mobile_app/widgets/shared/scrollable_empty_state.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';

import 'test_helper.dart';

class _FakeSource implements PageSource {
  @override
  bool hasMore = true;

  @override
  bool ended = false;

  @override
  Object? pageToken = 0;

  int requests = 0;

  /// What the page load does to the source, run after the frame that asked.
  void Function()? onLoad;

  @override
  void loadNextPage() {
    requests++;
    final load = onLoad;
    if (load != null) Future.microtask(load);
  }
}

void main() {
  // The refresh indicator's haptic tick reads its setting.
  setUpAll(() async {
    setUpTestEnvironment();
    await Settings.init();
  });
  tearDownAll(() async {
    await Settings.close();
  });

  Widget host(_FakeSource source, List<String> items,
          {bool loading = false,
          String? emptyText = "Nothing here",
          Future<void> Function()? onRefresh,
          bool scrollbar = false}) =>
      MaterialApp(
        home: Scaffold(
          body: PagedDeviceList(
            source: source,
            loading: loading,
            emptyText: emptyText,
            onRefresh: onRefresh,
            scrollbar: scrollbar,
            sections: [
              ListSection<String>(
                id: "items",
                items: items,
                keyOf: (item) => item,
                itemBuilder: (_, item, __) =>
                    SizedBox(height: 56, child: Text(item)),
              ),
            ],
          ),
        ),
      );

  /// Rebuilds the list from its parent [frames] times, one frame each.
  Future<void> rebuildFrames(WidgetTester tester, _FakeSource source,
      List<String> items, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pumpWidget(host(source, items));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group("PagedDeviceList", () {
    testWidgets(
        "asks for the next page once per appearance of its row, not once "
        "per rebuild", (tester) async {
      final source = _FakeSource();
      await tester.pumpWidget(host(source, ["a", "b"]));
      expect(source.requests, 1);

      await rebuildFrames(tester, source, ["a", "b"], 30);
      expect(source.requests, 1);

      // A page landed that added nothing visible: the row is still on
      // screen, and asks once more.
      source.pageToken = 1;
      await rebuildFrames(tester, source, ["a", "b"], 30);
      expect(source.requests, 2);
    });

    testWidgets("does not ask while its row is still far below the viewport",
        (tester) async {
      final source = _FakeSource();
      final items = [for (var i = 0; i < 100; i++) "item $i"];
      await tester.pumpWidget(host(source, items));
      await rebuildFrames(tester, source, items, 5);
      expect(source.requests, 0);

      await tester.dragUntilVisible(
          find.text("item 99"), find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      expect(source.requests, 1);

      await rebuildFrames(tester, source, items, 10);
      expect(source.requests, 1);
    });

    testWidgets(
        "stops asking after a failed page and shows its empty state instead",
        (tester) async {
      final source = _FakeSource();
      source.onLoad = () {
        source.ended = true;
        source.hasMore = false;
        source.pageToken = 1;
      };
      await tester.pumpWidget(host(source, []));
      await rebuildFrames(tester, source, [], 60);

      expect(source.requests, 1);
      expect(find.text("Nothing here"), findsOneWidget);
    });

    testWidgets(
        "asks at most once while a failed page leaves the source unchanged",
        (tester) async {
      // A source that reports neither the end nor a new token after its
      // load failed: the row alone must still not turn that into a loop.
      final source = _FakeSource();
      await tester.pumpWidget(host(source, []));
      await rebuildFrames(tester, source, [], 60);

      expect(source.requests, 1);
      expect(find.text("Nothing here"), findsNothing);
    });

    testWidgets("never asks once the source has ended", (tester) async {
      final source = _FakeSource()..ended = true;
      await tester.pumpWidget(host(source, ["a"]));
      await rebuildFrames(tester, source, ["a"], 10);
      expect(source.requests, 0);
    });

    testWidgets("shows the spinner while loading, and asks for nothing",
        (tester) async {
      final source = _FakeSource();
      await tester.pumpWidget(host(source, [], loading: true));

      expect(find.byType(DelayedCircularProgressIndicator), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.text("Nothing here"), findsNothing);
      expect(source.requests, 0);
      // Lets the spinner's delay run out before the test ends.
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets(
        "keeps an empty list a list while more may come, so its row can "
        "fetch the next page", (tester) async {
      final source = _FakeSource();
      await tester.pumpWidget(host(source, []));

      expect(find.byType(ScrollableEmptyState), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
      expect(source.requests, 1);
    });

    testWidgets("shows the empty state only once empty and ended",
        (tester) async {
      final source = _FakeSource()
        ..ended = true
        ..hasMore = false;
      await tester.pumpWidget(host(source, []));
      expect(find.byType(ScrollableEmptyState), findsOneWidget);
      expect(find.text("Nothing here"), findsOneWidget);

      await tester.pumpWidget(host(source, ["a"]));
      expect(find.byType(ScrollableEmptyState), findsNothing);
      expect(find.text("a"), findsOneWidget);

      await tester.pumpWidget(host(source, [], emptyText: null));
      expect(find.byType(ScrollableEmptyState), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets("refreshes on pull, with the scrollbar inside the indicator",
        (tester) async {
      final source = _FakeSource()
        ..ended = true
        ..hasMore = false;
      var refreshes = 0;
      await tester.pumpWidget(host(source, ["a"], scrollbar: true,
          onRefresh: () async {
        refreshes++;
      }));

      expect(
          find.descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollbar)),
          findsOneWidget);

      await tester.fling(find.text("a"), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    });

    testWidgets("has no refresh indicator without onRefresh", (tester) async {
      final source = _FakeSource();
      await tester.pumpWidget(host(source, ["a"]));
      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.byType(Scrollbar), findsNothing);
    });
  });
}
