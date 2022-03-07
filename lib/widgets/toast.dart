import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';


class Toast {
  static FToast fToast = FToast();

  static showToast(BuildContext context, List<Widget> widgets, Color color) {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: color,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: widgets,
      ),
    );

    fToast.init(context);


    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 2),
    );
  }

  static showErrorToast(BuildContext context, String text) {
    List<Widget> widgets = [
      Icon(PlatformIcons(context).error),
      const SizedBox(
        width: 12.0,
      ),
      Text(text)];
    showToast(context, widgets, Colors.redAccent);
  }

  static showConfirmationToast(BuildContext context, String text) {
    List<Widget> widgets = [
      Icon(PlatformIcons(context).checkMark),
      const SizedBox(
        width: 12.0,
      ),
      Text(text)];
    showToast(context, widgets, Colors.greenAccent);
  }
}
