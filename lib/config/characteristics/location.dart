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

import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:open_location_picker/open_location_picker.dart';

import '../../models/characteristic.dart';
import '../../theme.dart';

class Location {
  static Widget build(BuildContext context, Characteristic characteristic) {
    FormattedLocation? initial;
    bool init = false;
    return StatefulBuilder(builder: (context, setState) {
      if (!init) {
        init = true;
        if (characteristic.value != null && characteristic.value["Latitude"] != null && characteristic.value["Longitude"] != null) {
          initial = FormattedLocation.fromLatLng(
              lat: characteristic.value["Latitude"], lon: characteristic.value["Longitude"], displayName: characteristic.value_label ?? "");
        } else {
          _determinePosition().then((value) {
            if (value != null) {
              initial = FormattedLocation.fromLatLng(
                  lat: value.latitude, lon: value.longitude, geojson: GeoGeometry.point(LatLng(value.latitude, value.longitude), MyTheme.appColor));
            } else {
              const latitude = 51.338527718877394;
              const longitude = 12.38074998525586;
              initial = FormattedLocation.fromLatLng(
                  lat: latitude,
                  lon: longitude,
                  geojson: GeoGeometry.point(LatLng(latitude, longitude), MyTheme.appColor),
                  displayName: "Augustusplatz, Leipzig");
            }
            characteristic.value = {"Latitude": initial!.lat, "Longitude": initial!.lon};
            characteristic.value_label = initial!.displayName;
            setState(() {});
          });
        }
      }

      return initial == null
          ? Center(
              child: PlatformCircularProgressIndicator(),
            )
          : OpenMapPicker(
              initialValue: initial,
              options: OpenMapOptions(center: LatLng(initial!.lat, initial!.lon)),
              decoration: const InputDecoration(hintText: "Pick location"),
              onChanged: (FormattedLocation? newValue) {
                characteristic.value = {"Latitude": newValue?.lat, "Longitude": newValue?.lon};
                characteristic.value_label = newValue?.displayName;
              },
            );
    });
  }

  static Future<Position?> _determinePosition() async {
    LocationPermission permission;
    // Test if location services are enabled.
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await Geolocator.getCurrentPosition();
  }
}
