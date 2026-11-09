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

import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/protocol.dart';
import 'package:mobile_app/models/service.dart';

/// The value at [path] of one output of [service], read from a raw event [segments] map (protocol segment name -> serialized string), and the characteristic/function of the content variable at that path. Null when the path is not in this service's outputs, the segment is missing, or the serialization is unsupported.
///
/// Mirrors the marshaller (v2/unmarshal.go): the decoded segment is stored under
/// the top-level content variable name, and the rest of [path] walks into it.
/// A "*" segment means index 0. Structured values (Map or List) return null,
/// since live updates only carry scalars.
({dynamic value, String? characteristicId, String functionId})? extractValue(
    Service service, Protocol protocol, Map<String, String> segments, String path) {
  final parts = path.split('.').map((p) => p == '*' ? '0' : p).toList();
  final outputs = service.outputs;
  if (outputs == null) return null;

  for (final content in outputs) {
    final root = content.content_variable;
    if (root.name != parts.first) continue;

    final segmentName = _segmentName(protocol, content.protocol_segment_id);
    if (segmentName == null) return null;
    final raw = segments[segmentName];
    if (raw == null) return null;

    final Object? decoded;
    switch (content.serialization) {
      case 'json':
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          return null;
        }
      case 'plain-text':
        // The marshaller hands the segment back as the plain string (plain.go);
        // the content variable's type is all that says what it holds.
        decoded = _castPlain(raw, root.type);
        if (decoded == null) return null;
      default:
        return null;
    }

    dynamic value = decoded;
    var variable = root;
    for (final name in parts.skip(1)) {
      final sub = _subVariable(variable, name);
      if (sub == null) return null;
      variable = sub;
      value = _child(value, name);
      if (value == null) return null;
    }
    if (value is Map || value is List) return null;

    return (
      value: value,
      characteristicId: variable.characteristic_id,
      functionId: variable.function_id ?? '',
    );
  }
  return null;
}

/// A plain-text segment as the type of its content variable. Null when it does
/// not parse. Only the literal `true` and `false` are booleans, in any case.
Object? _castPlain(String raw, ContentType type) {
  final text = raw.trim();
  switch (type) {
    case ContentVariable.float:
      final value = double.tryParse(text);
      return value != null && value.isFinite ? value : null;
    case ContentVariable.integer:
      return int.tryParse(text);
    case ContentVariable.boolean:
      return switch (text.toLowerCase()) { 'true' => true, 'false' => false, _ => null };
    default:
      return raw;
  }
}

String? _segmentName(Protocol protocol, String segmentId) {
  for (final segment in protocol.protocol_segments) {
    if (segment.id == segmentId) return segment.name;
  }
  return null;
}

/// A list variable carries one template named "*" that the marshaller clones
/// per index, so an index without its own entry resolves to that template.
ContentVariable? _subVariable(ContentVariable parent, String name) {
  final subs = parent.sub_content_variables;
  if (subs == null || subs.isEmpty) return null;
  for (final sub in subs) {
    if (sub.name == name) return sub;
  }
  if (parent.type == ContentVariable.list && subs.first.name == '*') return subs.first;
  return null;
}

dynamic _child(dynamic value, String name) {
  if (value is Map) return value[name];
  if (value is List) {
    final index = int.tryParse(name);
    if (index == null || index < 0 || index >= value.length) return null;
    return value[index];
  }
  return null;
}
