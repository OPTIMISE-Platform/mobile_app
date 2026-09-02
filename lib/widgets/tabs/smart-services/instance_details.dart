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
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/toast.dart';

import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/expandable_text.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_edit_launch.dart';

class SmartServicesInstanceDetails extends StatefulWidget {
  final SmartServiceInstance instance;
  final BuildContext? parentContext;

  const SmartServicesInstanceDetails(this.instance, this.parentContext, {super.key});

  @override
  State<StatefulWidget> createState() => _SmartServicesInstanceDetailsState();
}

class _SmartServicesInstanceDetailsState extends State<SmartServicesInstanceDetails> {
  @override
  Widget build(BuildContext context) {
    final appBar = MyAppBar(widget.instance.name);

    final List<Widget> trailingHeader = [];

    if (widget.instance.error != null) {
      trailingHeader.add(Tooltip(
          message: widget.instance.error, triggerMode: TooltipTriggerMode.tap, child: const Icon(Icons.error, color: MyTheme.warnColor)));
    }

    trailingHeader.add(IconButton(
      onPressed: () async {
        final deleted = await showAdaptiveDialog(
            context: context,
            builder: (dialogContext) => AlertDialog.adaptive(
                  title: const Text("Do you want to permanently delete this service?"),
                  actions: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                    TextButton(
                        child: const Text('Delete'),
                        onPressed: () async {
                          final f = SmartServiceService.deleteInstance(widget.instance.id);
                          f.catchError(
                              (_) => Toast.showToastNoContext("Could not delete Smart Service ${widget.instance.name}"));
                          await Future.any([f, Future.delayed(const Duration(milliseconds: 500))]);
                          if (!mounted) return;
                          Navigator.pop(this.context, true);
                        })
                  ],
                ));
        if (deleted == true) {
          if (!mounted) return;
          Navigator.pop(this.context);
        }
      },
      icon: const Icon(Icons.delete),
    ));

    return Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            try {
              final release = await SmartServiceService.getRelease(widget.instance.release_id);
              final parameters = await SmartServiceService.getReleaseParameters(widget.instance.release_id);
              for (SmartServiceExtendedParameter p in parameters) {
                final existing = widget.instance.parameters!.firstWhere((extisting) => p.id == extisting.id);
                p.value = existing.value;
                p.value_label = existing.value_label;
              }
              if (!mounted) return;
              await Navigator.push(
                  this.context,
                  MaterialPageRoute(
                    builder: (_) => SmartServicesReleaseLaunch(
                      release,
                      instance: widget.instance,
                      parameters: parameters,
                    ),
                  ));
              if (!mounted) return;
              Navigator.pop(this.context);
            } catch (e) {
              Toast.showToastNoContext(e.toString());
            }
          },
          backgroundColor: MyTheme.appColor,
          child: Icon(Icons.edit, color: MyTheme.textColor),
        ),
        body: Scaffold(
            appBar: appBar.getAppBar(
                context,
                [
                  IconButton(
                    onPressed: () async {
                      final nameDescription = await showAdaptiveDialog(
                          context: context,
                          builder: (_) {
                            final result = {"name": widget.instance.name, "description": widget.instance.description};
                            return AlertDialog.adaptive(
                              title: const Text("Set Name and Description"),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextFormField(
                                    decoration: const InputDecoration(hintText: "Name"),
                                    initialValue: widget.instance.name,
                                    onChanged: (newValue) => result["name"] = newValue,
                                  ),
                                  TextFormField(
                                    decoration: const InputDecoration(hintText: "Description"),
                                    maxLines: 8,
                                    minLines: 8,
                                    initialValue: widget.instance.description,
                                    onChanged: (newValue) => result["description"] = newValue,
                                  ),
                                ],
                              ),
                              actions: <Widget>[
                                TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(context)),
                                TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context, result)),
                              ],
                            );
                          });
                      if (nameDescription == null) return;

                      final updated =
                          await SmartServiceService.updateInstanceInfo(widget.instance.id, nameDescription["name"], nameDescription["description"]);
                      widget.instance.name = updated.name;
                      widget.instance.description = updated.description;
                      setState(() {});
                    },
                    icon: const Icon(Icons.edit),
                  ), ...MyAppBar.getDefaultActions(context)
                ]),
            body: Scrollbar(
              child: widget.instance.parameters == null
                  ? const Center(child: DelayedCircularProgressIndicator())
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: MyTheme.inset,
                      itemCount: widget.instance.parameters!.length + 2,
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
                                child: const Icon(Icons.auto_fix_high, color: Colors.white),
                              ),
                            ),
                            title: Text(widget.instance.name),
                            subtitle: ExpandableText(widget.instance.description, 3),
                            trailing: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: trailingHeader),
                          );
                        }
                        if (i == widget.instance.parameters!.length + 1) {
                          return const SizedBox(height: 72); // prevent FAB overlap
                        }
                        return Column(children: [
                          const Divider(),
                          ListTile(
                            title: Text(widget.instance.parameters![i - 1].label),
                            trailing: Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .5 - 12),
                                child: Text(widget.instance.parameters![i - 1].value_label ?? widget.instance.parameters![i - 1].value.toString())),
                          )
                        ]);
                      },
                    ),
            )));
  }
}
