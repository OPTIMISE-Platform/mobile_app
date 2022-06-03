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
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';

import '../../../models/smart_service.dart';
import '../../../theme.dart';
import '../../shared/expandable_text.dart';

class SmartServicesInstanceDetails extends StatefulWidget {
  final SmartServiceInstance instance;

  const SmartServicesInstanceDetails(this.instance, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SmartServicesInstanceDetailsState();
}

class _SmartServicesInstanceDetailsState extends State<SmartServicesInstanceDetails> {
  List<SmartServiceExtendedParameter>? parameters;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      parameters = await SmartServiceService.getReleaseParameters(widget.instance.release_id);
      widget.instance.parameters?.forEach((iParam) => parameters!.firstWhere((extParam) => iParam.id == extParam.id).value = iParam.value);
      setState(() => {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final appBar = MyAppBar(widget.instance.name);
    return Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            // TODO
          },
          backgroundColor: MyTheme.appColor,
          child: Icon(Icons.edit, color: MyTheme.textColor),
        ),
        body: PlatformScaffold(
            appBar: appBar.getAppBar(context, MyAppBar.getDefaultActions(context)),
            body: Scrollbar(
              child: parameters == null
                  ? Center(child: PlatformCircularProgressIndicator())
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: MyTheme.inset,
                      itemCount: parameters!.length + 2,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return ListTile(
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
                            title: Text(widget.instance.name),
                            subtitle: ExpandableText(widget.instance.description, 3),
                            trailing: PlatformIconButton(
                              onPressed: () async {
                                final deleted = await showPlatformDialog(
                                    context: context,
                                    builder: (context) => PlatformAlertDialog(
                                          title: const Text("Do you want to permanently delete this service?"),
                                          actions: [
                                            PlatformDialogAction(
                                              child: PlatformText('Cancel'),
                                              onPressed: () => Navigator.pop(context),
                                            ),
                                            PlatformDialogAction(
                                                child: PlatformText('Delete'),
                                                cupertino: (_, __) => CupertinoDialogActionData(isDestructiveAction: true),
                                                onPressed: () async {
                                                  await SmartServiceService.deleteInstance(widget.instance.id);
                                                  Navigator.pop(this.context, true);
                                                })
                                          ],
                                        ));
                                if (deleted == true) {
                                  Navigator.pop(this.context);
                                }
                              },
                              icon: Icon(PlatformIcons(context).delete),
                              cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
                            ),
                          );
                        }
                        if (i == parameters!.length + 1) {
                          return const SizedBox(height: 72); // prevent FAB overlap
                        }
                        return Column(children: [
                          const Divider(),
                          ListTile(
                            title: Text(parameters![i - 1].label),
                            trailing: Text(parameters![i - 1].value.toString()),
                            subtitle: ExpandableText(parameters![i - 1].description, 1),
                          )
                        ]);
                      },
                    ),
            )));
  }
}
