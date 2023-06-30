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

import 'dart:math';

import 'package:arrow_path/arrow_path.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_material_symbols/flutter_material_symbols.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';

import 'base.dart';

class SmSePvFlow extends SmartServiceModuleWidget {
  bool preview = false;
  bool _chargingViaInverter = false;
  Request? solarGenerationRequest;
  Request? chargePowerRequest;
  Request? dischargePowerRequest;
  List<Request> gridConsumptionRequests = [];
  Request? batteryLevelRequest;
  final _FlowPaintBase _flowPaintSolar = _FlowPaintSolar();
  final _FlowPaintBase _flowPaintHousehold = _FlowPaintHousehold();
  final _FlowPaintBase _flowPaintGrid = _FlowPaintGrid();
  final _FlowPaintBase _flowPaintBattery = _FlowPaintBattery();
  double? _solarToBattery,
      _solarToHousehold,
      _solarToGrid,
      _gridToHousehold,
      _batteryToHousehold,
      _batteryToGrid,
      _householdToBattery;
  
  @override
  setPreview(bool enabled) => preview = enabled;

  @override
  double height = kIsWeb ? 11.5 : 10.5;

  @override
  double width = 1;

  _SmSePvFlowStateful? _s;

  SmSePvFlow() {
    _s = _SmSePvFlowStateful(this);
  }

  @override
  Widget buildInternal(BuildContext context, bool _) {
    return _s ?? const SizedBox.shrink();
  }

  @override
  Future<void> configure(data) async {
    if (data is! Map<String, dynamic>) return;
    _chargingViaInverter = data["chargingViaInverter"] ?? false;
    if (data["solarGenerationRequest"] != null) {
      solarGenerationRequest = Request.fromJson(data["solarGenerationRequest"]);
    }
    if (data["chargePowerRequest"] != null) {
      chargePowerRequest = Request.fromJson(data["chargePowerRequest"]);
    }
    if (data["dischargePowerRequest"] != null) {
      dischargePowerRequest = Request.fromJson(data["dischargePowerRequest"]);
    }
    if (data["gridConsumptionRequests"] != null) {
      for (final req in data["gridConsumptionRequests"]) {
        gridConsumptionRequests.add(Request.fromJson(req));
      }
    }
    if (data["batteryLevelRequest"] != null) {
      batteryLevelRequest = Request.fromJson(data["batteryLevelRequest"]);
    }
  }

  @override
  Future<void> refreshInternal() async {
    final List<Future> futures = [];
    double? solarGeneration;
    double? chargePower;
    double? dischargePower;
    double gridConsumption = 0.0;
    double? batteryLevel;

    futures.add(solarGenerationRequest
            ?.perform()
            .then((value) => solarGeneration = double.parse(value.body)) ??
        Future.value(null));
    futures.add(chargePowerRequest
            ?.perform()
            .then((value) => chargePower = double.parse(value.body)) ??
        Future.value(null));
    futures.add(dischargePowerRequest
            ?.perform()
            .then((value) => dischargePower = double.parse(value.body)) ??
        Future.value(null));
    for (final req in gridConsumptionRequests) {
      futures.add(req.perform().then((value) {
        gridConsumption += double.parse(value.body);
      }));
    }
    futures.add(batteryLevelRequest
            ?.perform()
            .then((value) => batteryLevel = double.parse(value.body)) ??
        Future.value(null));

    await Future.wait(futures);

    if ((chargePower ?? 0) < 0) {
      dischargePower = (chargePower ?? 0) * -1;
      chargePower = null;
    }

    _flowPaintSolar.value = solarGeneration;
    _flowPaintBattery.value = batteryLevel;
    _flowPaintGrid.value = gridConsumption;

    if (_chargingViaInverter) {
      _solarToBattery = chargePower;
      _householdToBattery = null;
      _flowPaintHousehold.value = gridConsumption +
          (solarGeneration ?? 0) +
          (dischargePower ?? 0) -
          (chargePower ?? 0);
    } else {
      _solarToBattery = null;
      _householdToBattery = chargePower;
      _flowPaintHousehold.value = gridConsumption +
          (solarGeneration ?? 0) +
          (dischargePower ?? 0);
    }
    _batteryToHousehold =
        min(dischargePower ?? 0, _flowPaintHousehold._value ?? 0);

    if (gridConsumption > 0) {
      _gridToHousehold = gridConsumption;
      _batteryToHousehold = dischargePower;
      _solarToHousehold = (solarGeneration ?? 0) -
          (_chargingViaInverter ? (chargePower ?? 0) : 0);
      _solarToGrid = null;
      _batteryToGrid = null;
    } else if (gridConsumption <= 0) {
      _gridToHousehold = null;
      _solarToHousehold = (_flowPaintHousehold._value ?? 0) -
          (_batteryToHousehold ?? 0);
      _solarToGrid = min(
          (solarGeneration ?? 0) -
              (_solarToHousehold ?? 0) -
              (_chargingViaInverter ? (chargePower ?? 0) : 0),
          (solarGeneration ?? 0));
      _batteryToGrid =
          (dischargePower ?? 0) - (_batteryToHousehold ?? 0);
    }
    return;
  }
}

class _SmSePvFlowStateful extends StatefulWidget {
  final SmSePvFlow _smSePvFlow;

  const _SmSePvFlowStateful(this._smSePvFlow);

  @override
  State<StatefulWidget> createState() => _SmSePvFlowStatefulState();
}

class _SmSePvFlowStatefulState extends State<_SmSePvFlowStateful>
    with TickerProviderStateMixin {
  late final Ticker _ticker = Ticker(onTick);

  Duration total = Duration.zero;
  Duration lastDraw = Duration.zero;
  double pos = 0.0;

  void onTick(Duration elapsed) {
    setState(() {
      total = elapsed;
    });
  }

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    _ticker.muted = !TickerMode.of(context);
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _ticker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    const m = 115.0;
    final s = min((width < height ? width : height) * 0.25, m);
    final size = Size(s, s);
    pos = (pos +
        ((total - lastDraw).inMicroseconds / _ArrowPainter.loopTime.inMicroseconds)) % 0.9;
    lastDraw = total;

    return Container(
        height: s,
        width: s * 4,
        padding: const EdgeInsets.only(
            top: MyTheme.insetSize,
            right: MyTheme.insetSize,
            left: MyTheme.insetSize / 2,
            bottom: MyTheme.insetSize / 2),
        child: Stack(children: [
          Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              CustomPaint(
                size: size,
                painter: widget._smSePvFlow._flowPaintSolar,
              )
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              CustomPaint(size: size, painter: widget._smSePvFlow._flowPaintBattery),
              CustomPaint(size: size, painter: widget._smSePvFlow._flowPaintGrid)
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              CustomPaint(
                size: size,
                painter: widget._smSePvFlow._flowPaintHousehold,
              )
            ]),
            // CustomPaint(size: MediaQuery.of(context).size, painter: _flowPaintAc)
          ]),
          CustomPaint(
              size: Size(max(width, m * 4), max(width, 130 * 4)),
              painter: _ArrowPainter(
                  widget._smSePvFlow._solarToBattery,
                  widget._smSePvFlow._solarToHousehold,
                  widget._smSePvFlow._solarToGrid,
                  widget._smSePvFlow._gridToHousehold,
                  widget._smSePvFlow._batteryToHousehold,
                  widget._smSePvFlow._batteryToGrid,
                  widget._smSePvFlow._householdToBattery,
                  widget._smSePvFlow._chargingViaInverter,
                  pos
              ))
        ]));
  }
}

class _FlowPaintBase extends CustomPainter {
  double? _value = 0;
  bool _shouldRepaint = false;

  IconData icon = MaterialSymbols.abc;
  Color color = Colors.white;
  String unit = "W";

  set value(double? value) {
    _shouldRepaint = _shouldRepaint || value != _value;
    _value = value;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final width = size.width * 0.5;
    var offset = Offset(width, width);
    paint.color = color;
    canvas.drawCircle(offset, width, paint);

    var textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
              color: Colors.black54,
              fontSize: 30,
              package: icon.fontPackage,
              fontFamily: icon.fontFamily),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center);
    textPainter.layout(minWidth: width * 2, maxWidth: width * 2);
    offset = Offset(0, size.height * (_value != null ? .1 : 0.35));
    textPainter.paint(canvas, offset);

    if (_value != null) {
      textPainter = TextPainter(
          text: TextSpan(
            text: "${(_value ?? 0).toStringAsFixed(0)} $unit",
            style: const TextStyle(color: Colors.black, fontSize: 22),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center);
      textPainter.layout(minWidth: width * 2, maxWidth: width * 2);
      offset = Offset(0, size.height * .5);
      textPainter.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (_shouldRepaint) {
      _shouldRepaint = false;
      return true;
    }
    return false;
  }
}

class _FlowPaintSolar extends _FlowPaintBase {
  _FlowPaintSolar() {
    color = Colors.amber;
    icon = MaterialSymbols.solar_power;
  }
}

class _FlowPaintHousehold extends _FlowPaintBase {
  _FlowPaintHousehold() {
    color = Colors.teal;
    icon = MaterialSymbols.house;
  }
}

class _FlowPaintGrid extends _FlowPaintBase {
  _FlowPaintGrid() {
    color = Colors.redAccent;
    icon = MaterialSymbols.electrical_services;
  }
}

class _FlowPaintBattery extends _FlowPaintBase {
  _FlowPaintBattery() {
    color = Colors.lightGreen;
    icon = MaterialSymbols.battery_full;
    unit = "%";
  }

  @override
  set value(double? v) {
    super.value = v;
    if (_value == 100 || _value == null) {
      icon = MaterialSymbols.battery_full;
    } else if ((_value ?? 0) > 85) {
      icon = MaterialSymbols.battery_6_bar;
    } else if ((_value ?? 0) > 70) {
      icon = MaterialSymbols.battery_5_bar;
    } else if ((_value ?? 0) > 55) {
      icon = MaterialSymbols.battery_4_bar;
    } else if ((_value ?? 0) > 40) {
      icon = MaterialSymbols.battery_3_bar;
    } else if ((_value ?? 0) > 25) {
      icon = MaterialSymbols.battery_2_bar;
    } else if ((_value ?? 0) > 10) {
      icon = MaterialSymbols.battery_1_bar;
    } else {
      icon = MaterialSymbols.battery_0_bar;
    }
  }
}

class _ArrowPainter extends CustomPainter {
  final double? _solarToBattery,
      _solarToHousehold,
      _solarToGrid,
      _gridToHousehold,
      _batteryToHousehold,
      _batteryToGrid,
      _householdToBattery;
  final bool _chargingViaInverter;
  final double _pos;
  static const Duration loopTime = Duration(milliseconds: 750);
  static const animationLength = 0.1;

  _ArrowPainter(this._solarToBattery,
      this._solarToHousehold,
      this._solarToGrid,
      this._gridToHousehold,
      this._batteryToHousehold,
      this._batteryToGrid,
      this._householdToBattery,
      this._chargingViaInverter,
      this._pos){}
  
  @override
  void paint(Canvas canvas, Size size) {
    if (_solarToBattery != null && _solarToBattery != 0.0) {
      _drawArrow(
          // solar to battery
          canvas,
          _solarToBattery ?? 0,
          Colors.amber,
          size.width * .3625,
          size.width * .1875,
          Direction.bottomLeft,
          size.width * .1175);
    }

    if (_solarToHousehold != null && _solarToHousehold != 0.0) {
      _drawArrow(
          // solar to household
          canvas,
          _solarToHousehold ?? 0,
          Colors.amber,
          size.width * .5,
          size.width * .2875,
          Direction.down,
          size.width * .225);
    }

    if (_solarToGrid != null && _solarToGrid != 0.0) {
      _drawArrow(
          // solar to grid
          canvas,
          _solarToGrid ?? 0,
          Colors.amber,
          size.width * .6375,
          size.width * .1875,
          Direction.bottomRight,
          size.width * .1175);
    }

    /*
    _drawArrow( // household to grid
        canvas,
        100,
        Colors.teal,
        size.width * .63,
        size.width * .6,
        Direction.topRight,
        size.width * .1175);
     */

    if (_gridToHousehold != null && _gridToHousehold != 0.0) {
      _drawArrow(
          // grid to household
          canvas,
          _gridToHousehold ?? 0,
          Colors.redAccent,
          size.width * .75,
          size.width * .4825,
          Direction.bottomLeft,
          size.width * .1175);
    }

    if (_batteryToHousehold != null &&
        _batteryToHousehold != 0.0 &&
        (_chargingViaInverter || (!_chargingViaInverter && (_householdToBattery == null || _householdToBattery == 0.0)))) {
      _drawArrow(
          // battery to household direct
          canvas,
          _batteryToHousehold ?? 0,
          Colors.lightGreen,
          size.width * .25,
          size.width * .4825,
          Direction.bottomRight,
          size.width * .1175);
    }

    if (_batteryToHousehold != null &&
        _batteryToHousehold != 0.0 &&
        !_chargingViaInverter && _householdToBattery != null && _householdToBattery != 0.0) {
      _drawArrow(
          // battery to household AC
          canvas,
          _batteryToHousehold ?? 0,
          Colors.lightGreen,
          size.width * .275,
          size.width * .425,
          Direction.bottomRight,
          size.width * .13);
    }

    if (_householdToBattery != null && _householdToBattery != 0.0) {
      _drawArrow(
          // household to battery
          canvas,
          _householdToBattery ?? 0,
          Colors.teal,
          size.width * .35,
          size.width * .65,
          Direction.topLeft,
          size.width * .13);
    }

    if (_batteryToGrid != null && _batteryToGrid != 0.0) {
      _drawArrow(
          // battery to grid
          canvas,
          _batteryToGrid ?? 0,
          Colors.lightGreen,
          size.width * .275,
          size.width * .4,
          Direction.right,
          size.width * .45);
    }
  }

  @override
  bool operator ==(Object other) {
    return (other is _ArrowPainter) &&
        other._solarToBattery == _solarToBattery &&
        other._solarToHousehold == _solarToHousehold &&
        other._solarToGrid == _solarToGrid &&
        other._gridToHousehold == _gridToHousehold &&
        other._batteryToHousehold == _batteryToHousehold &&
        other._batteryToGrid == _batteryToGrid &&
        other._householdToBattery == _householdToBattery &&
        other._chargingViaInverter == _chargingViaInverter &&
        other._pos == _pos;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate != this;
  }

  _drawArrow(Canvas canvas, double value, Color color, double fromX,
      double fromY, Direction direction, double length) {
    Paint p = Paint()
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    Path path = Path();
    path.moveTo(fromX, fromY);
    Offset offset = const Offset(0, 0);
    final textPainter = TextPainter(
        text: TextSpan(
          text: "${value.toStringAsFixed(0)} W",
          style: const TextStyle(color: Colors.black, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center);
    textPainter.layout();
    switch (direction) {
      case Direction.bottomLeft:
        path.relativeLineTo(-length * _pos, length * _pos);
        path.moveTo(fromX - length * _pos - length * animationLength, fromY + length * _pos + length * animationLength);
        path.relativeLineTo(-length * (1-_pos) + animationLength * length, length * (1-_pos) - animationLength * length);
        offset = Offset(fromX - length * .85, fromY + length * .3);
        break;
      case Direction.topLeft:
        path.relativeLineTo(-length * _pos, -length * _pos);
        path.moveTo(fromX - length * _pos - length * animationLength, fromY - length * _pos - length * animationLength);
        path.relativeLineTo(-length * (1-_pos) + animationLength * length, -length * (1-_pos) + animationLength * length);
        offset = Offset(fromX - length * .8, fromY - length * .6);
        break;
      case Direction.bottomRight:
        path.relativeLineTo(length * _pos, length * _pos);
        path.moveTo(fromX + length * _pos + length * animationLength, fromY + length * _pos + length * animationLength);
        path.relativeLineTo(length * (1-_pos) - animationLength * length, length * (1-_pos) - animationLength * length);
        offset = Offset(fromX + length * .15, fromY + length * .3);
        break;
      case Direction.topRight:
        path.relativeLineTo(length * _pos, -length * _pos);
        path.moveTo(fromX + length * _pos + length * animationLength, fromY - length * _pos - length * animationLength);
        path.relativeLineTo(length * (1-_pos) - animationLength * length, -length * (1-_pos) + animationLength * length);
        offset = Offset(fromX + length * .15, fromY - length * .5);
        break;
      case Direction.up:
        path.relativeLineTo(0, -length * _pos);
        path.moveTo(fromX,
            fromY - length * _pos - animationLength * length);
        path.relativeLineTo(
            0, -length * (1 - _pos) + animationLength * length);
        offset =
            Offset(fromX - textPainter.width / 2, fromY - length * 0.25 - 6);
        break;
      case Direction.down:
        path.relativeLineTo(0, length * _pos);
        path.moveTo(fromX,
            fromY + length * _pos + animationLength * length);
        path.relativeLineTo(
            0, length * (1 - _pos) - animationLength * length);
        offset =
            Offset(fromX - textPainter.width / 2, fromY + length * 0.25 - 6);
        break;
      case Direction.right:
        path.relativeLineTo(length * _pos, 0);
        path.moveTo(fromX + length * _pos + length * animationLength, fromY);
        path.relativeLineTo(length * (1-_pos) - animationLength * length, 0);
        offset = Offset(fromX + length / 2 - textPainter.width / 2, fromY - 6);
        break;
      case Direction.left:
        path.relativeLineTo(-length * _pos, 0);
        path.moveTo(fromX - length * _pos - length * animationLength, fromY);
        path.relativeLineTo(-length * (1-_pos) + animationLength * length, 0);
        offset = Offset(fromX - length / 2 + textPainter.width / 2, fromY - 6);
        break;
      default:
        throw UnimplementedError();
    }
    path = ArrowPath.addTip(path);
    canvas.drawPath(path, p);

    p.style = PaintingStyle.fill;
    canvas.drawRect(
        Rect.fromCenter(
            center: Offset(offset.dx + textPainter.width / 2, offset.dy + 6),
            width: textPainter.width + 3,
            height: textPainter.height + 3),
        p);
    textPainter.paint(canvas, offset);
  }
}

enum Direction {
  bottomLeft,
  topLeft,
  bottomRight,
  topRight,
  up,
  down,
  right,
  left
}
