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

import 'package:json_annotation/json_annotation.dart';

part 'db_query.g.dart';

@JsonSerializable()
class DbQuery {
  String? exportId, deviceId, serviceId, groupTime, orderDirection;
  int? limit, orderColumnIndex;
  QueriesRequestElementTime? time;
  List<QueriesRequestElementColumn>? columns;
  List<QueriesRequestElementFilter>? filters;

  DbQuery(this.exportId, this.deviceId, this.serviceId, this.groupTime, this.orderDirection, this.limit, this.orderColumnIndex, this.time,
      this.columns, this.filters);

  factory DbQuery.fromJson(Map<String, dynamic> json) => _$DbQueryFromJson(json);

  Map<String, dynamic> toJson() => _$DbQueryToJson(this);

  factory DbQuery.from(DbQuery q) => DbQuery(
      q.exportId,
      q.deviceId,
      q.serviceId,
      q.groupTime,
      q.orderDirection,
      q.limit,
      q.orderColumnIndex,
      q.time == null ? null : QueriesRequestElementTime.from(q.time!),
      q.columns == null ? null : List.generate(q.columns!.length, (i) => QueriesRequestElementColumn.from(q.columns![i])),
      q.filters == null ? null : List.generate(q.filters!.length, (i) => QueriesRequestElementFilter.from(q.filters![i])));
}

@JsonSerializable()
class QueriesRequestElementTime {
  String? last, start, end;

  QueriesRequestElementTime(this.last, this.start, this.end);

  factory QueriesRequestElementTime.fromJson(Map<String, dynamic> json) => _$QueriesRequestElementTimeFromJson(json);

  Map<String, dynamic> toJson() => _$QueriesRequestElementTimeToJson(this);

  factory QueriesRequestElementTime.from(QueriesRequestElementTime e) => QueriesRequestElementTime(e.last, e.start, e.end);
}

@JsonSerializable()
class QueriesRequestElementColumn {
  String name;
  String? groupType, math, sourceCharacteristicId, targetCharacteristicId, conceptId;

  QueriesRequestElementColumn(this.name, this.groupType, this.math, this.sourceCharacteristicId, this.targetCharacteristicId, this.conceptId);

  factory QueriesRequestElementColumn.fromJson(Map<String, dynamic> json) => _$QueriesRequestElementColumnFromJson(json);

  Map<String, dynamic> toJson() => _$QueriesRequestElementColumnToJson(this);

  factory QueriesRequestElementColumn.from(QueriesRequestElementColumn c) =>
      QueriesRequestElementColumn(c.name, c.groupType, c.math, c.sourceCharacteristicId, c.targetCharacteristicId, c.conceptId);
}

@JsonSerializable()
class QueriesRequestElementFilter {
  String column, type;
  String? math;
  dynamic value;

  QueriesRequestElementFilter(this.column, this.type, this.math, this.value);

  factory QueriesRequestElementFilter.fromJson(Map<String, dynamic> json) => _$QueriesRequestElementFilterFromJson(json);

  Map<String, dynamic> toJson() => _$QueriesRequestElementFilterToJson(this);

  factory QueriesRequestElementFilter.from(QueriesRequestElementFilter f) => QueriesRequestElementFilter(f.column, f.type, f.math, f.value);
}
