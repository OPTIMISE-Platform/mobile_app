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

import 'dart:async';

import 'package:basic_utils/basic_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/live/client_certificate.dart';
import 'package:mobile_app/services/settings.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// Two certificates for one key, issued by a throwaway CA with `openssl x509
// -req` (authorityKeyIdentifier=keyid, CN=test-account,
// subjectAltName=DNS:google-pixel-7.optimise-app-test-install). The first is valid 2026-01-01
// to 2026-02-01 (half: 2026-01-16 12:00 UTC), serial 0x0A1B2C3D.
const _oldCert = """-----BEGIN CERTIFICATE-----
MIIBqTCCAU+gAwIBAgIEChssPTAKBggqhkjOPQQDAjASMRAwDgYDVQQDDAd0ZXN0
IGNhMB4XDTI2MDEwMTAwMDAwMFoXDTI2MDIwMTAwMDAwMFowFzEVMBMGA1UEAwwM
dGVzdC1hY2NvdW50MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4FNPPTSgM6Vk
5Ea34/6Cm06Od/Z8SDeSubSW239av7o8Po00jSHGxRohrYeSXczQfgv5kHnpoGL0
BWEmpCgrcqOBjTCBijAdBgNVHQ4EFgQU7KoHCwUejXt5Uaw02N2T3xDDh44wEwYD
VR0lBAwwCgYIKwYBBQUHAwIwHwYDVR0jBBgwFoAUkOwHzwifihL9kkCYX5xzqcWH
Bz8wMwYDVR0RBCwwKoIoZ29vZ2xlLXBpeGVsLTcub3B0aW1pc2UtYXBwLXRlc3Qt
aW5zdGFsbDAKBggqhkjOPQQDAgNIADBFAiB8TdEE7U57ZyXGGGEmiknP9ghvzRe7
F22baR2akS2RUwIhALcSDgaxKln4GZx7rniNxpi4+irHgRsl0xQSMOYPNG8Y
-----END CERTIFICATE-----""";

// Serial 0x0A1B2C3E, valid 2026-01-16 to 2026-03-01.
const _newCert = """-----BEGIN CERTIFICATE-----
MIIBqTCCAU+gAwIBAgIEChssPjAKBggqhkjOPQQDAjASMRAwDgYDVQQDDAd0ZXN0
IGNhMB4XDTI2MDExNjAwMDAwMFoXDTI2MDMwMTAwMDAwMFowFzEVMBMGA1UEAwwM
dGVzdC1hY2NvdW50MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4FNPPTSgM6Vk
5Ea34/6Cm06Od/Z8SDeSubSW239av7o8Po00jSHGxRohrYeSXczQfgv5kHnpoGL0
BWEmpCgrcqOBjTCBijAdBgNVHQ4EFgQU7KoHCwUejXt5Uaw02N2T3xDDh44wEwYD
VR0lBAwwCgYIKwYBBQUHAwIwHwYDVR0jBBgwFoAUkOwHzwifihL9kkCYX5xzqcWH
Bz8wMwYDVR0RBCwwKoIoZ29vZ2xlLXBpeGVsLTcub3B0aW1pc2UtYXBwLXRlc3Qt
aW5zdGFsbDAKBggqhkjOPQQDAgNIADBFAiBK0F2Igu9oqqtrPYKuUBGEUQlQp0NJ
E7LSelQnxbRl3AIhAN2l37i2ZKrf0mvr9D7JNkPLTpmBPzqN/JRkjQAO1CGh
-----END CERTIFICATE-----""";

const _oldSerial = '169552957';
const _akiHex = '90ec07cf089f8a12fd9240985f9c73a9c587073f';

// As the app got it before it sent a hostname: no subjectAltName, another
// throwaway CA, valid 2026-01-01 to 2026-02-01, serial 0x0A1B2C3D.
const _certWithoutHostname = """-----BEGIN CERTIFICATE-----
MIIBczCCARigAwIBAgIEChssPTAKBggqhkjOPQQDAjASMRAwDgYDVQQDDAd0ZXN0
IGNhMB4XDTI2MDEwMTAwMDAwMFoXDTI2MDIwMTAwMDAwMFowFzEVMBMGA1UEAwwM
dGVzdC1hY2NvdW50MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEc4KrVJCCgFwm
gr+2Ai5E1D0frOo/4zCZi8KL0HWmcwWFSZK2JArYtCxXplPnhOfLbM3mtvuyETG7
A1IFg2tYF6NXMFUwHwYDVR0jBBgwFoAUUy2RkM3lL/Ao8+eVCYlm9511xAEwEwYD
VR0lBAwwCgYIKwYBBQUHAwIwHQYDVR0OBBYEFDE/cBMtOyXlrwVLOyr2aWhkuAe8
MAoGCCqGSM49BAMCA0kAMEYCIQDigdj348n72DMdCYpAk2NaIMD4bHHvZH18fHYx
jiWmLQIhANXVxKiZG5yHSnxgm0bGtKNgN8mViKE98xEODcQ09HGY
-----END CERTIFICATE-----""";

const _akiHexWithoutHostname = '532d9190cde52ff028f3e795098966f79d75c401';

const _hostname = 'google-pixel-7.optimise-app-test-install';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  late FakeBackend backend;
  late DateTime now;
  const storage = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'live-mqtt-install-id': 'test-install'});
    ClientCertificates.replacedForHostname.clear();
    backend = FakeBackend();
    now = DateTime.utc(2026, 1, 5);
    ClientCertificates.clock = () => now;
    ClientCertificates.apiUrl = () => 'https://api.test';
    ClientCertificates.device = () async => ('Google', 'Pixel 7');
    ClientCertificates.headers = () async => {'Authorization': 'Bearer t'};
    final dio = Dio()..httpClientAdapter = backend;
    ClientCertificates.dio = () async => dio;
  });

  tearDown(() {
    ClientCertificates.clock = DateTime.now;
  });

  Future<String?> stored(String key) => storage.read(key: key);
  String keyKey() => ClientCertificates.keyKeyOf('test-account');
  String certKey() => ClientCertificates.certKeyOf('test-account');

  List<RequestOptions> calls(String path) =>
      [for (final r in backend.requests) if (r.uri.path == path) r];

  void serveSign(String pem) =>
      backend.serveJson('POST', '/ca/sign', 200, pem, contentType: 'text/plain');

  test('reads serial, validity and authority key id from a certificate', () {
    final info = CertificateInfo.parse(_oldCert);
    expect(info.serial.toString(), _oldSerial);
    expect(info.notBefore, DateTime.utc(2026, 1, 1));
    expect(info.notAfter, DateTime.utc(2026, 2, 1));
    expect(info.authorityKeyId, _akiHex);
    expect(info.halfLife, DateTime.utc(2026, 1, 16, 12));
    expect(info.dnsNames, [_hostname]);
    expect(CertificateInfo.parse(_certWithoutHostname).dnsNames, isEmpty);
    expect(() => CertificateInfo.parse('nonsense'), throwsFormatException);
  });

  test('the hostname names the phone as the MGW pairing reports it, then the installation', () {
    String host(String manufacturer, String model) =>
        ClientCertificates.certificateHostname(manufacturer, model, 'optimise-app-x');
    expect(host('Google', 'Pixel 7'), 'google-pixel-7.optimise-app-x');
    expect(host('OnePlus', 'OnePlus 9 Pro'), 'oneplus-9-pro.optimise-app-x', reason: 'model already names the maker');
    expect(host('Apple', 'iPhone14,2'), 'apple-iphone14-2.optimise-app-x');
    expect(host('samsung', 'SM-G991B'), 'samsung-sm-g991b.optimise-app-x');
    expect(host('', '--'), 'optimise-app-x');
    expect(host('x', 'y' * 80).split('.').first, hasLength(63));
  });

  test('the first call posts a CSR for the account and stores key and certificate', () async {
    serveSign(_oldCert);

    final pair = await ClientCertificates.current();

    expect(pair, isNotNull);
    expect(pair!.certPem, _oldCert);
    final sign = calls('/ca/sign');
    expect(sign, hasLength(1));
    expect(sign.single.headers['Authorization'], 'Bearer t');
    final body = sign.single.data as Map;
    expect(body['expiration'], '2160h');
    expect(body['hostnames'], [_hostname], reason: 'phone as the MGW pairing reports it, and the MQTT client id');
    final csr = X509Utils.csrFromPem(body['csr'] as String);
    expect(csr.certificationRequestInfo?.subject?.values, contains('test-account'));
    expect(await stored(keyKey()), pair.keyPem);
    expect(await stored(certKey()), _oldCert);
    expect(calls('/ca/revoke'), isEmpty);
  });

  test('before half of the validity the stored pair is reused without a request', () async {
    serveSign(_oldCert);
    final first = await ClientCertificates.current();
    backend.requests.clear();

    now = DateTime.utc(2026, 1, 10);
    final second = await ClientCertificates.current();

    expect(second?.certPem, first?.certPem);
    expect(second?.keyPem, first?.keyPem);
    expect(backend.requests, isEmpty);
  });

  test('after half of the validity a new certificate for the same key is stored, then the old one is revoked', () async {
    serveSign(_oldCert);
    final first = await ClientCertificates.current();
    final firstCsr = (calls('/ca/sign').single.data as Map)['csr'] as String;
    backend.requests.clear();

    now = DateTime.utc(2026, 1, 20);
    serveSign(_newCert);
    backend.serveJson('POST', '/ca/revoke', 200, null);
    final second = await ClientCertificates.current();

    expect(second?.certPem, _newCert);
    expect(second?.keyPem, first?.keyPem);
    expect(await stored(certKey()), _newCert);
    expect(await stored(keyKey()), first?.keyPem);
    expect([for (final r in backend.requests) r.uri.path], ['/ca/sign', '/ca/revoke']);

    final renewCsr = (calls('/ca/sign').single.data as Map)['csr'] as String;
    expect(X509Utils.csrFromPem(renewCsr).certificationRequestInfo?.publicKeyInfo?.bytes,
        X509Utils.csrFromPem(firstCsr).certificationRequestInfo?.publicKeyInfo?.bytes);

    final revoke = calls('/ca/revoke').single;
    expect(revoke.headers['Authorization'], 'Bearer t');
    expect(revoke.data, {
      'serial': _oldSerial,
      'authority_key_id': _akiHex,
      'reason': 'superseded',
    });
  });

  test('a certificate without the hostname of this installation is replaced at once, then the old one is revoked', () async {
    serveSign(_certWithoutHostname);
    final first = await ClientCertificates.current();
    backend.requests.clear();

    serveSign(_oldCert);
    backend.serveJson('POST', '/ca/revoke', 200, null);
    final second = await ClientCertificates.current();

    expect(second?.certPem, _oldCert);
    expect(second?.keyPem, first?.keyPem);
    expect(await stored(certKey()), _oldCert);
    expect([for (final r in backend.requests) r.uri.path], ['/ca/sign', '/ca/revoke']);
    expect((calls('/ca/sign').single.data as Map)['hostnames'], [_hostname]);
    expect(calls('/ca/revoke').single.data, {
      'serial': _oldSerial,
      'authority_key_id': _akiHexWithoutHostname,
      'reason': 'superseded',
    });

    backend.requests.clear();
    expect((await ClientCertificates.current())?.certPem, _oldCert);
    expect(backend.requests, isEmpty);
  });

  test('a CA that leaves the hostname out is asked again only in the next run', () async {
    serveSign(_certWithoutHostname);
    await ClientCertificates.current();
    backend.serveJson('POST', '/ca/revoke', 200, null);
    await ClientCertificates.current();
    expect(calls('/ca/sign'), hasLength(2));
    backend.requests.clear();

    expect((await ClientCertificates.current())?.certPem, _certWithoutHostname);
    expect(backend.requests, isEmpty);

    ClientCertificates.replacedForHostname.clear(); // a new run
    await ClientCertificates.current();
    expect(calls('/ca/sign'), hasLength(1));
  });

  test('a failed revoke keeps the new certificate', () async {
    serveSign(_oldCert);
    await ClientCertificates.current();

    now = DateTime.utc(2026, 1, 20);
    serveSign(_newCert);
    backend.serveJson('POST', '/ca/revoke', 500, 'boom');
    final pair = await ClientCertificates.current();

    expect(pair?.certPem, _newCert);
    expect(await stored(certKey()), _newCert);
    expect(calls('/ca/revoke'), hasLength(1));

    // Not asked again: the new certificate is young.
    backend.requests.clear();
    expect((await ClientCertificates.current())?.certPem, _newCert);
    expect(backend.requests, isEmpty);
  });

  test('a failed renewal returns the old certificate while it is valid, then null', () async {
    serveSign(_oldCert);
    await ClientCertificates.current();

    now = DateTime.utc(2026, 1, 20);
    backend.serveJson('POST', '/ca/sign', 503, 'down');
    expect((await ClientCertificates.current())?.certPem, _oldCert);

    now = DateTime.utc(2026, 2, 5);
    expect(await ClientCertificates.current(), isNull);
    expect(await stored(certKey()), _oldCert);
  });

  test('a first call that fails, or gets no certificate, returns null and stores nothing', () async {
    backend.serveJson('POST', '/ca/sign', 403, 'forbidden');
    expect(await ClientCertificates.current(), isNull);

    serveSign('not a certificate');
    expect(await ClientCertificates.current(), isNull);

    expect(await stored(certKey()), isNull);
    expect(await stored(keyKey()), isNull);
  });

  test('a signing that ends after an account switch is discarded and stores nothing', () async {
    serveSign(_oldCert);
    final gate = Completer<void>();
    backend.holds['POST /ca/sign'] = gate;

    final pending = ClientCertificates.current();
    await pumpEventQueue();
    expect(calls('/ca/sign'), hasLength(1));
    await Settings.setAccount('other-account');
    try {
      gate.complete();
      expect(await pending, isNull);
    } finally {
      await Settings.setAccount('test-account');
    }

    expect(await stored(keyKey()), isNull);
    expect(await stored(certKey()), isNull);
    expect(await stored(ClientCertificates.keyKeyOf('other-account')), isNull);
    expect(await stored(ClientCertificates.certKeyOf('other-account')), isNull);
  });

  test('forget deletes key and certificate of one account, forgetAllBut those of all others', () async {
    for (final a in ['a', 'b', 'c']) {
      await storage.write(key: ClientCertificates.keyKeyOf(a), value: 'k$a');
      await storage.write(key: ClientCertificates.certKeyOf(a), value: 'c$a');
    }
    await storage.write(key: 'unrelated', value: 'x');

    await ClientCertificates.forget('a');
    expect(await stored(ClientCertificates.keyKeyOf('a')), isNull);
    expect(await stored(ClientCertificates.certKeyOf('a')), isNull);
    expect(await stored(ClientCertificates.keyKeyOf('b')), 'kb');

    await ClientCertificates.forgetAllBut('c');
    expect(await stored(ClientCertificates.keyKeyOf('b')), isNull);
    expect(await stored(ClientCertificates.certKeyOf('b')), isNull);
    expect(await stored(ClientCertificates.keyKeyOf('c')), 'kc');
    expect(await stored(ClientCertificates.certKeyOf('c')), 'cc');
    expect(await stored('unrelated'), 'x');

    await ClientCertificates.forgetAllBut(null);
    expect(await stored(ClientCertificates.keyKeyOf('c')), 'kc', reason: 'without an account to keep nothing is deleted');
  });
}
