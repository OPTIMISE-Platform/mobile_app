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
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:multiselect/multiselect.dart';

import '../../../models/smart_service.dart';
import '../../../theme.dart';
import '../../shared/expandable_text.dart';

class SmartServicesReleaseLaunch extends StatefulWidget {
  final SmartServiceRelease release;

  const SmartServicesReleaseLaunch(this.release, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SmartServicesReleaseLaunchState();
}

class _SmartServicesReleaseLaunchState extends State<SmartServicesReleaseLaunch> {
  List<SmartServiceExtendedParameter>? parameters;

  final appBar = const MyAppBar("Launch Release");
  static final _format = DateFormat.yMd().add_jms();
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  Widget _getEditWidget(int i, {int? sub}) {
    final p = parameters![i];
    final dynamic subValue = sub != null ? (p.value as List)[sub] : null;

    if (p.multiple && p.options != null) {
      return ConstrainedBox(
          constraints: BoxConstraints.tight(const Size(double.infinity, 48)),
          child: DropDownMultiSelect(
            key: ValueKey(i.toString()),
            decoration: const InputDecoration(),
            onChanged: (List x) {
              setState(() {
                p.value = p.options!.where((element) => x.contains(element.label)).map((e) => e.value).toList();
              });
            },
            options: p.options!.map((e) => e.label).toList(growable: false),
            selectedValues: p.options!.where((element) => (p.value ?? []).contains(element.value)).map((e) => e.label).toList(),
            whenEmpty: p.label,
          ));
    } else if (p.options != null) {
      final List<DropdownMenuItem> items = p.options!
          .map((e) => DropdownMenuItem(
                value: e.value,
                child: Text(e.label),
              ))
          .toList();
      return DropdownButton<dynamic>(
          key: ValueKey(i.toString()), items: items, value: p.value, onChanged: (value) => setState(() => p.value = value), hint: Text(p.label));
    }

    switch (p.type) {
      case ContentVariable.INTEGER:
        return PlatformTextFormField(
          key: ValueKey(i.toString() + sub.toString()),
          hintText: p.label,
          initialValue: sub != null
              ? (subValue ?? 0).toString()
              : p.value != null && p.value is! List
                  ? p.value.toString()
                  : p.default_value != null
                      ? p.default_value.toString()
                      : "",
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          autovalidateMode: AutovalidateMode.always,
          validator: (value) {
            if (value == null) {
              return "no empty values";
            }
            if (value.contains(".") || value.contains(",")) {
              return "no decimal numbers";
            }
            try {
              int.parse(value);
            } catch (e) {
              return "invalid number";
            }
          },
          onChanged: (value) {
            try {
              p.value = int.parse(value);
            } catch (e) {
              _logger.d("error parsing user input");
            }
          },
        );
      case ContentVariable.FLOAT:
        return PlatformTextFormField(
          key: ValueKey(i.toString() + sub.toString()),
          hintText: p.label,
          initialValue: sub != null
              ? (subValue ?? 0.0).toString()
              : p.value != null && p.value is! List
                  ? p.value.toString()
                  : p.default_value != null
                      ? p.default_value.toString()
                      : "",
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          autovalidateMode: AutovalidateMode.always,
          validator: (value) {
            try {
              double.parse(value ?? "");
            } catch (e) {
              return "no decimal value";
            }
          },
          onChanged: (value) {
            try {
              p.value = double.parse(value);
            } catch (e) {
              _logger.d("error parsing user input");
            }
          },
        );
      case ContentVariable.STRING:
        return PlatformTextFormField(
          key: ValueKey(i.toString() + sub.toString()),
          hintText: p.label,
          initialValue: (sub == null ? null : subValue ?? "") ?? (p.value != null && p.value is! List ? p.value : null) ?? p.default_value ?? "",
          onChanged: (newValue) {
            if (sub != null) {
              (p.value as List)[sub] = newValue;
            } else {
              p.value = newValue = newValue;
            }
          },
        );
      case ContentVariable.BOOLEAN:
        return Row(children: [
          Container(padding: const EdgeInsets.only(right: MyTheme.insetSize), child: Text(p.label)),
          PlatformSwitch(
            key: ValueKey(i.toString() + sub.toString()),
            onChanged: (bool newValue) {
              setState(() {
                if (sub != null) {
                  (p.value as List)[sub] = newValue;
                } else {
                  p.value = newValue = newValue;
                }
              });
            },
            value: (sub == null ? null : subValue ?? false) ?? (p.value != null && p.value is! List ? p.value : null) ?? p.default_value ?? false,
          )
        ]);
    }

    return const Text("not implemented");
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      parameters = await SmartServiceService.getReleaseParameters(widget.release.id);
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> configs = [
      ListTile(
        // header
        leading: Container(
          height: MediaQuery.of(context).textScaleFactor * 48,
          width: MediaQuery.of(context).textScaleFactor * 48,
          decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
          child: Padding(
            padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
            child: const Icon(Icons.auto_fix_high, color: Colors.white), // TODO icon
          ),
        ),
        title: Text(widget.release.name),
        subtitle: ExpandableText("${widget.release.description}\n\nReleased: ${_format.format(widget.release.createdAt())}", 3),
      )
    ];
    for (int i = 0; i < (parameters?.length ?? 0); i++) {
      final p = parameters![i];
      configs.addAll([
        const SizedBox(height: 5),
        const Divider(thickness: 5),
        const SizedBox(height: 5),
        ListTile(
            title: p.multiple && p.options == null ? Text(p.label) : _getEditWidget(i),
            subtitle: ExpandableText(p.description, 2),
            trailing: p.multiple && p.options == null
                ? PlatformIconButton(
                    icon: Icon(PlatformIcons(context).add),
                    onPressed: () {
                      setState(() {
                        if (p.value is List) {
                          (p.value as List).add(null);
                        } else {
                          p.value = <dynamic>[null];
                        }
                      });
                    },
                  )
                : null)
      ]);
      if (p.multiple && p.options == null && p.value is List) {
        for (int j = 0; j < (p.value as List).length; j++) {
          configs.add(ListTile(
            dense: true,
            title: _getEditWidget(i, sub: j),
            trailing: PlatformIconButton(
              icon: Icon(PlatformIcons(context).delete),
              onPressed: () {
                setState(() {
                  (p.value as List).removeAt(j);
                });
              },
            ),
          ));
        }
      }
    }
    configs.add(const SizedBox(height: 100)); // prevent FAB overlap
    return Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final nameDescription = await showPlatformDialog(
                context: context,
                builder: (_) {
                  final result = {"name": widget.release.name, "description": widget.release.description};
                  return PlatformAlertDialog(
                    title: const Text("Set Name and Description"),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PlatformTextFormField(
                          hintText: "Name",
                          initialValue: widget.release.name,
                          onChanged: (newValue) => result["name"] = newValue,
                        ),
                        PlatformTextFormField(
                          hintText: "Description",
                          maxLines: 8,
                          minLines: 8,
                          initialValue: widget.release.description,
                          onChanged: (newValue) => result["description"] = newValue,
                        ),
                      ],
                    ),
                    actions: <Widget>[
                      PlatformDialogAction(child: PlatformText('Cancel'), onPressed: () => Navigator.pop(context)),
                      PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, result)),
                    ],
                  );
                });
            if (nameDescription == null) return;
            await SmartServiceService.createInstance(
                widget.release.id, parameters!.map((e) => e.toSmartServiceParameter()).toList(), nameDescription["name"], nameDescription["description"]);
            Navigator.pop(this.context);
          },
          backgroundColor: MyTheme.appColor,
          label: Text("Start", style: TextStyle(color: MyTheme.textColor)),
          icon: Icon(Icons.play_arrow, color: MyTheme.textColor),
        ),
        body: PlatformScaffold(
            appBar: appBar.getAppBar(context, MyAppBar.getDefaultActions(context)),
            body: Scrollbar(
                child: parameters == null
                    ? Center(child: PlatformCircularProgressIndicator())
                    : ListView.builder(itemCount: configs.length, itemBuilder: (_, i) => configs[i]))));
  }
}
