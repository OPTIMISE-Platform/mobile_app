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

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/db_query.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/toast.dart';
import 'package:mutex/mutex.dart';

import '../models/db_query.dart';
import '../theme.dart';

class Chart extends StatefulWidget {
  final DeviceState _state;

  Chart(this._state, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ChartState(_state);
}

class _ChartState extends State<Chart> {
  static final _HHMMformat = DateFormat.Hm();
  static final _EHHMMformat = DateFormat.E().add_Hm();
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  final DeviceState _state;
  final _appBar = const MyAppBar("Chart");
  final _refreshMutex = Mutex();

  bool _initialized = false;
  bool _refreshing = false;
  bool _allValuesEqual = false;
  int _range = 1;
  String _aggregation = "mean";
  List<FlSpot>? _spots;

  _refresh(BuildContext context, int range) async {
    await _refreshMutex.protect(() async {
      setState(() {
        _refreshing = true;
      });
      late final List<List<dynamic>> data;
      try {
        data = await DbQueryService.query(DbQuery(null, _state.deviceId, _state.serviceId, _getGroupTime(range), null, null, null,
            QueriesRequestElementTime(_getTime(range), null, null), [QueriesRequestElementColumn(_state.path!, _aggregation, null)], null));
      } catch (_) {
        Toast.showErrorToast(context, "Could not load data");
        if (_spots == null) Navigator.pop(context);

        setState(() {
          _refreshing = false;
        });
        return;
      }
      final List<FlSpot> newSpots = [];
      _allValuesEqual = true;
      for (final point in data) {
        if (point.length == 2 && point[0] != null && point[1] is num) {
          double val = point[1] is int ? point[1].toDouble() : point[1] as double;
          if (val.isNaN) continue;
          val = double.parse(val.toStringAsFixed(2));
          if (newSpots.isNotEmpty && _allValuesEqual) {
            _allValuesEqual = val == newSpots.first.y;
          }
          newSpots.add(FlSpot(DateTime.parse(point[0]).millisecondsSinceEpoch.toDouble(), val));
        }
      }
      if (mounted) {
        setState(() {
          _spots = newSpots;
          _refreshing = false;
          _range = range;
        });
      }
    });
  }

  String? _getTime(int range) {
    switch (range) {
      case 0:
        return "15m";
      case 1:
        return "2h";
      case 2:
        return "12h";
      case 3:
        return "1d";
      case 4:
        return "7d";
    }
    return null;
  }

  String? _getGroupTime(int range) {
    switch (range) {
      case 0:
        return "30s";
      case 1:
        return "5m";
      case 2:
        return "30m";
      case 3:
        return "1h";
      case 4:
        return "3h";
    }
    return null;
  }

  double? _getInterval(range) {
    switch (range) {
      case 0:
        return 5 * 60 * 1000; // 5min
      case 1:
        return 30 * 60 * 1000; // 30min
      case 2:
        return 2 * 60 * 60 * 1000; // 2h
      case 3:
        return 6 * 60 * 60 * 1000; // 6h
      case 4:
        return 36 * 60 * 60 * 1000; // 1.5d
    }
    return null;
  }

  _ChartState(this._state) {
    _logger.d("Chart opened: " + _state.deviceId! + ", " + _state.serviceId! + ", " + _state.path!);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      _initialized = true;
      _refresh(context, _range);
    }
    final List<Widget> appBarActions = [
      PlatformPopupMenu(
        options: [
          PopupMenuOption(
              label: 'Mean',
              onTap: (_) {
                _aggregation = "mean";
                _refresh(context, _range);
              }),
          PopupMenuOption(
              label: 'Max',
              onTap: (_) {
                _aggregation = "max";
                _refresh(context, _range);
              }),
          PopupMenuOption(
              label: 'Min',
              onTap: (_) {
                _aggregation = "min";
                _refresh(context, _range);
              }),
        ],
        icon: PlatformIconButton(
          icon: Icon(Icons.show_chart, color: isCupertino(context) ? MyTheme.appColor : null),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
          material: (_, __) => MaterialIconButtonData(disabledColor: MyTheme.textColor),
        ),
        cupertino: (context, _) => CupertinoPopupMenuData(
            title: const Text("Select Aggregation"),
            cancelButtonData: CupertinoPopupMenuCancelButtonData(
              child: const Text('Close'),
              onPressed: () => Navigator.pop(context),
            )),
      ),
      PlatformPopupMenu(
        options: [
          PopupMenuOption(
              label: '15 Minutes',
              onTap: (_) {
                _refresh(context, 0);
              }),
          PopupMenuOption(
              label: '2 Hours',
              onTap: (_) {
                _refresh(context, 1);
              }),
          PopupMenuOption(
              label: '12 Hours',
              onTap: (_) {
                _refresh(context, 2);
              }),
          PopupMenuOption(
              label: '1 Day',
              onTap: (_) {
                _refresh(context, 3);
              }),
          PopupMenuOption(
              label: '7 Days',
              onTap: (_) {
                _refresh(context, 4);
              }),
        ],
        icon: PlatformIconButton(
          icon: Icon(PlatformIcons(context).clockSolid, color: isCupertino(context) ? MyTheme.appColor : null),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
          material: (_, __) => MaterialIconButtonData(disabledColor: MyTheme.textColor),
        ),
        cupertino: (context, _) => CupertinoPopupMenuData(
            title: const Text("Select Range"),
            cancelButtonData: CupertinoPopupMenuCancelButtonData(
              child: const Text('Close'),
              onPressed: () => Navigator.pop(context),
            )),
      ),
      PlatformIconButton(
        onPressed: _refreshing ? null : () => _refresh(context, _range),
        icon: _refreshing ? PlatformCircularProgressIndicator() : const Icon(Icons.refresh),
        cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
      )
    ];
    return PlatformScaffold(
        appBar: _appBar.getAppBar(context, appBarActions),
        body: _spots == null
            ? Center(child: PlatformCircularProgressIndicator())
            : Container(
                padding: MyTheme.inset,
                child: LineChart(
                  LineChartData(
                    borderData: FlBorderData(show: false),
                    maxY: !_allValuesEqual || _spots == null || _spots!.isEmpty ? null : (_spots?.first.y ?? 0) + 1,
                    minY: !_allValuesEqual || _spots == null || _spots!.isEmpty ? null : (_spots?.first.y ?? 0) - 1,
                    lineBarsData: [
                      LineChartBarData(
                        spots: _spots,
                        color: MyTheme.appColor,
                      )
                    ],
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: false,
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            interval: _getInterval(_range),
                            getTitlesWidget: (val, meta) {
                              if (val == meta.max || val == meta.min) {
                                return const SizedBox.shrink();
                              }
                              final dt = DateTime.fromMillisecondsSinceEpoch(val.floor()).toLocal();
                              return Text(_range < 4 ? _HHMMformat.format(dt) : _EHHMMformat.format(dt));
                            }),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            getTitlesWidget: (val, meta) {
                              if (val == meta.max || val == meta.min) {
                                return const SizedBox.shrink();
                              }
                              return defaultGetTitle(val, meta);
                            }),
                      ),
                    ),
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 400),
                )));
  }
}
