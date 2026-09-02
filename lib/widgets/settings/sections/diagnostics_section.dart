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

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart' as settings_service;
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:share_plus/share_plus.dart';

/// Debug information, the exception log, and the server endpoints.
List<Widget> diagnosticsSection(BuildContext context, AppState state) {
  final children = <Widget>[
    const Divider(),
    ListTile(
        title: const Text("Show Debug Information"),
        onTap: () async {
          var txt = "Version: ${dotenv.env["VERSION"]}\n"
              "Username: ${Auth().getUsername()}\n"
              "FCM Token (SHA1): ${sha1.convert(utf8.encode(state.fcmToken ?? ""))}\n"
              "Local Mode:  ${settings_service.Settings.getLocalMode()}\n\n"
              "Keycloak Url: ${settings_service.Settings.getKeycloakUrl()}\n"
              "Keycloak Redirect: ${settings_service.Settings.getKeycloakRedirect()}\n"
              "Api Url: ${settings_service.Settings.getApiUrl()}\n";
          if (isar != null) {
            final ex = await isar!.exceptionLogElements.where().findAll();
            if (ex.isNotEmpty) {
              txt += "\nException Log:\n";
              ex.forEach((e) => txt += "$e\n\n");
            }
          }
          if (!context.mounted) return;
          showAdaptiveDialog(
            context: context,
            builder: (context) => AlertDialog.adaptive(
              title: Row(children: [
                const Text("Debug"),
                const Spacer(),
                IconButton(
                    icon: Icon(Icons.share),
                    onPressed: () => Share.share(
                        "OPTIMISE Debug Information\n$txt",
                        subject: "OPTIMISE Debug Information"))
              ]),
              content: Scrollbar(
                  child: SingleChildScrollView(
                      child: Text(
                txt,
                textAlign: TextAlign.left,
              ))),
              actions: [
                TextButton(
                    child: const Text("Clear Log"),
                    onPressed: () async {
                      if (isar != null) {
                        await isar!.writeTxn(() async => await isar!
                            .exceptionLogElements
                            .where()
                            .deleteAll());
                      }
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    }),
                TextButton(
                    child: const Text("Close"),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          );
        })
  ];

  if (kDebugMode) {
    children.addAll([
      const Divider(),
      ListTile(
        leading: const Icon(Icons.bug_report),
        title: const Text("Delete FCM Token"),
        onTap: () async {
          await state.messaging.deleteToken();
          await state.messaging
              .getToken(vapidKey: dotenv.env["FireBaseVapidKey"]);
          Toast.showToastNoContext("OK");
        },
      ),
    ]);
  }

  children.addAll([
    const Divider(),
    ListTile(
      title: const Text("Server Settings"),
      onTap: () async {
        String? keycloakUrl = settings_service.Settings.getKeycloakUrl();
        String? keycloakRedirect =
            settings_service.Settings.getKeycloakRedirect();
        String? apiUrl = settings_service.Settings.getApiUrl();

        await showAdaptiveDialog(
          context: context,
          builder: (context) => AlertDialog.adaptive(
            title: const Text("Edit Server Settings"),
            content: Column(
              children: [
                TextFormField(
                    decoration: InputDecoration(hintText: "Keycloak Url"),
                    initialValue: keycloakUrl,
                    keyboardType: TextInputType.url,
                    autovalidateMode: AutovalidateMode.always,
                    onChanged: (value) {
                      keycloakUrl = value;
                    }),
                TextFormField(
                    decoration: InputDecoration(hintText: "Keycloak Redirect"),
                    initialValue: keycloakRedirect,
                    keyboardType: TextInputType.url,
                    autovalidateMode: AutovalidateMode.always,
                    onChanged: (value) {
                      keycloakRedirect = value;
                    }),
                TextFormField(
                    decoration: InputDecoration(hintText: "Api Url"),
                    initialValue: apiUrl,
                    keyboardType: TextInputType.url,
                    autovalidateMode: AutovalidateMode.always,
                    onChanged: (value) {
                      apiUrl = value;
                    }),
              ],
            ),
            actions: [
              TextButton(
                  child: const Text("Reset"),
                  onPressed: () async {
                    await settings_service.Settings.setKeycloakUrl(null);
                    await settings_service.Settings.setKeycloakRedirect(null);
                    await settings_service.Settings.setApiUrl(null);
                    Toast.showToastNoContext(
                        "Reset done, consider logging out");
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  }),
              TextButton(
                  child: const Text("Close"),
                  onPressed: () => Navigator.pop(context)),
              TextButton(
                  child: const Text("Save"),
                  onPressed: () async {
                    await settings_service.Settings.setKeycloakUrl(keycloakUrl);
                    await settings_service.Settings.setKeycloakRedirect(
                        keycloakRedirect);
                    await settings_service.Settings.setApiUrl(apiUrl);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  }),
            ],
          ),
        );
      },
    ),
  ]);

  return children;
}
