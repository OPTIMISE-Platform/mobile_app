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
enum _Metadata {
  deviceTypes,
  deviceClasses,
  functions,
  aspects,
  concepts,
  characteristics
}

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
    unawaited(_revalidateCaches(retryFailed: true));
  }

  @override
  Future<void> ensureInitialized() async {
    if (!_initialized) await init();
  }

  Future<void> init() async {
    if (_initialized) return;
    final epoch = AccountEpoch.current;
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
        loadDeviceIndex(),
        for (final m in _Metadata.values) _loadMetadata(m),
        loadStoredMGWs(),
      ]);
    } finally {
      debugPrint('AppState init took ${DateTime.now().difference(startTime)}');
      // An init that outlived its account loaded nothing for the next one, so
      // that account's ensureInitialized must still run its own.
      if (epoch == AccountEpoch.current) {
        _initialized = true;
        notifyListeners();
        unawaited(SchedulerBinding.instance.endOfFrame
            .then((_) => _revalidateCaches()));
      }
    }
  }

  /// When the in-memory copy of each metadata set was stored, as reported by
  /// its loader; a set whose load failed has no entry.
  final Map<_Metadata, DateTime> _metadataStoredAt = {};

  bool _revalidatingMetadata = false;

  /// The latest request to retry the sets whose last load failed, with the
  /// account epoch it was made under; null once a pass has covered it.
  ({int serial, int epoch})? _retryRequest;
  int _retrySerial = 0;

  /// Per set, the request serial it was last retried for, so one request
  /// retries a failing set once and a later request once more.
  final Map<_Metadata, int> _retriedFor = {};

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
      case _Metadata.deviceClasses:
        return loadDeviceClasses(
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

  /// The sets older than [metadataMaxAge] not yet [attempted], and with a
  /// retry [request] of [epoch] the sets without a stored time, whose last
  /// load failed, not yet retried for it.
  Set<_Metadata> _dueMetadata(
      int epoch, Set<_Metadata> attempted, ({int serial, int epoch})? request) {
    final now = DateTime.now();
    final retry = request != null && request.epoch == epoch ? request.serial : null;
    return {
      for (final m in _Metadata.values)
        if (_metadataStoredAt[m] == null
            ? retry != null && (_retriedFor[m] ?? -1) < retry
            : !attempted.contains(m) &&
                MetadataCache.isStale(_metadataStoredAt[m]!, metadataMaxAge, now))
          m,
    };
  }

  /// Refetches every metadata set older than [metadataMaxAge], and with
  /// [retryFailed] every set whose last load failed, in the background:
  /// failures are logged and keep what is on screen.
  Future<void> _revalidateCaches({bool retryFailed = false}) async {
    if (!_initialized) return;
    final epoch = AccountEpoch.current;
    if (_retryRequest != null && _retryRequest!.epoch != epoch) {
      _retryRequest = null;
    }
    if (retryFailed) _retryRequest = (serial: ++_retrySerial, epoch: epoch);
    // The running pass, or the one it starts when it ends, takes it up.
    if (_revalidatingMetadata) return;
    // Checked before anything reads Settings: nothing to do is the common case.
    if (_dueMetadata(epoch, const {}, _retryRequest).isEmpty ||
        Settings.getLocalMode()) {
      _retryRequest = null;
      return;
    }
    await _revalidateMetadata();
  }

  /// Loads every metadata set whose last load failed, and the stale ones,
  /// through the background pass.
  Future<void> retryFailedMetadata() => _revalidateCaches(retryFailed: true);

  /// One pass at a time: a call while one runs returns at once. The pass
  /// re-checks for due sets before it ends, and a retry request it did not
  /// cover, such as one of the next account, gets a pass of its own.
  Future<void> _revalidateMetadata() async {
    if (_revalidatingMetadata) return;
    _revalidatingMetadata = true;
    final epoch = AccountEpoch.current;
    // A logout during the pass has cleared the maps; nothing to reload.
    bool current() => _initialized && epoch == AccountEpoch.current;
    var refreshed = false;
    int? coveredSerial;
    try {
      final attempted = <_Metadata>{};
      while (true) {
        final request = _retryRequest;
        coveredSerial = request?.serial;
        final due = _dueMetadata(epoch, attempted, request);
        if (due.isEmpty) {
          if (request != null &&
              request.epoch == epoch &&
              _retryRequest?.serial == request.serial) {
            _retryRequest = null;
          }
          break;
        }
        for (final m in due) {
          attempted.add(m);
          if (_metadataStoredAt[m] == null) _retriedFor[m] = request!.serial;
        }
        final results = await Future.wait(due.map((m) =>
            _loadMetadata(m, maxAge: Duration.zero, quiet: true)));
        if (!current()) return;
        refreshed |= results.contains(true);
      }
    } finally {
      _revalidatingMetadata = false;
      // Also when a loader threw: the request's sets were tried, and keeping
      // it would start pass after pass.
      if (coveredSerial != null && _retryRequest?.serial == coveredSerial) {
        _retryRequest = null;
      }
      final pending = _retryRequest;
      if (pending != null && pending.epoch == AccountEpoch.current) {
        unawaited(_revalidateCaches());
      }
    }
    // After the flag: a listener starting a pass of its own is not dropped.
    if (refreshed) {
      notifyListeners();
      pushRefresh();
    }
  }

  Future<void> onLogout() async {
    await clearNotificationData();
    clearDeviceData();
    clearNetworkData();
    clearData();
    _metadataStoredAt.clear();
    _retryRequest = null;
    _retriedFor.clear();
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
  /// Throws when any loader failed, after all of them have finished, unless
  /// the account changed meanwhile.
  Future<void> reloadMetadata({void Function(double progress)? onProgress}) async {
    final epoch = AccountEpoch.current;
    forgetUnavailableDeviceTypes();
    final tasks = <Future<bool>>[
      for (final m in _Metadata.values)
        _loadMetadata(m, maxAge: Duration.zero),
    ];
    var done = 0;
    final results = await Future.wait(tasks.map((t) => t.whenComplete(() {
          done++;
          onProgress?.call(done / tasks.length);
        })));
    // The loaders dropped what they fetched for the gone account; that is
    // neither a reload to announce nor a failure to report.
    if (epoch != AccountEpoch.current) return;
    notifyListeners();
    pushRefresh();
    // The loaders toast and swallow their own errors; without this the caller
    // would report success over stale maps.
    if (results.contains(false)) {
      throw Exception("not all metadata could be reloaded");
    }
  }

  /// Fetches the device classes, the device types and the devices fresh: the
  /// classes list and its counts are made of them. Failures are reported and
  /// keep what is loaded. Does nothing in local mode, where none of them can
  /// be fetched.
  Future<void> reloadDeviceClasses() async {
    if (Settings.getLocalMode()) return;
    forgetUnavailableDeviceTypes();
    await Future.wait([
      _loadFreshReported(
          _Metadata.deviceClasses, () => joinableDeviceClassesLoad),
      _loadFreshReported(_Metadata.deviceTypes, () => joinableDeviceTypesLoad),
      CacheHelper.refreshDevicesNow().catchError((Object e, StackTrace s) {
        ErrorReporter.report('Could not refresh devices', e, s);
        return false;
      }),
    ]);
  }

  /// Loads [m] fresh, reporting a failure. A call joins a running load; unless
  /// that one fetched fresh and reported, a load of its own follows it.
  Future<void> _loadFreshReported(
      _Metadata m, ({bool fresh, bool quiet})? Function() joinable) async {
    final epoch = AccountEpoch.current;
    final joined = joinable();
    await _loadMetadata(m, maxAge: Duration.zero);
    if (joined == null || (joined.fresh && !joined.quiet)) return;
    if (epoch != AccountEpoch.current) return;
    await _loadMetadata(m, maxAge: Duration.zero);
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