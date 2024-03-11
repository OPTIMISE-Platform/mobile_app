import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

class Failure {
  final ErrorCode errorCode;
  final String detailedMessage;

  Failure(this.errorCode, this.detailedMessage);
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

  DEFAULT
}

Failure handleDioError(DioError error) {
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  Failure failure;
  switch (error.type) {
    case DioErrorType.connectTimeout:
      failure = Failure(ErrorCode.CONNECT_TIMEOUT, error.message);
      break;
    case DioErrorType.sendTimeout:
      failure = Failure(ErrorCode.SEND_TIMEOUT, error.message);
      break;
    case DioErrorType.receiveTimeout:
      failure = Failure(ErrorCode.RECEIVE_TIMEOUT, error.message);
      break;
    case DioErrorType.response:
      if (error.response != null &&
          error.response?.statusCode != null &&
          error.response?.statusMessage != null) {

        var message = error.response?.statusMessage ?? "";
        switch (error.response?.statusCode) {
          case 404:
            failure = Failure(ErrorCode.NOT_FOUND, message);
            break;
          case 401:
            failure = Failure(ErrorCode.UNAUTHORIZED, message);
            break;
          case 500:
            failure = Failure(ErrorCode.SERVER_ERROR, message);
            break;
          default:
            failure = Failure(ErrorCode.DEFAULT, message);
            break;
        }
        break;
      } else {
        failure = Failure(ErrorCode.DEFAULT, error.message);
        break;
      }
    case DioErrorType.cancel:
      failure = Failure(ErrorCode.CANCEL, error.message);
      break;
    default:
      failure = Failure(ErrorCode.DEFAULT, error.message);
      break;
  }

  _logger.e("Error Code: " + failure.errorCode.toString() + " - Detail: " + failure.detailedMessage);
  return failure;
}