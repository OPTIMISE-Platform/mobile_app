// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters

extension GetNetworkCollection on Isar {
  IsarCollection<Network> get networks => this.collection();
}

final NetworkSchema = CollectionSchema(
  name: r'Network',
  id: int.parse('-3925120672061997113'),
  properties: {
    r'annotations': PropertySchema(
      id: 0,
      name: r'annotations',
      type: IsarType.object,
      target: r'Annotations',
    ),
    r'creator': PropertySchema(
      id: 1,
      name: r'creator',
      type: IsarType.string,
    ),
    r'device_ids': PropertySchema(
      id: 2,
      name: r'device_ids',
      type: IsarType.stringList,
    ),
    r'device_local_ids': PropertySchema(
      id: 3,
      name: r'device_local_ids',
      type: IsarType.stringList,
    ),
    r'id': PropertySchema(
      id: 4,
      name: r'id',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 5,
      name: r'name',
      type: IsarType.string,
    ),
    r'shared': PropertySchema(
      id: 6,
      name: r'shared',
      type: IsarType.bool,
    )
  },
  estimateSize: _networkEstimateSize,
  serialize: _networkSerialize,
  deserialize: _networkDeserialize,
  deserializeProp: _networkDeserializeProp,
  idName: r'isarId',
  indexes: {
    r'id': IndexSchema(
      id: int.parse('-3268401673993471357'),
      name: r'id',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'id',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'name': IndexSchema(
      id: int.parse('879695947855722453'),
      name: r'name',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'name',
          type: IndexType.hash,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {r'Annotations': AnnotationsSchema},
  getId: _networkGetId,
  getLinks: _networkGetLinks,
  attach: _networkAttach,
  version: '3.0.5',
);

int _networkEstimateSize(
  Network object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.annotations;
    if (value != null) {
      bytesCount += 3 +
          AnnotationsSchema.estimateSize(
              value, allOffsets[Annotations]!, allOffsets);
    }
  }
  bytesCount += 3 + object.creator.length * 3;
  {
    final list = object.device_ids;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  {
    final list = object.device_local_ids;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  bytesCount += 3 + object.id.length * 3;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _networkSerialize(
  Network object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeObject<Annotations>(
    offsets[0],
    allOffsets,
    AnnotationsSchema.serialize,
    object.annotations,
  );
  writer.writeString(offsets[1], object.creator);
  writer.writeStringList(offsets[2], object.device_ids);
  writer.writeStringList(offsets[3], object.device_local_ids);
  writer.writeString(offsets[4], object.id);
  writer.writeString(offsets[5], object.name);
  writer.writeBool(offsets[6], object.shared);
}

Network _networkDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Network(
    reader.readString(offsets[4]),
    reader.readString(offsets[5]),
    reader.readObjectOrNull<Annotations>(
      offsets[0],
      AnnotationsSchema.deserialize,
      allOffsets,
    ),
    reader.readBool(offsets[6]),
    reader.readString(offsets[1]),
    reader.readStringList(offsets[3]),
    reader.readStringList(offsets[2]),
  );
  object.isarId = id;
  return object;
}

P _networkDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readObjectOrNull<Annotations>(
        offset,
        AnnotationsSchema.deserialize,
        allOffsets,
      )) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readStringList(offset)) as P;
    case 3:
      return (reader.readStringList(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readBool(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _networkGetId(Network object) {
  return object.isarId;
}

List<IsarLinkBase<dynamic>> _networkGetLinks(Network object) {
  return [];
}

void _networkAttach(IsarCollection<dynamic> col, Id id, Network object) {
  object.isarId = id;
}

extension NetworkQueryWhereSort on QueryBuilder<Network, Network, QWhere> {
  QueryBuilder<Network, Network, QAfterWhere> anyIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension NetworkQueryWhere on QueryBuilder<Network, Network, QWhereClause> {
  QueryBuilder<Network, Network, QAfterWhereClause> isarIdEqualTo(Id isarId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: isarId,
        upper: isarId,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterWhereClause> isarIdNotEqualTo(
      Id isarId) {
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

  QueryBuilder<Network, Network, QAfterWhereClause> isarIdGreaterThan(Id isarId,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: isarId, includeLower: include),
      );
    });
  }

  QueryBuilder<Network, Network, QAfterWhereClause> isarIdLessThan(Id isarId,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: isarId, includeUpper: include),
      );
    });
  }

  QueryBuilder<Network, Network, QAfterWhereClause> isarIdBetween(
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

  QueryBuilder<Network, Network, QAfterWhereClause> idEqualTo(String id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'id',
        value: [id],
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterWhereClause> idNotEqualTo(String id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'id',
              lower: [],
              upper: [id],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'id',
              lower: [id],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'id',
              lower: [id],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'id',
              lower: [],
              upper: [id],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<Network, Network, QAfterWhereClause> nameEqualTo(String name) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'name',
        value: [name],
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterWhereClause> nameNotEqualTo(
      String name) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [],
              upper: [name],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [name],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [name],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'name',
              lower: [],
              upper: [name],
              includeUpper: false,
            ));
      }
    });
  }
}

extension NetworkQueryFilter
    on QueryBuilder<Network, Network, QFilterCondition> {
  QueryBuilder<Network, Network, QAfterFilterCondition> annotationsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'annotations',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> annotationsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'annotations',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'creator',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'creator',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'creator',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> creatorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'creator',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> device_idsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'device_ids',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> device_idsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'device_ids',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'device_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'device_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'device_ids',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'device_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'device_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'device_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'device_ids',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_ids',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'device_ids',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> device_idsLengthEqualTo(
      int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_ids',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> device_idsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_ids',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> device_idsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_ids',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_ids',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_idsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_ids',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> device_idsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_ids',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'device_local_ids',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'device_local_ids',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_local_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'device_local_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'device_local_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'device_local_ids',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'device_local_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'device_local_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'device_local_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'device_local_ids',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_local_ids',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'device_local_ids',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_local_ids',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_local_ids',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_local_ids',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_local_ids',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_local_ids',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition>
      device_local_idsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'device_local_ids',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idContains(String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'id',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> isarIdEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> isarIdGreaterThan(
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

  QueryBuilder<Network, Network, QAfterFilterCondition> isarIdLessThan(
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

  QueryBuilder<Network, Network, QAfterFilterCondition> isarIdBetween(
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

  QueryBuilder<Network, Network, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<Network, Network, QAfterFilterCondition> sharedEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'shared',
        value: value,
      ));
    });
  }
}

extension NetworkQueryObject
    on QueryBuilder<Network, Network, QFilterCondition> {
  QueryBuilder<Network, Network, QAfterFilterCondition> annotations(
      FilterQuery<Annotations> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'annotations');
    });
  }
}

extension NetworkQueryLinks
    on QueryBuilder<Network, Network, QFilterCondition> {}

extension NetworkQuerySortBy on QueryBuilder<Network, Network, QSortBy> {
  QueryBuilder<Network, Network, QAfterSortBy> sortByCreator() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creator', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> sortByCreatorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creator', Sort.desc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> sortByShared() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'shared', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> sortBySharedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'shared', Sort.desc);
    });
  }
}

extension NetworkQuerySortThenBy
    on QueryBuilder<Network, Network, QSortThenBy> {
  QueryBuilder<Network, Network, QAfterSortBy> thenByCreator() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creator', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenByCreatorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creator', Sort.desc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenByIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenByIsarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.desc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenByShared() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'shared', Sort.asc);
    });
  }

  QueryBuilder<Network, Network, QAfterSortBy> thenBySharedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'shared', Sort.desc);
    });
  }
}

extension NetworkQueryWhereDistinct
    on QueryBuilder<Network, Network, QDistinct> {
  QueryBuilder<Network, Network, QDistinct> distinctByCreator(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'creator', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Network, Network, QDistinct> distinctByDevice_ids() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'device_ids');
    });
  }

  QueryBuilder<Network, Network, QDistinct> distinctByDevice_local_ids() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'device_local_ids');
    });
  }

  QueryBuilder<Network, Network, QDistinct> distinctById(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'id', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Network, Network, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Network, Network, QDistinct> distinctByShared() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'shared');
    });
  }
}

extension NetworkQueryProperty
    on QueryBuilder<Network, Network, QQueryProperty> {
  QueryBuilder<Network, int, QQueryOperations> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isarId');
    });
  }

  QueryBuilder<Network, Annotations?, QQueryOperations> annotationsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'annotations');
    });
  }

  QueryBuilder<Network, String, QQueryOperations> creatorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'creator');
    });
  }

  QueryBuilder<Network, List<String>?, QQueryOperations> device_idsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'device_ids');
    });
  }

  QueryBuilder<Network, List<String>?, QQueryOperations>
      device_local_idsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'device_local_ids');
    });
  }

  QueryBuilder<Network, String, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Network, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<Network, bool, QQueryOperations> sharedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'shared');
    });
  }
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Network _$NetworkFromJson(Map<String, dynamic> json) => Network(
      json['id'] as String,
      json['name'] as String,
      json['annotations'] == null
          ? null
          : Annotations.fromJson(json['annotations'] as Map<String, dynamic>),
      json['shared'] as bool,
      json['creator'] as String,
      (json['device_local_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      (json['device_ids'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );

Map<String, dynamic> _$NetworkToJson(Network instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'creator': instance.creator,
      'annotations': instance.annotations,
      'shared': instance.shared,
      'device_local_ids': instance.device_local_ids,
      'device_ids': instance.device_ids,
    };
