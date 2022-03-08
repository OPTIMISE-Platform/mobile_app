import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mutex/mutex.dart';

import 'models/device_class.dart';
import 'models/device_permsearch.dart';
import 'models/device_type.dart';
import 'widgets/toast.dart';

class AppState extends ChangeNotifier {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  bool _metaInitialized = false;

  final Map<String, DeviceClass> deviceClasses = {};
  final Mutex _deviceClassesMutex = Mutex();

  final Map<String, DeviceTypePermSearch> deviceTypes = {};
  final Mutex _deviceTypesMutex = Mutex();

  final Map<String, NestedFunction> nestedFunctions = {};
  final Mutex _nestedFunctionsMutex = Mutex();

  String _deviceSearchText = '';

  int totalDevices = 0;
  final Mutex _totalDevicesMutex = Mutex();

  final List<DevicePermSearch> devices = <DevicePermSearch>[];
  final Mutex _devicesMutex = Mutex();

  int _deviceClassArrIndex = 0;
  int _classOffset = 0;

  bool loggedIn() => Auth.tokenValid();

  bool loggingIn() => Auth.loggingIn();

  initAllMeta(BuildContext context) async {
    await loadDeviceClasses(context);
    await loadDeviceTypes(context);
    await loadNestedFunctions(context);
    _metaInitialized = true;
  }

  loadDeviceClasses(BuildContext context) async {
    final locked = _deviceClassesMutex.isLocked;
    _deviceClassesMutex.acquire();
    if (locked) {
      return deviceClasses;
    }
    for (var element
        in (await DeviceClassesService.getDeviceClasses(context, this))) {
      deviceClasses[element.id] = element;
    }
    notifyListeners();
    _deviceClassesMutex.release();
  }

  loadDeviceTypes(BuildContext context) async {
    final locked = _deviceTypesMutex.isLocked;
    _deviceTypesMutex.acquire();
    if (locked) {
      return deviceTypes;
    }
    for (var element
        in (await DeviceTypesService.getDeviceTypes(context, this))) {
      deviceTypes[element.id] = element;
    }
    notifyListeners();
    _deviceTypesMutex.release();
  }

  loadNestedFunctions(BuildContext context) async {
    final locked = _nestedFunctionsMutex.isLocked;
    _nestedFunctionsMutex.acquire();
    if (locked) {
      return nestedFunctions;
    }
    for (var element
    in (await FunctionsService.getNestedFunctions(context, this))) {
      nestedFunctions[element.id] = element;
    }
    notifyListeners();
    _nestedFunctionsMutex.release();
  }

  updateTotalDevices(BuildContext context) async {
    _totalDevicesMutex.acquire();
    final total =
        await DevicesService.getTotalDevices(context, this, _deviceSearchText);
    if (total != totalDevices) {
      totalDevices = total;
      notifyListeners();
    }
  }

  searchDevices(String query, BuildContext context, [bool force = false]) async {
    if (!force && query == _deviceSearchText) {
      return;
    }
    _deviceClassArrIndex = 0;
    _classOffset = 0;
    if (devices.isNotEmpty) {
      devices.clear();
      notifyListeners();
    }
    _deviceSearchText = query;
    updateTotalDevices(context);
    loadDevices(context);
  }

  refreshDevices(BuildContext context) async {
    await searchDevices(_deviceSearchText, context, true);
  }

  loadDevices(BuildContext context, [int size = 50]) async {
    if (_devicesMutex.isLocked) {
      return;
    }
    _devicesMutex.acquire();

    if (!_metaInitialized) {
      await initAllMeta(context);
    }

    late final List<DevicePermSearch> newDevices;
    try {
      List<String> deviceTypeIds = deviceTypes.values
          .where((element) =>
              element.device_class_id ==
              deviceClasses.keys.elementAt(_deviceClassArrIndex))
          .map((e) => e.id)
          .toList(growable: false);

      newDevices = await DevicesService.getDevices(
          context, this, size, _classOffset, _deviceSearchText, deviceTypeIds);
    } catch (e) {
      _logger.e("Could not get devices: " + e.toString());
      Toast.showErrorToast(context, "Could not load devices");
      return;
    } finally {
      _devicesMutex.release();
    }
    devices.addAll(newDevices);
    _classOffset += newDevices.length;
    if (newDevices.isNotEmpty) notifyListeners();
    if (totalDevices < devices.length) {
      await updateTotalDevices(context); // when loadDevices called directly
    }
    if (newDevices.length < size &&
        deviceClasses.length - 1 > _deviceClassArrIndex) {
      _classOffset = 0;
      _deviceClassArrIndex++;
      loadDevices(context, size - newDevices.length);
    }
  }

  @override
  void notifyListeners() {
    _logger.d("notifying listeners");
    super.notifyListeners();
  }
}
