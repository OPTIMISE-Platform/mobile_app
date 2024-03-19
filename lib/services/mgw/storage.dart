import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:path_provider/path_provider.dart';

const LOG_PREFIX = "MGW-STORAGE-SERVICE";

class MgwStorage {
  static const _mgwCredentialsKeyPrefix = "credentials_";
  static const _mgwBasicAuthCredentialsKeyPrefix = "basic_auth_credentials_";
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
    await init();
    _logger.d(LOG_PREFIX + ": Store mgw device credentials for: " + user.login);
    var credentials = json.encode(user);
    return await _box?.put(_mgwCredentialsKeyPrefix, credentials).then((
        value) => _box?.flush());
  }

  static Future<DeviceUserCredentials> LoadCredentials() async {
    await init();
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
    await init();
    _logger.d(LOG_PREFIX + ": Store paired mgw: " + mgw.mDNSServiceName);
    var storedMGWs = await LoadPairedMGWs();
    storedMGWs.add(mgw);
    return await _box?.put(_mgwConnectedKeyPrefix, json.encode(storedMGWs)).then((
        value) => _box?.flush());
  }

  static Future<List<MGW>> LoadPairedMGWs() async {
    await init();
    _logger.d(LOG_PREFIX + ": Load paired mgws");
    var encodedMgws = await _box?.get(_mgwConnectedKeyPrefix);
    List<MGW> mgws = [];
    if(encodedMgws != null) {
      for(final mgw in jsonDecode(encodedMgws)) {
        mgws.add(MGW.fromJson(mgw));
      }
      return mgws;
    }
    _logger.d(LOG_PREFIX + ": Loaded mgws: " + mgws.toString());
    return mgws;
  }



  // TODO: remove loading and saving of basic auth credentials later
  static Future<void> StoreBasicAuthCredentials(String password) async {
    await init();
    _logger.d(LOG_PREFIX + ": Store mgw device basic auth credentials: " + password);
    return await _box?.put(_mgwBasicAuthCredentialsKeyPrefix, password).then((
        value) => _box?.flush());
  }

  static Future<String> LoadBasicAuthCredentials() async {
    await init();
    _logger.d(LOG_PREFIX + ": Load mgw device basic auth credentials");
    var password = await _box?.get(_mgwBasicAuthCredentialsKeyPrefix);
    if(password != null) {
      _logger.d(LOG_PREFIX + ": Loaded mgw device basic auth credentials");
      return password;
    }
    throw("Credentials not stored");
  }
}