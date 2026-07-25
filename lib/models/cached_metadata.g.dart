// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_metadata.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCachedMetadataCollection on Isar {
  IsarCollection<CachedMetadata> get cachedMetadatas => this.collection();
}

const CachedMetadataSchema = CollectionSchema(
  name: r'CachedMetadata',
  id: 8577931195188195036,
  properties: {
    r'bytes': PropertySchema(id: 0, name: r'bytes', type: IsarType.byteList),
    r'key': PropertySchema(id: 1, name: r'key', type: IsarType.string),
    r'updatedAt': PropertySchema(
      id: 2,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
  },

  estimateSize: _cachedMetadataEstimateSize,
  serialize: _cachedMetadataSerialize,
  deserialize: _cachedMetadataDeserialize,
  deserializeProp: _cachedMetadataDeserializeProp,
  idName: r'id',
  indexes: {
    r'key': IndexSchema(
      id: -4906094122524121629,
      name: r'key',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'key',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _cachedMetadataGetId,
  getLinks: _cachedMetadataGetLinks,
  attach: _cachedMetadataAttach,
  version: '3.3.2',
);

int _cachedMetadataEstimateSize(
  CachedMetadata object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.bytes.length;
  bytesCount += 3 + object.key.length * 3;
  return bytesCount;
}

void _cachedMetadataSerialize(
  CachedMetadata object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeByteList(offsets[0], object.bytes);
  writer.writeString(offsets[1], object.key);
  writer.writeDateTime(offsets[2], object.updatedAt);
}

CachedMetadata _cachedMetadataDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CachedMetadata();
  object.bytes = reader.readByteList(offsets[0]) ?? [];
  object.id = id;
  object.key = reader.readString(offsets[1]);
  object.updatedAt = reader.readDateTime(offsets[2]);
  return object;
}

P _cachedMetadataDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readByteList(offset) ?? []) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _cachedMetadataGetId(CachedMetadata object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _cachedMetadataGetLinks(CachedMetadata object) {
  return [];
}

void _cachedMetadataAttach(
  IsarCollection<dynamic> col,
  Id id,
  CachedMetadata object,
) {
  object.id = id;
}

extension CachedMetadataByIndex on IsarCollection<CachedMetadata> {
  Future<CachedMetadata?> getByKey(String key) {
    return getByIndex(r'key', [key]);
  }

  CachedMetadata? getByKeySync(String key) {
    return getByIndexSync(r'key', [key]);
  }

  Future<bool> deleteByKey(String key) {
    return deleteByIndex(r'key', [key]);
  }

  bool deleteByKeySync(String key) {
    return deleteByIndexSync(r'key', [key]);
  }

  Future<List<CachedMetadata?>> getAllByKey(List<String> keyValues) {
    final values = keyValues.map((e) => [e]).toList();
    return getAllByIndex(r'key', values);
  }

  List<CachedMetadata?> getAllByKeySync(List<String> keyValues) {
    final values = keyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'key', values);
  }

  Future<int> deleteAllByKey(List<String> keyValues) {
    final values = keyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'key', values);
  }

  int deleteAllByKeySync(List<String> keyValues) {
    final values = keyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'key', values);
  }

  Future<Id> putByKey(CachedMetadata object) {
    return putByIndex(r'key', object);
  }

  Id putByKeySync(CachedMetadata object, {bool saveLinks = true}) {
    return putByIndexSync(r'key', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByKey(List<CachedMetadata> objects) {
    return putAllByIndex(r'key', objects);
  }

  List<Id> putAllByKeySync(
    List<CachedMetadata> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'key', objects, saveLinks: saveLinks);
  }
}

extension CachedMetadataQueryWhereSort
    on QueryBuilder<CachedMetadata, CachedMetadata, QWhere> {
  QueryBuilder<CachedMetadata, CachedMetadata, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CachedMetadataQueryWhere
    on QueryBuilder<CachedMetadata, CachedMetadata, QWhereClause> {
  QueryBuilder<CachedMetadata, CachedMetadata, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterWhereClause> keyEqualTo(
    String key,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'key', value: [key]),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterWhereClause> keyNotEqualTo(
    String key,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'key',
                lower: [],
                upper: [key],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'key',
                lower: [key],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'key',
                lower: [key],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'key',
                lower: [],
                upper: [key],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension CachedMetadataQueryFilter
    on QueryBuilder<CachedMetadata, CachedMetadata, QFilterCondition> {
  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'bytes', value: value),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'bytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'bytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'bytes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'bytes', length, true, length, true);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'bytes', 0, true, 0, true);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'bytes', 0, false, 999999, true);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'bytes', 0, true, length, include);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'bytes', length, include, 999999, true);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  bytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'bytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'key',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'key',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyLessThan(String value, {bool include = false, bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'key',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'key',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'key',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'key',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'key',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'key',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'key', value: ''),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  keyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'key', value: ''),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'updatedAt', value: value),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  updatedAtGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  updatedAtLessThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterFilterCondition>
  updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'updatedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension CachedMetadataQueryObject
    on QueryBuilder<CachedMetadata, CachedMetadata, QFilterCondition> {}

extension CachedMetadataQueryLinks
    on QueryBuilder<CachedMetadata, CachedMetadata, QFilterCondition> {}

extension CachedMetadataQuerySortBy
    on QueryBuilder<CachedMetadata, CachedMetadata, QSortBy> {
  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy> sortByKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'key', Sort.asc);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy> sortByKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'key', Sort.desc);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy>
  sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension CachedMetadataQuerySortThenBy
    on QueryBuilder<CachedMetadata, CachedMetadata, QSortThenBy> {
  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy> thenByKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'key', Sort.asc);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy> thenByKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'key', Sort.desc);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QAfterSortBy>
  thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension CachedMetadataQueryWhereDistinct
    on QueryBuilder<CachedMetadata, CachedMetadata, QDistinct> {
  QueryBuilder<CachedMetadata, CachedMetadata, QDistinct> distinctByBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bytes');
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QDistinct> distinctByKey({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'key', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CachedMetadata, CachedMetadata, QDistinct>
  distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension CachedMetadataQueryProperty
    on QueryBuilder<CachedMetadata, CachedMetadata, QQueryProperty> {
  QueryBuilder<CachedMetadata, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CachedMetadata, List<int>, QQueryOperations> bytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bytes');
    });
  }

  QueryBuilder<CachedMetadata, String, QQueryOperations> keyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'key');
    });
  }

  QueryBuilder<CachedMetadata, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
