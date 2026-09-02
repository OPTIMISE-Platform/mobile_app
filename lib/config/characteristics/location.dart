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
import 'package:geolocator/geolocator.dart';
import 'package:open_location_picker/open_location_picker.dart';

import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/shared/location.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';

class Location extends StatefulWidget {
  final Characteristic characteristic;
  final StateSetter externalSetState;

  const Location({
    super.key,
    required this.characteristic,
    required this.externalSetState,
  });

  @override
  State<Location> createState() => _LocationState();
}

class _LocationState extends State<Location> {
  FormattedLocation? initial;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    if (widget.characteristic.value != null &&
        widget.characteristic.value["Latitude"] != null &&
        widget.characteristic.value["Longitude"] != null) {
      initial = FormattedLocation.fromLatLng(
        lat: widget.characteristic.value["Latitude"],
        lon: widget.characteristic.value["Longitude"],
        displayName: widget.characteristic.value_label ?? "",
      );
    } else {
      final pos = await determinePosition();

      if (pos != null) {
        initial = FormattedLocation.fromLatLng(
          lat: pos.latitude,
          lon: pos.longitude,
          geojson: GeoGeometry.point(
            LatLng(pos.latitude, pos.longitude),
            MyTheme.appColor,
          ),
        );
      } else {
        const lat = 51.338527718877394;
        const lon = 12.38074998525586;
        initial = FormattedLocation.fromLatLng(
          lat: lat,
          lon: lon,
          displayName: "Augustusplatz, Leipzig",
          geojson: GeoGeometry.point(const LatLng(lat, lon), MyTheme.appColor),
        );
      }

      widget.characteristic.value = {
        "Latitude": initial!.lat,
        "Longitude": initial!.lon,
      };
      widget.characteristic.value_label = initial!.displayName;
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: DelayedCircularProgressIndicator());
    }

    return OpenMapSettings(
      onError: (context, error) => debugPrint(error.toString()),
      getCurrentLocation: _getCurrentLocation,
      getLocationStream: _getLocationStream,
      child: OpenMapPicker(
        initialValue: initial,
        options: OpenMapOptions(
          center: LatLng(initial!.lat, initial!.lon),
        ),
        decoration: const InputDecoration(hintText: "Pick location"),
        onChanged: (newValue) {
          widget.characteristic.value = {
            "Latitude": newValue?.lat,
            "Longitude": newValue?.lon,
          };
          widget.characteristic.value_label = newValue?.displayName;
        },
      )
    );
  }

  // ---------------------------------------------------------------------------
  // Location helpers — kept here to avoid cluttering build()
  // ---------------------------------------------------------------------------

  static Future<LatLng?> _getCurrentLocation() async {
    final pos = await determinePosition();
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  }

  static Stream<LatLng> _getLocationStream() =>
      Geolocator.getPositionStream(locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50, // meters
      )).map((pos) => LatLng(pos.latitude, pos.longitude));
}