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

import 'package:dio/dio.dart';
import 'package:isar_community/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class LocationService {
  static final _logger = Logger(printer: SimplePrinter());

  static late Dio _dio;

  static initOptions() async {
    _dio = await DioFactory.create(DioConfig.standard);
  }

  static Future<List<Future<Location>>> getLocations({
    bool forceBackend = false,
  }) async {
    if (!forceBackend && isar != null) {
      return (await isar!.locations.where().sortByName().findAll())
          .map((e) => e.initImage())
          .toList();
    }

    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-repository/locations';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = "9999";

    final headers = await Auth().getHeaders();
    await initOptions();

    var cont = true;
    final locations = <Location>[];

    while (cont) {
      queryParameters["offset"] = locations.length.toString();
      final Response<List<dynamic>?> resp;
      try {
        resp = await _dio.get<List<dynamic>?>(
          uri,
          queryParameters: queryParameters,
          options: Options(headers: headers),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
          throw UnexpectedStatusCodeException(
            e.response?.statusCode,
            "$uri ${e.message}",
          );
        }
        rethrow;
      }
      if (resp.statusCode == 304) {
        _logger.d("Using cached device locations");
      }

      final l = resp.data ?? [];
      final add = List<Location>.generate(
        l.length,
        (index) => Location.fromJson(l[index]),
      );
      locations.addAll(add);
      cont = add.length == 9999;
    }
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.putAll(locations);
      });
    }
    return locations.map((e) => e.initImage()).toList(growable: false);
  }

  static Future<Location> saveLocation(Location location) async {
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/locations/${location.id}';

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<dynamic> resp;
    try {
      resp = await _dio.put<dynamic>(
        uri,
        options: Options(headers: headers),
        data: location.toJson(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(
          e.response?.statusCode,
          "$uri ${e.message}",
        );
      }
      rethrow;
    }

    final savedLocation = Location.fromJson(resp.data);
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.put(savedLocation);
      });
    }
    return savedLocation.initImage();
  }

  static Future<Location> createLocation(String name) async {
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/locations/';

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>(
        uri,
        options: Options(headers: headers),
        data: Location("", name, "", "", [], []).toJson(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(
          e.response?.statusCode,
          "$uri ${e.message}",
        );
      }
      rethrow;
    }
    final savedLocation = Location.fromJson(resp.data);
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.put(savedLocation);
      });
    }
    return savedLocation.initImage();
  }

  static Future<void> deleteLocation(String id) async {
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/locations/$id';

    final headers = await Auth().getHeaders();
    await initOptions();
    try {
      await _dio.delete(uri, options: Options(headers: headers));
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(
          e.response?.statusCode,
          "$uri ${e.message}",
        );
      }
      rethrow;
    }

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.delete(fastHash(id));
      });
    }

    return;
  }

  static bool isListAvailable() => ApiAvailableService().isAvailable(
    '${Settings.getApiUrl() ?? 'localhost'}/device-repository/locations',
  );

  static bool isCreateEditDeleteAvailable() =>
      ApiAvailableService().isAvailable(
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/locations',
      );
}
