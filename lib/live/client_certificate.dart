/*
 * Copyright 2026 InfAI (CC SES)
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

import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mutex/mutex.dart';

/// The client certificate of the cloud MQTT login, one per account.
///
/// The key is an EC P-256 key made on the phone; the platform CA signs a CSR
/// for it (`POST /ca/sign`) and sets the common name to the user id. The
/// hostname names phone and installation in the CA's list, as the MGW enters
/// its network id: manufacturer and model as the MGW pairing reports them, and
/// the MQTT client id of this installation ([certificateHostname]). From
/// half of its validity on, or when it was issued for another hostname, a new
/// certificate is fetched for the same key and the old one is revoked
/// (`POST /ca/revoke`), as the MGW cloud proxy does. A failed revoke is only
/// logged.
class ClientCertificates {
  ClientCertificates._();

  static final _logger = Logger(printer: SimplePrinter());

  // Without resetOnError: on Android every store shares one file, and its
  // reset would delete the other stores' values too.
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _expiration = '2160h';

  static const _keyPrefix = 'live-mqtt-key:';
  static const _certPrefix = 'live-mqtt-cert:';

  static String keyKeyOf(String account) => '$_keyPrefix$account';
  static String certKeyOf(String account) => '$_certPrefix$account';

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @visibleForTesting
  static Future<Dio> Function() dio = () => DioFactory.create(DioConfig.standard);

  @visibleForTesting
  static Future<Map<String, String>> Function() headers = () => Auth().getHeaders();

  @visibleForTesting
  static String? Function() apiUrl = Settings.getApiUrl;

  /// Manufacturer and model, as the app reports them when pairing with an MGW.
  @visibleForTesting
  static Future<(String, String)> Function() device = () async => (await getManufacturer(), await getDeviceName());

  static final _mutex = Mutex();

  /// Accounts whose certificate was replaced in this run because it lacked the
  /// hostname of [certificateHostname]. Once per run: a CA that leaves the
  /// hostname out must not be asked again on every connect.
  @visibleForTesting
  static final replacedForHostname = <String>{};

  /// Deletes the stored key and certificate of [account]; no revoke.
  static Future<void> forget(String account) => _mutex.protect(() => _forget(account));

  static Future<void> _forget(String account) async {
    // Each on its own: a failing first deletion must not keep the second.
    Object? failure;
    for (final key in [keyKeyOf(account), certKeyOf(account)]) {
      try {
        await _secure.delete(key: key);
      } catch (e) {
        failure ??= e;
      }
    }
    if (failure != null) throw failure;
  }

  /// Deletes the key and certificate of every account but [keep]. What an
  /// account switch wipes: the previous account is not known to the wipe, so
  /// it is everything that is not the current one. Does nothing without
  /// [keep].
  static Future<void> forgetAllBut(String? keep) async {
    if (keep == null || keep.isEmpty) return;
    await _mutex.protect(() async {
      final all = await _secure.readAll();
      Object? failure;
      for (final key in all.keys.toList()) {
        final account = key.startsWith(_keyPrefix)
            ? key.substring(_keyPrefix.length)
            : key.startsWith(_certPrefix)
                ? key.substring(_certPrefix.length)
                : null;
        if (account == null || account == keep) continue;
        try {
          await _secure.delete(key: key);
        } catch (e) {
          failure ??= e;
        }
      }
      if (failure != null) throw failure;
    });
  }

  /// The key and certificate (both PEM) of the signed-in account, renewed when
  /// past half of the validity or issued for another hostname. Null when there is none and none could be
  /// obtained; a certificate that is due for renewal but still valid is
  /// returned when the renewal failed.
  static Future<({String certPem, String keyPem})?> current() =>
      _mutex.protect(_current);

  static Future<({String certPem, String keyPem})?> _current() async {
    final account = Settings.getAccount();
    if (account == null || account.isEmpty) return null;
    try {
      final (manufacturer, model) = await device();
      final hostname = certificateHostname(manufacturer, model, await liveClientId());
      final keyPem = await _secure.read(key: keyKeyOf(account));
      final certPem = await _secure.read(key: certKeyOf(account));
      CertificateInfo? stored;
      if (certPem != null) {
        try {
          stored = CertificateInfo.parse(certPem);
        } on FormatException catch (e) {
          _logger.w('Stored live certificate is unreadable: ${e.message}');
        }
      }
      final now = clock();
      if (keyPem != null && certPem != null && stored != null && now.isBefore(stored.halfLife)) {
        if (stored.dnsNames.contains(hostname) || !replacedForHostname.add(account)) {
          return (certPem: certPem, keyPem: keyPem);
        }
        _logger.d('Live certificate lacks the hostname of this installation, replaced');
      }
      try {
        final obtained = await _obtain(account, hostname, keyPem, certPem, stored);
        if (obtained != null) return obtained;
        // Another account signed in meanwhile, nothing of this one is used.
        return null;
      } catch (e) {
        _logger.w('Could not obtain a live certificate: ${_describe(e)}');
        if (keyPem != null && certPem != null && stored != null && now.isBefore(stored.notAfter)) {
          return (certPem: certPem, keyPem: keyPem);
        }
        return null;
      }
    } catch (e) {
      _logger.w('Could not read the live certificate: ${_describe(e)}');
      return null;
    }
  }

  /// Null when the signed-in account is no longer [account] after the signing:
  /// the certificate is dropped, and nothing is stored under the old account.
  static Future<({String certPem, String keyPem})?> _obtain(
      String account, String hostname, String? storedKeyPem, String? oldCertPem, CertificateInfo? old) async {
    final (keyPem, priv, pub) = _keyPair(storedKeyPem);
    final csr = X509Utils.generateEccCsrPem({'CN': account}, priv, pub);

    final base = apiUrl();
    if (base == null || base.isEmpty) throw StateError('no API url');
    final client = await dio();
    final response = await client.post<String>(
      '$base/ca/sign',
      data: {
        'csr': csr,
        'expiration': _expiration,
        'hostnames': [hostname],
      },
      options: Options(headers: await headers(), responseType: ResponseType.plain),
    );
    final certPem = response.data;
    if (certPem == null) throw const FormatException('empty certificate response');
    // Parsed before it is stored: a body that is not a certificate must not
    // replace a working one.
    CertificateInfo.parse(certPem);

    // The signing took a while; an account switch in between must not get the
    // old account's certificate stored, nor have it used.
    if (Settings.getAccount() != account) {
      _logger.d('Account changed while a live certificate was signed, discarded');
      return null;
    }

    await _secure.write(key: keyKeyOf(account), value: keyPem);
    await _secure.write(key: certKeyOf(account), value: certPem);

    if (old != null) {
      await _revoke(client, base, old);
    }
    return (certPem: certPem, keyPem: keyPem);
  }

  static Future<void> _revoke(Dio client, String base, CertificateInfo old) async {
    final aki = old.authorityKeyId;
    if (aki == null) {
      _logger.w('Old live certificate has no authority key id, not revoked');
      return;
    }
    try {
      await client.post<dynamic>(
        '$base/ca/revoke',
        data: {'serial': old.serial.toString(), 'authority_key_id': aki, 'reason': 'superseded'},
        options: Options(headers: await headers(), responseType: ResponseType.plain),
      );
    } catch (e) {
      _logger.w('Could not revoke the old live certificate: ${_describe(e)}');
    }
  }

  /// The stored key, or a new one. The public key of a stored key is derived.
  static (String, ECPrivateKey, ECPublicKey) _keyPair(String? storedKeyPem) {
    if (storedKeyPem != null) {
      try {
        final priv = CryptoUtils.ecPrivateKeyFromPem(storedKeyPem);
        final q = priv.parameters!.G * priv.d!;
        return (storedKeyPem, priv, ECPublicKey(q, priv.parameters));
      } catch (e) {
        _logger.w('Stored live key is unreadable, making a new one: ${_describe(e)}');
      }
    }
    final pair = CryptoUtils.generateEcKeyPair();
    final priv = pair.privateKey as ECPrivateKey;
    return (CryptoUtils.encodeEcPrivateKeyToPem(priv), priv, pair.publicKey as ECPublicKey);
  }

  /// `<device>.<clientId>`, e.g. `google-pixel-7.optimise-app-<installId>`. The
  /// device part is lowercase letters, digits and hyphens, at most 63 long, so
  /// the CA keeps it as a dNSName; the manufacturer is left out when the model
  /// starts with it.
  @visibleForTesting
  static String certificateHostname(String manufacturer, String model, String clientId) {
    final name = model.toLowerCase().startsWith(manufacturer.toLowerCase()) ? model : '$manufacturer $model';
    var label = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    if (label.length > 63) label = label.substring(0, 63);
    label = label.replaceAll(RegExp(r'^-+|-+$'), '');
    return label.isEmpty ? clientId : '$label.$clientId';
  }

  /// No response body, header or key material: those carry the token.
  static String _describe(Object e) {
    if (e is DioException) return 'HTTP ${e.response?.statusCode ?? e.type.name}';
    return e.runtimeType.toString();
  }
}

/// The few fields of an X.509 certificate that the live login needs, read from
/// the DER encoding directly: validity and hostnames decide the renewal, serial
/// and authority key id name the certificate at the CA when it is revoked.
class CertificateInfo {
  final BigInt serial;
  final DateTime notBefore;
  final DateTime notAfter;

  /// Lowercase hex of the keyIdentifier of the AuthorityKeyIdentifier
  /// extension, as the CA's revoke endpoint takes it; null when absent.
  final String? authorityKeyId;

  /// The dNSName entries of the SubjectAltName extension, where the CA puts
  /// the hostnames of the sign request.
  final List<String> dnsNames;

  CertificateInfo(this.serial, this.notBefore, this.notAfter, this.authorityKeyId, this.dnsNames);

  DateTime get halfLife => notBefore.add(notAfter.difference(notBefore) ~/ 2);

  /// Throws [FormatException] when [pem] holds no readable certificate.
  factory CertificateInfo.parse(String pem) {
    final match = RegExp(r'-----BEGIN CERTIFICATE-----([^-]+)-----END CERTIFICATE-----').firstMatch(pem);
    if (match == null) throw const FormatException('no certificate');
    try {
      final der = base64.decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
      return _parseDer(der);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('unreadable certificate: ${e.runtimeType}');
    }
  }

  static CertificateInfo _parseDer(Uint8List der) {
    final cert = _Tlv.read(der, 0);
    if (cert.tag != 0x30) throw const FormatException('certificate is not a sequence');
    final tbs = _Tlv.read(der, cert.start);
    if (tbs.tag != 0x30) throw const FormatException('tbsCertificate is not a sequence');
    final fields = _Tlv.children(der, tbs);
    var i = 0;
    if (fields[i].tag == 0xA0) i++; // version
    final serialField = fields[i++];
    if (serialField.tag != 0x02) throw const FormatException('no serial number');
    i++; // signature algorithm
    i++; // issuer
    final validity = _Tlv.children(der, fields[i++]);
    final notBefore = _time(der, validity[0]);
    final notAfter = _time(der, validity[1]);

    String? aki;
    final dnsNames = <String>[];
    for (final f in fields.skip(i)) {
      if (f.tag != 0xA3) continue;
      final extensions = _Tlv.children(der, _Tlv.read(der, f.start));
      for (final ext in extensions) {
        final parts = _Tlv.children(der, ext);
        final oid = der.sublist(parts[0].start, parts[0].end);
        // 2.5.29.35 authorityKeyIdentifier, 2.5.29.17 subjectAltName
        if (oid.length != 3 || oid[0] != 0x55 || oid[1] != 0x1D || (oid[2] != 0x23 && oid[2] != 0x11)) {
          continue;
        }
        final value = parts.last; // OCTET STRING wrapping a SEQUENCE
        final seq = _Tlv.read(der, value.start);
        for (final item in _Tlv.children(der, seq)) {
          final content = der.sublist(item.start, item.end);
          if (oid[2] == 0x23 && item.tag == 0x80) {
            // keyIdentifier [0]
            aki = [for (final b in content) b.toRadixString(16).padLeft(2, '0')].join();
          } else if (oid[2] == 0x11 && item.tag == 0x82) {
            // dNSName [2] IA5String
            dnsNames.add(ascii.decode(content));
          }
        }
      }
    }
    return CertificateInfo(_integer(der, serialField), notBefore, notAfter, aki, dnsNames);
  }

  static BigInt _integer(Uint8List der, _Tlv t) {
    final bytes = der.sublist(t.start, t.end);
    var value = BigInt.zero;
    for (final b in bytes) {
      value = (value << 8) | BigInt.from(b);
    }
    if (bytes.isNotEmpty && bytes.first & 0x80 != 0) {
      value -= BigInt.one << (8 * bytes.length);
    }
    return value;
  }

  static DateTime _time(Uint8List der, _Tlv t) {
    final s = ascii.decode(der.sublist(t.start, t.end));
    final String full;
    if (t.tag == 0x17) {
      // UTCTime: YYMMDDHHMMSSZ, two digit years from 50 on are 19xx.
      final yy = int.parse(s.substring(0, 2));
      full = '${yy >= 50 ? 19 : 20}$s';
    } else if (t.tag == 0x18) {
      full = s;
    } else {
      throw const FormatException('unknown time type');
    }
    final m = RegExp(r'^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(?:\.\d+)?Z$').firstMatch(full);
    if (m == null) throw const FormatException('unknown time format');
    final n = [for (var g = 1; g <= 6; g++) int.parse(m.group(g)!)];
    return DateTime.utc(n[0], n[1], n[2], n[3], n[4], n[5]);
  }
}

/// One DER element: [start, end) is its content.
class _Tlv {
  final int tag;
  final int start;
  final int end;

  _Tlv(this.tag, this.start, this.end);

  static _Tlv read(Uint8List b, int pos) {
    if (pos + 2 > b.length) throw const FormatException('truncated DER');
    final tag = b[pos];
    var len = b[pos + 1];
    var start = pos + 2;
    if (len & 0x80 != 0) {
      final n = len & 0x7F;
      if (n == 0 || n > 4 || start + n > b.length) throw const FormatException('bad DER length');
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | b[start + i];
      }
      start += n;
    }
    if (start + len > b.length) throw const FormatException('truncated DER');
    return _Tlv(tag, start, start + len);
  }

  static List<_Tlv> children(Uint8List b, _Tlv parent) {
    final out = <_Tlv>[];
    var pos = parent.start;
    while (pos < parent.end) {
      final t = read(b, pos);
      out.add(t);
      pos = t.end;
    }
    return out;
  }
}
