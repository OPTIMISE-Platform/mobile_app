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

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive/hive.dart';
import 'package:mobile_app/exceptions/settings_exception.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:path_provider/path_provider.dart';

class Settings {
  static bool isInitialized = false;

  static const _boxName = "settings.box";
  static Box<String>? _box;

  static const _themeKey = "theme";
  static const _defaultTheme = "";
  static String _currentThemeValue = "";

  static const _themeColorKey = "theme_color";
  static const _defaultThemeColor = "";
  static String _currentThemeColorValue = "";

  static const _displayedFractionDigitsKey = "displayed_fraction_digits";
  static const _defaultDisplayedFractionDigits = 2;
  static int _currentDisplayedFractionDigits = 0;

  static const _smartServiceDashboardsKey = "smart_service_dashboards";

  static const _hapticFeedBackEnabledKey = "haptic_feedback_enabled";

  static const _functionPreferredCharacteristicKeyPrefix = "functionPreferredCharacteristic_";

  static const _cacheUpdatedAtPrefix = "cacheUpdated_";

  static const _keycloakUrlKey = "keycloak_url";
  static const _keycloakRedirectKey = "keycloak_redirect";
  static const _apiUrlKey = "api_url";

  static const _localModeKey = "local_mode";

  static const _filterModeKey = "filter_mode";

  static const _dmModeKey = "dm_mode";

  static const _preReleaseModeKey = "preRelease_mode";

  static checkInit() {
    if (!isInitialized) {
      throw SettingsNotInitializedException();
    }
  }

  static init() async {
    if (!isInitialized) {
      if (!kIsWeb) {
        Hive.init((await getApplicationDocumentsDirectory()).path);
      }
      _box = await Hive.openBox<String>(_boxName);

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
    _setDefaults();
  }

  static close() async {
    if (isInitialized) {
      await _box?.close();
      _box = null;
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

  static bool tutorialSeen(Tutorial tutorial) {
    checkInit();
    return _box!.containsKey(tutorial.toString());
  }

  static Future<void> markTutorialSeen(Tutorial tutorial) {
    checkInit();
    return _box!.put(tutorial.toString(), true.toString());
  }

  static Future<void> resetTutorials() async {
    checkInit();
    await Future.wait(Tutorial.values.map((e) => _box!.delete(e.toString())));
  }

  static List<SmartServiceDashboard> getSmartServiceDashboards() {
    checkInit();
    final str = _box!.get(_smartServiceDashboardsKey);
    if (str == null) return [];
    final List<dynamic> l = json.decode(str);
    return List<SmartServiceDashboard>.generate(l.length, (index) => SmartServiceDashboard.fromJson(l[index]));
  }

  static setSmartServiceDashboards(List<SmartServiceDashboard> dashboards) async {
    checkInit();
    await _box?.put(_smartServiceDashboardsKey, json.encode(dashboards)).then((value) => _box?.flush());
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

  static bool getDeviceManagerMode() {
    checkInit();
    return _box!.get(_dmModeKey, defaultValue: "true") == "true";
  }

  static Future<void> setDeviceManagerMode(bool? value) {
    checkInit();
    return _box!.put(_dmModeKey, value.toString());
  }

  static bool getPreReleaseMode() {
    checkInit();
    return _box!.get(_preReleaseModeKey, defaultValue: "false") == "true";
  }

  static Future<void> setPreReleaseMode(bool? value) {
    checkInit();
    return _box!.put(_preReleaseModeKey, value.toString());
  }
}

enum Tutorial { addFavoriteButton, deviceListItem }
