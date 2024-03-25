/*
 * Copyright 2024 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:flutter/material.dart';

const tabFavorites = 0;
const tabDashboard = 1;
const tabDevices = 2;
const tabLocations = 3;
const tabGroups = 4;
const tabNetworks = 5;
const tabClasses = 6;
const tabSmartServices = 7;
const tabGateways = 8;

List<NavigationItem> navItems = [
  NavigationItem("Favorites",tabFavorites, Icons.star_border),
  NavigationItem("Dashboard",tabDashboard, Icons.dashboard),
  NavigationItem("Devices",tabDevices, Icons.devices),
  NavigationItem("Locations",tabLocations, Icons.location_on),
  NavigationItem("Groups",tabGroups, Icons.devices_other),
  NavigationItem("Networks",tabNetworks, Icons.hub_outlined),
  NavigationItem("Classes",tabClasses, Icons.category),
  NavigationItem("Services",tabSmartServices, Icons.auto_fix_high),
  NavigationItem("Gateways",tabGateways, Icons.device_hub),
];

class NavigationItem {
  String name;
  int index;
  IconData icon;
  NavigationItem(this.name, this.index, this.icon);
}