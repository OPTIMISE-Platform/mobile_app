/*
 * Copyright 2026 InfAI (CC SES)
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
import 'package:intl/intl.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/advertisements.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/display_time.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/gateways/follows_stored_gateway.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_error_block.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_dot.dart';
import 'package:mobile_app/widgets/tabs/gateways/unpair_dialog.dart';

/// Opens the status of [mgw] in a bottom sheet. The other gateways bound to
/// its network are listed below it and open in its place.
Future<void> showMgwStatusSheet(BuildContext context, MGW mgw) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (sheetContext) => SingleChildScrollView(
        padding:
            const EdgeInsets.fromLTRB(Spacing.xl, 0, Spacing.xl, Spacing.xl),
        child: _MgwStatusSheet(
          initial: mgw,
          onRemoved: () => Navigator.pop(sheetContext),
        ),
      ),
    );

class _MgwStatusSheet extends StatefulWidget {
  const _MgwStatusSheet({required this.initial, required this.onRemoved});

  final MGW initial;
  final VoidCallback onRemoved;

  @override
  State<_MgwStatusSheet> createState() => _MgwStatusSheetState();
}

class _MgwStatusSheetState extends State<_MgwStatusSheet> {
  late MGW _shown = widget.initial;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: AppState(), builder: _build);

  // Read from AppState on every change, so an address refresh or a new
  // binding shows while the sheet is open.
  Widget _build(BuildContext context, Widget? _) {
    final theme = Theme.of(context);
    final gateways = AppState().gateways;
    final shown = MgwStorage.resolve(_shown, gateways) ?? _shown;
    final others = gateways
        .where((m) =>
            m.networkId == shown.networkId &&
            !identical(m, shown) &&
            !MgwStorage.isSamePairing(m, shown))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Keyed by the entry, so switching starts the panel afresh.
        MgwStatusPanel(
            key: ObjectKey(_shown), mgw: _shown, onRemoved: widget.onRemoved),
        if (others.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          Text("Other gateways in this network",
              style: theme.textTheme.titleSmall),
          for (final mgw in others)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MgwStatusDot(gateway: mgw),
              title: Text(mgw.mDNSServiceName, overflow: TextOverflow.ellipsis),
              subtitle: Text(mgw.ip, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _shown = mgw),
            ),
        ],
      ],
    );
  }
}

/// Texts that explain a [MgwReport].
abstract final class MgwStatusText {
  static String explanation(MgwReport? report) {
    switch (report?.failedCheck) {
      case MgwFailedCheck.noCredentials:
        return "This phone holds no pairing for the gateway. Pair it again.";
      case MgwFailedCheck.sessionStorage:
        return "This phone could not read its stored pairing data. Check "
            "again.";
      case MgwFailedCheck.loginFailed:
        return report!.status == MgwStatus.unreachable
            ? "The gateway answered, but its login did not."
            : "The gateway did not let this phone log in. Pair it again.";
      default:
        break;
    }
    switch (report?.status) {
      case MgwStatus.ok:
        return "The app talks to this gateway directly on the local network.";
      case MgwStatus.unreachable:
        return "Nothing answers at this address. The phone may be on another "
            "network, or the gateway is off.";
      case MgwStatus.foreign:
        return "A device answers at this address, but it serves a different "
            "network.";
      case MgwStatus.unauthorized:
        return "The gateway answers but does not accept this phone. Pair it "
            "again.";
      case MgwStatus.unknown:
        return "This phone could not complete the check. Check again.";
      case null:
        return "Checking whether the gateway answers.";
    }
  }

  static String failedCheck(MgwFailedCheck check) {
    switch (check) {
      case MgwFailedCheck.notAnswering:
        return "Not answering";
      case MgwFailedCheck.foreignNetwork:
        return "Advertises a different network";
      case MgwFailedCheck.noCredentials:
        return "No credentials";
      case MgwFailedCheck.loginFailed:
        return "Login failed";
      case MgwFailedCheck.sessionStorage:
        return "Session storage failed";
      case MgwFailedCheck.rejected:
        return "Rejected";
    }
  }

  /// Null when the authenticated request carried no session.
  static String? session(MgwReport report) {
    if (report.retriedWithFreshLogin) {
      return "Stored session rejected, logged in again";
    }
    switch (report.sessionReused) {
      case true:
        return "Stored session reused";
      case false:
        return "New login";
      case null:
        return null;
    }
  }
}

/// Status of a paired gateway, why it is what it is, and what can be done.
class MgwStatusPanel extends StatefulWidget {
  const MgwStatusPanel({required this.mgw, this.onRemoved, super.key});

  final MGW mgw;

  /// Called once the pairing was removed.
  final VoidCallback? onRemoved;

  @override
  State<MgwStatusPanel> createState() => _MgwStatusPanelState();
}

class _MgwStatusPanelState extends State<MgwStatusPanel>
    with FollowsStoredGateway {
  static final _timeFormat = DateFormat.yMd().add_jms();

  MgwReport? _report;

  /// Checks in flight; a forced one may overlap one already running.
  int _running = 0;
  bool _pairing = false;

  /// The failure of the last action, with the title it is shown under.
  ({String title, PairingFailure failure})? _problem;

  bool get _checking => _running > 0;

  @override
  bool get holdsGateway => _pairing;

  @override
  void initState() {
    super.initState();
    followGateway(widget.mgw);
    _report = MgwReachability.cachedReportOf(gateway);
    if (_report == null) {
      _running++;
      _probe(false);
    }
    MgwReachability.revision.addListener(_onReachabilityChanged);
  }

  @override
  void dispose() {
    MgwReachability.revision.removeListener(_onReachabilityChanged);
    super.dispose();
  }

  @override
  void gatewayChanged(MGW previous) {
    if (MgwReachability.cacheKeyFor(previous) ==
        MgwReachability.cacheKeyFor(gateway)) {
      return;
    }
    _report = MgwReachability.cachedReportOf(gateway);
    if (_report == null) _check();
  }

  void _onReachabilityChanged() {
    // While pairing, the entry may still change; the pairing checks itself.
    if (!mounted || _pairing) return;
    final cached = MgwReachability.cachedReportOf(gateway);
    if (cached == null) {
      _check();
    } else {
      setState(() => _report = cached);
    }
  }

  Future<void> _check({bool force = false}) async {
    if (_checking && !force) return;
    setState(() => _running++);
    await _probe(force);
  }

  /// Runs one check counted in [_running] by the caller.
  Future<void> _probe(bool force) async {
    try {
      final report = await MgwReachability.check(gateway, force: force);
      if (mounted) setState(() => _report = report);
    } finally {
      _running--;
      if (mounted) setState(() {});
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  /// The network to bind [mgw] to when pairing again; null to cancel, also
  /// when the panel closed meanwhile.
  ///
  /// What answers at the address is checked first, as on the pairing page:
  /// pairing a stranger would replace this pairing's credentials with ones
  /// another gateway issued.
  Future<String?> _networkForPairAgain(MGW mgw) async {
    final networks = AppState().networks;
    var advertised = await MgwAdvertisements.networkIdOf(mgw.ip);
    if (!mounted) return null;
    if (advertised.isEmpty && _report?.status == MgwStatus.foreign) {
      advertised = _report?.advertisedNetworkId ?? "";
    }
    if (advertised.isNotEmpty && advertised == mgw.networkId) {
      return mgw.networkId;
    }
    if (advertised.isEmpty) {
      if (mgw.networkId.isEmpty) {
        if (networks.isEmpty) throw PairingFailure.noNetworks;
        final chosen = await askForNetwork(context, networks);
        return mounted ? chosen?.id : null;
      }
      final pair = await _confirm(
          "Pair gateway again?",
          "The gateway does not say which network it serves. Pair it for "
              "${_networkName(mgw.networkId)}?",
          "Pair");
      return pair && mounted ? mgw.networkId : null;
    }
    if (networks.isEmpty) throw PairingFailure.noNetworks;
    final network = networks.where((n) => n.id == advertised).firstOrNull;
    if (network == null) {
      throw const PairingFailure(
          "The gateway at this address serves a network this account does "
          "not have.",
          hint: "Pairing was cancelled; the stored pairing is unchanged.");
    }
    final rebind = await _confirm(
        "Bind to ${network.name}?",
        "The gateway at ${mgw.ip} serves ${network.name}, not "
            "${mgw.networkId.isEmpty ? "the network it was paired for" : _networkName(mgw.networkId)}. "
            "Pairing again binds it to ${network.name}.",
        "Pair and bind");
    return rebind && mounted ? network.id : null;
  }

  Future<void> _pairAgain() async {
    setState(() {
      _pairing = true;
      _problem = null;
    });
    // Every way out resets _pairing: left set, it disables the actions and
    // mutes the status for good.
    try {
      await _pairAgainSteps();
    } catch (e, s) {
      ErrorReporter.log("Pairing again failed", e, s);
      if (mounted) {
        setState(() =>
            _problem = (title: "Pairing failed", failure: PairingFailure.of(e)));
      }
    } finally {
      if (mounted && _pairing) setState(() => _pairing = false);
    }
  }

  Future<void> _pairAgainSteps() async {
    void fail(PairingFailure failure) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _problem = (title: "Pairing failed", failure: failure);
      });
    }

    // Resolved now: the address refresh may have moved the entry since the
    // panel opened, and pairing must go where the gateway is.
    final old = MgwStorage.resolve(gateway, await MgwStorage.LoadPairedMGWs());
    if (old == null) {
      fail(const PairingFailure("This pairing is no longer stored.",
          hint: "Pair the gateway from the pairing page."));
      return;
    }
    final String? networkId;
    try {
      networkId = await _networkForPairAgain(old);
    } on PairingFailure catch (e) {
      fail(e);
      return;
    }
    if (networkId == null || !mounted) {
      if (mounted) setState(() => _pairing = false);
      return;
    }
    final result = await pairAndStore(
        MGW(old.hostname, old.mDNSServiceName, old.coreId, old.ip,
            networkId: networkId, pairingId: old.pairingId),
        AppState(),
        replacing: old);
    final failure = result.failure;
    if (!mounted) {
      if (failure != null) {
        Toast.showToastNoContext("Pairing was not possible: ${failure.message}");
      }
      return;
    }
    if (failure != null) {
      fail(failure);
      return;
    }
    setState(() {
      _pairing = false;
      gateway = result.stored!;
    });
    // Storing it dropped the cached status and the merge after it probed the
    // gateway again, so this reads that answer instead of a second probe.
    await _check();
  }

  Future<void> _remove() async {
    final result = await removePairing(context, gateway);
    if (!mounted) return;
    switch (result) {
      case PairingRemoval.removed:
        widget.onRemoved?.call();
      case PairingRemoval.notFound:
        setState(() => _problem = (
              title: "Could not remove the pairing",
              failure: const PairingFailure(pairingNotFoundMessage)
            ));
      case PairingRemoval.cancelled:
      case PairingRemoval.failed:
        break;
    }
  }

  String _networkName(String id) {
    final match = AppState().networks.where((n) => n.id == id).firstOrNull;
    return match?.name ?? id;
  }

  List<(String, String)> _details(MgwReport report) {
    final failed = report.failedCheck;
    final session = MgwStatusText.session(report);
    return [
      if (failed != null) ("Failed check", MgwStatusText.failedCheck(failed)),
      if (report.httpStatus != null) ("HTTP status", "${report.httpStatus}"),
      if (report.gatewayMessage?.isNotEmpty == true)
        ("Gateway message", report.gatewayMessage!),
      if (report.error?.isNotEmpty == true) ("Error", report.error!),
      if (failed == MgwFailedCheck.foreignNetwork) ...[
        ("Expected network", _networkName(report.expectedNetworkId ?? "")),
        ("Advertised network", _networkName(report.advertisedNetworkId ?? "")),
      ],
      ("Address checked", report.address),
      if (session != null) ("Session", session),
      ("Last checked", _timeFormat.format(toDisplayTime(report.checkedAt))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted =
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final report = _report;
    final mgw = gateway;
    final network = mgw.networkId.isEmpty
        ? "No network bound"
        : _networkName(mgw.networkId);
    final busy = _pairing || _checking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(mgw.mDNSServiceName, style: theme.textTheme.titleLarge),
        const SizedBox(height: Spacing.xxs),
        Text("${mgw.ip} · $network", style: muted),
        const SizedBox(height: Spacing.lg),
        Row(
          children: [
            Icon(Icons.fiber_manual_record,
                size: 14, color: MgwStatusDot.colorOf(report?.status)),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(MgwStatusDot.labelOf(report?.status),
                  style: theme.textTheme.titleMedium),
            ),
            if (_checking)
              const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 14 + Spacing.sm),
          child: Text(MgwStatusText.explanation(report), style: muted),
        ),
        if (report != null) ...[
          const SizedBox(height: Spacing.md),
          for (final (label, value) in _details(report))
            _DetailRow(label: label, value: value),
        ],
        if (_problem != null) ...[
          const SizedBox(height: Spacing.md),
          MgwErrorBlock(
            title: _problem!.title,
            message: _problem!.failure.message,
            hint: _problem!.failure.hint,
            margin: EdgeInsets.zero,
          ),
        ],
        const SizedBox(height: Spacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _check(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text("Check again"),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : _pairAgain,
                icon: _pairing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.link),
                label: const Text("Pair again"),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Text("Pairing again needs the gateway in pairing mode.",
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: Spacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: _pairing ? null : _remove,
            icon: const Icon(Icons.link_off),
            label: const Text("Remove pairing"),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
              child: SelectableText(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
