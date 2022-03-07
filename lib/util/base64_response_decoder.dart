import 'dart:convert';

import 'package:dio/dio.dart';

ResponseDecoder DecodeIntoBase64() {
  return (List<int> responseBytes, RequestOptions options, ResponseBody responseBody) {
    return const Base64Encoder().convert(responseBytes);
  };
}
