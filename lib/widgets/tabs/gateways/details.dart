import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/mgw_deployment.dart';
import 'package:mobile_app/services/mgw/module_manager.dart';
import 'package:mobile_app/theme.dart';
import 'package:provider/provider.dart';

const double TOP_PADDING = 100;
const textStyle = TextStyle(color: Colors.white, fontSize: 35);

class MGWDetail extends StatefulWidget {
  const MGWDetail({super.key, required this.mgw});
  final MGW mgw;

  @override
  State<MGWDetail> createState() => _MGWDetailState();
}

class _MGWDetailState extends State<MGWDetail> {
  late final Future<List<Deployment>> _deploymentsFuture;

  @override
  void initState() {
    super.initState();
    _deploymentsFuture = MgwModuleService.create(widget.mgw.ip)
        .then((service) => service.getDeployments(null));
  }

  Widget handleDeployments(List<Deployment> deployments) {
    if (deployments.isEmpty) {
      return const Column(children: [
        Icon(Icons.error_outline, color: Colors.red, size: 40),
        Padding(
          padding: EdgeInsets.only(top: TOP_PADDING),
          child: Text('No deployments!'),
        ),
      ]);
    }

    return Material(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.mgw.mDNSServiceName)),
        body: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: MyTheme.inset,
          itemCount: deployments.length,
          itemBuilder: (BuildContext context, int index) {
            final deployment = deployments[index];
            final stateColor = switch (deployment.state) {
              "healthy" => Colors.green,
              "unhealthy" => Colors.red,
              "transitioning" => Colors.lime,
              _ => Colors.grey,
            };

            return Padding(
              padding: const EdgeInsets.only(top: 30),
              child: ListTile(
                title: Text(deployment.name),
                subtitle: Text(deployment.module.version),
                leading: Icon(Icons.fiber_manual_record, color: stateColor, size: 18),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget handleError(Object? error) {
    return Column(children: [
      const Padding(
        padding: EdgeInsets.only(top: TOP_PADDING),
        child: Icon(Icons.error_outline, color: Colors.red, size: 40),
      ),
      Padding(
        padding: EdgeInsets.only(top: TOP_PADDING),
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
      ),
    ]);
  }

  Widget handleDeploymentsResponse(AsyncSnapshot<List<Deployment>> snapshot) {
    if (snapshot.hasData) return handleDeployments(snapshot.data!);
    if (snapshot.hasError) return handleError(snapshot.error);
    return handleLoading();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return FutureBuilder(
          future: _deploymentsFuture,
          builder: (context, AsyncSnapshot<List<Deployment>> snapshot) {
            return handleDeploymentsResponse(snapshot);
          },
        );
      },
    );
  }
}