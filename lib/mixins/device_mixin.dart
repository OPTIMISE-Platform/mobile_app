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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/mgw_device_manager.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/joined_load.dart';
import 'package:mobile_app/shared/metadata_cache.dart';
import 'package:mutex/mutex.dart';

mixin DeviceMixin on ChangeNotifier {
  static final _logger = Logger(printer: SimplePrinter());

  final Map<String, DeviceClass> deviceClasses = {};
  final _deviceClassesMutex = Mutex();
  final _deviceClassesLoad = JoinedLoad();

  final Map<String, DeviceType> deviceTypes = {};
  final _deviceTypesMutex = Mutex();
  final _deviceTypesLoad = JoinedLoad();

  final List<DeviceInstance> devices = [];
  final _devicesMutex = Mutex();
  bool _allDevicesLoaded = false;
  bool _devicesLoadedOnce = false;
  int _deviceOffset = 0;

  /// Set when a page load failed; lists then show their end state instead of
  /// asking for the next page, and only the next [searchDevices] clears it.
  bool _devicesLoadFailed = false;

  int _devicePageLoads = 0;

  /// Bumped by every [searchDevices] and [clearDeviceData]. A page load that
  /// started under an older value discards its result instead of mixing it
  /// into the new search's list.
  int _devicesGeneration = 0;

  /// Devices seen with the inactive attribute: seeded from the Isar device
  /// cache, which the full cache refresh fills with every device of the
  /// account, and kept current by every page fetched or saved since. Lets a
  /// row count the devices its list would show without a request per row.
  final Set<String> _inactiveDeviceIds = {};

  /// The device type of every device in the index, by device id, kept the
  /// same way as [_inactiveDeviceIds]. Class rows count their devices by it.
  final Map<String, String> _indexedDeviceTypes = {};

  /// Whether the index holds every device of the account: after
  /// [replaceDeviceIndex], or a seed from a cache a full refresh has filled.
  bool _deviceIndexComplete = false;

  /// The indexed device ids per class, built on demand and dropped whenever
  /// the index or the types change.
  Map<String, List<String>>? _classDeviceIdsCache;

  Map<String, List<String>> get _classDeviceIds =>
      _classDeviceIdsCache ??= _buildClassDeviceIds();

  Map<String, List<String>> _buildClassDeviceIds() {
    final byClass = <String, List<String>>{};
    for (final e in _indexedDeviceTypes.entries) {
      final classId = deviceTypes[e.value]?.device_class_id;
      if (classId != null) (byClass[classId] ??= []).add(e.key);
    }
    return byClass;
  }

  /// Bumped when the index is replaced or cleared, so a seed that read the
  /// cache before that is discarded.
  int _inactiveIndexEpoch = 0;

  /// Ids noted while a seed is reading the cache; their note is newer than
  /// what the seed read.
  Set<String>? _notedDuringSeed;

  final List<DeviceGroup> deviceGroups = [];
  final _deviceGroupsMutex = Mutex();
  bool _deviceGroupsLoadedOnce = false;

  DeviceSearchFilter _deviceSearchFilter = DeviceSearchFilter.empty();

  int totalDevices = 0;
  final _totalDevicesMutex = Mutex();

  bool get loadingDevices => _totalDevicesMutex.isLocked || _devicesMutex.isLocked;
  bool get allDevicesLoaded => _allDevicesLoaded;

  /// True after the last page load failed; see [devicesListEnded].
  bool get devicesLoadFailed => _devicesLoadFailed;

  /// No further page arrives without a new search: all pages are in, or the
  /// last one failed. Lists show their end state (e.g. "No Devices") then.
  bool get devicesListEnded => _allDevicesLoaded || _devicesLoadFailed;

  /// Whether the current search includes inactive devices, for code that
  /// starts a narrower search (a group's members) and must keep the toggle.
  bool get showsInactiveDevices => _deviceSearchFilter.showInactive;

  /// Changes when a page load has run to its end, whatever the outcome, and
  /// when [clearDeviceData] resets paging. A list's next-page row is keyed on
  /// it, so it asks once more after each of those instead of on every rebuild.
  int get devicePageLoads => _devicePageLoads;

  /// Raw pages fetched so far (before hiding inactive devices). Unlike
  /// [devices].length, this advances even on a page that filters down to
  /// nothing, so a rebuild gated on it (DeviceList's Selector) still notices.
  int get rawDevicesFetched => _deviceOffset;

  /// Upper bound for a list's itemCount while paginating. Not [totalDevices]
  /// (the server's raw, unfiltered count): hidden devices can leave
  /// devices.length permanently below it, which would add trailing blank
  /// rows instead of ending the list. The devices.length >= totalDevices
  /// branch covers tests that fill [devices] directly to match [totalDevices]
  /// without ever driving [_allDevicesLoaded] true through a real fetch.
  int get devicesListItemCount =>
      (devicesListEnded || devices.length >= totalDevices)
          ? devices.length
          : devices.length + 1;

  /// True once an initial device load has completed. Callers that rely on the
  /// device list being populated must force their search until then, since
  /// [searchDevices] skips an unchanged filter — which on a fresh start matches
  /// the initial empty filter.
  bool get devicesLoadedOnce => _devicesLoadedOnce;

  /// True once devices *and* device groups have each completed an initial load.
  /// Before that, "no favorites yet" is indistinguishable from "not loaded
  /// yet" — the favorites screen uses this to show a spinner instead of briefly
  /// flashing the empty "Add Favorites" state during startup. A failed device
  /// load counts as loaded, like in [devicesListEnded]: no page follows it
  /// without a new search, so waiting for one would spin forever.
  bool get favoritesDataLoaded =>
      (_devicesLoadedOnce || _devicesLoadFailed) && _deviceGroupsLoadedOnce;
  bool get loadingDeviceClasses => _deviceClassesMutex.isLocked;
  bool loadingDeviceGroups() => _deviceGroupsMutex.isLocked;

  /// Implemented by [AppState] — called before loading devices to ensure
  /// device classes, types, and other metadata are loaded first.
  Future<void> ensureInitialized();

  // ---------------------------------------------------------------------------
  // Device classes
  // ---------------------------------------------------------------------------

  /// [serveStale] as in [loadMetadataCached].
  @visibleForTesting
  Future<List<DeviceClass>> Function(Duration maxAge,
          {void Function(DateTime storedAt)? serveStale}) fetchDeviceClasses =
      (maxAge, {serveStale}) => DeviceClassesService.getDeviceClasses(
          maxAge: maxAge, serveStale: serveStale);

  /// [quiet] logs a failure instead of reporting it, for a background load
  /// over a list already on screen. A failure keeps the classes loaded before.
  Future<bool> loadDeviceClasses(
          {Duration maxAge = metadataMaxAge,
          void Function(DateTime storedAt)? serveStale,
          bool quiet = false}) =>
      _deviceClassesLoad.run(
          () => _loadDeviceClasses(maxAge, serveStale, quiet),
          tag: (fresh: maxAge == Duration.zero, quiet: quiet));

  /// How the class load a call would now join was started, or null if none.
  ({bool fresh, bool quiet})? get joinableDeviceClassesLoad =>
      _deviceClassesLoad.joinableTag as ({bool fresh, bool quiet})?;

  Future<bool> _loadDeviceClasses(Duration maxAge,
      void Function(DateTime storedAt)? serveStale, bool quiet) async {
    final epoch = AccountEpoch.current;
    var loaded = false;
    await _deviceClassesMutex.acquire();
    try {
      final fetched = await fetchDeviceClasses(maxAge, serveStale: serveStale);
      // A fetch that outlived its account leaves the next one's map alone.
      if (epoch != AccountEpoch.current) return false;
      // Swap after the fetch: clearing first would leave the map visibly
      // empty for the whole request, clearing at all is what drops entries
      // deleted on the backend.
      deviceClasses.clear();
      for (final e in fetched) {
        deviceClasses[e.id] = e;
      }
      loaded = true;
    } catch (e, s) {
      if (quiet || epoch != AccountEpoch.current) {
        ErrorReporter.log('Could not get device classes', e, s);
      } else {
        ErrorReporter.report('Could not get device classes', e, s);
      }
    } finally {
      _deviceClassesMutex.release();
    }
    if (epoch != AccountEpoch.current) return false;
    if (loaded) _loadUsedClassImages();
    // Also after a failure, after the release: the Classes list shows a
    // spinner while [loadingDeviceClasses] and must learn that it ended.
    notifyListeners();
    return loaded;
  }

  /// Whether the loaded types are every type of the platform, because the
  /// backend has no /user-device-types; then the complete device index says
  /// which of them the user's devices have.
  bool get _typesFromIndex => _deviceTypesAreAll && _deviceIndexComplete;

  /// The ids of the user's device types that belong to one of [classIds].
  List<String> deviceTypeIdsOfClasses(Iterable<String> classIds) {
    final classes = classIds.toSet();
    final indexed =
        _typesFromIndex ? _indexedDeviceTypes.values.toSet() : null;
    return [
      for (final t in deviceTypes.values)
        if (classes.contains(t.device_class_id) &&
            (indexed == null || indexed.contains(t.id)))
          t.id
    ];
  }

  /// The classes of the user's device types, in the order of [deviceClasses].
  /// [deviceTypes] normally holds the types of the user's devices only.
  List<DeviceClass> get usedDeviceClasses {
    final used = _typesFromIndex
        ? _classDeviceIds.keys.toSet()
        : {for (final t in deviceTypes.values) t.device_class_id};
    return [
      for (final c in deviceClasses.values)
        if (used.contains(c.id)) c
    ];
  }

  /// Images are shown for the user's classes only (class list, device rows,
  /// detail page), so only those are downloaded; none while the types are the
  /// platform's and the index cannot yet tell the user's from them.
  void _loadUsedClassImages() {
    if (_deviceTypesAreAll && !_deviceIndexComplete) return;
    for (final c in usedDeviceClasses) {
      c.loadImage();
    }
  }

  // ---------------------------------------------------------------------------
  // Device types
  // ---------------------------------------------------------------------------

  /// Type ids a fresh load did not return. Without this, a device whose type
  /// the backend does not deliver would refetch the list on every page. Kept
  /// until [forgetUnavailableDeviceTypes] or an account change.
  final Set<String> _unavailableDeviceTypeIds = {};

  /// No fresh load before this time after one failed, so an offline start
  /// does not retry on every page.
  DateTime? _deviceTypesRetryAfter;

  @visibleForTesting
  Duration deviceTypesRetryDelay = const Duration(minutes: 1);

  /// Set by the first successful type load, whatever it returned.
  bool _deviceTypesLoaded = false;

  /// [DeviceTypesService.userListIsAllTypes] as of the list in [deviceTypes].
  bool _deviceTypesAreAll = false;

  @visibleForTesting
  bool Function() deviceTypesAreAll = () => DeviceTypesService.userListIsAllTypes;

  void _setDeviceTypes(List<DeviceType> fetched) {
    deviceTypes.clear();
    for (final e in fetched) {
      deviceTypes[e.id] = e;
    }
    _deviceTypesLoaded = true;
    _deviceTypesAreAll = deviceTypesAreAll();
    _classDeviceIdsCache = null;
    _loadUsedClassImages();
  }

  /// [serveStale] as in [loadMetadataCached].
  @visibleForTesting
  Future<List<DeviceType>> Function(Duration maxAge,
          {void Function(DateTime storedAt)? serveStale}) fetchDeviceTypes =
      (maxAge, {serveStale}) =>
          DeviceTypesService.getDeviceTypes(null, maxAge, serveStale);

  /// [quiet] logs a failure instead of reporting it, for a background load
  /// over a list already on screen.
  Future<bool> loadDeviceTypes(
          {Duration maxAge = metadataMaxAge,
          void Function(DateTime storedAt)? serveStale,
          bool quiet = false}) =>
      _deviceTypesLoad.run(() => _loadDeviceTypes(maxAge, serveStale, quiet),
          tag: (fresh: maxAge == Duration.zero, quiet: quiet));

  /// How the type load a call would now join was started, or null if none.
  ({bool fresh, bool quiet})? get joinableDeviceTypesLoad =>
      _deviceTypesLoad.joinableTag as ({bool fresh, bool quiet})?;

  /// Waits for an [ensureDeviceTypes] holding the mutex and then fetches
  /// itself: that call may have failed or skipped its fetch, so its end says
  /// nothing about whether this load would have succeeded.
  Future<bool> _loadDeviceTypes(Duration maxAge,
      void Function(DateTime storedAt)? serveStale, bool quiet) async {
    final epoch = AccountEpoch.current;
    await _deviceTypesMutex.acquire();
    try {
      final fetched = await fetchDeviceTypes(maxAge, serveStale: serveStale);
      if (epoch != AccountEpoch.current) return false;
      _setDeviceTypes(fetched);
      if (maxAge == Duration.zero) _typesWithoutDevices.addAll(_orphanTypes());
    } catch (e, s) {
      // Not the next account's failure to be told about.
      if (quiet || epoch != AccountEpoch.current) {
        ErrorReporter.log('Could not get device types', e, s);
      } else {
        ErrorReporter.report('Could not get device types', e, s);
      }
      return false;
    } finally {
      _deviceTypesMutex.release();
    }
    _reloadTypesWithoutDevices();
    notifyListeners();
    return true;
  }

  /// Only the types of the user's devices are loaded, so a type missing here
  /// means the user's devices changed since the list was cached: reload it,
  /// bypassing the cache.
  Future<void> ensureDeviceTypes(Iterable<String> typeIds) async {
    final ids = typeIds.toSet();
    bool hasMissing() => ids.any(
        (id) => !deviceTypes.containsKey(id) && !_unavailableDeviceTypeIds.contains(id));
    if (!hasMissing()) return;
    await _loadFreshDeviceTypes(hasMissing,
        () => _unavailableDeviceTypeIds
            .addAll(ids.where((id) => !deviceTypes.containsKey(id))));
  }

  /// A fresh type load while [needed] holds, at most one per
  /// [deviceTypesRetryDelay] after a failure. [afterLoad] records what the
  /// load did not resolve, so the same cause does not fetch again.
  Future<void> _loadFreshDeviceTypes(
      bool Function() needed, void Function() afterLoad) async {
    final epoch = AccountEpoch.current;
    // Not via loadDeviceTypes: joining a load that is already running there
    // returns without fetching, and that load may have been served from cache.
    await _deviceTypesMutex.acquire();
    try {
      // The cause belongs to the account of [epoch]: after a change it says
      // nothing about the next account's types, nor its retry state.
      if (epoch != AccountEpoch.current || !needed()) return;
      final retryAfter = _deviceTypesRetryAfter;
      if (retryAfter != null && DateTime.now().isBefore(retryAfter)) return;
      final List<DeviceType> fetched;
      try {
        fetched = await fetchDeviceTypes(Duration.zero);
      } catch (e, s) {
        if (epoch != AccountEpoch.current) {
          ErrorReporter.log('Could not reload device types', e, s);
          return;
        }
        _deviceTypesRetryAfter = DateTime.now().add(deviceTypesRetryDelay);
        // Logged only: the devices are on screen already, just without states.
        ErrorReporter.log('Could not reload device types', e, s);
        return;
      }
      if (epoch != AccountEpoch.current) return;
      _deviceTypesRetryAfter = null;
      _setDeviceTypes(fetched);
      afterLoad();
      _typesWithoutDevices.addAll(_orphanTypes());
    } finally {
      _deviceTypesMutex.release();
    }
    notifyListeners();
  }

  /// Types a fresh load returned although no device in the complete index has
  /// them; not reloaded for again.
  final Set<String> _typesWithoutDevices = {};

  /// The user's types without a device in the complete index; empty while the
  /// index is incomplete or the types are the platform's.
  Set<String> _orphanTypes() {
    if (!_deviceTypesLoaded || !_deviceIndexComplete || _deviceTypesAreAll) {
      return const {};
    }
    final indexed = _indexedDeviceTypes.values.toSet();
    return {
      for (final id in deviceTypes.keys)
        if (!indexed.contains(id)) id
    };
  }

  /// The list holds only types of the user's devices, so a type without any
  /// in the complete index means the list is behind, e.g. its last device was
  /// deleted: reload it fresh.
  void _reloadTypesWithoutDevices() {
    bool needed() =>
        _orphanTypes().difference(_typesWithoutDevices).isNotEmpty;
    if (needed()) unawaited(_loadFreshDeviceTypes(needed, () {}));
  }

  /// After every change of the index: the class map is rebuilt on demand,
  /// newly used classes get their images, and the types are checked.
  void _deviceIndexChanged() {
    _classDeviceIdsCache = null;
    _loadUsedClassImages();
    _reloadTypesWithoutDevices();
  }

  /// Lets [ensureDeviceTypes] try again for types an earlier fresh load did
  /// not return.
  void forgetUnavailableDeviceTypes() {
    _unavailableDeviceTypeIds.clear();
    _typesWithoutDevices.clear();
    _deviceTypesRetryAfter = null;
  }

  // ---------------------------------------------------------------------------
  // Visible device counts
  // ---------------------------------------------------------------------------

  /// How many of [ids] a device list searched with the current "Show
  /// inactive" setting shows: inactive devices are hidden unless they are
  /// favourites, the same rule [loadDevices] applies. A device never seen
  /// counts as shown, as it did before hidden devices existed.
  int visibleDeviceCount(Iterable<String> ids) {
    if (showsInactiveDevices || _inactiveDeviceIds.isEmpty) return ids.length;
    Set<String>? favorites;
    var count = 0;
    for (final id in ids) {
      if (!_inactiveDeviceIds.contains(id)) {
        count++;
        continue;
      }
      favorites ??= Settings.getFavoriteDeviceIds();
      if (favorites.contains(id)) count++;
    }
    return count;
  }

  /// How many devices of class [classId] its list shows, by the rule of
  /// [visibleDeviceCount]. Null until the index holds every device of the
  /// account: a count over part of them would be too low.
  int? visibleDeviceCountOfClass(String classId) {
    if (!_deviceIndexComplete) return null;
    final ids = _classDeviceIds[classId];
    // A listed class has a device of the user's type by definition: none in
    // the complete index means the type list is behind, which starts a fresh
    // type load (_reloadTypesWithoutDevices); 0 would be wrong meanwhile.
    if (ids == null || ids.isEmpty) return null;
    return visibleDeviceCount(ids);
  }

  /// Records the inactive attribute and the type of [devices] as just fetched
  /// or saved.
  void noteDevices(Iterable<DeviceInstance> devices) {
    var changed = false;
    var typesChanged = false;
    for (final d in devices) {
      _notedDuringSeed?.add(d.id);
      changed |= d.isInactive
          ? _inactiveDeviceIds.add(d.id)
          : _inactiveDeviceIds.remove(d.id);
      final previousType = _indexedDeviceTypes[d.id];
      if (previousType != d.device_type_id) {
        _indexedDeviceTypes[d.id] = d.device_type_id;
        typesChanged = true;
        // Class counts show only over a complete index.
        changed |= _deviceIndexComplete;
      }
    }
    if (typesChanged) _deviceIndexChanged();
    if (changed) notifyListeners();
  }

  /// Replaces the index with [all], every device of the account, so devices
  /// deleted since drop out of it. [complete] false empties it without
  /// claiming that the account has no devices.
  void replaceDeviceIndex(Iterable<DeviceInstance> all,
      {bool complete = true}) {
    _inactiveIndexEpoch++;
    final nextInactive = <String>{};
    final nextTypes = <String, String>{};
    for (final d in all) {
      if (d.isInactive) nextInactive.add(d.id);
      nextTypes[d.id] = d.device_type_id;
    }
    // A type no loaded one matches would keep its class off the list until
    // the next revalidation. Only once types are loaded: before that every
    // type is missing, and init is about to load them.
    if (_deviceTypesLoaded) unawaited(ensureDeviceTypes(nextTypes.values));
    if (complete == _deviceIndexComplete &&
        setEquals(nextInactive, _inactiveDeviceIds) &&
        mapEquals(nextTypes, _indexedDeviceTypes)) {
      return;
    }
    _deviceIndexComplete = complete;
    _inactiveDeviceIds
      ..clear()
      ..addAll(nextInactive);
    _indexedDeviceTypes
      ..clear()
      ..addAll(nextTypes);
    _deviceIndexChanged();
    notifyListeners();
  }

  @visibleForTesting
  Future<CachedDeviceIndex> Function() readCachedDeviceIndex =
      DevicesService.getCachedDeviceIndex;

  /// Seeds the index from the device cache, one local read for all rows.
  Future<void> loadDeviceIndex() async {
    final epoch = _inactiveIndexEpoch;
    final noted = _notedDuringSeed = {};
    final CachedDeviceIndex cached;
    try {
      cached = await readCachedDeviceIndex();
    } catch (e, s) {
      ErrorReporter.log('Could not read the device index from the cache', e, s);
      return;
    } finally {
      if (identical(_notedDuringSeed, noted)) _notedDuringSeed = null;
    }
    if (epoch != _inactiveIndexEpoch) return;
    var changed = false;
    for (final id in cached.inactive) {
      if (!noted.contains(id)) changed |= _inactiveDeviceIds.add(id);
    }
    for (final e in cached.deviceTypes.entries) {
      if (noted.contains(e.key) || _indexedDeviceTypes[e.key] == e.value) {
        continue;
      }
      changed = true;
      _indexedDeviceTypes[e.key] = e.value;
    }
    if (cached.complete && !_deviceIndexComplete) {
      _deviceIndexComplete = true;
      changed = true;
    }
    if (changed) {
      _deviceIndexChanged();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Devices
  // ---------------------------------------------------------------------------

  Future<void> searchDevices(
      DeviceSearchFilter filter, [
        bool force = false,
      ]) async {
    // An unchanged filter still searches after a failed load: repeating a
    // search is how a list retries.
    if (!force && !_devicesLoadFailed && _deviceSearchFilter == filter) return;
    _devicesGeneration++;
    _allDevicesLoaded = false;
    _devicesLoadFailed = false;
    notifyListeners();
    _deviceSearchFilter = filter;
    _deviceOffset = 0;
    await loadDevices(null, true);
  }

  Future<void> refreshDevices() =>
      searchDevices(_deviceSearchFilter, true);

  Future<void> loadDevices([
        int? offset,
        bool clear = false,
      ]) async {
    debugPrint("loadDevices");
    if (_allDevicesLoaded) return;
    if (_devicesLoadFailed && !clear) return;

    final generation = _devicesGeneration;
    final locked = _devicesMutex.isLocked;
    await _devicesMutex.acquire();
    // A next-page request joins the load in flight. A search (clear) waits for
    // it instead: that load is stale by now and discards its page below.
    if (locked && !clear) {
      _devicesMutex.release();
      return;
    }

    // Single release in a finally: loadingDevices is read straight off this
    // mutex, so any path out of here that skips the release leaves the list
    // spinning for the rest of the process.
    try {
      // A newer search queued behind this call runs its own load.
      if (generation != _devicesGeneration) return;
      if (_allDevicesLoaded || (offset != null && offset < devices.length)) {
        notifyListeners();
        return;
      }
      if (clear) devices.clear();

      await ensureInitialized();
      if (generation != _devicesGeneration) return;

      const limit = 50;
      late final DeviceInstanceWithTotal page;
      try {
        page = await DevicesService.getDevices(
          limit,
          _deviceOffset,
          _deviceSearchFilter,
          devices.isNotEmpty ? devices.last : null,
        );
      } catch (e, s) {
        if (generation != _devicesGeneration) return;
        _devicesLoadFailed = true;
        ErrorReporter.report('Could not load devices', e, s);
        notifyListeners();
        return;
      }
      if (generation != _devicesGeneration) return;
      final newDevices = page.devices;
      totalDevices = page.total;

      _devicesLoadedOnce = true;
      // Raw, unfiltered page size and offset: hiding happens below, on this
      // page's contents, and must not change whether pagination continues.
      _allDevicesLoaded = newDevices.length < limit;
      _deviceOffset += newDevices.length;

      // Favourites are never hidden, whatever the filter: the Favorites screen
      // shows the favourites among whatever search ran last.
      final visibleDevices = _deviceSearchFilter.showInactive
          ? newDevices
          : newDevices
              .where((d) => !d.isInactive || d.favorite)
              .toList(growable: false);

      if (visibleDevices.isNotEmpty) {
        for (final d in visibleDevices) {
          if (deviceTypes[d.device_type_id] != null) {
            d.prepareStates(deviceTypes[d.device_type_id]!);
          }
        }
        devices.addAll(visibleDevices);
      }
      // Notified even when the page filtered down to nothing: devices.length
      // may be unchanged, but rawDevicesFetched always moved.
      notifyListeners();

      if (visibleDevices.isNotEmpty) {
        // Started, not awaited - it suspends on its first await, so the
        // release below still happens right after the list is on screen.
        unawaited(_loadStatesInBackground(visibleDevices));
      }
    } finally {
      _devicePageLoads++;
      _devicesMutex.release();
    }
  }

  Future<void> _loadStatesInBackground(List<DeviceInstance> newDevices) async {
    // After the list is on screen, since it may fetch; devices whose type was
    // missing get their states only now.
    final typesReady = ensureDeviceTypes(newDevices.map((d) => d.device_type_id)).then((_) {
      for (final d in newDevices) {
        final type = deviceTypes[d.device_type_id];
        if (type != null) d.prepareStates(type);
      }
    });
    await _refreshConnectionStatuses(newDevices);
    await typesReady;
    try {
      await loadStates(newDevices, [], [
        dotenv.env['FUNCTION_GET_ON_OFF_STATE'] ?? '',
      ]);
    } catch (e, s) {
      ErrorReporter.report('Could not load device states', e, s);
    }
    // notifyListeners() is already called inside loadStates
  }

  /// Copies the connection state of [source] onto the matching entries of
  /// [target] and tells each one it changed.
  ///
  /// The notification is the point: the list listens per device, so a state
  /// written without it stays invisible until something else rebuilds the whole
  /// list - which is the slower states load right after, or nothing at all.
  @visibleForTesting
  static void applyConnectionStates(
      List<DeviceInstance> target, List<DeviceInstance> source) {
    for (final d in source) {
      final match = target.where((t) => t.id == d.id);
      if (match.isEmpty) continue;
      final device = match.first;
      if (device.connection_state == d.connection_state) continue;
      device.connection_state = d.connection_state;
      device.notifyStateChanged();
    }
  }

  Future<void> _refreshConnectionStatuses(List<DeviceInstance> newDevices) async {
    final futures = <Future>[
      MgwDeviceManager.updateDeviceConnectionStatusFromMgw(newDevices),
    ];
    final outsideLocalNet = newDevices
        .where((d) => d.network?.localGatewayHosts?.isNotEmpty != true)
        .map((d) => d.id)
        .toList(growable: false);

    if (outsideLocalNet.isNotEmpty) {
      final filter = DeviceSearchFilter('', deviceIds: outsideLocalNet);
      futures.add(
        DevicesService.getDevices(outsideLocalNet.length, 0, filter, null,
            forceBackend: true)
            .catchError((Object e, StackTrace s) async {
          if (!Settings.getLocalMode()) {
            ErrorReporter.report(
                'Error refreshing device status, using cache', e, s);
          }
          final cached = (await DevicesService.getDevices(
            outsideLocalNet.length, 0, filter, null,
            forceBackend: false,
          )).devices;
          for (final d in cached) {
            d.connection_state = DeviceConnectionStatus.unknown;
          }
          return DeviceInstanceWithTotal(cached, cached.length);
        }).then((ds) => applyConnectionStates(newDevices, ds.devices)),
      );
    }
    await Future.wait(futures);
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Future<void> loadStates(
      List<DeviceInstance> devices,
      List<DeviceGroup> groups, [
        List<String>? limitToFunctionIds,
      ]) async {
    final commandCallbacks = <CommandCallback>[];

    for (final device in devices) {
      final callbacks = device.getStateFillFunctions(limitToFunctionIds);
      if (device.connection_state == DeviceConnectionStatus.offline) {
        for (final cb in callbacks) {
          cb.callback(null);
        }
      } else {
        commandCallbacks.addAll(callbacks);
      }
    }
    for (final group in groups) {
      group.prepareStates();
      commandCallbacks.addAll(group.getStateFillFunctions(limitToFunctionIds));
    }

    if (commandCallbacks.isEmpty) {
      _notifyEntities(devices, groups);
      return;
    }

    List<DeviceCommandResponse> result;
    try {
      result = await DeviceCommandsService.runCommands(
        commandCallbacks.map((e) => e.command).toList(growable: false),
      );
    } catch (e, s) {
      // One catch: the two used to differ only in their message, and the one
      // on ApiUnavailableException never ran anyway - that exception only ever
      // arrives wrapped in a DioException.
      ErrorReporter.report('failed to loadStates', e, s);
      result = List.filled(commandCallbacks.length, DeviceCommandResponse(200, null));
    }

    assert(result.length == commandCallbacks.length);
    for (var i = 0; i < commandCallbacks.length; i++) {
      if (result[i].status_code == 200) {
        commandCallbacks[i].callback(result[i].message);
      } else {
        _logger.e('${result[i].status_code}: ${result[i].message}');
        commandCallbacks[i].callback(null);
      }
    }
    _notifyEntities(devices, groups);
  }

  /// Signals only the affected devices/groups (not the whole AppState) so their
  /// list items / detail pages rebuild without waking every other consumer.
  void _notifyEntities(List<DeviceInstance> devices, List<DeviceGroup> groups) {
    for (final d in devices) {
      d.notifyStateChanged();
    }
    for (final g in groups) {
      g.notifyStateChanged();
    }
  }

  // ---------------------------------------------------------------------------
  // Device groups
  // ---------------------------------------------------------------------------

  /// The account epoch the last load started under. A call made after an
  /// account change that waited for a load of the previous account fetches
  /// itself, since that load discarded its result.
  int? _deviceGroupsLoadEpoch;

  Future<void> loadDeviceGroups() async {
    final epoch = AccountEpoch.current;
    final locked = _deviceGroupsMutex.isLocked;
    await _deviceGroupsMutex.acquire();
    // A call from before an account change loads nothing, and a call joins
    // only a load of its own account.
    if (epoch != AccountEpoch.current ||
        (locked && _deviceGroupsLoadEpoch == epoch)) {
      _deviceGroupsMutex.release();
      return;
    }
    _deviceGroupsLoadEpoch = epoch;
    // Single release in the finally: loadingDeviceGroups() is read off the
    // mutex, so a path out that skips it leaves the list spinning for good.
    try {
      deviceGroups.clear();
      notifyListeners();
      try {
        final fetched =
            await Future.wait(await DeviceGroupsService.getDeviceGroups());
        // A load that outlived its account leaves the next one's list alone.
        if (epoch != AccountEpoch.current) return;
        deviceGroups.addAll(fetched);
      } catch (e, s) {
        if (epoch != AccountEpoch.current) {
          ErrorReporter.log('Could not load device groups', e, s);
          return;
        }
        ErrorReporter.report('Could not load device groups', e, s);
      }
      _deviceGroupsLoadedOnce = true;
    } finally {
      _deviceGroupsMutex.release();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  void clearDeviceData() {
    _devicesGeneration++;
    _inactiveIndexEpoch++;
    _inactiveDeviceIds.clear();
    _indexedDeviceTypes.clear();
    _deviceIndexComplete = false;
    _classDeviceIdsCache = null;
    _notedDuringSeed = null;
    _devicePageLoads++;
    _devicesLoadFailed = false;
    deviceClasses.clear();
    deviceTypes.clear();
    _deviceTypesLoaded = false;
    _deviceTypesAreAll = false;
    forgetUnavailableDeviceTypes();
    _deviceSearchFilter = DeviceSearchFilter.empty();
    totalDevices = 0;
    devices.clear();
    _allDevicesLoaded = false;
    _devicesLoadedOnce = false;
    _deviceOffset = 0;
    deviceGroups.clear();
    _deviceGroupsLoadedOnce = false;
  }
}