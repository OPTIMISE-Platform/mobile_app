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

class MGWDetail extends StatelessWidget {
  const MGWDetail({super.key, required this.mgw});
  final MGW mgw;

  handleDeployments(deployments) {
    if (deployments.length == 0) {
      return Column(
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 40,
            ),
            Padding(
              padding: const EdgeInsets.only(top: TOP_PADDING),
              child: Text('No deployments!'),
            ),
          ]);
    }

    return Material(
      child: Scaffold(
        appBar: AppBar(
          title: Text(mgw.mDNSServiceName),
        ),
        //passing in the ListView.builder
        body: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: MyTheme.inset,
                itemCount: deployments.length,
                itemBuilder: (BuildContext context, int index) {
                  var deployment = deployments.elementAt(index);
                  var stateColor = Colors.grey;
                  switch(deployment.state) {
                    case "healthy":
                      stateColor = Colors.green;
                      break;
                    case "unhealthy":
                      stateColor = Colors.red;
                      break;
                    case "transitioning":
                      stateColor = Colors.lime;
                      break;
                    default:
                      stateColor = Colors.grey;
                  }

                  return Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: ListTile(
                        title: Text(deployment.name),
                          subtitle: Text(deployment.module.version),
                        leading: Icon(
                          Icons.fiber_manual_record,
                          color: stateColor,
                          size: 18,
                        ),
                      ));
                })
        )
    );
  }

  handlError(error) {
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
            child: Text('Load...', style: textStyle),
          )
        ]);
  }

  handleDeploymentsResponse(AsyncSnapshot<List<Deployment>> deploymentsWrapper) {
    if (deploymentsWrapper.hasData) {
      return handleDeployments(deploymentsWrapper.data);
    }

    if (deploymentsWrapper.hasError) {
      return handlError(deploymentsWrapper.error);
    }

    return handleLoading();
  }

 @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      var moduleManager = MgwModuleService(mgw.ip);
      return FutureBuilder(
          future: moduleManager.getDeployments(null),
          builder: (BuildContext context, AsyncSnapshot<List<Deployment>> deploymentsWrapper) {
            return handleDeploymentsResponse(deploymentsWrapper);
          }
      );
    });
  }
}