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

import 'package:dio/dio.dart';

/// The validator the backend sent with a stored list: its `ETag` and the full
/// request URI the answer belongs to. An `ETag` only validates the exact
/// resource it came from, so the URI travels with it.
class MetadataValidator {
  final String etag;
  final String uri;

  const MetadataValidator(this.etag, this.uri);

  @override
  bool operator ==(Object other) =>
      other is MetadataValidator && other.etag == etag && other.uri == uri;

  @override
  int get hashCode => Object.hash(etag, uri);

  @override
  String toString() => 'MetadataValidator($etag, $uri)';
}

/// What a metadata fetch produced.
sealed class MetadataFetch {
  const MetadataFetch();
}

/// The list as the backend sent it. [validator] is set only when the whole
/// list came in a single answer that carried an `ETag`.
class Fetched extends MetadataFetch {
  final List<dynamic> raw;
  final MetadataValidator? validator;

  const Fetched(this.raw, this.validator);
}

/// The backend answered `304` to the stored validator: the stored copy is
/// current.
class NotModified extends MetadataFetch {
  const NotModified();
}

/// Options for a request to [uri]. `If-None-Match` is sent only when
/// [validator] comes from exactly this URI. A `304` counts as a valid status,
/// so the caller sees it as a response instead of a [DioException].
Options conditionalOptions(
    Map<String, String> headers, Uri uri, MetadataValidator? validator) {
  final h = Map<String, String>.of(headers);
  if (validator != null && validator.uri == uri.toString()) {
    h['If-None-Match'] = validator.etag;
  }  return Options(
    headers: h,
    validateStatus: (s) => s != null && ((s >= 200 && s < 300) || s == 304),
  );
}

/// ETag and URI of a `200` answer, null without an `ETag` header. The value is
/// kept as sent, a weak `W/"..."` included, and goes back unchanged.
MetadataValidator? validatorOf(Response<dynamic> resp) {
  final etag = resp.headers.value('etag');  if (etag == null || etag.trim().isEmpty) return null;
  return MetadataValidator(etag, resp.requestOptions.uri.toString());
}
