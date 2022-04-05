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

import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../theme.dart';


class Toast {
  static FToast fToast = FToast();

  static showToast(BuildContext context, List<Widget> widgets, Color color, [Duration? duration]) {
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
      toastDuration: duration ?? const Duration(seconds: 2),
    );
  }

  static showErrorToast(BuildContext context, String text, [Duration? duration]) {
    List<Widget> widgets = [
      Icon(PlatformIcons(context).error, color: MyTheme.isDarkMode ? null : Colors.black),
      const SizedBox(
        width: 12.0,
      ),
      Text(text)];
    showToast(context, widgets, MyTheme.errorColor, duration);
  }

  static showConfirmationToast(BuildContext context, String text, [Duration? duration]) {
    List<Widget> widgets = [
      Icon(PlatformIcons(context).checkMark, color: MyTheme.isDarkMode ? null : Colors.black),
      const SizedBox(
        width: 12.0,
      ),
      Text(text)];
    showToast(context, widgets, MyTheme.successColor, duration);
  }

  static showWarningToast(BuildContext context, String text, [Duration? duration]) {
    List<Widget> widgets = [
      Icon(PlatformIcons(context).error, color: MyTheme.isDarkMode ? null : Colors.black),
      const SizedBox(
        width: 12.0,
      ),
      Text(text)];
    showToast(context, widgets, MyTheme.warnColor, duration);
  }

  static showInformationToast(BuildContext context, String text, [Duration? duration]) {
    List<Widget> widgets = [
      Icon(PlatformIcons(context).info, color: MyTheme.isDarkMode ? null : Colors.black),
      const SizedBox(
        width: 12.0,
      ),
      Text(text)];
    showToast(context, widgets, MyTheme.isDarkMode ? const Color(0x80FFFFFF) : Colors.black26, duration);
  }
}
