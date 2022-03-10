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
import 'package:mobile_app/widgets/app_bar.dart';


class PageSpinner extends StatefulWidget {
  final String _title;

  const PageSpinner(this._title, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PageSpinnerState(_title);
  }
}

class _PageSpinnerState extends State<PageSpinner> {
  late final MyAppBar _appBar;
  final String _title;

  _PageSpinnerState(this._title) {
    _appBar = MyAppBar();
    _appBar.setTitle(_title);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      //backgroundColor: MyTheme.appColor,
      appBar: _appBar.getAppBar(context),
      body: Center(
          child: PlatformCircularProgressIndicator(),
      ),
    );
  }
}
