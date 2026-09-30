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

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/mixins/data_mixin.dart';
import 'package:mobile_app/mixins/device_mixin.dart';
import 'package:mobile_app/mixins/network_mixin.dart';
import 'package:mobile_app/mixins/notification_mixin.dart';
import 'package:mobile_app/native_pipe.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/metadata_cache.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';

/// The reference metadata [AppState] loads at start and revalidates.
enum _Metadata { deviceTypes, functions, aspects, concepts, characteristics }

class AppState extends ChangeNotifier
    with
        DeviceMixin,
        NetworkMixin,
        NotificationMixin,
        DataMixin,
        WidgetsBindingObserver {
  static final _instance = AppState._internal();

  factory AppState() => _instance;

  bool _initialized = false;

  bool get loggedIn => Auth().loggedIn;
  bool get loggingIn => Auth().loggingIn;
  bool get initialized => _initialized;

  AppState._internal() {
    WidgetsBinding.instance.addObserver(this);
    manageNetworkDiscovery();
    NativePipe.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    handleQueuedMessages();
    manageNetworkDiscovery();
    unawaited(CacheHelper.scheduleCacheUpdates().catchError(
        (Object e, StackTrace s) =>
            ErrorReporter.log('Could not refresh cache', e, s)));
    unawaited(_revalidateCaches(refetchClasses: true));
  }

  @override
  Future<void> ensureInitialized() async {
    if (!_initialized) await init();
  }

  Future<void> init() async {
    if (_initialized) return;
    final startTime = DateTime.now();

    try {
      unawaited(initMessaging());
      // Not in the Future.wait below: a row wants its device's location on
      // the very first render, but nothing else needs to block init on it -
      // loadLocations() reports its own errors via ErrorReporter. Only when
      // nothing is loaded yet (the real cold-start/post-login case, since
      // locations only ever gets entries from this same loader or
      // clearNetworkData() empties it again on logout): loadLocations()
      // itself always clears first, so calling it whenever init() runs would
      // instead race and drop a load already served another way.
      if (locations.isEmpty) unawaited(loadLocations());
      // Stored copies of any age are served here, so only an empty cache
      // waits for the backend; what is too old is revalidated after the frame.
      await Future.wait([
        loadInactiveDeviceIds(),
        loadCachedDeviceClasses(),
        for (final m in _Metadata.values) _loadMetadata(m),
        loadStoredMGWs(),
      ]);
    } finally {
      debugPrint('AppState init took ${DateTime.now().difference(startTime)}');
      _initialized = true;
      notifyListeners();
      unawaited(SchedulerBinding.instance.endOfFrame.then((_) =>
          _revalidateCaches(refetchClasses: deviceClassesFromCache)));
    }
  }

  /// When the in-memory copy of each metadata set was stored, as reported by
  /// its loader; a set whose load failed has no entry.
  final Map<_Metadata, DateTime> _metadataStoredAt = {};

  bool _revalidatingMetadata = false;

  /// The device types as [init] loads them: a stored copy of any age is
  /// served, and one older than [metadataMaxAge] is revalidated later.
  Future<bool> loadStoredDeviceTypes() => _loadMetadata(_Metadata.deviceTypes);

  Future<bool> _loadMetadata(_Metadata m,
      {Duration maxAge = metadataMaxAge, bool quiet = false}) {
    final epoch = AccountEpoch.current;
    void record(DateTime storedAt) {
      // A load that outlived a logout must not mark the next session's data.
      if (epoch == AccountEpoch.current) _metadataStoredAt[m] = storedAt;
    }
    switch (m) {
      case _Metadata.deviceTypes:
        return loadDeviceTypes(
            maxAge: maxAge, serveStale: record, quiet: quiet);
      case _Metadata.functions:
        return loadNestedFunctions(
            maxAge: maxAge, serveStale: record, quiet: quiet);
      case _Metadata.aspects:
        return loadAspects(maxAge: maxAge, serveStale: record, quiet: quiet);
      case _Metadata.concepts:
        return loadConcepts(maxAge: maxAge, serveStale: record, quiet: quiet);
      case _Metadata.characteristics:
        return loadCharacteristics(
            maxAge: maxAge, serveStale: record, quiet: quiet);
    }
  }

  Set<_Metadata> _staleMetadata() {
    final now = DateTime.now();
    return {
      for (final e in _metadataStoredAt.entries)
        if (MetadataCache.isStale(e.value, metadataMaxAge, now)) e.key,
    };
  }

  /// Refetches the device classes when [refetchClasses] and every metadata set
  /// older than [metadataMaxAge], in the background: failures are logged and
  /// keep what is on screen.
  Future<void> _revalidateCaches({required bool refetchClasses}) async {
    // Checked before anything reads Settings: nothing to do is the common case.
    if (!_initialized) return;
    final metadataDue = !_revalidatingMetadata && _staleMetadata().isNotEmpty;
    if (!refetchClasses && !metadataDue) return;
    if (Settings.getLocalMode()) return;
    await Future.wait([
      if (refetchClasses) refetchDeviceClasses(),
      if (metadataDue) _revalidateMetadata(),
    ]);
  }

  /// One pass at a time: a call while one runs returns at once, since the
  /// running pass re-checks for stale sets and clears its flag in the same
  /// synchronous step, so nothing reported stale meanwhile is missed.
  Future<void> _revalidateMetadata() async {
    if (_revalidatingMetadata) return;
    _revalidatingMetadata = true;
    final epoch = AccountEpoch.current;
    // A logout during the pass has cleared the maps; nothing to reload.
    bool current() => _initialized && epoch == AccountEpoch.current;
    try {
      final attempted = <_Metadata>{};
      var refreshed = false;
      while (true) {
        final due = _staleMetadata().difference(attempted);
        if (due.isEmpty) break;
        attempted.addAll(due);
        final results = await Future.wait(due.map((m) =>
            _loadMetadata(m, maxAge: Duration.zero, quiet: true)));
        if (!current()) return;
        refreshed |= results.contains(true);
      }
      if (refreshed) {
        notifyListeners();
        pushRefresh();
      }
    } finally {
      _revalidatingMetadata = false;
    }
  }

  Future<void> onLogout() async {
    await clearNotificationData();
    clearDeviceData();
    clearNetworkData();
    clearData();
    _metadataStoredAt.clear();
    _initialized = false;
    // No clearCache here: the only caller (Auth._cleanup) has already awaited
    // it — this unawaited second run raced whatever a re-login started.
  }

  final _refreshPressedController = StreamController.broadcast();

  Stream get refreshPressed => _refreshPressedController.stream;

  void pushRefresh() => _refreshPressedController.add(null);

  /// Fetches the metadata maps fresh and notifies the open tabs to reload
  /// their data. Devices, groups, networks and locations are covered by the
  /// tabs' [refreshPressed] listeners. The loaders swap their maps only after
  /// a successful fetch, so readers never see them empty mid-reload, and
  /// `Duration.zero` keeps the stored copies when a fetch fails.
  ///
  /// [onProgress] reports the fraction of completed reload tasks (0..1).
  /// Throws when any loader failed, after all of them have finished.
  Future<void> reloadMetadata({void Function(double progress)? onProgress}) async {
    forgetUnavailableDeviceTypes();
    final tasks = <Future<bool>>[
      // No fallback: the stored copy would pass a failed fetch off as success.
      loadDeviceClasses(fallbackToCache: false),
      for (final m in _Metadata.values)
        _loadMetadata(m, maxAge: Duration.zero),
    ];
    var done = 0;
    final results = await Future.wait(tasks.map((t) => t.whenComplete(() {
          done++;
          onProgress?.call(done / tasks.length);
        })));
    notifyListeners();
    pushRefresh();
    // The loaders toast and swallow their own errors; without this the caller
    // would report success over stale maps.
    if (results.contains(false)) {
      throw Exception("not all metadata could be reloaded");
    }
  }

  // Memoized result of setAndGetDisabledTabs(). Recomputing walks every nav
  // item and calls the services' isAvailable()/isListAvailable() checks, each
  // of which parses a URI and scans the networks (~2ms a piece). This used to
  // run on every notifyListeners(); now we only redo it when one of the inputs
  // the result depends on actually changes.
  List<bool>? _disabledTabsCache;
  String? _disabledTabsInputSig;

  /// Cheap signature of the inputs [setAndGetDisabledTabs] depends on, without
  /// running the expensive availability checks.
  String _disabledTabsInput() {
    final sb = StringBuffer()
      ..write(locations.length)
      ..write(',')
      ..write(deviceGroups.length)
      ..write(',')
      ..write(networks.length)
      ..write(',')
      ..write(deviceClasses.length)
      ..write(',')
      ..write(Settings.getLocalMode() ? '1' : '0')
      ..write(',')
      ..write(Settings.getApiUrl() ?? '');
    return sb.toString();
  }

  List<bool> setAndGetDisabledTabs() {
    final input = _disabledTabsInput();
    final cached = _disabledTabsCache;
    if (cached != null && _disabledTabsInputSig == input) {
      return cached;
    }

    final disabledList = List.generate(navItems.length, (_) => true);
    for (final navItem in navItems) {
      switch (navItem.index) {
        case tabLocations:
          navItem.disabled =
              locations.isEmpty && !LocationService.isListAvailable();
          break;
        case tabGroups:
          navItem.disabled =
              deviceGroups.isEmpty && !DeviceGroupsService.isListAvailable();
          break;
        case tabNetworks:
          navItem.disabled =
              networks.isEmpty && !NetworksService.isAvailable();
          break;
        case tabClasses:
          navItem.disabled =
              deviceClasses.isEmpty && !DeviceClassesService.isAvailable();
          break;
        case tabSmartServices:
        case tabDashboard:
          navItem.disabled = !SmartServiceService.isAvailable();
          break;
        default:
          navItem.disabled = false;
      }
      disabledList[navItem.index] = navItem.disabled;
    }

    _disabledTabsInputSig = input;
    _disabledTabsCache = disabledList;
    return disabledList;
  }

  // ---------------------------------------------------------------------------
  // notifyListeners passthrough (required by some call sites)
  // ---------------------------------------------------------------------------

  @override
  // ignore: unnecessary_overrides
  void notifyListeners() => super.notifyListeners();
}