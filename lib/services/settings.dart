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

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive/hive.dart';
import 'package:mobile_app/exceptions/settings_exception.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/models/sensor_tab.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/value_change_style.dart';
import 'package:path_provider/path_provider.dart';

class Settings {
  static bool isInitialized = false;

  static const _boxName = "settings.box";
  static Box<String>? _box;

  /// The marks that describe the content of the Android secure storage's
  /// file. In a box of their own, which the manifest's backup rules leave out
  /// like that file: restored without it, they would describe a file that is
  /// not there.
  static const _secureStorageMarksBoxName = "secure_storage_marks.box";
  static Box<String>? _marks;

  static const _themeKey = "theme";
  static const _defaultTheme = "";
  static String _currentThemeValue = "";

  static const _themeColorKey = "theme_color";
  static const _defaultThemeColor = "";
  static String _currentThemeColorValue = "";

  static const _displayedFractionDigitsKey = "displayed_fraction_digits";
  static const _defaultDisplayedFractionDigits = 2;
  static int _currentDisplayedFractionDigits = 0;

  // Per account under the prefix; the unkeyed keys are what an earlier
  // version stored for everyone, moved to the first account that reads them.
  static const _smartServiceDashboardsKeyPrefix = "smart_service_dashboards_";
  static const _legacySmartServiceDashboardsKey = "smart_service_dashboards";

  // Superseded by the sensor tabs; moved like the unkeyed tabs.
  static const _pinnedSensorsKey = "pinned_sensors";

  static const _sensorTabsKeyPrefix = "sensor_tabs_";
  static const _legacySensorTabsKey = "sensor_tabs";

  static const _initialTabKey = "initial_tab";

  static const _valueChangeStyleKey = "value_change_style";

  static const _hapticFeedBackEnabledKey = "haptic_feedback_enabled";

  static const _functionPreferredCharacteristicKeyPrefix = "functionPreferredCharacteristic_";

  static const _cacheUpdatedAtPrefix = "cacheUpdated_";

  static const _keycloakUrlKey = "keycloak_url";
  static const _keycloakRedirectKey = "keycloak_redirect";
  static const _apiUrlKey = "api_url";

  static const _localModeKey = "local_mode";

  static const _filterModeKey = "filter_mode";

  static const _preReleaseModeKey = "preRelease_mode";

  static const _accountKey = "account";

  static const _favoriteDevicesKeyPrefix = "favorite_devices_";
  static const _favoriteGroupsKeyPrefix = "favorite_groups_";

  static const _favoritesMovedKey = "favorites_moved_off_cache";

  static const _deviceGroupsCachedWithAspectListsKey = "device_groups_cached_with_aspect_lists";

  static const _accountWipePendingKey = "account_wipe_pending";
  static const _fcmTokenDeletionPendingKey = "fcm_token_deletion_pending";

  static const _credentialsStoredKey = "auth_credentials_stored";
  static const _signedOutKey = "auth_signed_out";

  static const _secureStorageCheckStoredKey = "secure_storage_check_stored";
  static const _secureStorageCheckFailuresKey = "secure_storage_check_failures";
  static const _secureStorageResetPendingKey = "secure_storage_reset_pending";

  static const _secureStorageMarkKeys = [
    _credentialsStoredKey,
    _secureStorageCheckStoredKey,
    _secureStorageCheckFailuresKey,
    _secureStorageResetPendingKey,
  ];

  static checkInit() {
    if (!isInitialized) {
      throw SettingsNotInitializedException();
    }
  }

  static init() async {
    if (!isInitialized) {
      Hive.init((await getApplicationDocumentsDirectory()).path);
      _box = await Hive.openBox<String>(_boxName);
      _marks = await Hive.openBox<String>(_secureStorageMarksBoxName);

      _setDefaults();

      isInitialized = true;
    }
  }

  static _setDefaults() {
    _currentThemeValue = _hiveGetWithDefault(_themeKey, _defaultTheme);
    _currentThemeColorValue = _hiveGetWithDefault(_themeColorKey, _defaultThemeColor);
    _currentDisplayedFractionDigits = _hiveGetIntWithDefault(_displayedFractionDigitsKey, _defaultDisplayedFractionDigits);
  }

  static clear() async {
    checkInit();
    await _box?.clear();
    await _marks?.clear();
    _setDefaults();
  }

  static close() async {
    if (isInitialized) {
      await _box?.close();
      _box = null;
      await _marks?.close();
      _marks = null;
      _currentThemeValue = "";
      _currentThemeColorValue = "";
      _currentDisplayedFractionDigits = 0;
      isInitialized = false;
    }
  }

  static String _hiveGetWithDefault(String key, String defaultValue) {
    String? result = _box?.get(key, defaultValue: defaultValue);
    if (result == null) {
      return defaultValue;
    }
    return result;
  }

  static int _hiveGetIntWithDefault(String key, int defaultValue) {
    String? resultStr = _box?.get(key);
    if (resultStr == null) {
      return defaultValue;
    }
    int? result = int.tryParse(resultStr);
    if (result == null) {
      return defaultValue;
    }
    return result;
  }

  static String getDefaultTheme() {
    return _defaultTheme;
  }

  static String getTheme() {
    checkInit();
    return _currentThemeValue;
  }

  static setTheme(String theme) async {
    checkInit();
    _currentThemeValue = theme;
    await _box?.put(_themeKey, theme).then((value) => _box?.flush());
  }

  static resetTheme() async {
    checkInit();
    _currentThemeValue = _defaultTheme;
    await _box?.delete(_themeKey).then((value) => _box?.flush());
  }

  static String getDefaultThemeColor() {
    return _defaultThemeColor;
  }

  static String getThemeColor() {
    checkInit();
    return _currentThemeColorValue;
  }

  static setThemeColor(String color) async {
    checkInit();
    _currentThemeColorValue = color;
    await _box?.put(_themeColorKey, color).then((value) => _box?.flush());
  }

  static resetThemeColor() async {
    checkInit();
    _currentThemeColorValue = _defaultThemeColor;
    await _box?.delete(_themeColorKey).then((value) => _box?.flush());
  }

  static int getDefaultDisplayedFractionDigits() {
    return _defaultDisplayedFractionDigits;
  }

  static int getDisplayedFractionDigits() {
    checkInit();
    return _currentDisplayedFractionDigits;
  }

  static setDisplayedFractionDigits(int value) async {
    checkInit();
    _currentDisplayedFractionDigits = value;
    await _box?.put(_displayedFractionDigitsKey, value.toString()).then((v) => _box?.flush());
  }

  /// The dashboards of the signed-in account; empty without one.
  static List<SmartServiceDashboard> getSmartServiceDashboards() {
    checkInit();
    final str = _accountValue(
        _smartServiceDashboardsKeyPrefix, _legacyDashboards);
    if (str == null) return [];
    final List<dynamic> l = json.decode(str);
    return List<SmartServiceDashboard>.generate(l.length, (index) => SmartServiceDashboard.fromJson(l[index]));
  }

  /// A no-op without an account, like the favorites.
  static setSmartServiceDashboards(List<SmartServiceDashboard> dashboards) async {
    checkInit();
    await _setAccountValue(_smartServiceDashboardsKeyPrefix, _legacyDashboards,
        json.encode(dashboards));
  }

  /// The user-defined tabs of the sensors page of the signed-in account, each
  /// with its own pinned values, in display order; empty without an account.
  ///
  /// Migrates the earlier flat `pinned_sensors` list into a single default tab.
  static List<SensorTab> getSensorTabs() {
    checkInit();
    final str = _accountValue(_sensorTabsKeyPrefix, _legacySensorTabs);
    if (str == null) return [];
    try {
      final List<dynamic> l = json.decode(str);
      return List<SensorTab>.generate(
          l.length, (i) => SensorTab.fromJson(l[i] as Map<String, dynamic>));
    } catch (_) {
      return []; // ignore an unreadable/outdated entry rather than breaking the page
    }
  }

  /// A no-op without an account, like the favorites.
  static Future<void> setSensorTabs(List<SensorTab> tabs) async {
    checkInit();
    await _setAccountValue(
        _sensorTabsKeyPrefix, _legacySensorTabs, json.encode(tabs));
  }

  /// The unkeyed sensor tabs first; without them the pre-tabs pins.
  static final Map<String, String? Function(String)> _legacySensorTabs = {
    _legacySensorTabsKey: (v) => v,
    _pinnedSensorsKey: _migratePinnedSensors,
  };

  static final Map<String, String? Function(String)> _legacyDashboards = {
    _legacySmartServiceDashboardsKey: (v) => v,
  };

  /// Reads the pre-tabs `pinned_sensors` list as one "Sensors" tab, encoded
  /// like the tabs; null when it holds none.
  static String? _migratePinnedSensors(String str) {
    try {
      final List<dynamic> l = json.decode(str);
      if (l.isEmpty) return null;
      final pins = List<SensorPin>.generate(
          l.length, (i) => SensorPin.fromJson(l[i] as Map<String, dynamic>));
      return json.encode([
        SensorTab(id: 'migrated', name: 'Sensors', pins: pins),
      ]);
    } catch (_) {
      return null;
    }
  }

  /// Moves the unkeyed sensor tabs and dashboards to the signed-in account.
  /// Called by an account switch before the new key is written: the values
  /// belong to the account that was signed in when they were stored.
  static Future<void> moveLegacyAccountSettings() async {
    checkInit();
    await _resolveAccountValue(_sensorTabsKeyPrefix, _legacySensorTabs).move;
    await _resolveAccountValue(
            _smartServiceDashboardsKeyPrefix, _legacyDashboards)
        .move;
  }

  /// The value under [prefix] for the signed-in account, null without one.
  static String? _accountValue(
      String prefix, Map<String, String? Function(String)> legacy) {
    final resolved = _resolveAccountValue(prefix, legacy);
    resolved.move?.catchError((Object e, StackTrace s) =>
        ErrorReporter.log('Could not move a setting to the account', e, s));
    return resolved.value;
  }

  /// Without a value of its own, the account takes over what the first present
  /// key of [legacy] holds, converted; [move] then stores it under the account
  /// and deletes every legacy key, so no later account inherits it. Hive shows
  /// the new value at once, before [move] completes.
  static ({String? value, Future<void>? move}) _resolveAccountValue(
      String prefix, Map<String, String? Function(String)> legacy) {
    final account = getAccount();
    if (account == null) return (value: null, move: null);
    final key = prefix + account;
    final own = _box!.get(key);
    final present = legacy.keys.where(_box!.containsKey).toList();
    if (present.isEmpty) return (value: own, move: null);
    if (own != null) return (value: own, move: _moveLegacy(null, null, present));
    final taken = legacy[present.first]!(_box!.get(present.first)!);
    return (value: taken, move: _moveLegacy(key, taken, present));
  }

  /// The delete waits for the write, so a failed write loses nothing.
  static Future<void> _moveLegacy(
      String? key, String? value, List<String> legacyKeys) async {
    if (key != null && value != null) await _box!.put(key, value);
    await _box!.deleteAll(legacyKeys);
    await _box!.flush();
  }

  static Future<void> _setAccountValue(String prefix,
      Map<String, String? Function(String)> legacy, String value) async {
    final account = getAccount();
    if (account == null) return;
    // Takes over the legacy value first, or a later account would inherit it.
    await _resolveAccountValue(prefix, legacy).move;
    await _box?.put(prefix + account, value).then((v) => _box?.flush());
  }

  /// The tab (or, for a Locations/Groups/Networks/Classes value, the Devices
  /// segment) opened when the app starts. Defaults to Favorites (tab 0).
  static int getInitialTab() {
    checkInit();
    return int.tryParse(_box!.get(_initialTabKey) ?? '') ?? 0;
  }

  static Future<void> setInitialTab(int index) async {
    checkInit();
    await _box?.put(_initialTabKey, index.toString()).then((v) => _box?.flush());
  }

  /// How a reading marks a new value; [ValueChangeStyle.flash] until chosen.
  static ValueChangeStyle getValueChangeStyle() {
    checkInit();
    return ValueChangeStyle.parse(_box!.get(_valueChangeStyleKey));
  }

  static Future<void> setValueChangeStyle(ValueChangeStyle style) async {
    checkInit();
    await _box?.put(_valueChangeStyleKey, style.name).then((v) => _box?.flush());
  }

  static bool getHapticFeedBackEnabled() {
    checkInit();
    return _box!.get(_hapticFeedBackEnabledKey, defaultValue: "true") == "true";
  }

  static Future<void> setHapticFeedBackEnabled(bool value) {
    checkInit();
    return _box!.put(_hapticFeedBackEnabledKey, value.toString());
  }

  static String? getFunctionPreferredCharacteristicId(String functionId) {
    checkInit();
    return _box!.get(_functionPreferredCharacteristicKeyPrefix + functionId);
  }

  static Future<void> setFunctionPreferredCharacteristicId(String functionId, String? characteristicId) async {
    checkInit();
    if (characteristicId != null) {
      return await _box!.put(_functionPreferredCharacteristicKeyPrefix + functionId, characteristicId).then((value) => _box?.flush());
    } else {
      return await _box!.delete(_functionPreferredCharacteristicKeyPrefix + functionId).then((value) => _box?.flush());
    }
  }

  static Future<void> deleteAllFunctionPreferredCharacteristicIds() async {
    checkInit();
    final futures = _box!.keys.where((e) => (e as String).startsWith(_functionPreferredCharacteristicKeyPrefix)).map((e) => _box!.delete(e));
    return await Future.wait(futures).then((value) => _box?.flush());
  }

  static Future<void> setCacheUpdated(String cache) {
    checkInit();
    return _box!.put(_cacheUpdatedAtPrefix + cache, DateTime.now().millisecondsSinceEpoch.toString());
  }

  static DateTime? getCacheUpdated(String cache) {
    // return DateTime.fromMillisecondsSinceEpoch(0); // TODO debug ONLY
    checkInit();
    final ms = _box!.get(_cacheUpdatedAtPrefix + cache);
    if (ms == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(int.parse(ms));
  }

  /// Forgets when each cache was last refreshed, so the next
  /// [CacheHelper.scheduleCacheUpdates] refills immediately instead of treating
  /// an emptied cache as up to a day fresh.
  static Future<void> clearCacheUpdated() async {
    checkInit();
    final keys = _box!.keys
        .where((e) => (e as String).startsWith(_cacheUpdatedAtPrefix))
        .toList();
    await Future.wait(keys.map((e) => _box!.delete(e)));
    await _box?.flush();
  }

  static String? getKeycloakUrl() {
    checkInit();
    return _box!.get(_keycloakUrlKey) ?? dotenv.env["KEYCLOAK_URL"];
  }

  static Future<void> setKeycloakUrl(String? value) {
    checkInit();
    if (value == null) {
      return _box!.delete(_keycloakUrlKey);
    } else {
      return _box!.put(_keycloakUrlKey, value);
    }
  }

  static String? getKeycloakRedirect() {
    checkInit();
    return _box!.get(_keycloakRedirectKey) ?? dotenv.env["KEYCLOAK_REDIRECT"];
  }

  static Future<void> setKeycloakRedirect(String? value) {
    checkInit();
    if (value == null) {
      return _box!.delete(_keycloakRedirectKey);
    } else {
      return _box!.put(_keycloakRedirectKey, value);
    }
  }

  static String? getApiUrl() {
    checkInit();
    return _box!.get(_apiUrlKey) ?? dotenv.env["API_URL"];
  }

  static Future<void> setApiUrl(String? value) {
    checkInit();
    if (value == null) {
      return _box!.delete(_apiUrlKey);
    } else {
      return _box!.put(_apiUrlKey, value);
    }
  }

  static bool getLocalMode() {
    checkInit();
    return _box!.get(_localModeKey, defaultValue: "false") == "true";
  }

  static Future<void> setLocalMode(bool? value) {
    checkInit();
    return _box!.put(_localModeKey, value.toString());
  }

  static bool getFilterMode() {
    checkInit();
    return _box!.get(_filterModeKey, defaultValue: "false") == "true";
  }

  static Future<void> setFilterMode(bool? value) {
    checkInit();
    return _box!.put(_filterModeKey, value.toString());
  }

  static bool getPreReleaseMode() {
    checkInit();
    return _box!.get(_preReleaseModeKey, defaultValue: "false") == "true";
  }

  static Future<void> setPreReleaseMode(bool? value) {
    checkInit();
    return _box!.put(_preReleaseModeKey, value.toString());
  }

  /// The `sub` of the account currently signed in, remembered by [Auth] so it
  /// is available synchronously and without a client (offline start). Never
  /// cleared on logout: the favorites below are keyed by it and must survive
  /// until the same account returns.
  static String? getAccount() {
    checkInit();
    return _box!.get(_accountKey);
  }

  static Future<void> setAccount(String value) {
    checkInit();
    return _box!.put(_accountKey, value).then((v) => _box?.flush());
  }

  /// Favorites are per installation and per account, and deliberately not part
  /// of the device/group cache: that cache has to stay disposable so it can be
  /// dropped when the account changes. Keyed by account so a second account on
  /// the same phone does not inherit the first one's favorites.
  static Set<String> getFavoriteDeviceIds() => _getFavoriteIds(_favoriteDevicesKeyPrefix);

  static Future<void> setFavoriteDeviceIds(Set<String> ids) =>
      _setFavoriteIds(_favoriteDevicesKeyPrefix, ids);

  static Set<String> getFavoriteGroupIds() => _getFavoriteIds(_favoriteGroupsKeyPrefix);

  static Future<void> setFavoriteGroupIds(Set<String> ids) =>
      _setFavoriteIds(_favoriteGroupsKeyPrefix, ids);

  static Set<String> _getFavoriteIds(String prefix) {
    checkInit();
    final account = getAccount();
    if (account == null) return {};
    final str = _box!.get(prefix + account);
    if (str == null) return {};
    try {
      return (json.decode(str) as List<dynamic>).map((e) => e.toString()).toSet();
    } catch (_) {
      return {}; // ignore an unreadable entry rather than breaking every list
    }
  }

  static Future<void> _setFavoriteIds(String prefix, Set<String> ids) async {
    checkInit();
    final account = getAccount();
    if (account == null) return;
    await _box?.put(prefix + account, json.encode(ids.toList())).then((v) => _box?.flush());
  }

  /// Whether the favorites stored on the cached device/group rows have been
  /// copied into the per-account lists above (see FavoritesMigration).
  static bool getFavoritesMoved() {
    checkInit();
    return _box!.get(_favoritesMovedKey, defaultValue: "false") == "true";
  }

  static Future<void> setFavoritesMoved(bool value) {
    checkInit();
    return _box!.put(_favoritesMovedKey, value.toString()).then((v) => _box?.flush());
  }

  /// Whether the cached device groups were fetched by a version that keeps the
  /// criteria's aspect lists; rows from an older one lack them.
  static bool getDeviceGroupsCachedWithAspectLists() {
    checkInit();
    return _box!.get(_deviceGroupsCachedWithAspectListsKey, defaultValue: "false") == "true";
  }

  static Future<void> setDeviceGroupsCachedWithAspectLists(bool value) {
    checkInit();
    return _box!.put(_deviceGroupsCachedWithAspectListsKey, value.toString()).then((v) => _box?.flush());
  }

  /// Set by an account switch until the previous account's cached rows are
  /// wiped; a sign-in and the app start retry the wipe while it is set.
  static bool getAccountWipePending() {
    checkInit();
    return _box!.get(_accountWipePendingKey, defaultValue: "false") == "true";
  }

  static Future<void> setAccountWipePending(bool value) {
    checkInit();
    return _box!.put(_accountWipePendingKey, value.toString()).then((v) => _box?.flush());
  }

  /// Set while the FCM token of a signed-out account may still exist; cleared
  /// only by a successful deletion.
  static bool getFcmTokenDeletionPending() {
    checkInit();
    return _box!.get(_fcmTokenDeletionPendingKey, defaultValue: "false") == "true";
  }

  static Future<void> setFcmTokenDeletionPending(bool value) {
    checkInit();
    return _box!.put(_fcmTokenDeletionPendingKey, value.toString()).then((v) => _box?.flush());
  }

  /// Whether [Auth] has stored credentials it has not deleted since. Kept
  /// outside the secure storage, whose iOS read answers nothing instead of
  /// an error before the first unlock.
  static bool getCredentialsStored() {
    checkInit();
    return _marks!.get(_credentialsStoredKey, defaultValue: "false") == "true";
  }

  static Future<void> setCredentialsStored(bool value) {
    checkInit();
    return _marks!.put(_credentialsStoredKey, value.toString()).then((v) => _marks?.flush());
  }

  /// Set by every logout before it deletes the credentials, cleared once a
  /// login has stored its own. Kept outside the secure storage, whose
  /// deletion can fail or report success without deleting.
  static bool getSignedOut() {
    checkInit();
    return _box!.get(_signedOutKey, defaultValue: "false") == "true";
  }

  static Future<void> setSignedOut(bool value) {
    checkInit();
    return _box!.put(_signedOutKey, value.toString()).then((v) => _box?.flush());
  }

  /// Whether the entry the secure-storage check of `AppInitializer` reads was
  /// written. Kept outside the secure storage, so that the entry reading as
  /// absent can tell a store that lost it.
  static bool getSecureStorageCheckStored() {
    checkInit();
    return _marks!.get(_secureStorageCheckStoredKey, defaultValue: "false") == "true";
  }

  static Future<void> setSecureStorageCheckStored(bool value) {
    checkInit();
    return _marks!.put(_secureStorageCheckStoredKey, value.toString()).then((v) => _marks?.flush());
  }

  /// Starts in a row whose secure-storage check failed.
  static int getSecureStorageCheckFailures() {
    checkInit();
    return int.tryParse(_marks!.get(_secureStorageCheckFailuresKey) ?? "") ?? 0;
  }

  static Future<void> setSecureStorageCheckFailures(int value) {
    checkInit();
    return _marks!.put(_secureStorageCheckFailuresKey, value.toString()).then((v) => _marks?.flush());
  }

  /// Whether the secure storage's file is to be deleted at the next start,
  /// before anything loads it.
  static bool getSecureStorageResetPending() {
    checkInit();
    return _marks!.get(_secureStorageResetPendingKey, defaultValue: "false") == "true";
  }

  static Future<void> setSecureStorageResetPending(bool value) {
    checkInit();
    return _marks!.put(_secureStorageResetPendingKey, value.toString()).then((v) => _marks?.flush());
  }

  /// Moves the marks of the secure storage that an earlier version kept in
  /// the settings box into their own box. A value found there wins: it was
  /// put there after this box was filled, by an earlier version that ran
  /// since or by a restore of its backup. Flushed before the delete.
  static Future<void> moveSecureStorageMarks() async {
    checkInit();
    final present = _secureStorageMarkKeys.where(_box!.containsKey).toList();
    if (present.isEmpty) return;
    await _marks!.putAll({for (final key in present) key: _box!.get(key)!});
    await _marks!.flush();
    await _box!.deleteAll(present);
    await _box!.flush();
  }

  /// Drops every mark of the secure storage, as for a file that is not there.
  static Future<void> clearSecureStorageMarks() async {
    checkInit();
    await _marks!.deleteAll(_secureStorageMarkKeys);
    await _marks!.flush();
  }
}
