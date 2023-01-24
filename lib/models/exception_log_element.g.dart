// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exception_log_element.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters

extension GetExceptionLogElementCollection on Isar {
  IsarCollection<ExceptionLogElement> get exceptionLogElements =>
      this.collection();
}

final ExceptionLogElementSchema = CollectionSchema(
  name: r'ExceptionLogElement',
  id: int.parse('-4945544615666128633'),
  properties: {
    r'logTime': PropertySchema(
      id: 0,
      name: r'logTime',
      type: IsarType.dateTime,
    ),
    r'message': PropertySchema(
      id: 1,
      name: r'message',
      type: IsarType.string,
    ),
    r'stack': PropertySchema(
      id: 2,
      name: r'stack',
      type: IsarType.string,
    )
  },
  estimateSize: _exceptionLogElementEstimateSize,
  serialize: _exceptionLogElementSerialize,
  deserialize: _exceptionLogElementDeserialize,
  deserializeProp: _exceptionLogElementDeserializeProp,
  idName: r'isarId',
  indexes: {
    r'logTime': IndexSchema(
      id: int.parse('-2612057588556721033'),
      name: r'logTime',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'logTime',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _exceptionLogElementGetId,
  getLinks: _exceptionLogElementGetLinks,
  attach: _exceptionLogElementAttach,
  version: '3.0.5',
);

int _exceptionLogElementEstimateSize(
  ExceptionLogElement object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.message;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.stack.length * 3;
  return bytesCount;
}

void _exceptionLogElementSerialize(
  ExceptionLogElement object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.logTime);
  writer.writeString(offsets[1], object.message);
  writer.writeString(offsets[2], object.stack);
}

ExceptionLogElement _exceptionLogElementDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ExceptionLogElement(
    reader.readStringOrNull(offsets[1]),
    reader.readString(offsets[2]),
  );
  return object;
}

P _exceptionLogElementDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _exceptionLogElementGetId(ExceptionLogElement object) {
  return object.isarId;
}

List<IsarLinkBase<dynamic>> _exceptionLogElementGetLinks(
    ExceptionLogElement object) {
  return [];
}

void _exceptionLogElementAttach(
    IsarCollection<dynamic> col, Id id, ExceptionLogElement object) {}

extension ExceptionLogElementQueryWhereSort
    on QueryBuilder<ExceptionLogElement, ExceptionLogElement, QWhere> {
  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhere>
      anyIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhere>
      anyLogTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'logTime'),
      );
    });
  }
}

extension ExceptionLogElementQueryWhere
    on QueryBuilder<ExceptionLogElement, ExceptionLogElement, QWhereClause> {
  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      isarIdEqualTo(Id isarId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: isarId,
        upper: isarId,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      isarIdNotEqualTo(Id isarId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: isarId, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: isarId, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: isarId, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: isarId, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      isarIdGreaterThan(Id isarId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: isarId, includeLower: include),
      );
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      isarIdLessThan(Id isarId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: isarId, includeUpper: include),
      );
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      isarIdBetween(
    Id lowerIsarId,
    Id upperIsarId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerIsarId,
        includeLower: includeLower,
        upper: upperIsarId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      logTimeEqualTo(DateTime logTime) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'logTime',
        value: [logTime],
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      logTimeNotEqualTo(DateTime logTime) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'logTime',
              lower: [],
              upper: [logTime],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'logTime',
              lower: [logTime],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'logTime',
              lower: [logTime],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'logTime',
              lower: [],
              upper: [logTime],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      logTimeGreaterThan(
    DateTime logTime, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'logTime',
        lower: [logTime],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      logTimeLessThan(
    DateTime logTime, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'logTime',
        lower: [],
        upper: [logTime],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterWhereClause>
      logTimeBetween(
    DateTime lowerLogTime,
    DateTime upperLogTime, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'logTime',
        lower: [lowerLogTime],
        includeLower: includeLower,
        upper: [upperLogTime],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ExceptionLogElementQueryFilter on QueryBuilder<ExceptionLogElement,
    ExceptionLogElement, QFilterCondition> {
  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      isarIdEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      isarIdGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      isarIdLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      isarIdBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'isarId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      logTimeEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'logTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      logTimeGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'logTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      logTimeLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'logTime',
        value: value,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      logTimeBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'logTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'message',
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'message',
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'message',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'message',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'message',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'message',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'message',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'message',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'message',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'message',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'message',
        value: '',
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      messageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'message',
        value: '',
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'stack',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'stack',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'stack',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'stack',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'stack',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'stack',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'stack',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'stack',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'stack',
        value: '',
      ));
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterFilterCondition>
      stackIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'stack',
        value: '',
      ));
    });
  }
}

extension ExceptionLogElementQueryObject on QueryBuilder<ExceptionLogElement,
    ExceptionLogElement, QFilterCondition> {}

extension ExceptionLogElementQueryLinks on QueryBuilder<ExceptionLogElement,
    ExceptionLogElement, QFilterCondition> {}

extension ExceptionLogElementQuerySortBy
    on QueryBuilder<ExceptionLogElement, ExceptionLogElement, QSortBy> {
  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      sortByLogTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logTime', Sort.asc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      sortByLogTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logTime', Sort.desc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      sortByMessage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'message', Sort.asc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      sortByMessageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'message', Sort.desc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      sortByStack() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stack', Sort.asc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      sortByStackDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stack', Sort.desc);
    });
  }
}

extension ExceptionLogElementQuerySortThenBy
    on QueryBuilder<ExceptionLogElement, ExceptionLogElement, QSortThenBy> {
  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      thenByIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.asc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      thenByIsarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.desc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      thenByLogTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logTime', Sort.asc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      thenByLogTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logTime', Sort.desc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      thenByMessage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'message', Sort.asc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      thenByMessageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'message', Sort.desc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      thenByStack() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stack', Sort.asc);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QAfterSortBy>
      thenByStackDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stack', Sort.desc);
    });
  }
}

extension ExceptionLogElementQueryWhereDistinct
    on QueryBuilder<ExceptionLogElement, ExceptionLogElement, QDistinct> {
  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QDistinct>
      distinctByLogTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'logTime');
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QDistinct>
      distinctByMessage({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'message', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ExceptionLogElement, ExceptionLogElement, QDistinct>
      distinctByStack({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stack', caseSensitive: caseSensitive);
    });
  }
}

extension ExceptionLogElementQueryProperty
    on QueryBuilder<ExceptionLogElement, ExceptionLogElement, QQueryProperty> {
  QueryBuilder<ExceptionLogElement, int, QQueryOperations> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isarId');
    });
  }

  QueryBuilder<ExceptionLogElement, DateTime, QQueryOperations>
      logTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'logTime');
    });
  }

  QueryBuilder<ExceptionLogElement, String?, QQueryOperations>
      messageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'message');
    });
  }

  QueryBuilder<ExceptionLogElement, String, QQueryOperations> stackProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stack');
    });
  }
}
