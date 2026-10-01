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
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_cache_hive_store/http_cache_hive_store.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/notification.dart';
import 'package:mobile_app/services/aspects.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/characteristics.dart';
import 'package:mobile_app/services/concepts.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/favorites_migration.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/metadata_cache.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/locations.dart';

class CacheHelper {
  static String bodyCacheIDBuilder(RequestOptions request) {
    List<int> bytes = utf8.encode(request.method + request.uri.toString());
    if (request.data != null) {
      bytes = [...bytes, ...utf8.encode(request.data)];
    }
    return sha1.convert(bytes).toString();
  }

  static String newCacheKeyBuilder({
    required Uri url,
    Map<String, String>? headers,
    Object? body,
  }) {
    List<int> bytes = utf8.encode(url.toString());
    if (body != null) {
      bytes = [...bytes, ...utf8.encode(body.toString())];
    }
    return sha1.convert(bytes).toString();
  }

  static Future<String?> getCacheFile({String customSuffix = ""}) async {
    final dir = await getCacheDir();
    if (dir == null) {
      return null;
    }
    return "${dir.path}/cache$customSuffix.box";
  }

  static Future<Directory?> getCacheDir() async {
    if (Platform.isAndroid) {
      List<Directory>? cacheDirs = await getExternalCacheDirectories();
      if (cacheDirs != null && cacheDirs.isNotEmpty) {
        return cacheDirs[0];
      }
    }

    return await getApplicationDocumentsDirectory();
  }

  /// [keepMetadata] spares the metadata byte cache, for a caller that fetches
  /// it fresh right after and needs the stored copies if that fails.
  static Future<void> clearCache({bool keepMetadata = false}) async {
    final cacheFile = (await getCacheFile());
    await HiveCacheStore(cacheFile).clean();
    // The metadata byte cache lives in Isar, not Hive — without this the
    // metadata services keep serving their cached bytes.
    if (!keepMetadata) await MetadataCache.clear();
    // Deliberately NOT cleared here: the Isar entity collections. They leak
    // the previous account's devices to the next account until the next
    // refresh, but wiping them here kills the offline cache on any transient
    // NotLoggedIn auth event, and three services read the emptied collections
    // as authoritative. The account-switch leak needs a clear-on-account-change
    // at login instead. Favorites no longer stand in the way: they live in
    // their own per-account list (Settings.getFavoriteDeviceIds), not on these
    // rows.
  }

  /// Switches the app to [account]: records the wipe as pending, moves the
  /// epoch, writes the new account key, resets the state in memory as a
  /// logout does and wipes what the previous account left on disk, including
  /// the entity collections that [clearCache] deliberately spares. Each step
  /// runs even when one before it failed; failures are logged.
  ///
  /// Only called when a different account has actually been observed signing
  /// in (see Auth), never on logout and never on a transient NotLoggedIn: those
  /// are the cases where the cache is the offline copy the user still needs.
  static Future<void> switchAccount(String account) async {
    // First: what does not complete runs at the next sign-in or start, also
    // after a kill before the reset below queues the token deletion.
    await _logged(() => Settings.setAccountWipePending(true));
    await _logged(() => Settings.setFcmTokenDeletionPending(true));
    // The key right after the epoch, with no await between: everything that
    // reads it, and the tabs that remount on the epoch, see the new account.
    AccountEpoch.advance();
    await _logged(() => Settings.setAccount(account));
    afterAccountKeyForTest?.call();
    await AppState().onLogout();
    AppState().notifyListeners();
    await _logged(_wipeAccountData);
  }

  /// Retries the wipe of a switch that did not complete. Leaves the session
  /// alone: what it drops of the signed-in account the next refresh refills,
  /// and a refresh running across it stays due.
  static Future<void> retryPendingAccountWipe() async {
    if (!Settings.getAccountWipePending()) return;
    await _logged(_wipeAccountData);
  }

  static Future<void> _logged(Future<void> Function() step) async {
    try {
      await step();
    } catch (e, s) {
      ErrorReporter.log('Account switch step failed', e, s);
    }
  }

  /// Each part runs whatever the others do; the flag is cleared only when all
  /// of them succeeded.
  static Future<void> _wipeAccountData() async {
    var complete = true;
    Future<void> part(Future<void> Function() step) async {
      try {
        await step();
      } catch (e, s) {
        complete = false;
        ErrorReporter.log('Account switch wipe failed', e, s);
      }
    }

    await part(() async {
      beforeAccountWipeForTest?.call();
      await clearCache();
    });
    if (isar != null) {
      await part(() => isar!.writeTxn(() async {
            // Inside the transaction: a refresh writing or checking after it
            // sees it.
            _entityWipes++;
            await isar!.deviceInstances.clear();
            await isar!.deviceGroups.clear();
            await isar!.networks.clear();
            await isar!.locations.clear();
            // The offline fallback of the notification list reads these, so
            // the next account would be shown the previous one's.
            await isar!.notifications.clear();
          }));
    }
    // After the rows, so a refresh that marked itself before they went is
    // due again. Without it the emptied cache counts as refreshed today and
    // the next refill waits up to a day - three services read their (now
    // empty) collection as the answer rather than as a cache miss.
    await part(Settings.clearCacheUpdated);
    if (complete) await part(() => Settings.setAccountWipePending(false));
  }

  /// Called before the cache clear of an account change's wipe; throwing from
  /// it fails that part.
  @visibleForTesting
  static void Function()? beforeAccountWipeForTest;

  /// Called right after a switch has written the new account key.
  @visibleForTesting
  static void Function()? afterAccountKeyForTest;

  /// Bumped by the wipe of the entity rows. A refresh that saw it move writes
  /// nothing more and does not mark its collection refreshed, so it stays due.
  static int _entityWipes = 0;

  static bool _current(int epoch, int wipes) =>
      epoch == AccountEpoch.current && wipes == _entityWipes;

  /// [AccountEpoch.writeIfCurrent], also skipped after a wipe; checked inside
  /// the transaction, so a wipe queued after it always runs after the check.
  static Future<bool> _writeIfCurrent(
      int epoch, int wipes, Future<void> Function() write) async {
    var written = false;
    await AccountEpoch.writeIfCurrent(isar!, epoch, () async {
      if (wipes != _entityWipes) return;
      await write();
      written = true;
    });
    return written;
  }

  /// [onProgress] reports the fraction of completed refresh tasks (0..1),
  /// one step per finished endpoint.
  ///
  /// [includeMetadata] warms the metadata caches alongside the Isar
  /// collections. A caller that reloads the in-memory metadata right after
  /// (settings refresh via [AppState.reloadMetadata]) passes false — the
  /// reload fetches fresh itself, and including the getters here would fetch
  /// and parse everything twice.
  ///
  /// Returns false when one of the Isar collections could not be refreshed;
  /// those parts report their own error and keep the old rows. A failing
  /// metadata getter still throws.
  static Future<bool> refreshCache({
    bool includeMetadata = true,
    void Function(double progress)? onProgress,
  }) async {
    if (isar == null) {
      return true;
    }
    final collections = <Future<bool>>[
      _tracked(_devices, () => _refreshDevicesShared(quiet: false)),
      _tracked(_deviceGroups, () => _refreshDeviceGroups(quiet: false)),
      _tracked(_networks, () => _refreshNetworks(quiet: false)),
      _tracked(_locations, () => _refreshLocations(quiet: false)),
    ];
    final tasks = <Future>[
      ...collections,
      if (includeMetadata) ...[
        // maxAge zero, or these serve the byte cache straight back and refresh
        // nothing - anything younger than the default counts as current, so
        // "include the metadata" was warming a cache that was already warm.
        // Skipping the cache rather than clearing it keeps the stored copy if
        // the fetch fails. A cold start with a stored session never reaches
        // this method; AppState.init serves the stored metadata there and
        // revalidates what is older than maxAge after the first frame.
        FunctionsService.getFunctions(maxAge: Duration.zero),
        AspectsService.getAspects(maxAge: Duration.zero),
        ConceptsService.getConcepts(maxAge: Duration.zero),
        CharacteristicsService.getCharacteristics(maxAge: Duration.zero),
        DeviceTypesService.getDeviceTypes(null, Duration.zero),
        DeviceClassesService.getDeviceClasses(maxAge: Duration.zero),
      ],
    ];
    var done = 0;
    await Future.wait(tasks.map((t) => t.whenComplete(() {
          done++;
          onProgress?.call(done / tasks.length);
        })));
    return !(await Future.wait(collections)).contains(false);
  }

  /// How long a refreshed entity collection counts as current.
  static const entityMaxAge = Duration(days: 1);

  /// Whether a full device refresh has completed for this account, so the
  /// device rows in Isar are all of its devices rather than pages seen.
  static bool devicesRefreshedOnce() =>
      Settings.getCacheUpdated(_devices) != null;

  static const _devices = "devices";
  static const _deviceGroups = "deviceGroups";
  static const _networks = "networks";
  static const _locations = "locations";

  /// Refreshes running per collection, from any path. A count rather than a
  /// flag, because the explicit refreshes may overlap each other.
  static final Map<String, int> _refreshesRunning = {};

  /// [quiet] refreshes run in the background over rows already on screen, so
  /// their failure is logged only; so is one whose account is gone.
  static void _refreshFailed(
      String message, Object e, StackTrace s, bool quiet, int epoch) {
    if (quiet || epoch != AccountEpoch.current) {
      ErrorReporter.log(message, e, s);
    } else {
      ErrorReporter.report(message, e, s);
    }
  }

  static Future<bool> _tracked(
      String cache, Future<bool> Function() refresh) async {
    _refreshesRunning[cache] = (_refreshesRunning[cache] ?? 0) + 1;
    try {
      return await refresh();
    } finally {
      final left = _refreshesRunning[cache]! - 1;
      if (left == 0) {
        _refreshesRunning.remove(cache);
      } else {
        _refreshesRunning[cache] = left;
      }
    }
  }

  /// Whether a collection refreshed at [refreshedAt] needs a refresh now: never
  /// refreshed, at least [entityMaxAge] ago, or at a time in the future.
  @visibleForTesting
  static bool entityRefreshDue(DateTime? refreshedAt, DateTime now) {
    if (refreshedAt == null) return true;
    final age = now.difference(refreshedAt);
    return age >= entityMaxAge || age.isNegative;
  }

  /// Starts a refresh of every collection that is due and not already being
  /// refreshed, and completes when those have ended. Arms no timer, since one
  /// does not survive the app being killed; start and resume call this instead.
  static Future<void> scheduleCacheUpdates() async {
    if (isar == null || !Auth().loggedIn || Settings.getLocalMode()) {
      return;
    }
    // Before any refresh: until this has run, the cached rows are the only
    // record of the existing favorites, and a refresh replaces them.
    try {
      await FavoritesMigration.run();
    } catch (e, s) {
      ErrorReporter.log('Moving favorites off the cache failed', e, s);
    }
    // No await from here to the last start, so a second call cannot slip
    // between the running check and the start.
    final now = DateTime.now();
    final started = <Future<bool>>[
      for (final (cache, refreshedAt, refresh) in [
        (_devices, Settings.getCacheUpdated(_devices), _refreshDevicesShared),
        (_deviceGroups, deviceGroupsRefreshedAt(), _refreshDeviceGroups),
        (_networks, Settings.getCacheUpdated(_networks), _refreshNetworks),
        (_locations, Settings.getCacheUpdated(_locations), _refreshLocations),
      ])
        if (!_refreshesRunning.containsKey(cache) &&
            entityRefreshDue(refreshedAt, now))
          _tracked(cache, () => refresh(quiet: true))
              .catchError((Object e, StackTrace s) {
            ErrorReporter.log('Could not refresh cache', e, s);
            return false;
          }),
    ];
    await Future.wait(started);
  }

  /// Called after each chunk the device refresh has written, so a test can
  /// change the account between two chunks; the refresh waits for what it
  /// returns.
  @visibleForTesting
  static FutureOr<void> Function()? afterDeviceChunkForTest;

  /// Called right after the device refresh has pruned the rows it did not
  /// fetch, before it marks the collection refreshed; the refresh waits for
  /// what it returns.
  @visibleForTesting
  static FutureOr<void> Function()? afterDevicePruneForTest;

  static _DeviceRefreshRun? _deviceRun;

  /// Joins the device refresh running under the current account instead of
  /// starting a second one, whose prune could drop rows the other fetched. A
  /// caller that reports gets the failure of a quiet run it joined reported.
  static Future<bool> _refreshDevicesShared({required bool quiet}) async {
    final joined = _deviceRun;
    if (joined != null && joined.epoch == AccountEpoch.current) {
      final ok = await joined.done;
      final failure = joined.failure;
      if (!ok && !quiet && joined.quiet && failure != null) {
        _refreshFailed(failure.message, failure.error, failure.stack, false,
            joined.epoch);
      }
      return ok;
    }
    final run = _DeviceRefreshRun(quiet, AccountEpoch.current);
    _deviceRun = run;
    run.done = _refreshDevices(quiet: quiet, run: run).whenComplete(() {
      if (identical(_deviceRun, run)) _deviceRun = null;
    });
    return run.done;
  }

  static Future<bool> _refreshDevices(
      {required bool quiet, _DeviceRefreshRun? run}) async {
    final epoch = AccountEpoch.current;
    final wipes = _entityWipes;
    var allDevicesLoaded = false;
    const limit = 5000;
    var deviceOffset = 0;
    DeviceInstance? last;
    final List<DeviceInstance> newDevices = [];

    while (!allDevicesLoaded) {
      final List<DeviceInstance> page;
      try {
        // Stored below in chunks, and indexed by replaceDeviceIndex once
        // complete; the service's own write-through would store it twice.
        page = (await DevicesService.getDevices(
            limit, deviceOffset, DeviceSearchFilter(""), last,
            forceBackend: true, store: false)).devices;
      } catch (e, s) {
        run?.failure = (message: "Could not get devices", error: e, stack: s);
        _refreshFailed("Could not get devices", e, s, quiet, epoch);
        return false;
      }
      newDevices.addAll(page);
      // The page, not the total: from [limit] devices on the total never
      // drops below it again.
      allDevicesLoaded = page.length < limit;
      deviceOffset = newDevices.length;
      last = newDevices.isNotEmpty ? newDevices.last : null;
    }

    if (isar != null) {
      // Write in chunks: serializing thousands of devices for Isar happens on
      // the calling (UI) isolate, so doing it in one putAll blocks frames right
      // after login. Upserted over the old rows and pruned only at the end, so
      // a refresh dropped half-way leaves the old rows plus the new ones, never
      // an empty or partial collection.
      const chunkSize = 500;
      for (var i = 0; i < newDevices.length; i += chunkSize) {
        final end = i + chunkSize < newDevices.length
            ? i + chunkSize
            : newDevices.length;
        final chunk = newDevices.sublist(i, end);
        if (!await _writeIfCurrent(epoch, wipes, () async {
          // The flags from fetch time are seconds old by now.
          await DevicesService.applyFavoriteMirror(chunk);
          await isar!.deviceInstances.putAll(chunk);
        })) {
          return false;
        }
        final afterChunk = afterDeviceChunkForTest;
        if (afterChunk != null) await afterChunk();
      }
      final fetched = {for (final d in newDevices) d.isarId};
      if (!await _writeIfCurrent(epoch, wipes, () async {
        final stored =
            await isar!.deviceInstances.where().isarIdProperty().findAll();
        await isar!.deviceInstances
            .deleteAll(stored.where((id) => !fetched.contains(id)).toList());
      })) {
        return false;
      }
      final afterPrune = afterDevicePruneForTest;
      if (afterPrune != null) await afterPrune();
    }
    if (!_current(epoch, wipes)) return false;
    AppState().replaceDeviceIndex(newDevices);

    await Settings.setCacheUpdated(_devices);
    return true;
  }

  static Future<bool> _refreshDeviceGroups({required bool quiet}) async {
    final epoch = AccountEpoch.current;
    final wipes = _entityWipes;
    late final List<DeviceGroup> deviceGroups;
    try {
      deviceGroups = await Future.wait(
          await DeviceGroupsService.getDeviceGroups(forceBackend: true));
    } catch (e, s) {
      _refreshFailed("Could not get deviceGroups", e, s, quiet, epoch);
      return false;
    }

    if (isar != null &&
        !await _writeIfCurrent(epoch, wipes, () async {
          // The images loaded meanwhile; a favorite tapped during that must
          // not be overwritten by the mirror the groups were loaded with.
          await DeviceGroupsService.applyFavoriteMirror(deviceGroups);
          await isar!.deviceGroups.clear();
          await isar!.deviceGroups.putAll(deviceGroups);
        })) {
      return false;
    }
    if (!_current(epoch, wipes)) return false;
    // Before any further await, so a load in between does not flag fresh rows.
    if (!Settings.getDeviceGroupsCachedWithAspectLists()) {
      unawaited(Settings.setDeviceGroupsCachedWithAspectLists(true).then((_) {}, onError: (Object e, StackTrace s) {
        ErrorReporter.log("Could not mark the device group cache as current", e, s);
      }));
    }

    await Settings.setCacheUpdated(_deviceGroups);
    return true;
  }

  /// Runs the device refresh as an explicit one: failures are reported, and
  /// it counts as running for [scheduleCacheUpdates].
  static Future<bool> refreshDevicesNow() =>
      _tracked(_devices, () => _refreshDevicesShared(quiet: false));

  /// Runs the device refresh as the background one does, quietly.
  @visibleForTesting
  static Future<bool> refreshDevicesInBackgroundForTest() =>
      _tracked(_devices, () => _refreshDevicesShared(quiet: true));

  @visibleForTesting
  static Future<bool> refreshDeviceGroupsNow() =>
      _tracked(_deviceGroups, () => _refreshDeviceGroups(quiet: false));

  /// When the device group cache was last refreshed, for [scheduleCacheUpdates].
  /// Rows cached before aspect lists count as never refreshed, so the first
  /// start after the upgrade refetches them.
  static DateTime? deviceGroupsRefreshedAt() =>
      Settings.getDeviceGroupsCachedWithAspectLists() ? Settings.getCacheUpdated(_deviceGroups) : null;

  static Future<bool> _refreshNetworks({required bool quiet}) async {
    if (isar == null) {
      return true;
    }
    final epoch = AccountEpoch.current;
    final wipes = _entityWipes;
    late final List<Network> networks;

    try {
      networks = await NetworksService.getNetworks(null, true);
    } catch (e, s) {
      _refreshFailed("Could not get networks", e, s, quiet, epoch);
      return false;
    }

    if (isar != null &&
        !await _writeIfCurrent(epoch, wipes, () async {
          await isar!.networks.clear();
          await isar!.networks.putAll(networks);
        })) {
      return false;
    }
    if (!_current(epoch, wipes)) return false;

    await Settings.setCacheUpdated(_networks);
    return true;
  }

  static Future<bool> _refreshLocations({required bool quiet}) async {
    if (isar == null) {
      return true;
    }
    final epoch = AccountEpoch.current;
    final wipes = _entityWipes;
    late final List<Location> locations;

    try {
      locations = await Future.wait(
          await LocationService.getLocations(forceBackend: true));
    } catch (e, s) {
      _refreshFailed("Could not get locations", e, s, quiet, epoch);
      return false;
    }

    if (isar != null &&
        !await _writeIfCurrent(epoch, wipes, () async {
          await isar!.locations.clear();
          await isar!.locations.putAll(locations);
        })) {
      return false;
    }
    if (!_current(epoch, wipes)) return false;

    await Settings.setCacheUpdated(_locations);
    return true;
  }
}

/// A device refresh in flight, for callers that join it.
class _DeviceRefreshRun {
  _DeviceRefreshRun(this.quiet, this.epoch);

  final bool quiet;
  final int epoch;
  late final Future<bool> done;
  ({String message, Object error, StackTrace stack})? failure;
}
