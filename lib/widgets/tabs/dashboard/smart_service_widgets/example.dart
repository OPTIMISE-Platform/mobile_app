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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mutex/mutex.dart';

class SmSeExample extends SmartServiceModuleWidget {
  String data = "";
  final Mutex _refreshing = Mutex();

  @override
  int height = 1;

  @override
  int width = 1;

  @override
  Widget build(BuildContext context, bool _) {
    return ListTile(title: _refreshing.isLocked ? Center(child: PlatformCircularProgressIndicator()) : Text(data));
  }

  @override
  void configure(data) {
    this.data = data;
  }

  @override
  Future<void> refresh() async {
    await _refreshing.protect(() async => await Future.delayed(Duration(seconds: Random().nextInt(3), milliseconds: 300)));
    return;
  }
}
