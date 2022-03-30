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
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:path_provider/path_provider.dart';

import '../exceptions/no_network_exception.dart';

class AppUpdater {
  static final _client = http.Client();

  late final updateSupported = _updateSupported();

  late int currentBuild;
  late int latestBuild;
  late int downloadSize;
  late DateTime updateDate;

  late String updateUrl;
  late String localFile;

  AppUpdater();

  bool _updateSupported() {
    if (Platform.isAndroid && dotenv.env["DISTRIBUTOR"] == "github" && dotenv.env["GITHUB_REPO"] != null && dotenv.env["version"] != null) {
      return true;
    }
    return false;
  }

  Future<bool> updateAvailable() async {
    if (!updateSupported) return false;

    ConnectivityResult connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) throw NoNetworkException();

    final url = "https://api.github.com/repos/" + dotenv.env["GITHUB_REPO"]! + '/releases?per_page=1';
    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }

    final resp = await _client.get(uri);
    if (resp.statusCode != 200) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    final decoded = (json.decode(utf8.decode(resp.bodyBytes)) as List<dynamic>)[0] as Map<String, dynamic>;
    latestBuild = int.parse((decoded["tag_name"] as String).split("+")[1]);
    currentBuild = int.parse(dotenv.env["version"]!.split("+")[1]);

    if (latestBuild > currentBuild) {
      final asset = (decoded["assets"] as List<dynamic>).firstWhere((element) => element["name"] == "app-release.apk");
      updateUrl = asset["browser_download_url"];
      downloadSize = asset["size"];
      updateDate = DateTime.parse(asset["updated_at"]);
      return true;
    }

    return false;
  }

  Stream<double> downloadUpdate() async* {
    var uri = Uri.parse(updateUrl);
    if (updateUrl.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }

    final req = http.Request('GET', uri);
    final resp = _client.send(req);
    localFile = (await getApplicationSupportDirectory()).path + '/update.apk';

    final List<List<int>> chunks = [];
    int downloaded = 0;
    double percentage = 0;

    await for(final r in resp.asStream()) {
      if (r.statusCode != 200) {
        throw UnexpectedStatusCodeException(r.statusCode);
      }

      await for (final chunk in r.stream) {
        percentage = downloaded / r.contentLength! * 100;
        yield percentage;
        chunks.add(chunk);
        downloaded += chunk.length;
      }

      percentage = downloaded / r.contentLength! * 100;
      yield percentage;

      File file = File(localFile);
      final Uint8List bytes = Uint8List(r.contentLength!);
      int offset = 0;
      for (List<int> chunk in chunks) {
        bytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      await file.writeAsBytes(bytes);
    }
  }
}
