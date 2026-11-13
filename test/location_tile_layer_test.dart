import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_location_picker/open_location_picker.dart';

import 'package:mobile_app/config/characteristics/location.dart';

void main() {
  test("OSM tiles are requested from the plain host with the application id as user agent", () {
    Widget builder(context, tileWidget, tile) => tileWidget;
    final layer = osmTileLayer(TileLayer(urlTemplate: "unused", tileBuilder: builder));

    expect(layer.urlTemplate, "https://tile.openstreetmap.org/{z}/{x}/{y}.png");
    expect(layer.subdomains, isEmpty);
    expect(layer.tileProvider.headers["User-Agent"], "flutter_map (org.infai.optimise.mobile_app)");
    expect(layer.tileBuilder, same(builder));
  });
}
