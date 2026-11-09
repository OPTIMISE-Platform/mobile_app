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

// Evaluator for the formula language of SENERGY converter extensions.
//
// Own derivation: a hand-written lexer and a recursive-descent parser, one
// method per precedence level, written from the govaluate v3 manual and from
// running the Go library on probe expressions. No code was taken over.
//
// Observed Go behaviour that is reproduced on purpose:
//  * every number literal and every parameter is a float64 ([double]); the
//    integer-valued results of strlen, strIndex and atoi stay integers
//    ([int]) and therefore fail arithmetic and compare unequal to doubles;
//  * `a ? b : c` is not right-associative: the operators `?`, `:` and `??`
//    share one level and group from the left, so `a ? b : c ? d : e` only
//    works when parenthesised;
//  * a string literal ends at the first quote character of either kind;
//  * symbol characters are read greedily, so `x==-1` is a syntax error.
//
// Not supported and rejected with a [ConversionException] instead of being
// evaluated: regex (`=~`, `!~`), bit operators, `in`, date-like string
// literals, comma expressions outside a call, hex float input to atof, and
// trailing tokens after a complete expression.

import 'dart:convert';
import 'dart:math' as math;

/// Raised for every parse, evaluation or conversion failure.
class ConversionException implements Exception {
  final String message;

  const ConversionException(this.message);

  @override
  String toString() => 'ConversionException: $message';
}

/// A custom function of the formula language. Receives the evaluated
/// arguments and returns one of: [double], [int], [String], [bool], null,
/// `Map<String, dynamic>` or `List`.
typedef ExpressionFunction = dynamic Function(List<dynamic> args);

/// A parsed formula. Parse once, evaluate with different parameters.
class Expression {
  final _Node _root;

  Expression._(this._root);

  /// Parses [formula]. Throws [ConversionException] on a syntax error or on
  /// unsupported syntax.
  factory Expression.parse(String formula) {
    final tokens = _tokenize(formula);
    _checkBalance(tokens);
    _checkSyntax(tokens);
    final parser = _Parser(tokens);
    final root = parser.parseAll();
    return Expression._(root);
  }

  /// Evaluates the formula. [parameters] maps identifier to value; numbers
  /// should already be [double] (see the converter's input cleanup).
  dynamic evaluate(Map<String, dynamic> parameters) {
    return _root.eval(parameters);
  }
}

// ---------------------------------------------------------------------------
// Number formatting as Go prints it

/// Shortest round-trip digits and decimal exponent of a finite, positive
/// [d]: `d = 0.DIGITS * 10^(exp + 1)`, so the exponent is that of `D.IGITS`.
(String, int) _shortestDigits(double d) {
  final s = d.toStringAsExponential();
  final parts = s.split('e');
  final digits = parts[0].replaceAll('.', '');
  return (digits, int.parse(parts[1]));
}

String _positional(String digits, int decimalPoint) {
  final nd = digits.length;
  if (decimalPoint <= 0) {
    return '0.${'0' * (-decimalPoint)}$digits';
  }
  if (decimalPoint >= nd) {
    return digits + '0' * (decimalPoint - nd);
  }
  return '${digits.substring(0, decimalPoint)}.${digits.substring(decimalPoint)}';
}

String? _special(double d) {
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d.isNegative ? '-Inf' : '+Inf';
  if (d == 0) return d.isNegative ? '-0' : '0';
  return null;
}

/// Go `strconv.FormatFloat(d, 'f', -1, 64)`, used by ntoa.
String goFormatPlain(double d) {
  final special = _special(d);
  if (special != null) return special;
  final (digits, exp) = _shortestDigits(d.abs());
  return (d.isNegative ? '-' : '') + _positional(digits, exp + 1);
}

/// Go `fmt.Sprint(d)` for a float64 (verb `%v`): shortest digits, exponent
/// form when the decimal exponent is below -4 or at least 6 (observed:
/// 100000 -> "100000", 1000000 -> "1e+06", 0.00001 -> "1e-05").
String goFormatValue(double d) {
  final special = _special(d);
  if (special != null) return special;
  final (digits, exp) = _shortestDigits(d.abs());
  final sign = d.isNegative ? '-' : '';
  if (exp < -4 || exp >= 6) {
    final mantissa = digits.length > 1
        ? '${digits[0]}.${digits.substring(1)}'
        : digits;
    final e = exp.abs().toString().padLeft(2, '0');
    return '$sign${mantissa}e${exp < 0 ? '-' : '+'}$e';
  }
  return sign + _positional(digits, exp + 1);
}

/// Go `fmt.Sprint` of a value as it appears in string concatenation.
String _sprint(dynamic v) {
  if (v == null) return '<nil>';
  if (v is String) return v;
  if (v is bool) return v.toString();
  if (v is int) return v.toString();
  if (v is double) return goFormatValue(v);
  if (v is List) return '[${v.map(_sprint).join(' ')}]';
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()
      ..sort(_compareStrings);
    return 'map[${keys.map((k) => '$k:${_sprint(v[k])}').join(' ')}]';
  }
  throw ConversionException('cannot format value of type ${v.runtimeType}');
}

/// Orders strings by code point, which equals Go's byte-wise UTF-8 order.
int _compareStrings(String a, String b) {
  final ra = a.runes.iterator;
  final rb = b.runes.iterator;
  while (true) {
    final hasA = ra.moveNext();
    final hasB = rb.moveNext();
    if (!hasA && !hasB) return 0;
    if (!hasA) return -1;
    if (!hasB) return 1;
    if (ra.current != rb.current) return ra.current < rb.current ? -1 : 1;
  }
}

/// Go `reflect.DeepEqual` over the value kinds of the language. An [int]
/// never equals a [double], as an int64 never equals a float64 there.
bool _deepEqual(dynamic a, dynamic b) {
  if (a == null || b == null) return a == null && b == null;
  if (a is int) return b is int && a == b;
  if (a is double) return b is double && a == b;
  if (a is String) return b is String && a == b;
  if (a is bool) return b is bool && a == b;
  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map) {
    if (b is! Map || a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEqual(a[key], b[key])) return false;
    }
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tokens and lexer

enum _Kind {
  prefix,
  numeric,
  boolean,
  string,
  variable,
  function,
  separator,
  comparator,
  logical,
  modifier,
  clause,
  clauseClose,
  ternary,
}

class _Token {
  final _Kind kind;
  final Object value;

  const _Token(this.kind, this.value);
}

/// Token kinds that may follow a token of the given kind (null = start).
const Map<_Kind?, Set<_Kind>> _validNext = {
  null: {
    _Kind.prefix,
    _Kind.numeric,
    _Kind.boolean,
    _Kind.variable,
    _Kind.function,
    _Kind.string,
    _Kind.clause,
  },
  _Kind.clause: {
    _Kind.prefix,
    _Kind.numeric,
    _Kind.boolean,
    _Kind.variable,
    _Kind.function,
    _Kind.string,
    _Kind.clause,
    _Kind.clauseClose,
  },
  _Kind.clauseClose: {
    _Kind.comparator,
    _Kind.modifier,
    _Kind.numeric,
    _Kind.boolean,
    _Kind.variable,
    _Kind.string,
    _Kind.clause,
    _Kind.clauseClose,
    _Kind.logical,
    _Kind.ternary,
    _Kind.separator,
  },
  _Kind.numeric: _afterValue,
  _Kind.boolean: _afterValue,
  _Kind.string: _afterValue,
  _Kind.variable: _afterValue,
  _Kind.modifier: {
    _Kind.prefix,
    _Kind.numeric,
    _Kind.variable,
    _Kind.function,
    _Kind.string,
    _Kind.boolean,
    _Kind.clause,
    _Kind.clauseClose,
  },
  _Kind.comparator: {
    _Kind.prefix,
    _Kind.numeric,
    _Kind.boolean,
    _Kind.variable,
    _Kind.function,
    _Kind.string,
    _Kind.clause,
    _Kind.clauseClose,
  },
  _Kind.logical: {
    _Kind.prefix,
    _Kind.numeric,
    _Kind.boolean,
    _Kind.variable,
    _Kind.function,
    _Kind.string,
    _Kind.clause,
    _Kind.clauseClose,
  },
  _Kind.prefix: {
    _Kind.numeric,
    _Kind.boolean,
    _Kind.variable,
    _Kind.function,
    _Kind.clause,
    _Kind.clauseClose,
  },
  _Kind.ternary: {
    _Kind.prefix,
    _Kind.numeric,
    _Kind.boolean,
    _Kind.string,
    _Kind.variable,
    _Kind.function,
    _Kind.clause,
    _Kind.separator,
  },
  _Kind.function: {_Kind.clause},
  _Kind.separator: {
    _Kind.prefix,
    _Kind.numeric,
    _Kind.boolean,
    _Kind.string,
    _Kind.variable,
    _Kind.function,
    _Kind.clause,
  },
};

const Set<_Kind> _afterValue = {
  _Kind.modifier,
  _Kind.comparator,
  _Kind.logical,
  _Kind.clauseClose,
  _Kind.ternary,
  _Kind.separator,
};

/// Kinds after which an expression may end.
const Set<_Kind> _endsExpression = {
  _Kind.clauseClose,
  _Kind.numeric,
  _Kind.boolean,
  _Kind.string,
  _Kind.variable,
};

const Set<String> _prefixSymbols = {'-', '!', '~'};
const Set<String> _modifierSymbols = {
  '+', '-', '*', '/', '%', '**', '&', '|', '^', '>>', '<<', //
};
const Set<String> _unsupportedModifiers = {'&', '|', '^', '>>', '<<'};
const Set<String> _logicalSymbols = {'&&', '||'};
const Set<String> _comparatorSymbols = {
  '==', '!=', '>', '>=', '<', '<=', '=~', '!~', //
};
const Set<String> _unsupportedComparators = {'=~', '!~'};
const Set<String> _ternarySymbols = {'?', ':', '??'};

final RegExp _letterRe = RegExp(r'\p{L}', unicode: true);
final RegExp _digitRe = RegExp(r'\p{Nd}', unicode: true);
final RegExp _spaceRe = RegExp(r'\s');
final RegExp _numberRe = RegExp(r'^(?:\d+\.?\d*|\.\d+)$');

bool _isSpace(int c) => _spaceRe.hasMatch(String.fromCharCode(c));
bool _isLetter(int c) => _letterRe.hasMatch(String.fromCharCode(c));
bool _isDigit(int c) => _digitRe.hasMatch(String.fromCharCode(c));
bool _isQuote(int c) => c == 0x27 || c == 0x22;
bool _isNumericChar(int c) => _isDigit(c) || c == 0x2e;
bool _isVariableChar(int c) => _isLetter(c) || _isDigit(c) || c == 0x5f;
bool _isSymbolChar(int c) =>
    !(_isDigit(c) || _isLetter(c) || c == 0x28 || c == 0x29 || _isQuote(c));

class _Lexer {
  final List<int> _chars;
  int _pos = 0;

  _Lexer(String source) : _chars = source.runes.toList();

  bool get _canRead => _pos < _chars.length;

  int _read() {
    if (_pos >= _chars.length) {
      throw const ConversionException('unexpected end of expression');
    }
    return _chars[_pos++];
  }

  /// Reads while [condition] holds. Returns the text and whether the read
  /// stopped on the condition or on whitespace (false: end of input).
  (String, bool) _readUntilFalse(
    bool includeWhitespace,
    bool breakWhitespace,
    bool Function(int) condition,
  ) {
    final buffer = StringBuffer();
    var stopped = false;
    while (_canRead) {
      var c = _read();
      if (c == 0x5c) {
        // a backslash escapes the next character, whatever it is
        c = _read();
        buffer.writeCharCode(c);
        continue;
      }
      if (_isSpace(c)) {
        if (breakWhitespace && buffer.length > 0) {
          stopped = true;
          break;
        }
        if (!includeWhitespace) continue;
      }
      if (condition(c)) {
        buffer.writeCharCode(c);
      } else {
        stopped = true;
        _pos--;
        break;
      }
    }
    return (buffer.toString(), stopped);
  }

  String _readToken(bool Function(int) condition) {
    _pos--;
    return _readUntilFalse(false, true, condition).$1;
  }

  _Token? next(_Kind? state, Set<String> functions) {
    while (_canRead) {
      final c = _read();
      if (_isSpace(c)) continue;

      if (_isNumericChar(c)) {
        final text = _readToken(_isNumericChar);
        if (!_numberRe.hasMatch(text)) {
          throw ConversionException("unable to parse numeric value '$text'");
        }
        return _Token(_Kind.numeric, double.parse(text));
      }
      if (c == 0x2c) return const _Token(_Kind.separator, ',');
      if (c == 0x5b) {
        final (name, closed) = _readUntilFalse(true, false, (x) => x != 0x5d);
        if (!closed) {
          throw const ConversionException('unclosed parameter bracket');
        }
        _pos++;
        return _Token(_Kind.variable, name);
      }
      if (_isLetter(c)) {
        final name = _readToken(_isVariableChar);
        if (functions.contains(name)) return _Token(_Kind.function, name);
        if (name == 'true') return const _Token(_Kind.boolean, true);
        if (name == 'false') return const _Token(_Kind.boolean, false);
        if (name == 'in' || name == 'IN') {
          throw const ConversionException("unsupported operator 'in'");
        }
        return _Token(_Kind.variable, name);
      }
      if (_isQuote(c)) {
        final (text, closed) = _readUntilFalse(
          true,
          false,
          (x) => !_isQuote(x),
        );
        if (!closed) {
          throw const ConversionException('unclosed string literal');
        }
        _pos++;
        if (_looksLikeDate(text)) {
          throw ConversionException(
            'unsupported string literal that reads as a date: "$text"',
          );
        }
        return _Token(_Kind.string, text);
      }
      if (c == 0x28) return const _Token(_Kind.clause, '(');
      if (c == 0x29) return const _Token(_Kind.clauseClose, ')');

      final symbol = _readToken(_isSymbolChar);
      if ((_validNext[state] ?? const {}).contains(_Kind.prefix) &&
          _prefixSymbols.contains(symbol)) {
        if (symbol == '~') {
          throw const ConversionException("unsupported operator '~'");
        }
        return _Token(_Kind.prefix, symbol);
      }
      if (_modifierSymbols.contains(symbol)) {
        if (_unsupportedModifiers.contains(symbol)) {
          throw ConversionException("unsupported operator '$symbol'");
        }
        return _Token(_Kind.modifier, symbol);
      }
      if (_logicalSymbols.contains(symbol)) {
        return _Token(_Kind.logical, symbol);
      }
      if (_comparatorSymbols.contains(symbol)) {
        if (_unsupportedComparators.contains(symbol)) {
          throw ConversionException("unsupported operator '$symbol'");
        }
        return _Token(_Kind.comparator, symbol);
      }
      if (_ternarySymbols.contains(symbol)) {
        return _Token(_Kind.ternary, symbol);
      }
      throw ConversionException("invalid token: '$symbol'");
    }
    return null;
  }
}

List<_Token> _tokenize(String formula) {
  final lexer = _Lexer(formula);
  final functions = expressionFunctions.keys.toSet();
  final tokens = <_Token>[];
  _Kind? state;
  while (true) {
    final token = lexer.next(state, functions);
    if (token == null) break;
    state = token.kind;
    tokens.add(token);
  }
  return tokens;
}

void _checkBalance(List<_Token> tokens) {
  var depth = 0;
  for (final token in tokens) {
    if (token.kind == _Kind.clause) depth++;
    if (token.kind == _Kind.clauseClose) depth--;
  }
  if (depth != 0) throw const ConversionException('unbalanced parenthesis');
}

void _checkSyntax(List<_Token> tokens) {
  _Kind? state;
  _Token? last;
  for (final token in tokens) {
    if (!(_validNext[state] ?? const {}).contains(token.kind)) {
      if (last != null &&
          last.kind == _Kind.variable &&
          token.kind == _Kind.clause) {
        throw ConversionException('undefined function ${last.value}');
      }
      throw ConversionException(
        'cannot transition token types from ${state?.name} [${last?.value}] '
        'to ${token.kind.name} [${token.value}]',
      );
    }
    state = token.kind;
    last = token;
  }
  if (state == null || !_endsExpression.contains(state)) {
    throw const ConversionException('unexpected end of expression');
  }
}

// Layouts that the Go lexer turns into a time value when a string literal
// matches them (ANSIC, UnixDate, RubyDate, Kitchen, RFC3339 with and without
// fraction, and the date/ISO8601 variants). Range checks follow Go.
const _months = 'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec';
const _days = 'Mon|Tue|Wed|Thu|Fri|Sat|Sun';
final List<RegExp> _dateLayouts = [
  RegExp('^(?:$_days) (?:$_months) [ 0-3]?\\d \\d\\d:\\d\\d:\\d\\d \\d{4}\$'),
  RegExp(
    '^(?:$_days) (?:$_months) [ 0-3]?\\d \\d\\d:\\d\\d:\\d\\d [A-Z]{3,5} \\d{4}\$',
  ),
  RegExp(
    '^(?:$_days) (?:$_months) [0-3]\\d \\d\\d:\\d\\d:\\d\\d [+-]\\d{4} \\d{4}\$',
  ),
  RegExp(r'^\d{1,2}:\d\d(?:AM|PM)$'),
  RegExp(r'^\d{4}-\d\d-\d\d$'),
  RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d$'),
  RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$'),
  RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d[+-]\d\d:\d\d$'),
  RegExp(
    r'^\d{4}-\d\d-\d\dT\d\d(?::\d\d(?::\d\d(?:\.\d+)?)?)?(?:Z|[+-]\d{4})$',
  ),
  RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$'),
];

bool _looksLikeDate(String s) {
  // Deliberately over-inclusive on ranges: a literal that merely resembles a
  // date is rejected, which is the safe side of "unsupported".
  return _dateLayouts.any((re) => re.hasMatch(s));
}

// ---------------------------------------------------------------------------
// Syntax tree

abstract class _Node {
  dynamic eval(Map<String, dynamic> params);
}

class _Literal extends _Node {
  final Object value;

  _Literal(this.value);

  @override
  dynamic eval(Map<String, dynamic> params) => value;
}

class _Variable extends _Node {
  final String name;

  _Variable(this.name);

  @override
  dynamic eval(Map<String, dynamic> params) {
    if (!params.containsKey(name)) {
      throw ConversionException("no parameter '$name' found");
    }
    return params[name];
  }
}

class _Call extends _Node {
  final String name;
  final List<_Node> args;

  _Call(this.name, this.args);

  @override
  dynamic eval(Map<String, dynamic> params) {
    final values = [for (final arg in args) arg.eval(params)];
    return expressionFunctions[name]!(values);
  }
}

class _Unary extends _Node {
  final String op;
  final _Node operand;

  _Unary(this.op, this.operand);

  @override
  dynamic eval(Map<String, dynamic> params) {
    final v = operand.eval(params);
    if (op == '-') {
      if (v is! double) {
        throw ConversionException(
          "Value '${_sprint(v)}' cannot be used with the prefix '-'",
        );
      }
      return -v;
    }
    if (v is! bool) {
      throw ConversionException(
        "Value '${_sprint(v)}' cannot be used with the prefix '!'",
      );
    }
    return !v;
  }
}

class _Binary extends _Node {
  final String op;
  final _Node left;
  final _Node right;

  _Binary(this.op, this.left, this.right);

  @override
  dynamic eval(Map<String, dynamic> params) {
    final l = left.eval(params);
    // Short-circuit like the Go evaluator: && and || skip the right side
    // only for a bool on the left.
    if (op == '&&' && l == false) return false;
    if (op == '||' && l == true) return true;
    final r = right.eval(params);
    switch (op) {
      case '&&':
      case '||':
        if (l is! bool) throw _logicalError(l);
        if (r is! bool) throw _logicalError(r);
        return op == '&&' ? (l && r) : (l || r);
      case '==':
        return _deepEqual(l, r);
      case '!=':
        return !_deepEqual(l, r);
      case '<':
      case '<=':
      case '>':
      case '>=':
        return _compare(l, r);
      case '+':
        if (l is double && r is double) return l + r;
        if (l is String || r is String) return _sprint(l) + _sprint(r);
        throw ConversionException(
          "Value '${_sprint(l)}' cannot be used with the modifier '+', it is not a number",
        );
      default:
        if (l is! double) throw _modifierError(l);
        if (r is! double) throw _modifierError(r);
        switch (op) {
          case '-':
            return l - r;
          case '*':
            return l * r;
          case '/':
            return l / r;
          case '%':
            return l.remainder(r);
          case '**':
            return math.pow(l, r).toDouble();
        }
    }
    throw ConversionException('unknown operator $op');
  }

  ConversionException _logicalError(dynamic v) => ConversionException(
    "Value '${_sprint(v)}' cannot be used with the logical operator '$op', it is not a bool",
  );

  ConversionException _modifierError(dynamic v) => ConversionException(
    "Value '${_sprint(v)}' cannot be used with the modifier '$op', it is not a number",
  );

  bool _compare(dynamic l, dynamic r) {
    final int order;
    if (l is double && r is double) {
      switch (op) {
        case '<':
          return l < r;
        case '<=':
          return l <= r;
        case '>':
          return l > r;
        default:
          return l >= r;
      }
    } else if (l is String && r is String) {
      order = _compareStrings(l, r);
    } else {
      throw ConversionException(
        "Value '${_sprint(l)}' cannot be used with the comparator '$op', it is not a number",
      );
    }
    switch (op) {
      case '<':
        return order < 0;
      case '<=':
        return order <= 0;
      case '>':
        return order > 0;
      default:
        return order >= 0;
    }
  }
}

/// One of `?`, `:` and `??` with the semantics of the Go stages: `?` yields
/// its right side for a true condition and null for false (a non-bool
/// condition is an error), `:` and `??` yield the left side unless it is
/// null. Chained they group from the left.
class _TernaryStage extends _Node {
  final String op;
  final _Node left;
  final _Node right;

  _TernaryStage(this.op, this.left, this.right);

  @override
  dynamic eval(Map<String, dynamic> params) {
    final l = left.eval(params);
    if (op == '?') {
      if (l == false) return null;
      if (l is! bool) {
        throw ConversionException(
          "Value '${_sprint(l)}' cannot be used with the ternary operator '?', it is not a bool",
        );
      }
      return right.eval(params);
    }
    if (l != null) return l;
    return right.eval(params);
  }
}

// ---------------------------------------------------------------------------
// Parser: one method per precedence level, lowest binding first.

class _Parser {
  final List<_Token> _tokens;
  int _pos = 0;

  _Parser(this._tokens);

  _Token? get _peek => _pos < _tokens.length ? _tokens[_pos] : null;

  bool _peekIs(_Kind kind, [Set<String>? symbols]) {
    final t = _peek;
    return t != null &&
        t.kind == kind &&
        (symbols == null || symbols.contains(t.value));
  }

  _Node parseAll() {
    final node = _ternary();
    if (_pos != _tokens.length) {
      final t = _tokens[_pos];
      if (t.kind == _Kind.separator) {
        throw const ConversionException(
          'a comma outside a function call is not supported',
        );
      }
      throw ConversionException("unexpected token '${t.value}'");
    }
    return node;
  }

  _Node _ternary() {
    var node = _or();
    while (_peekIs(_Kind.ternary)) {
      final op = _tokens[_pos++].value as String;
      node = _TernaryStage(op, node, _or());
    }
    return node;
  }

  _Node _or() {
    var node = _and();
    while (_peekIs(_Kind.logical, const {'||'})) {
      _pos++;
      node = _Binary('||', node, _and());
    }
    return node;
  }

  _Node _and() {
    var node = _comparison();
    while (_peekIs(_Kind.logical, const {'&&'})) {
      _pos++;
      node = _Binary('&&', node, _comparison());
    }
    return node;
  }

  _Node _comparison() {
    var node = _additive();
    while (_peekIs(_Kind.comparator)) {
      final op = _tokens[_pos++].value as String;
      node = _Binary(op, node, _additive());
    }
    return node;
  }

  _Node _additive() {
    var node = _multiplicative();
    while (_peekIs(_Kind.modifier, const {'+', '-'})) {
      final op = _tokens[_pos++].value as String;
      node = _Binary(op, node, _multiplicative());
    }
    return node;
  }

  _Node _multiplicative() {
    var node = _exponent();
    while (_peekIs(_Kind.modifier, const {'*', '/', '%'})) {
      final op = _tokens[_pos++].value as String;
      node = _Binary(op, node, _exponent());
    }
    return node;
  }

  _Node _exponent() {
    var node = _unary();
    while (_peekIs(_Kind.modifier, const {'**'})) {
      _pos++;
      node = _Binary('**', node, _unary());
    }
    return node;
  }

  _Node _unary() {
    if (_peekIs(_Kind.prefix)) {
      final op = _tokens[_pos++].value as String;
      return _Unary(op, _unary());
    }
    return _primary();
  }

  _Node _primary() {
    final t = _peek;
    if (t == null) {
      throw const ConversionException('unexpected end of expression');
    }
    _pos++;
    switch (t.kind) {
      case _Kind.numeric:
      case _Kind.string:
      case _Kind.boolean:
        return _Literal(t.value);
      case _Kind.variable:
        return _Variable(t.value as String);
      case _Kind.clause:
        final inner = _ternary();
        _expectClose();
        return inner;
      case _Kind.function:
        return _call(t.value as String);
      default:
        throw ConversionException("unexpected token '${t.value}'");
    }
  }

  void _expectClose() {
    if (!_peekIs(_Kind.clauseClose)) {
      throw const ConversionException('expected a closing parenthesis');
    }
    _pos++;
  }

  _Node _call(String name) {
    if (!_peekIs(_Kind.clause)) {
      throw ConversionException("function '$name' needs an argument list");
    }
    _pos++;
    final args = <_Node>[];
    if (!_peekIs(_Kind.clauseClose)) {
      args.add(_ternary());
      while (_peekIs(_Kind.separator)) {
        _pos++;
        args.add(_ternary());
      }
    }
    _expectClose();
    return _Call(name, args);
  }
}

// ---------------------------------------------------------------------------
// Custom functions. Strings are byte strings on the Go side: indices and
// lengths count UTF-8 bytes.

ConversionException _argError(String fn, String message) =>
    ConversionException('$fn: $message');

void _arity(String fn, List<dynamic> args, int n) {
  if (args.length != n) {
    throw _argError(fn, 'expect exactly $n argument${n == 1 ? '' : 's'}');
  }
}

String _string(String fn, List<dynamic> args, int i) {
  final v = args[i];
  if (v is String) return v;
  throw _argError(fn, 'expect argument ${i + 1} to be a string');
}

int _integer(String fn, List<dynamic> args, int i) {
  final v = args[i];
  if (v is int) return v;
  if (v is double && v.isFinite) return v.truncate();
  throw _argError(fn, 'expect argument ${i + 1} to be a number');
}

Map<String, dynamic> _stringMap(String fn, dynamic v) {
  if (v == null) return <String, dynamic>{};
  if (v is Map) {
    final result = <String, dynamic>{};
    for (final entry in v.entries) {
      final key = entry.key;
      if (key is! String) {
        throw _argError(fn, 'expect argument 1 to be a map with string keys');
      }
      result[key] = entry.value;
    }
    return result;
  }
  throw _argError(fn, 'expect argument 1 to be a map[string]interface{}');
}

int _byteIndexOf(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return 0;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

/// Go maps case rune by rune (one rune to one rune); a rune whose Dart case
/// mapping is longer than one rune stays as it is, as in Go.
String _mapCase(String s, String Function(String) mapper) {
  final out = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = mapper(ch);
    out.write(mapped.runes.length == 1 ? mapped : ch);
  }
  return out.toString();
}

final RegExp _intRe = RegExp(r'^[+-]?\d+$');
final RegExp _floatRe = RegExp(
  r'^[+-]?(?:\d+(?:_\d+)*\.?(?:\d+(?:_\d+)*)?|\.\d+(?:_\d+)*)(?:[eE][+-]?\d+(?:_\d+)*)?$',
);
final RegExp _infNanRe = RegExp(
  r'^[+-]?(?:inf|infinity|nan)$',
  caseSensitive: false,
);

/// The custom functions, by name.
final Map<String, ExpressionFunction> expressionFunctions = {
  'substr': (args) {
    _arity('substr', args, 3);
    final bytes = utf8.encode(_string('substr', args, 0));
    final from = _integer('substr', args, 1);
    final to = _integer('substr', args, 2);
    if (from < 0 || to < from || to > bytes.length) {
      throw _argError('substr', 'slice bounds out of range');
    }
    try {
      return utf8.decode(bytes.sublist(from, to));
    } on FormatException {
      throw _argError('substr', 'the slice cuts a multi-byte character');
    }
  },
  'replace': (args) {
    _arity('replace', args, 3);
    final s = _string('replace', args, 0);
    final from = _string('replace', args, 1);
    final to = _string('replace', args, 2);
    return s.replaceAll(from, to);
  },
  'trimSuffix': (args) {
    _arity('trimSuffix', args, 2);
    final s = _string('trimSuffix', args, 0);
    final suffix = _string('trimSuffix', args, 1);
    return suffix.isNotEmpty && s.endsWith(suffix)
        ? s.substring(0, s.length - suffix.length)
        : s;
  },
  'trimPrefix': (args) {
    _arity('trimPrefix', args, 2);
    final s = _string('trimPrefix', args, 0);
    final prefix = _string('trimPrefix', args, 1);
    return prefix.isNotEmpty && s.startsWith(prefix)
        ? s.substring(prefix.length)
        : s;
  },
  'strIndex': (args) {
    _arity('strIndex', args, 2);
    final s = utf8.encode(_string('strIndex', args, 0));
    final sub = utf8.encode(_string('strIndex', args, 1));
    return _byteIndexOf(s, sub);
  },
  'strlen': (args) {
    _arity('strlen', args, 1);
    return utf8.encode(_string('strlen', args, 0)).length;
  },
  'toUpperCase': (args) {
    _arity('toUpperCase', args, 1);
    return _mapCase(_string('toUpperCase', args, 0), (c) => c.toUpperCase());
  },
  'toLowerCase': (args) {
    _arity('toLowerCase', args, 1);
    return _mapCase(_string('toLowerCase', args, 0), (c) => c.toLowerCase());
  },
  'atoi': (args) {
    _arity('atoi', args, 1);
    final s = _string('atoi', args, 0);
    final parsed = _intRe.hasMatch(s) ? int.tryParse(s) : null;
    if (parsed == null) {
      throw _argError('atoi', 'parsing "$s": invalid syntax or out of range');
    }
    return parsed;
  },
  'atof': (args) {
    _arity('atof', args, 1);
    final s = _string('atof', args, 0);
    if (_infNanRe.hasMatch(s)) {
      final lower = s.toLowerCase();
      if (lower.endsWith('nan')) return double.nan;
      return lower.startsWith('-') ? double.negativeInfinity : double.infinity;
    }
    if (!_floatRe.hasMatch(s)) {
      throw _argError('atof', 'parsing "$s": invalid syntax');
    }
    final value = double.parse(s.replaceAll('_', ''));
    if (value.isInfinite) {
      throw _argError('atof', 'parsing "$s": value out of range');
    }
    return value;
  },
  'mapSet': (args) {
    _arity('mapSet', args, 3);
    final m = _stringMap('mapSet', args[0]);
    final key = _string('mapSet', args, 1);
    m[key] = args[2];
    return m;
  },
  'mapGet': (args) {
    _arity('mapGet', args, 2);
    final m = _stringMap('mapGet', args[0]);
    final key = _string('mapGet', args, 1);
    if (!m.containsKey(key)) throw _argError('mapGet', 'key not found');
    return m[key];
  },
  'mapDelete': (args) {
    _arity('mapDelete', args, 2);
    final m = _stringMap('mapDelete', args[0]);
    m.remove(_string('mapDelete', args, 1));
    return m;
  },
  'ntoa': (args) {
    _arity('ntoa', args, 1);
    final v = args[0];
    if (v is int) return v.toString();
    if (v is double) return goFormatPlain(v);
    throw _argError('ntoa', 'expect argument 1 to be a number');
  },
};
