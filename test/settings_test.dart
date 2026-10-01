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

import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:hive/hive.dart";
import "package:mobile_app/models/sensor_pin.dart";
import "package:mobile_app/models/sensor_tab.dart";
import "package:mobile_app/models/smart_service.dart";
import "package:mobile_app/services/settings.dart";

import "test_helper.dart";

void main() {
  setUpAll(() {
    setUpTestEnvironment();
  });
  setUp(() async {
    await Settings.init();
  });
  tearDown(() async {
    await Settings.clear();
    await Settings.close();
  });

  group("theme", () {
    test("get default theme", () {
      expect(Settings.getTheme(), equals(Settings.getDefaultTheme()));
    });

    test("set new theme", () async {
      await Settings.setTheme("foo");
      expect(Settings.getTheme(), equals("foo"));
    });

    test("theme is persistent", () async {
      await Settings.setTheme("bar");
      await Settings.close();
      await Settings.init();
      expect(Settings.getTheme(), equals("bar"));
    });

  });


  group("theme color", () {
    test("get color", () {
      expect(Settings.getThemeColor(), equals(Settings.getDefaultThemeColor()));
    });

    test("set new color", () async {
      await Settings.setThemeColor("foo");
      expect(Settings.getThemeColor(), equals("foo"));
    });

    test("color is persistent", () async {
      await Settings.setThemeColor("bar");
      await Settings.close();
      await Settings.init();
      expect(Settings.getThemeColor(), equals("bar"));
    });
  });

  group("displayed fraction digits", () {
    test("get default", () {
      expect(Settings.getDisplayedFractionDigits(), equals(Settings.getDefaultDisplayedFractionDigits()));
    });

    test("set new value", () async {
      await Settings.setDisplayedFractionDigits(3);
      expect(Settings.getDisplayedFractionDigits(), equals(3));
    });

    test("persistence", () async {
      await Settings.setDisplayedFractionDigits(4);
      await Settings.close();
      await Settings.init();
      expect(Settings.getDisplayedFractionDigits(), equals(4));
    });
  });

  group("cache timestamps", () {
    test("clearCacheUpdated forgets them all but keeps other settings", () async {
      await Settings.setCacheUpdated("devices");
      await Settings.setCacheUpdated("networks");
      await Settings.setTheme("keep-me");
      expect(Settings.getCacheUpdated("devices"), isNotNull);

      await Settings.clearCacheUpdated();

      expect(Settings.getCacheUpdated("devices"), isNull);
      expect(Settings.getCacheUpdated("networks"), isNull);
      expect(Settings.getTheme(), "keep-me");
    });
  });

  group("favorites", () {
    test("are empty and unwritable without an account", () async {
      expect(Settings.getFavoriteDeviceIds(), isEmpty);
      await Settings.setFavoriteDeviceIds({"device-1"});
      expect(Settings.getFavoriteDeviceIds(), isEmpty);
    });

    test("are stored and read back for the signed-in account", () async {
      await Settings.setAccount("account-a");
      await Settings.setFavoriteDeviceIds({"device-1", "device-2"});
      await Settings.setFavoriteGroupIds({"group-1"});
      expect(Settings.getFavoriteDeviceIds(), {"device-1", "device-2"});
      expect(Settings.getFavoriteGroupIds(), {"group-1"});
    });

    test("devices and groups do not share a list", () async {
      await Settings.setAccount("account-a");
      await Settings.setFavoriteDeviceIds({"device-1"});
      expect(Settings.getFavoriteGroupIds(), isEmpty);
    });

    test("a second account does not inherit the first one's favorites", () async {
      await Settings.setAccount("account-a");
      await Settings.setFavoriteDeviceIds({"device-1"});

      await Settings.setAccount("account-b");
      expect(Settings.getFavoriteDeviceIds(), isEmpty);
      await Settings.setFavoriteDeviceIds({"device-2"});

      // and switching back finds the first account's list untouched
      await Settings.setAccount("account-a");
      expect(Settings.getFavoriteDeviceIds(), {"device-1"});
    });

    test("survive a restart", () async {
      await Settings.setAccount("account-a");
      await Settings.setFavoriteDeviceIds({"device-1"});
      await Settings.close();
      await Settings.init();
      expect(Settings.getAccount(), "account-a");
      expect(Settings.getFavoriteDeviceIds(), {"device-1"});
    });
  });


  group("sensor tabs and dashboards", () {
    // What an earlier version stored for everyone, under the unkeyed keys.
    Future<void> storeLegacy(String key, Object value) =>
        Hive.box<String>("settings.box").put(key, jsonEncode(value));
    bool hasLegacy(String key) =>
        Hive.box<String>("settings.box").containsKey(key);
    // The legacy keys go once the account's copy is written.
    Future<bool> legacyGone(String key) async {
      for (var i = 0; i < 100 && hasLegacy(key); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return !hasLegacy(key);
    }

    const tab = SensorTab(id: "t1", name: "Kitchen");
    final dashboard = SmartServiceDashboard("d1", "Energy", []);

    List<String> tabIds() => Settings.getSensorTabs().map((t) => t.id).toList();
    List<String> dashboardIds() =>
        Settings.getSmartServiceDashboards().map((d) => d.id).toList();

    test("are empty without an account and leave the old entries alone",
        () async {
      await storeLegacy("sensor_tabs", [tab]);
      await storeLegacy("smart_service_dashboards", [dashboard]);

      expect(Settings.getSensorTabs(), isEmpty);
      expect(Settings.getSmartServiceDashboards(), isEmpty);
      await Settings.setSensorTabs([tab]);
      expect(hasLegacy("sensor_tabs"), isTrue);
      expect(hasLegacy("smart_service_dashboards"), isTrue);
    });

    test("move to the first account that reads them, once", () async {
      await storeLegacy("sensor_tabs", [tab]);
      await storeLegacy("smart_service_dashboards", [dashboard]);
      await Settings.setAccount("account-a");

      expect(tabIds(), ["t1"]);
      expect(dashboardIds(), ["d1"]);
      expect(await legacyGone("sensor_tabs"), isTrue);
      expect(await legacyGone("smart_service_dashboards"), isTrue);
      await Settings.close();
      await Settings.init();
      expect(tabIds(), ["t1"], reason: "stored under the account");
      expect(dashboardIds(), ["d1"]);
    });

    test("move the pins from before the tabs as one tab", () async {
      await storeLegacy("pinned_sensors", [
        const SensorPin(deviceId: "device-1", functionId: "f1").toJson()
      ]);
      await Settings.setAccount("account-a");

      final tabs = Settings.getSensorTabs();
      expect(tabs.single.pins.single.deviceId, "device-1");
      expect(await legacyGone("pinned_sensors"), isTrue);
    });

    test("old entries left next to the account's own are deleted", () async {
      await Settings.setAccount("account-a");
      await Settings.setSensorTabs([tab]);
      await storeLegacy("sensor_tabs", [const SensorTab(id: "t9", name: "Old")]);

      expect(tabIds(), ["t1"]);
      expect(await legacyGone("sensor_tabs"), isTrue,
          reason: "a later account would inherit it");
    });

    test("a write of the first account takes the old entries over too",
        () async {
      await storeLegacy("sensor_tabs", [tab]);
      await Settings.setAccount("account-a");
      await Settings.setSensorTabs([const SensorTab(id: "t2", name: "Hall")]);

      await Settings.setAccount("account-b");
      expect(Settings.getSensorTabs(), isEmpty);
    });

    test("a second account sees none of the first one's, and the first finds "
        "its own again", () async {
      await storeLegacy("sensor_tabs", [tab]);
      await Settings.setAccount("account-a");
      expect(tabIds(), ["t1"]);
      await Settings.setSmartServiceDashboards([dashboard]);

      await Settings.setAccount("account-b");
      expect(Settings.getSensorTabs(), isEmpty);
      expect(Settings.getSmartServiceDashboards(), isEmpty);
      await Settings.setSensorTabs([const SensorTab(id: "t2", name: "Hall")]);

      await Settings.setAccount("account-a");
      expect(tabIds(), ["t1"]);
      expect(dashboardIds(), ["d1"]);
      await Settings.setAccount("account-b");
      expect(tabIds(), ["t2"]);
    });
  });
}