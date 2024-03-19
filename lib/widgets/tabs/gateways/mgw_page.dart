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

TextEditingController _textFieldController = TextEditingController();

Future<void> pairWithBasicAuth(BuildContext context, MGW mgw) async {
  // TODO remove pairing with basic auth credentials
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Password'),
        content: TextField(
          controller: _textFieldController,
          decoration: InputDecoration(hintText: "Password"),
        ),
        actions: <Widget>[
          TextButton(
            child: Text('CANCEL'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          TextButton(
            child: Text('OK'),
            onPressed: () async {
              var password = _textFieldController.text;
              await MgwStorage.StoreBasicAuthCredentials(password);
              Navigator.pop(context);
            },
          ),
        ],
      );
    },
  );
}

Future<List<MGW>> DiscoverLocalGatewayHosts() async {
  _logger.d("Discover local gateways...");
  Discovery discovery = await startDiscovery('_snrgy._tcp', ipLookupType: IpLookupType.any);
  List<MGW> gateways = [];
  List<String> foundHostnames = [];
  discovery.addListener(() {
    discovery.services.forEach((service) {
      _logger.d("Found service: " + service.toString());
      var hostname = service.host??"";
      var serviceName = service.name??"";
      var coreId = utf8.decode(service.txt?["core-id"]??[]);

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

  _logger.d("Pair with gateway: "+ host);
  DeviceUserCredentials credentials = await authService.RegisterDevice();
  _logger.d("Paired successfully with gateway: "+ host);

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

class AddLocalNetwork extends StatefulWidget {
  const AddLocalNetwork({Key? key}) : super(key: key);

  @override
  _AddLocalNetworkState createState() => _AddLocalNetworkState();
}

class _AddLocalNetworkState extends State<AddLocalNetwork> {
  handleData(List<MGW> mgws, AppState appState, widgetBuildContext) {
    if (mgws.length == 0) {
      return Column(
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 40,
            ),
            Padding(
              padding: const EdgeInsets.only(top: TOP_PADDING),
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
                    title: Text(mgw.mDNSServiceName ?? "No name provided"),
                    trailing: MaterialButton(
                        child: Icon(
                            Icons.add
                        ),
                        onPressed: () async {
                          try {
                            _logger.d("Try to pair token based");
                            await PairWithGateway(mgw);
                            await StoreGateway(mgw, appState);
                          } on Failure catch (e) {
                            _logger.e("Pairing is not possible: " + e.detailedMessage);
                            if (e.errorCode == ErrorCode.UNAUTHORIZED) {
                              // MGW is still using basic auth protection -> ask user for password
                              try {
                                _logger.d("Try to pair basic auth based");
                                await pairWithBasicAuth(widgetBuildContext, mgw);
                                await StoreGateway(mgw, appState);
                              } catch (e) {
                                _logger.e("Pairing is not possible: " + e.toString());
                                Toast.showToastNoContext(
                                    "Pairing was not possible");
                              }
                            } else {
                              Toast.showToastNoContext(
                                  "Pairing was not possible. Check if pairing mode is enabled!");
                            }
                          }
                          Navigator.pop(context);
                        }
                    ),
                  )
              );
            }
        )
    );
  }

  handleError(error) {
    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: TOP_PADDING),
            child: const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 40,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: TOP_PADDING),
            child: Text('Error: ${error}', style: textStyle),
          ),
        ]);
  }

  handleLoading() {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
      children: [
          Padding(
            padding: const EdgeInsets.only(top: TOP_PADDING),
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
            title: Text("Gateways"),
          ),
          body: FutureBuilder(
              future: DiscoverLocalGatewayHosts(),
              builder: (BuildContext context,
                  AsyncSnapshot<List<MGW>> servicesWrapper) {
                return handleResponse(servicesWrapper, state, context);
              })
      );
    });
  }
}
