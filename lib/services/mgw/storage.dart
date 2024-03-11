import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:path_provider/path_provider.dart';

const LOG_PREFIX = "MGW-STORAGE-SERVICE";

class MgwStorage {
  static const _mgwCredentialsKeyPrefix = "credentials_";
  static const _mgwConnectedKeyPrefix = "connected_mgws_";

  static const _boxName = "mgw.box";
  static Box<String>? _box;
  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  static var isInitialized = false;

  static init() async {
    if(isInitialized) return;
    Hive.init((await getApplicationDocumentsDirectory()).path);
    _box = await Hive.openBox<String>(_boxName);
    isInitialized = true;
  }

  static Future<void> StoreCredentials(DeviceUserCredentials user) async {
    init();
    _logger.d(LOG_PREFIX + ": Store mgw device credentials for: " + user.login);
    var credentials = json.encode(user);
    return await _box?.put(_mgwCredentialsKeyPrefix, credentials).then((
        value) => _box?.flush());
  }

  static Future<DeviceUserCredentials> LoadCredentials() async {
    init();
    _logger.d(LOG_PREFIX + ": Load mgw device credentials");
    var credentials = await _box?.get(_mgwCredentialsKeyPrefix);
    if(credentials != null) {
      DeviceUserCredentials deviceUser = DeviceUserCredentials.fromJson(json.decode(credentials));
      _logger.d(LOG_PREFIX + ": Loaded mgw device credentials for " + deviceUser.login);
      return deviceUser;
    }
    throw("Credentials not stored");
  }

  static Future<void> StorePairedMGW(MGW mgw) async {
    init();
    _logger.d(LOG_PREFIX + ": Store paired mgw: " + mgw.mDNSServiceName);
    var storedMGWs = await LoadPairedMGWs();
    storedMGWs.add(mgw);
    return await _box?.put(_mgwConnectedKeyPrefix, json.encode(storedMGWs)).then((
        value) => _box?.flush());
  }

  static Future<List<MGW>> LoadPairedMGWs() async {
    init();
    _logger.d(LOG_PREFIX + ": Load mgw device credentials");
    var encodedMgws = await _box?.get(_mgwConnectedKeyPrefix);
    if(encodedMgws != null) {
      List<MGW> mgws = json.decode(encodedMgws);
      _logger.d(LOG_PREFIX + ": Loaded mgws");
      return mgws;
    }
    return [];
  }
}