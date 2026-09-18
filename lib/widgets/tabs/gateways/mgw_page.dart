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

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/mgw/advertisements.dart';
import 'package:mobile_app/services/mgw/discovery.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:mobile_app/services/mgw/storage.dart';

import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:provider/provider.dart';

const double TOP_PADDING = 100;
const textStyle = TextStyle(color: Colors.white, fontSize: 35);

final _logger = Logger(
  printer: SimplePrinter(),
);

Future<List<MGW>> DiscoverLocalGatewayHosts() async {
  _logger.d("Discover local gateways...");
  final found = await MgwDiscoveryService.discover();
  return found.map((g) {
    final host = g.ip.isEmpty ? g.hostname : g.ip;
    // Carry the advertised port: a core is not necessarily on the default one.
    final address =
        g.port == defaultGatewayPort ? host : "$host:${g.port}";
    return MGW(g.hostname, g.name, g.coreId, address);
  }).toList();
}

/// Asks which cloud network the gateway serves.
///
/// Only the fallback: the gateway publishes this itself under /core/discovery,
/// see [MgwAdvertisements]. It is asked when nothing is published - a gateway
/// whose cloud proxy is not signed in - because without the binding the app
/// pairs successfully and still never talks to the gateway.
Future<Network?> _askForNetwork(BuildContext context, AppState appState) async {
  if (appState.networks.isEmpty) {
    Toast.showToastNoContext("No networks loaded yet");
    return null;
  }
  return showDialog<Network>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text("Which network does this gateway serve?"),
      children: appState.networks
          .map((n) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, n),
                child: Text(n.name),
              ))
          .toList(),
    ),
  );
}

/// Asks for a gateway's host or address.
Future<String?> _askForHost(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _HostDialog());

/// Owns the text controller so it outlives the dialog's closing animation.
///
/// Disposing it right after [showDialog] returns is too early: that future
/// completes on the pop, while the route animates out and its text field keeps
/// rebuilding - and rebuilding re-subscribes to the controller, which then
/// throws for having been disposed.
class _HostDialog extends StatefulWidget {
  const _HostDialog();

  @override
  State<_HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<_HostDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Gateway address"),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(hintText: "Host or IP"),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('OK'),
        ),
      ],
    );
  }
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
  // Without this the gateway stays unused until the next network load.
  await appState.mergeGatewaysWithNetworks();
}

Future<void> StartPairing(MGW mgw, AppState appState, BuildContext context) async {
  try {
    _logger.d("Try to pair token based");
    await PairWithGateway(mgw);
    await StoreGateway(mgw, appState);
  } on Failure catch (e) {
    _logger.e("Pairing is not possible: ${e.detailedMessage}");
    // Pairing without an open pairing window is the common failure and the
    // gateway reports it as a 500 with "no credential session open", which
    // names the cause but not the remedy - so keep the hint for that case and
    // let the gateway speak for every other one.
    Toast.showToastNoContext(e.errorCode == ErrorCode.SERVER_ERROR
        ? "Pairing was not possible. Check if pairing mode is enabled! (${e.detailedMessage})"
        : "Pairing was not possible: ${e.detailedMessage}");
  }
  if (!context.mounted) return;
  Navigator.pop(context);
}

class AddLocalNetwork extends StatefulWidget {
  const AddLocalNetwork({super.key});

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

  /// Pairs a gateway the user entered by hand.
  ///
  /// Needed beside discovery because a core that does not advertise - the
  /// installer makes that optional - is otherwise unreachable for the app.
  Future<void> _addManually(AppState appState) async {
    final host = await _askForHost(context);
    if (host == null || host.isEmpty || !mounted) return;
    final network = await _networkFor(host, appState);
    if (network == null || !mounted) return;
    await StartPairing(
        MGW(host, host, "", host, networkId: network.id), appState, context);
  }

  Future<void> _pairDiscovered(MGW mgw, AppState appState) async {
    final network = await _networkFor(mgw.ip, appState);
    if (network == null || !mounted) return;
    mgw.networkId = network.id;
    await StartPairing(mgw, appState, context);
  }

  /// The network the gateway serves.
  ///
  /// The gateway publishes it under /core/discovery and needs no session for
  /// that, so asking is the fallback rather than the rule: it is left for a
  /// gateway that publishes nothing - its cloud proxy is not signed in - or one
  /// that names a network this account does not have.
  Future<Network?> _networkFor(String host, AppState appState) async {
    final advertised = await MgwAdvertisements.networkIdOf(host);
    if (advertised.isNotEmpty) {
      final match = appState.networks.where((n) => n.id == advertised);
      if (match.isNotEmpty) return match.first;
      _logger.d(
          "Gateway serves $advertised, which is not among the loaded networks");
    }
    if (!mounted) return null;
    return _askForNetwork(context, appState);
  }

  handleData(List<MGW> mgws, AppState appState, widgetBuildContext) {
    if (mgws.isEmpty) {
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
                        onPressed: () => _pairDiscovered(mgw, appState)
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
                icon: const Icon(Icons.add),
                tooltip: "Add by address",
                onPressed: () => _addManually(state),
              ),
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
