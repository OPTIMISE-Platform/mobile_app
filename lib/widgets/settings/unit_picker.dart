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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/services/settings.dart' as settings_service;
import 'package:mobile_app/theme.dart';
import 'package:numberpicker/numberpicker.dart';

/// The unit picker: every function whose concept offers more than one
/// characteristic, filtered by a search box. Its own widget because the search
/// string is state — on the enclosing StatelessWidget it was reset by any
/// parent rebuild.
class UnitPickerList extends StatefulWidget {
  const UnitPickerList({super.key});

  @override
  State<UnitPickerList> createState() => _UnitPickerListState();
}

class _UnitPickerListState extends State<UnitPickerList> {
  String _functionSearch = "";

  @override
  Widget build(BuildContext context) {
    final functions = AppState()
        .platformFunctions
        .values
        .where((f) =>
            (AppState().concepts[f.concept_id]?.characteristics ?? []).length > 1 &&
            f.name.toLowerCase().contains(_functionSearch.toLowerCase()))
        .toList();
    final list = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: functions.length,
        itemBuilder: (context, i) {
          final f = functions[i];
          return ListTile(
              title: PopupMenuButton<String?>(
            initialValue: settings_service.Settings
                    .getFunctionPreferredCharacteristicId(f.id) ??
                AppState().concepts[f.concept_id]?.base_characteristic_id,
            itemBuilder: (_) => (AppState().concepts[f.concept_id]?.characteristics ?? [])
                .map(
                  (e) => PopupMenuItem<String?>(
                      value: e.id,
                      child: Text(e.name)),
                )
                .toList()
              ..add(const PopupMenuItem<String?>(
                  value: null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Divider(), Text("Reset")],
                  ))),
            onSelected: (v) {
              settings_service.Settings
                  .setFunctionPreferredCharacteristicId(f.id, v);
              reinit();
              AppState().notifyListeners();
              AppState().pushRefresh();
              setState(() {});
            },
            child: Text(f.name),
          ));
        });
    final column = SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: MyTheme.inset,
              child: TextFormField(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search',
                ),
                onChanged: (filter) => setState(() => _functionSearch = filter),
                initialValue: _functionSearch,
              )),
          Expanded(child: Scrollbar(child: list))
        ]));
    return column;
  }
}

StatefulBuilder Function(BuildContext context)
    getDisplayedFractionsDigitSelectDialog(AppState state) {
  return (context) {
    var currentDisplayedFractionDigitsSetting =
        settings_service.Settings.getDisplayedFractionDigits();
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog.adaptive(
          actions: [
            TextButton(
                child: const Text("OK"),
                onPressed: () => Navigator.pop(context)),
          ],
          content: NumberPicker(
              value: currentDisplayedFractionDigitsSetting,
              minValue: -1,
              maxValue: 21,
              step: 1,
              textMapper: (input) => input == "-1" ? "∞" : input,
              onChanged: (value) => setState(() {
                    currentDisplayedFractionDigitsSetting = value;
                    settings_service.Settings.setDisplayedFractionDigits(value);
                    state.notifyListeners();
                  }))),
    );
  };
}
