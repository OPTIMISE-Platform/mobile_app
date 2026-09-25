import 'package:flutter/material.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/mgw_module.dart';
import 'package:mobile_app/services/mgw/module_manager.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

const double TOP_PADDING = 100;
const textStyle = TextStyle(color: Colors.white, fontSize: 35);

class MGWDetail extends StatefulWidget {
  const MGWDetail({super.key, required this.mgw});
  final MGW mgw;

  @override
  State<MGWDetail> createState() => _MGWDetailState();
}

class _MGWDetailState extends State<MGWDetail> {
  // Held in state: building the future inside build() reissued the request on
  // every rebuild.
  late Future<List<Module>> _modules;

  @override
  void initState() {
    super.initState();
    _modules = MgwModuleService(widget.mgw.ip).getModules();
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

  Widget handleModules(List<Module> modules) {
    if (modules.isEmpty) {
      return const Column(children: [
        Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 40,
        ),
        Padding(
          padding: EdgeInsets.only(top: TOP_PADDING),
          child: Text('No modules!'),
        ),
      ]);
    }

    return Material(
        child: Scaffold(
            appBar: AppBar(
              title: Text(widget.mgw.mDNSServiceName),
            ),
            body: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: Spacing.insetVertical,
                itemCount: modules.length,
                itemBuilder: (BuildContext context, int index) {
                  final module = modules.elementAt(index);
                  return GroupedListTile(
                    key: ValueKey(module.id),
                    position: SlicePosition.forIndex(index, modules.length),
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
                  );
                },
                findChildIndexCallback: (key) {
                  final id = (key as ValueKey<String>).value;
                  final index = modules.indexWhere((m) => m.id == id);
                  return index == -1 ? null : index;
                })));
  }

  Widget handlError(error) {
    return Column(children: [
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

  Widget handleLoading() {
    return const Column(children: [
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
        child: Text('Load...', style: textStyle),
      )
    ]);
  }

  Widget handleModulesResponse(AsyncSnapshot<List<Module>> modulesWrapper) {
    if (modulesWrapper.hasData) {
      return handleModules(modulesWrapper.data!);
    }

    if (modulesWrapper.hasError) {
      return handlError(modulesWrapper.error);
    }

    return handleLoading();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _modules,
        builder:
            (BuildContext context, AsyncSnapshot<List<Module>> modulesWrapper) {
          return handleModulesResponse(modulesWrapper);
        });
  }
}
