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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/app_update.dart';

Map<String, dynamic> _release(String tag,
        {bool apk = true, bool manifest = false}) =>
    {
      "tag_name": tag,
      "assets": [
        {"name": "LICENSE"},
        if (apk) {"name": "app-release.apk"},
        if (manifest) {"name": "manifest.plist"},
      ],
    };

void main() {
  test("picks the highest build, not the first entry GitHub lists", () {
    // The order the releases API returned on 2026-09-28.
    final releases = [
      _release("0.2.0-dev.9+411"),
      _release("0.2.0-dev.8+410"),
      _release("0.2.0-dev.7+409"),
      _release("0.2.0-dev.14+416"),
      _release("0.2.0-dev.13+415"),
      _release("0.2.0-dev.10+412"),
      _release("0.1.2+398"),
    ];
    expect(AppUpdater.newestRelease(releases)?["tag_name"], "0.2.0-dev.14+416");
  });

  test("skips releases without an APK or without a build number", () {
    final releases = [
      _release("0.2.0-dev.15+417", apk: false),
      _release("v2"),
      _release("0.2.0-dev.14+416"),
    ];
    expect(AppUpdater.newestRelease(releases)?["tag_name"], "0.2.0-dev.14+416");
  });

  test("looks for the asset it is given, so iOS skips releases without a manifest", () {
    // The iOS build attaches its manifest after the release already exists.
    final releases = [
      _release("0.2.0-dev.16+418"),
      _release("0.2.0-dev.15+417", manifest: true),
    ];
    expect(
        AppUpdater.newestRelease(releases, asset: AppUpdater.manifestAsset)?["tag_name"],
        "0.2.0-dev.15+417");
  });

  test("returns null when nothing qualifies", () {
    expect(AppUpdater.newestRelease(const []), isNull);
    expect(AppUpdater.newestRelease([_release("v2")]), isNull);
  });
}
