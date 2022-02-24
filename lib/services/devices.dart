import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_permsearch.dart';

import 'auth.dart';

class DevicesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static Future<List<DevicePermSearch>> getDevices(
      int limit, int offset, String search, List<String>? byDeviceTypes) async {
    _logger.v("Devices '" +
        search +
        "' " +
        offset.toString() +
        "-" +
        (offset + limit).toString());

    final url = Uri.parse(
        (dotenv.env["API_URL"] ?? 'localhost') + '/permissions/query/v3/query');
    final body = <String, dynamic>{
      "resource": "devices",
      "find": {
        "limit": limit,
        "offset": offset,
        "sortBy": "name.asc",
        "search": search,
      }
    };
    if (byDeviceTypes != null && byDeviceTypes.length > 0) {
      body["filter"] = {
        "condition": {
          "feature": "features.device_type_id",
          "operation": "any_value_in_feature",
          "value": byDeviceTypes,
        }
      };
    }

    final encoded = json.encode(body);

    final client = await Auth.getHttpClient();
    final resp = await client.post(url, body: encoded);
    if (resp.statusCode > 299) {
      throw "Unexpected status code " + resp.statusCode.toString();
    }

    final decoded = json.decode(resp.body);
    if (decoded == null) {
      return [];
    }
    final l = decoded as List<dynamic>;
    return List<DevicePermSearch>.generate(
        l.length, (index) => DevicePermSearch.fromJson(l[index]));
  }

  static Future<int> getTotalDevices(String search) async {
    String uri = (dotenv.env["API_URL"] ?? 'localhost') +
        '/permissions/query/v3/total/devices';
    if (search.isNotEmpty) {
      uri += "?search=" + search;
    }
    final url = Uri.parse(uri);
    final client = await Auth.getHttpClient();
    final resp = await client.get(url);
    if (resp.statusCode > 299) {
      throw "Unexpected status code " + resp.statusCode.toString();
    }

    final decoded = json.decode(resp.body);
    if (decoded == null) {
      return 0;
    }
    return decoded;
  }
}
