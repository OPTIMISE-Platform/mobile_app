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
import 'package:mobile_app/mixins/device_mixin.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/scrollable_empty_state.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';

/// Where a [PagedDeviceList] gets its next page from. The list reads it on
/// every build and never listens to it: whoever builds the list rebuilds it
/// when the source changes.
abstract interface class PageSource {
  /// Whether the list ends in a row that asks for the next page.
  bool get hasMore;

  /// No page comes before a new search: all have arrived or the last one
  /// failed.
  bool get ended;

  /// Must change whenever a page load ends, successful or not. The next-page
  /// row is keyed on it: it asks once when it appears and once more after
  /// each load it stays on screen for, never once per rebuild.
  Object? get pageToken;

  /// Must not notify listeners synchronously: it is called while the list
  /// builds.
  void loadNextPage();
}

/// The device search of [DeviceMixin] as a [PageSource].
class DeviceSearchPages implements PageSource {
  const DeviceSearchPages(this.state, {this.untilEnded = false});

  final DeviceMixin state;

  /// Keeps asking until the search has ended, also once the devices shown
  /// reach the server's total. For a list that needs the search complete (a
  /// location's devices); other lists stop at [DeviceMixin.devicesListItemCount].
  final bool untilEnded;

  @override
  bool get hasMore => untilEnded
      ? !state.devicesListEnded
      : state.devicesListItemCount > state.devices.length;

  @override
  bool get ended => state.devicesListEnded;

  @override
  Object get pageToken => state.devicePageLoads;

  @override
  void loadNextPage() => state.loadDevices();
}

/// A [SectionedListView] over a paged [source]: a spinner while [loading], an
/// empty state once nothing is left to show or to come, otherwise the
/// sections followed by a zero-height row that asks for the next page.
class PagedDeviceList extends StatelessWidget {
  const PagedDeviceList({
    required this.source,
    required this.sections,
    this.loading = false,
    this.emptyText,
    this.onRefresh,
    this.scrollbar = false,
    this.physics,
    this.trailing = const [],
    super.key,
  });

  final PageSource source;

  final List<ListSection<Object?>> sections;

  /// Shows the spinner in place of the list.
  final bool loading;

  /// Shown, still pullable, when every section is empty and [source] has
  /// ended. Not before: a page whose devices are all hidden leaves the list
  /// empty, and only its next-page row fetches the page after. Null keeps an
  /// empty list a list.
  final String? emptyText;

  /// Wraps everything in a [RefreshIndicator] that calls this after a haptic
  /// tick.
  final Future<void> Function()? onRefresh;

  /// Puts a [Scrollbar] around the content, inside the [RefreshIndicator].
  final bool scrollbar;

  final ScrollPhysics? physics;

  /// Below the next-page row, e.g. FAB clearance.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Center(child: DelayedCircularProgressIndicator());
    } else if (emptyText != null &&
        source.ended &&
        sections.every((s) => s.items.isEmpty)) {
      body = ScrollableEmptyState(emptyText!);
    } else {
      body = SectionedListView(
        physics: physics,
        sections: sections,
        trailing: [
          if (source.hasMore && !source.ended)
            _NextPageRow(source, key: _NextPageKey(source.pageToken)),
          ...trailing,
        ],
      );
    }
    if (scrollbar) body = Scrollbar(child: body);
    final refresh = onRefresh;
    if (refresh != null) {
      body = RefreshIndicator(
        onRefresh: () async {
          HapticFeedbackProxy.lightImpact();
          await refresh();
        },
        child: body,
      );
    }
    return body;
  }
}

class _NextPageKey extends LocalKey {
  const _NextPageKey(this.token);

  final Object? token;

  @override
  bool operator ==(Object other) =>
      other is _NextPageKey && other.token == token;

  @override
  int get hashCode => Object.hash(_NextPageKey, token);
}

/// Asks for the next page when it is first built, which the list does only
/// once the row scrolls near the viewport. A new page token gives it a new
/// key and so a new State, which asks again.
class _NextPageRow extends StatefulWidget {
  const _NextPageRow(this.source, {super.key});

  final PageSource source;

  @override
  State<_NextPageRow> createState() => _NextPageRowState();
}

class _NextPageRowState extends State<_NextPageRow> {
  @override
  void initState() {
    super.initState();
    widget.source.loadNextPage();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
