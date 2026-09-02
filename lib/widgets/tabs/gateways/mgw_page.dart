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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/storage.dart';

import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:nsd/nsd.dart';
import 'package:provider/provider.dart';

const double TOP_PADDING = 100;
const textStyle = TextStyle(color: Colors.white, fontSize: 35);

final _logger = Logger(
  printer: SimplePrinter(),
);

/// Asks for the gateway's basic-auth password and stores it.
///
/// Returns whether a password was entered: on cancel the caller must not go on
/// to register the gateway, or it lands in the paired list with no credentials
/// and every later request against it fails.
Future<bool> pairWithBasicAuth(BuildContext context, MGW mgw) async {
  // TODO remove pairing with basic auth credentials
  // Controller per invocation, not a global one: it holds the password, and a
  // global keeps it in memory for the process and pre-fills the next pairing.
  final controller = TextEditingController();
  try {
    final stored = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Password'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(hintText: "Password"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('CANCEL'),
              onPressed: () {
                Navigator.pop(context, false);
              },
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () async {
                if (controller.text.isEmpty) {
                  Navigator.pop(context, false);
                  return;
                }
                await MgwStorage.StoreBasicAuthCredentials(controller.text);
                if (!context.mounted) return;
                Navigator.pop(context, true);
              },
            ),
          ],
        );
      },
    );
    return stored ?? false;
  } finally {
    controller.dispose();
  }
}

Future<List<MGW>> DiscoverLocalGatewayHosts() async {
  _logger.d("Discover local gateways...");
  Discovery discovery = await startDiscovery('_snrgy._tcp', ipLookupType: IpLookupType.any);
  List<MGW> gateways = [];
  List<String> foundHostnames = [];
  discovery.addListener(() {
    discovery.services.forEach((service) {
      _logger.d("Found service: $service");
      var hostname = service.host??"";
      var serviceName = service.name??"";
      var coreId = utf8.decode(service.txt?["serial"]??[]);

      var ip = service.addresses?[0].address??"";
      if(!foundHostnames.contains(hostname)) {
        var gateway = MGW(hostname, serviceName, coreId, ip);
        gateways.add(gateway);
      }
      foundHostnames.add(hostname);
    });
  });
  await Future.delayed(Duration(seconds: 5));

  await stopDiscovery(discovery);
  return gateways;
}

Future<void> PairWithGateway(MGW mgw) async {
  var host = mgw.ip;
  MgwAuthService authService = MgwAuthService(host);

  _logger.d("Pair with gateway: $host");
  DeviceUserCredentials credentials = await authService.RegisterDevice();
  _logger.d("Paired successfully with gateway: $host");

  _logger.d("Store device credentials");
  await MgwStorage.StoreCredentials(credentials);
  _logger.d("Stored credentials");
}

Future<void> StoreGateway(MGW mgw, AppState appState) async {
  _logger.d("Store paired mgw");
  await MgwStorage.StorePairedMGW(mgw);
  _logger.d("Stored mgw");

  appState.gateways.add(mgw);
}

Future<void> StartPairing(MGW mgw, AppState appState, BuildContext widgetBuildContext, BuildContext context) async {
  try {
    _logger.d("Try to pair token based");
    await PairWithGateway(mgw);
    await StoreGateway(mgw, appState);
  } on Failure catch (e) {
    _logger.e("Pairing is not possible: ${e.detailedMessage}");
    if (e.errorCode == ErrorCode.UNAUTHORIZED) {
      // MGW is still using basic auth protection -> ask user for password
      try {
        _logger.d("Try to pair basic auth based");
        if (!widgetBuildContext.mounted) {
          // Nothing left to ask on: say so rather than closing the sheet as if
          // the gateway had been paired.
          _logger.e("Cannot ask for the password, the page is gone");
          Toast.showToastNoContext("Pairing was not possible");
        } else if (await pairWithBasicAuth(widgetBuildContext, mgw)) {
          await StoreGateway(mgw, appState);
        } else {
          // Cancelled or left empty - registering the gateway now would add it
          // to the list without credentials.
          Toast.showToastNoContext("Pairing needs the gateway password");
        }
      } catch (e) {
        _logger.e("Pairing is not possible: $e");
        Toast.showToastNoContext(
            "Pairing was not possible");
      }
    } else {
      Toast.showToastNoContext(
          "Pairing was not possible. Check if pairing mode is enabled!");
    }
  }
  if (!context.mounted) return;
  Navigator.pop(context);
}

class AddLocalNetwork extends StatefulWidget {
  const AddLocalNetwork({Key? key}) : super(key: key);

  @override
  _AddLocalNetworkState createState() => _AddLocalNetworkState();
}

class _AddLocalNetworkState extends State<AddLocalNetwork> {
  // Held in state: constructing the future inside build restarted the 5s mDNS
  // discovery on every AppState notify, racing the previous run's stop. The
  // _searching flag keeps the refresh button from starting an overlapping run.
  late Future<List<MGW>> _discovery;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _discovery = _runDiscovery();
  }

  Future<List<MGW>> _runDiscovery() async {
    _searching = true;
    try {
      return await DiscoverLocalGatewayHosts();
    } finally {
      _searching = false;
      if (mounted) setState(() {});
    }
  }

  handleData(List<MGW> mgws, AppState appState, widgetBuildContext) {
    if (mgws.length == 0) {
      return const Column(
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 40,
            ),
            Padding(
              padding: EdgeInsets.only(top: TOP_PADDING),
              child: Text('No gateways found'),
            ),
          ]);
    }

    return Material(
        child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: MyTheme.inset,
            itemCount: mgws.length,
            itemBuilder: (BuildContext context, int index) {
              var mgw = mgws.elementAt(index);
              return Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: ListTile(
                    title: Text(mgw.mDNSServiceName),
                    trailing: MaterialButton(
                        child: const Icon(
                            Icons.add
                        ),
                        onPressed: () => StartPairing(mgw, appState, widgetBuildContext, context)
                    )
                  )
              );
            }
        )
    );
  }

  handleError(error) {
    return Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: TOP_PADDING),
            child: Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 40,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: TOP_PADDING),
            child: Text('Error: $error', style: textStyle),
          ),
        ]);
  }

  handleLoading() {
    return const Column(
        crossAxisAlignment: CrossAxisAlignment.center,
      children: [
          Padding(
            padding: EdgeInsets.only(top: TOP_PADDING),
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: TOP_PADDING),
            child: Text('Search...', style: textStyle),
          )
        ]);
  }

  handleResponse(servicesWrapper, AppState appState, context) {
    if (servicesWrapper.hasData) {
      return handleData(servicesWrapper.data!, appState, context);
    }
    if (servicesWrapper.hasError) {
      return handleError(servicesWrapper.error);
    }
    return handleLoading();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      return Scaffold(
          appBar: AppBar(
            title: const Text("Gateways"),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: "Search again",
                onPressed: _searching
                    ? null
                    : () => setState(() => _discovery = _runDiscovery()),
              ),
            ],
          ),
          body: FutureBuilder(
              future: _discovery,
              builder: (BuildContext context,
                  AsyncSnapshot<List<MGW>> servicesWrapper) {
                return handleResponse(servicesWrapper, state, context);
              })
      );
    });
  }
}
