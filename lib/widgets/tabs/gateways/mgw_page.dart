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
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_error_block.dart';
import 'package:provider/provider.dart';

final _logger = Logger(
  printer: SimplePrinter(),
);

MGW _toMgw(DiscoveredGateway g) =>
    MGW(g.hostname, g.name, g.coreId, g.address);

/// Gateways on the local network. [onUpdate] gets them as they come in.
Future<List<MGW>> DiscoverLocalGatewayHosts(
    {void Function(List<MGW> found)? onUpdate}) async {
  _logger.d("Discover local gateways...");
  final found = await MgwDiscoveryService.discover(
      onUpdate: onUpdate == null
          ? null
          : (found) => onUpdate(found.map(_toMgw).toList()));
  return found.map(_toMgw).toList();
}

/// Why pairing did not work, in the words shown on the page.
class PairingFailure implements Exception {
  const PairingFailure(this.message, {this.hint});

  /// The gateway's message, or the error when it did not answer.
  final String message;

  /// What to do about it, where that is known.
  final String? hint;

  static const pairingModeHint =
      "The gateway accepts a new phone only in pairing mode. Turn pairing "
      "mode on at the gateway and try again.";

  static const noNetworks = PairingFailure("No networks are loaded yet.",
      hint: "Open the networks list once so they load, then try again.");

  static const sameNetworkHint =
      "Check that this phone is on the same network as the gateway.";

  factory PairingFailure.of(Object error) {
    final message = describeMgwError(error);
    if (error is Failure) {
      // Pairing without an open pairing window is the common failure, and the
      // gateway reports it as a 500 that names the cause but not the remedy.
      if (error.errorCode == ErrorCode.SERVER_ERROR ||
          error.detailedMessage.contains("credential session")) {
        return PairingFailure(message, hint: pairingModeHint);
      }
      if (MgwReachability.classify(error.errorCode) == MgwStatus.unreachable) {
        return PairingFailure(message, hint: sameNetworkHint);
      }
    }
    return PairingFailure(message);
  }
}

/// Asks which cloud network the gateway serves.
///
/// Only the fallback: the gateway publishes this itself under /core/discovery,
/// see [MgwAdvertisements]. It is asked when nothing is published - a gateway
/// whose cloud proxy is not signed in - because without the binding the app
/// pairs successfully and still never talks to the gateway.
Future<Network?> askForNetwork(BuildContext context, List<Network> networks) {
  return showDialog<Network>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Which network does this gateway serve?"),
      contentPadding: const EdgeInsets.symmetric(vertical: Spacing.md),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: networks
              .map((n) => ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: Spacing.xl),
                    leading: const Icon(Icons.hub_outlined),
                    title: Text(n.name, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, n),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
      ],
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
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final address = parseGatewayInput(_controller.text);
    if (address == null) {
      setState(() => _error =
          "Enter a host name or IP address, optionally with a port.");
      return;
    }
    Navigator.pop(context, address);
  }

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
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: "Host or IP",
          hintText: "192.168.1.5 or 192.168.1.5:8081",
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text("Continue"),
        ),
      ],
    );
  }
}

/// Registers this phone with [mgw] and stores the entry in place of
/// [replacing], with the credentials the gateway issued under its pairing id.
/// Returns the entry as stored.
///
/// Entry and credentials are stored in one step, so a failure leaves no
/// credentials under an id no entry carries; the secrets of other gateways
/// stay as they are.
Future<MGW> PairWithGateway(MGW mgw, {MGW? replacing}) async {
  final host = mgw.ip;
  final authService = MgwAuthService(host);

  _logger.d("Pair with gateway: $host");
  final credentials = await authService.RegisterDevice();
  _logger.d("Paired successfully with gateway: $host");

  final stored = await MgwStorage.StorePairedMGW(mgw,
      replacing: replacing, credentials: credentials);
  _logger.d("Stored mgw and its credentials");
  return stored;
}

/// Brings the app's gateway list and routing up to date after a pairing.
Future<void> _applyPairing(AppState appState) async {
  // Reloaded rather than appended: pairing again replaces the stored entry.
  await appState.loadStoredMGWs();
  // A status from before the pairing would keep the gateway unused.
  MgwReachability.forget();
  // Without this the gateway stays unused until the next network load.
  await appState.mergeGatewaysWithNetworks();
}

/// Pairs with [mgw] and stores it in place of [replacing]: the entry as stored
/// on success, the failure otherwise.
Future<({MGW? stored, PairingFailure? failure})> pairAndStore(
    MGW mgw, AppState appState,
    {MGW? replacing}) async {
  try {
    _logger.d("Try to pair token based");
    final stored = await PairWithGateway(mgw, replacing: replacing);
    await _applyPairing(appState);
    return (stored: stored, failure: null);
  } catch (e, s) {
    ErrorReporter.log("Pairing with ${mgw.ip} failed", e, s);
    return (stored: null, failure: PairingFailure.of(e));
  }
}

/// Finds gateways on the local network and pairs this phone with one.
class AddLocalNetwork extends StatefulWidget {
  const AddLocalNetwork({super.key});

  @override
  State<AddLocalNetwork> createState() => _AddLocalNetworkState();
}

class _AddLocalNetworkState extends State<AddLocalNetwork> {
  /// Row key while pairing with a discovered gateway, [_manualKey] while
  /// pairing one entered by hand.
  static const _manualKey = "";

  List<MGW> _found = const [];
  bool _searching = false;
  Object? _searchError;
  String? _pairing;
  PairingFailure? _pairFailure;

  /// Counts searches, so updates of a search that was replaced are dropped.
  int _search = 0;

  bool get _busy => _pairing != null;

  @override
  void initState() {
    super.initState();
    _runDiscovery();
  }

  Future<void> _runDiscovery() async {
    // Not overlapping: the platform discovery of a second run would race the
    // stop of the first.
    if (_searching) return;
    final run = ++_search;
    void update(void Function() change) {
      if (mounted && run == _search) setState(change);
    }

    update(() {
      _searching = true;
      _searchError = null;
      _pairFailure = null;
      _found = const [];
    });
    try {
      final found = await DiscoverLocalGatewayHosts(
          onUpdate: (found) => update(() => _found = found));
      update(() => _found = found);
    } catch (e, s) {
      ErrorReporter.log("Could not search for gateways", e, s);
      update(() => _searchError = e);
    } finally {
      update(() => _searching = false);
    }
  }

  /// Pairs a gateway the user entered by hand.
  ///
  /// Needed beside discovery because a core that does not advertise - the
  /// installer makes that optional - is otherwise unreachable for the app.
  Future<void> _addManually(AppState appState) async {
    final host = await _askForHost(context);
    if (host == null || host.isEmpty || !mounted) return;
    await _pair(MGW(host, host, "", host), _manualKey, appState);
  }

  Future<void> _pair(MGW mgw, String key, AppState appState) async {
    setState(() {
      _pairing = key;
      _pairFailure = null;
    });
    PairingFailure? failure;
    try {
      final network = await _networkFor(mgw.ip, appState);
      if (network == null) return;
      failure = (await pairAndStore(
              MGW(mgw.hostname, mgw.mDNSServiceName, mgw.coreId, mgw.ip,
                  networkId: network.id),
              appState))
          .failure;
    } on PairingFailure catch (e) {
      failure = e;
    } finally {
      if (mounted) {
        setState(() {
          _pairing = null;
          _pairFailure = failure;
        });
      }
    }
    if (!mounted) {
      // Only here a toast: the page that would show the failure is gone.
      if (failure != null) {
        Toast.showToastNoContext("Pairing was not possible: ${failure.message}");
      }
      return;
    }
    if (failure == null) Navigator.pop(context);
  }

  /// The network the gateway serves, null when the user cancelled.
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
    if (appState.networks.isEmpty) throw PairingFailure.noNetworks;
    if (!mounted) return null;
    return askForNetwork(context, appState.networks);
  }

  /// A discovered gateway with a core id is paired only under that id: an
  /// entry added by address carries none and may be another gateway that
  /// answered there once.
  bool _isPaired(MGW found, AppState state) => found.coreId.isNotEmpty
      ? state.gateways.any((g) => g.coreId == found.coreId)
      : state.gateways.any((g) => MgwStorage.isSameGateway(g, found));

  Widget _row(BuildContext context, MGW mgw, SlicePosition position,
      AppState state) {
    final pairingThis = _pairing == mgw.hostname;
    final paired = _isPaired(mgw, state);
    void pair() => _pair(mgw, mgw.hostname, state);
    final Widget trailing;
    if (pairingThis) {
      trailing = const SizedBox.square(
          dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5));
    } else if (paired) {
      // Pairing again stays possible: it is the remedy for a gateway that
      // forgot this phone.
      trailing = OutlinedButton(
        onPressed: _busy ? null : pair,
        child: const Text("Pair again"),
      );
    } else {
      trailing = FilledButton(
        onPressed: _busy ? null : pair,
        child: const Text("Pair"),
      );
    }
    return GroupedListTile(
      position: position,
      hairlineInset: GroupedListTile.insetIconLeading,
      child: ListTile(
        enabled: !_busy || pairingThis,
        leading: const Icon(Icons.router_outlined),
        title: Text(mgw.mDNSServiceName, overflow: TextOverflow.ellipsis),
        subtitle: Row(children: [
          Flexible(child: Text(mgw.ip, overflow: TextOverflow.ellipsis)),
          if (paired) ...[
            const SizedBox(width: Spacing.sm),
            const _PairedLabel(),
          ],
        ]),
        trailing: trailing,
      ),
    );
  }

  List<Widget> _messages() => [
        if (_searching)
          const _StatusLine("Searching the local network…"),
        if (_searchError != null) ...[
          MgwErrorBlock(
            title: "Could not search the local network",
            message: describeMgwError(_searchError!),
            hint: "You can still enter the gateway's address.",
          ),
          const SizedBox(height: Spacing.md),
        ],
        if (_pairFailure != null) ...[
          MgwErrorBlock(
            title: "Pairing failed",
            message: _pairFailure!.message,
            hint: _pairFailure!.hint,
          ),
          const SizedBox(height: Spacing.md),
        ],
      ];

  Widget _body(AppState state) {
    if (_found.isEmpty && !_searching) {
      return _EmptyState(
        messages: _messages(),
        onSearch: _busy ? null : _runDiscovery,
        onEnterAddress: _busy ? null : () => _addManually(state),
      );
    }
    return SectionedListView(
      physics: const AlwaysScrollableScrollPhysics(),
      leading: _messages(),
      sections: [
        ListSection<MGW>(
          id: "found",
          title: "Found gateways",
          items: _found,
          keyOf: (mgw) => mgw.hostname,
          itemBuilder: (context, mgw, position) =>
              _row(context, mgw, position, state),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Pair gateway"),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: "Enter address",
              onPressed: _busy ? null : () => _addManually(state),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Search again",
              onPressed: _searching || _busy ? null : _runDiscovery,
            ),
          ],
          // Always reserved, so the page does not jump when a search ends.
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: _searching
                ? const LinearProgressIndicator()
                : const SizedBox(height: 4),
          ),
        ),
        body: _body(state),
      );
    });
  }
}

class _PairedLabel extends StatelessWidget {
  const _PairedLabel();

  @override
  Widget build(BuildContext context) {
    final ink = context.appColors.appInk;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 16, color: ink),
        const SizedBox(width: Spacing.xxs),
        Text("Paired",
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: ink)),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg + Spacing.xxs, 0, Spacing.lg, Spacing.md),
      child: Text(text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// No gateway found: what to check, and the two ways on.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.messages,
    required this.onSearch,
    required this.onEnterAddress,
  });

  final List<Widget> messages;
  final VoidCallback? onSearch;
  final VoidCallback? onEnterAddress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: Spacing.listPadding(context),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 2 * Spacing.md),
          child: Column(
            children: [
              ...messages,
              const SizedBox(height: Spacing.xl * 2),
              Icon(Icons.router_outlined, size: 48, color: muted),
              const SizedBox(height: Spacing.lg),
              Text("No gateway found", style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                child: Text(
                  "The gateway must be in pairing mode and on the same "
                  "network as this phone.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
              const SizedBox(height: Spacing.xl),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onSearch,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Search again"),
                  ),
                  OutlinedButton.icon(
                    onPressed: onEnterAddress,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text("Enter address"),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}
