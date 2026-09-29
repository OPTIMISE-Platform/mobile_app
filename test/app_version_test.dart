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
import 'package:mobile_app/shared/app_version.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> _installed(String version, String buildNumber) async {
  PackageInfo.setMockInitialValues(
    appName: "mobile_app",
    packageName: "org.infai.optimise.mobile_app",
    version: version,
    buildNumber: buildNumber,
    buildSignature: "",
  );
  await AppVersion.init();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("takes version and build from the installed package", () async {
    await _installed("0.2.0-dev.20", "422");
    expect(AppVersion.build, 422);
    expect(AppVersion.display, "0.2.0-dev.20+422");
  });

  test("has no build when the package carries no number", () async {
    await _installed("0.2.0", "");
    expect(AppVersion.build, isNull);
    expect(AppVersion.display, "0.2.0");
  });
}
