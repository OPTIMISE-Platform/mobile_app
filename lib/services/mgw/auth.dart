import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/shared/dio_factory.dart';

@JsonSerializable()
class InitLoginResponse {
  String flowId;

  InitLoginResponse(this.flowId);
  InitLoginResponse.fromJson(Map<String, dynamic> json): flowId = json['id'];
}

@JsonSerializable()
class LoginResponse {
  String token;
  String expires_at;

  LoginResponse(this.token, this.expires_at);
  LoginResponse.fromJson(Map<String, dynamic> json): token = json['session_token'], expires_at = json['session']['expires_at'];
}

@JsonSerializable()
class KratosClientErrorMessage {
  String id;
  String message;

  KratosClientErrorMessage(this.id, this.message);
  KratosClientErrorMessage.fromJson(Map<String, dynamic> json): id = json['id'], message = json['text'];
}

/*
Failure handleKratosClientError(Failure failure) {
  if(failure.errorCode == ErrorCode.BAD_REQUEST) {
    failure.message
  }
}*/

const LOG_PREFIX = "MGW-AUTH-SERVICE";

class MgwAuth {
  MgwAuth._(this._dio, this.baseUrl);

  final Dio _dio;
  final String baseUrl;

  static const authPath = "/core/auth";
  static const loginPath = "/login";

  final _logger = Logger(printer: SimplePrinter());

  static Future<MgwAuth> create(String host) async {
    final dio = await DioFactory.create(DioConfig.mgwAuth);
    return MgwAuth._(dio, "http://$host:8080$authPath");
  }

  Future<LoginResponse> Login(String? username, String? password) async {
    final loginInitResponse = await InitLogin();
    return await CompleteLogin(loginInitResponse.flowId, username, password);
  }

  Future<LoginResponse> CompleteLogin(String flowId, String? username, String? password) async {
    final payload = jsonEncode({'identifier': username, 'password': password, 'method': "password"});
    Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio.post<Map<String, dynamic>>(
        "$baseUrl$loginPath?refresh=true&flow=$flowId",
        data: payload,
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      _logger.e("$LOG_PREFIX: Could not login");
      throw handleDioException(e);
    }

    if (resp.data == null) throw Exception("Login response empty");
    return LoginResponse.fromJson(resp.data!);
  }

  Future<InitLoginResponse> InitLogin() async {
    Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio.get<Map<String, dynamic>>("$baseUrl$loginPath/api");
    } on DioException catch (e) {
      _logger.e("$LOG_PREFIX: Could not init login");
      throw handleDioException(e);
    }

    if (resp.data == null) throw Exception("Login response empty");
    return InitLoginResponse.fromJson(resp.data!);
  }
}