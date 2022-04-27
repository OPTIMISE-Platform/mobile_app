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

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db_query.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DbQuery _$DbQueryFromJson(Map<String, dynamic> json) => DbQuery(
      json['exportId'] as String?,
      json['deviceId'] as String?,
      json['serviceId'] as String?,
      json['groupTime'] as String?,
      json['orderDirection'] as String?,
      json['limit'] as int?,
      json['orderColumnIndex'] as int?,
      json['time'] == null
          ? null
          : QueriesRequestElementTime.fromJson(
              json['time'] as Map<String, dynamic>),
      (json['columns'] as List<dynamic>?)
          ?.map((e) =>
              QueriesRequestElementColumn.fromJson(e as Map<String, dynamic>))
          .toList(),
      (json['filters'] as List<dynamic>?)
          ?.map((e) =>
              QueriesRequestElementFilter.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DbQueryToJson(DbQuery instance) => <String, dynamic>{
      'exportId': instance.exportId,
      'deviceId': instance.deviceId,
      'serviceId': instance.serviceId,
      'groupTime': instance.groupTime,
      'orderDirection': instance.orderDirection,
      'limit': instance.limit,
      'orderColumnIndex': instance.orderColumnIndex,
      'time': instance.time,
      'columns': instance.columns,
      'filters': instance.filters,
    };

QueriesRequestElementTime _$QueriesRequestElementTimeFromJson(
        Map<String, dynamic> json) =>
    QueriesRequestElementTime(
      json['last'] as String?,
      json['start'] as String?,
      json['end'] as String?,
    );

Map<String, dynamic> _$QueriesRequestElementTimeToJson(
        QueriesRequestElementTime instance) =>
    <String, dynamic>{
      'last': instance.last,
      'start': instance.start,
      'end': instance.end,
    };

QueriesRequestElementColumn _$QueriesRequestElementColumnFromJson(
        Map<String, dynamic> json) =>
    QueriesRequestElementColumn(
      json['name'] as String,
      json['groupType'] as String?,
      json['math'] as String?,
    );

Map<String, dynamic> _$QueriesRequestElementColumnToJson(
        QueriesRequestElementColumn instance) =>
    <String, dynamic>{
      'name': instance.name,
      'groupType': instance.groupType,
      'math': instance.math,
    };

QueriesRequestElementFilter _$QueriesRequestElementFilterFromJson(
        Map<String, dynamic> json) =>
    QueriesRequestElementFilter(
      json['column'] as String,
      json['type'] as String,
      json['math'] as String?,
      json['value'],
    );

Map<String, dynamic> _$QueriesRequestElementFilterToJson(
        QueriesRequestElementFilter instance) =>
    <String, dynamic>{
      'column': instance.column,
      'type': instance.type,
      'math': instance.math,
      'value': instance.value,
    };
