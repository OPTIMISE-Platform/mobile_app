import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

class Failure {
  final ErrorCode errorCode;
  final String detailedMessage;

  /// HTTP status of the gateway's answer, null when none arrived.
  final int? statusCode;

  Failure(this.errorCode, this.detailedMessage, {this.statusCode});

  @override
  String toString() => statusCode == null
      ? "Failure($errorCode: $detailedMessage)"
      : "Failure($errorCode, HTTP $statusCode: $detailedMessage)";
}

enum ErrorCode {
  // Server 400
  NOT_FOUND,
  UNAUTHORIZED,
  BAD_REQUEST,

  // Server 500
  SERVER_ERROR,

  // Client
  CONNECT_TIMEOUT,
  CANCEL,
  RECEIVE_TIMEOUT,
  SEND_TIMEOUT,
  NO_INTERNET_CONNECTION,

  /// Refused or reset: nothing accepted the connection at that address.
  CONNECTION_ERROR,

  DEFAULT
}

/// The core services answer errors with a plain text body that names the cause,
/// while the status message only carries the HTTP reason phrase. Prefer the
/// body, but fall back for an empty, oversized or non-text one.
String _responseDetail(Response response) {
  final body = response.data;
  if (body is String) {
    final text = body.trim();
    if (text.isNotEmpty && text.length <= 200 && !text.startsWith("<")) {
      return text;
    }
  }
  // The identity provider answers with a JSON error object instead.
  if (body is Map) {
    final error = body["error"];
    final message = error is Map
        ? (error["reason"] ?? error["message"])
        : (body["message"] ?? error);
    if (message is String && message.trim().isNotEmpty) return message.trim();
  }
  return response.statusMessage ?? "";
}

Failure handleDioException(DioException error) {
  final logger = Logger(
    printer: SimplePrinter(),
  );

  Failure failure;
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
      failure = Failure(ErrorCode.CONNECT_TIMEOUT, error.message ?? "");
      break;
    case DioExceptionType.sendTimeout:
      failure = Failure(ErrorCode.SEND_TIMEOUT, error.message ?? "");
      break;
    case DioExceptionType.receiveTimeout:
      failure = Failure(ErrorCode.RECEIVE_TIMEOUT, error.message ?? "");
      break;
    case DioExceptionType.badResponse:
      // The reason phrase is optional on the wire, so only the status decides.
      final status = error.response?.statusCode;
      if (status != null) {
        var message = _responseDetail(error.response!);
        switch (status) {
          case 404:
            failure = Failure(ErrorCode.NOT_FOUND, message, statusCode: status);
            break;
          case 401:
            failure =
                Failure(ErrorCode.UNAUTHORIZED, message, statusCode: status);
            break;
          case 500:
            failure =
                Failure(ErrorCode.SERVER_ERROR, message, statusCode: status);
            break;
          default:
            failure = Failure(ErrorCode.DEFAULT, message, statusCode: status);
            break;
        }
        break;
      } else {
        failure = Failure(ErrorCode.DEFAULT, error.message ?? "");
        break;
      }
    case DioExceptionType.cancel:
      failure = Failure(ErrorCode.CANCEL, error.message ?? "");
      break;
    case DioExceptionType.connectionError:
      failure = Failure(ErrorCode.CONNECTION_ERROR,
          error.error?.toString() ?? error.message ?? "Connection failed");
      break;
    // A reset after connecting surfaces as unknown with the socket error.
    case DioExceptionType.unknown when error.error is SocketException:
      failure = Failure(ErrorCode.CONNECTION_ERROR, error.error.toString());
      break;
    default:
      final detail = error.message ?? error.error?.toString() ?? "Unknown error";
      failure = Failure(ErrorCode.DEFAULT, detail);
      break;
  }

  logger.e(
      "Error Code: ${failure.errorCode} - Detail: ${failure.detailedMessage}");
  return failure;
}
