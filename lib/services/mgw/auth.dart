import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/error.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

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
  // Use this service to access the exposed identity provider for login/logout

  final authPath = "/core/auth";
  final loginPath = "/login";
  String baseUrl = "";

  MgwAuth(String host) {
    baseUrl = "http://" + host + ":8080" + authPath;
  }

  final _logger = Logger(
    printer: SimplePrinter(),
  );

  final dio = Dio(BaseOptions(
      connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
    ..interceptors.add(ApiAvailableInterceptor());

  Future<LoginResponse> Login(String? username, String? password) async {
    var loginInitResponse = await InitLogin();
    var loginResponse = await CompleteLogin(loginInitResponse.flowId, username, password);
    return loginResponse;
  }

  Future<LoginResponse> CompleteLogin(String flowId, String? username, String? password) async {
    // Also automatically refreshes token
    var data = {'identifier': username, 'password': password, 'method': "password"};
    final payload = jsonEncode(data);
    Response<Map<String, dynamic>> resp;
    try {
      resp = await dio.post<Map<String, dynamic>>(baseUrl + loginPath + "?refresh=true&flow=" + flowId, data: payload, options: Options(contentType: Headers.jsonContentType));
    } on DioError catch (e) {
      _logger.e(LOG_PREFIX + ": Could not login");
      var failure = handleDioError(e);
      throw(failure);
    };

    if(resp.data == null) {
      throw("Login response empty");
    } else {
      return LoginResponse.fromJson(resp.data!);
    }
  }

  Future<InitLoginResponse> InitLogin() async {
    Response<Map<String, dynamic>> resp;

    try {
      resp = await dio.get<Map<String, dynamic>>(baseUrl + loginPath + "/api");
    } on DioError catch (e) {
      _logger.e(LOG_PREFIX + ": Could not init login");
      var failure = handleDioError(e);
      throw(failure);
    };

    if(resp.data == null) {
      throw("Login response empty");
    } else {
      return InitLoginResponse.fromJson(resp.data!);
    }
  }
}