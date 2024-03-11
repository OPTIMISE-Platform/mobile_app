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

final _logger = Logger(
  printer: SimplePrinter(),
);

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

      var ip = service.addresses?[0].host??"";
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

Future<void> PairWithGateway(String host) async {
  MgwAuthService authService = MgwAuthService(host);

  _logger.d("Pair with gateway: "+ host);
  DeviceUserCredentials credentials = await authService.RegisterDevice();
  _logger.d("Paired successfully with gateway: "+ host);

  _logger.d("Store device credentials");
  await MgwStorage.StoreCredentials(credentials);
  _logger.d("Stored credentials");
}

const double TOP_PADDING = 100;
const textStyle = TextStyle(color: Colors.white, fontSize: 35);

class AddLocalNetwork extends StatelessWidget {
  const AddLocalNetwork({Key? key}) : super(key: key);

  handleData(List<MGW> mgws, AppState appState) {
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
                          var ip = mgw.ip;
                          try {
                            await PairWithGateway(ip);
                            appState.gateways.add(mgw);
                          } on Failure catch (e) {
                            if (e.errorCode == ErrorCode.SERVER_ERROR) {
                              // TODO dont use 500 to inidcate that pairing is closed
                              Toast.showToastNoContext(
                                  "Pairing was not possible. Check if pairing mode is enabled!");
                            } else {
                              Toast.showToastNoContext(
                                  "Pairing was not possible!");
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

  handleResponse(servicesWrapper, AppState appState) {
    if (servicesWrapper.hasData) {
      return handleData(servicesWrapper.data!, appState);
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
                return handleResponse(servicesWrapper, state);
              })
      );
    });
  }
}
