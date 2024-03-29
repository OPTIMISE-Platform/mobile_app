/*
 * Copyright 2022 InfAI (CC SES)
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

class KeyedList<K, T> {
  final Map<K, List<T>> m = {};

  insert(K key, T element) {
    final  l = m[key] ?? [];
    l.add(element);
    m[key] = l;
  }

  List<Pair<K, T>> list() {
    final List<Pair<K, T>> result = [];
    m.forEach((key, value) {
      for (var element in value) {
        result.add(Pair<K, T>(key, element));
      }
    });

    return result;
  }

}

class Pair<K, T> {
  final K k;
  final T t;

  Pair(this.k, this.t);

  factory Pair.fromJson(Map<String, dynamic> json) => Pair(json["k"], json["t"]);

  Map<String, dynamic> toJson() => {"k": k is String ? k : json.encode(k), "t": t is String ? t : json.encode(t)};
}
