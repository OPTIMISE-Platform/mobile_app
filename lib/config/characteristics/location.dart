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
import 'package:open_location_picker/open_location_picker.dart';

import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/shared/location.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';

class Location {
  static Widget build(BuildContext context, Characteristic characteristic, StateSetter setState) {
    FormattedLocation? initial;
    bool init = false;
    if (!init) {
      init = true;
      if (characteristic.value != null && characteristic.value != "" && characteristic.value["Latitude"] != null && characteristic.value["Longitude"] != null) {
        initial = FormattedLocation.fromLatLng(
            lat: characteristic.value["Latitude"], lon: characteristic.value["Longitude"], displayName: characteristic.value_label ?? "");
      } else {
        determinePosition().then((value) {
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
        ? const Center(
            child: DelayedCircularProgressIndicator(),
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
  }
}
