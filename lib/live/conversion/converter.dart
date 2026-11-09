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

// Local port of the SENERGY converter: shortest path over the cast graph,
// input cleanup before every hop, extension edges that evaluate a formula.

import 'casts.dart';
import 'expression.dart';

export 'casts.dart' show Characteristics;
export 'expression.dart' show ConversionException;

/// A conversion rule from a concept (`concept.conversions`): a formula over
/// one placeholder, added to the built-in graph for one conversion call.
class ConversionEdge {
  final String from;
  final String to;
  final int distance;
  final String formula;
  final String placeholderName;

  const ConversionEdge({
    required this.from,
    required this.to,
    required this.distance,
    required this.formula,
    required this.placeholderName,
  });

  String get _key =>
      '$from\u0000$to\u0000$distance\u0000$formula\u0000$placeholderName';
}

/// Converts values between characteristics in the app, with the casts of the
/// SENERGY converter service.
class LocalConverter {
  static final _Graph _builtIn = _Graph(builtInCasts);
  static const int _maxCachedGraphs = 32;

  final Map<String, _Graph> _extended = {};

  /// Converts [value] from characteristic [from] to [to] along the shortest
  /// path over the built-in casts plus [extensions]. [from] equal to [to]
  /// returns [value] unchanged, a null [value] stays null. Throws
  /// [ConversionException] when there is no path or a cast fails.
  dynamic convert(
    dynamic value,
    String from,
    String to, {
    List<ConversionEdge> extensions = const [],
  }) {
    if (from == to) return value;
    if (value == null) return null;
    try {
      final graph = extensions.isEmpty ? _builtIn : _graphFor(extensions);
      var out = value;
      for (final cast in graph.casts(from, to)) {
        out = cast(_cleanup(out));
      }
      return out;
    } on ConversionException {
      rethrow;
    } catch (e) {
      throw ConversionException('recovered: $e');
    }
  }

  _Graph _graphFor(List<ConversionEdge> extensions) {
    final key = extensions.map((e) => e._key).join('\u0001');
    final cached = _extended[key];
    if (cached != null) return cached;
    final graph = _Graph([
      ...builtInCasts,
      for (final e in extensions)
        CastEdge(e.from, e.to, e.distance, _formulaCast(e)),
    ]);
    if (_extended.length >= _maxCachedGraphs) {
      _extended.remove(_extended.keys.first);
    }
    return _extended[key] = graph;
  }

  static CastFunction _formulaCast(ConversionEdge edge) {
    Expression? parsed;
    return (input) {
      try {
        parsed ??= Expression.parse(edge.formula);
      } on ConversionException catch (e) {
        throw ConversionException(
          'unable to parse extension expression (${edge.formula}): ${e.message}',
        );
      }
      try {
        return parsed!.evaluate(<String, dynamic>{edge.placeholderName: input});
      } on ConversionException catch (e) {
        throw ConversionException(
          'unable to evaluate extension expression (${edge.formula}) '
          'with input (${edge.placeholderName}): ${e.message}',
        );
      }
    };
  }
}

/// Port of the converter's inputCleanup: every number becomes a double, maps
/// and lists are rebuilt recursively, strings and bools stay.
dynamic _cleanup(dynamic v) {
  if (v == null || v is String || v is bool) return v;
  if (v is num) {
    final d = v.toDouble();
    if (!d.isFinite) {
      throw ConversionException('cleanup error: unsupported value: $d');
    }
    return d;
  }
  if (v is Map) {
    if (v.keys.every((k) => k is String)) {
      return <String, dynamic>{
        for (final e in v.entries) e.key as String: _cleanup(e.value),
      };
    }
    return <dynamic, dynamic>{
      for (final e in v.entries) e.key: _cleanup(e.value),
    };
  }
  if (v is List) return <dynamic>[for (final e in v) _cleanup(e)];
  throw ConversionException('cleanup error: unsupported type ${v.runtimeType}');
}

class _Arc {
  final int distance;
  final CastFunction cast;

  _Arc(this.distance, this.cast);
}

/// The cast graph. Later edges with the same from and to replace earlier
/// ones (an extension overrides a built-in cast), as in the Go register.
class _Graph {
  final Map<String, Map<String, _Arc>> _arcs = {};
  final Set<String> _nodes = {};
  final Map<String, List<CastFunction>> _paths = {};

  _Graph(Iterable<CastEdge> edges) {
    for (final edge in edges) {
      _arcs.putIfAbsent(edge.from, () => {})[edge.to] = _Arc(
        edge.distance,
        edge.cast,
      );
      _nodes
        ..add(edge.from)
        ..add(edge.to);
    }
  }

  List<CastFunction> casts(String from, String to) {
    final key = '$from\u0000$to';
    final cached = _paths[key];
    if (cached != null) return cached;
    final path = _shortestPath(from, to);
    final result = <CastFunction>[
      for (var i = 0; i + 1 < path.length; i++)
        _arcs[path[i]]![path[i + 1]]!.cast,
    ];
    return _paths[key] = result;
  }

  /// Label-correcting search by distance, as in the Go library: distances
  /// may be negative (extensions use -1 to win over built-in paths); once the
  /// target is reached, entries at or above its distance are dropped.
  List<String> _shortestPath(String from, String to) {
    if (!_nodes.contains(from)) {
      throw ConversionException('unknown characteristic $from');
    }
    if (!_nodes.contains(to)) {
      throw ConversionException('unknown characteristic $to');
    }
    final distance = <String, int>{from: 0};
    final previous = <String, String>{};
    var best = 0x7fffffffffffffff;
    var reached = false;
    final queue = <(String, int)>[(from, 0)];
    var steps = 0;
    while (queue.isNotEmpty) {
      if (++steps > 100000) {
        throw ConversionException(
          'no conversion path from $from to $to (cycle)',
        );
      }
      var index = 0;
      for (var i = 1; i < queue.length; i++) {
        if (queue[i].$2 < queue[index].$2) index = i;
      }
      final (node, nodeDistance) = queue.removeAt(index);
      final known = distance[node] ?? 0x7fffffffffffffff;
      if (nodeDistance >= best || nodeDistance > known) continue;
      for (final entry in (_arcs[node] ?? const <String, _Arc>{}).entries) {
        final target = entry.key;
        final candidate = nodeDistance + entry.value.distance;
        if (candidate < (distance[target] ?? 0x7fffffffffffffff)) {
          if (previous[node] == target && target != to) {
            throw ConversionException('loop in conversion graph at $node');
          }
          distance[target] = candidate;
          previous[target] = node;
          if (target == to) {
            reached = true;
            best = candidate;
            continue;
          }
          queue.add((target, candidate));
        }
      }
    }
    if (!reached) {
      throw ConversionException('no conversion path from $from to $to');
    }
    final path = <String>[to];
    var current = to;
    while (current != from) {
      current = previous[current]!;
      path.add(current);
      if (path.length > _nodes.length + 1) {
        throw ConversionException('cycle in conversion path from $from to $to');
      }
    }
    return path.reversed.toList();
  }
}
