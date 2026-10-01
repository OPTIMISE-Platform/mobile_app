import 'package:flutter/material.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/mgw_module.dart';
import 'package:mobile_app/services/mgw/module_manager.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/tabs/gateways/follows_stored_gateway.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_error_block.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_panel.dart';

class MGWDetail extends StatefulWidget {
  const MGWDetail({super.key, required this.mgw});
  final MGW mgw;

  @override
  State<MGWDetail> createState() => _MGWDetailState();
}

class _MGWDetailState extends State<MGWDetail> with FollowsStoredGateway {
  // Held in state: building the future inside build() reissued the request on
  // every rebuild.
  late Future<List<Module>> _modules;

  @override
  void initState() {
    super.initState();
    followGateway(widget.mgw);
    _modules = MgwModuleService(gateway.ip).getModules();
  }

  @override
  void gatewayChanged(MGW previous) {
    if (previous.ip == gateway.ip) return;
    setState(() => _modules = MgwModuleService(gateway.ip).getModules());
  }

  /// Grey unless the module is deployed; the deployment's state is 1 for
  /// healthy and 2 for unhealthy, anything else means disabled or unknown.
  Color _stateColor(Module module) {
    if (!module.is_deployed) return Colors.grey;
    switch (module.deployment.state) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _statusCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
          child: MgwStatusPanel(
            mgw: widget.mgw,
            onRemoved: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  /// What stands in for the module rows while they load or when there are none.
  Widget? _modulesPlaceholder(
      BuildContext context, AsyncSnapshot<List<Module>> snapshot) {
    final theme = Theme.of(context);
    final muted =
        theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (snapshot.hasError) {
      return MgwErrorBlock(
        title: "Could not load the modules",
        message: describeMgwError(snapshot.error!),
      );
    }
    if (!snapshot.hasData) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg + Spacing.xxs),
        child: Row(children: [
          const SizedBox.square(
              dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Spacing.md),
          Text("Loading modules…", style: muted),
        ]),
      );
    }
    if (snapshot.data!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg + Spacing.xxs),
        child: Text("No modules installed", style: muted),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(gateway.mDNSServiceName)),
      body: FutureBuilder<List<Module>>(
        future: _modules,
        builder: (context, snapshot) {
          final placeholder = _modulesPlaceholder(context, snapshot);
          return SectionedListView(
            physics: const AlwaysScrollableScrollPhysics(),
            leading: [
              _statusCard(context),
              if (placeholder != null) ...[
                const SizedBox(height: Spacing.lg),
                placeholder,
              ],
            ],
            sections: [
              ListSection<Module>(
                id: "modules",
                title: "Modules",
                items: snapshot.data ?? const [],
                keyOf: (module) => module.id,
                itemBuilder: (context, module, position) => GroupedListTile(
                  position: position,
                  hairlineInset: GroupedListTile.insetIconLeading,
                  child: ListTile(
                    title: Text(module.name),
                    subtitle: Text(module.version),
                    leading: Icon(
                      Icons.fiber_manual_record,
                      color: _stateColor(module),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
