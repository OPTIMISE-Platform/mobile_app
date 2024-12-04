// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_instance.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetDeviceInstanceCollection on Isar {
  IsarCollection<DeviceInstance> get deviceInstances => this.collection();
}

const DeviceInstanceSchema = CollectionSchema(
  name: r'DeviceInstance',
  id: -8399428298092944646,
  properties: {
    r'attributes': PropertySchema(
      id: 0,
      name: r'attributes',
      type: IsarType.objectList,
      target: r'Attribute',
    ),
    r'connection_state': PropertySchema(
      id: 1,
      name: r'connection_state',
      type: IsarType.byte,
      enumMap: _DeviceInstanceconnection_stateEnumValueMap,
    ),
    r'device_type_id': PropertySchema(
      id: 2,
      name: r'device_type_id',
      type: IsarType.string,
    ),
    r'display_name': PropertySchema(
      id: 3,
      name: r'display_name',
      type: IsarType.string,
    ),
    r'favorite': PropertySchema(
      id: 4,
      name: r'favorite',
      type: IsarType.bool,
    ),
    r'id': PropertySchema(
      id: 5,
      name: r'id',
      type: IsarType.string,
    ),
    r'local_id': PropertySchema(
      id: 6,
      name: r'local_id',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 7,
      name: r'name',
      type: IsarType.string,
    ),
    r'owner_id': PropertySchema(
      id: 8,
      name: r'owner_id',
      type: IsarType.string,
    ),
    r'shared': PropertySchema(
      id: 9,
      name: r'shared',
      type: IsarType.bool,
    )
  },
  estimateSize: _deviceInstanceEstimateSize,
  serialize: _deviceInstanceSerialize,
  deserialize: _deviceInstanceDeserialize,
  deserializeProp: _deviceInstanceDeserializeProp,
  idName: r'isarId',
  indexes: {
    r'id': IndexSchema(
      id: -3268401673993471357,
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
    r'local_id': IndexSchema(
      id: 3920594403020751642,
      name: r'local_id',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'local_id',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'display_name': IndexSchema(
      id: -7654124764797891805,
      name: r'display_name',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'display_name',
          type: IndexType.hash,
          caseSensitive: false,
        )
      ],
    ),
    r'favorite': IndexSchema(
      id: 4264748667377999100,
      name: r'favorite',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'favorite',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {r'Attribute': AttributeSchema},
  getId: _deviceInstanceGetId,
  getLinks: _deviceInstanceGetLinks,
  attach: _deviceInstanceAttach,
  version: '3.1.0+1',
);

int _deviceInstanceEstimateSize(
  DeviceInstance object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final list = object.attributes;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        final offsets = allOffsets[Attribute]!;
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount +=
              AttributeSchema.estimateSize(value, offsets, allOffsets);
        }
      }
    }
  }
  bytesCount += 3 + object.device_type_id.length * 3;
  {
    final value = object.display_name;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.id.length * 3;
  bytesCount += 3 + object.local_id.length * 3;
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.owner_id.length * 3;
  return bytesCount;
}

void _deviceInstanceSerialize(
  DeviceInstance object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeObjectList<Attribute>(
    offsets[0],
    allOffsets,
    AttributeSchema.serialize,
    object.attributes,
  );
  writer.writeByte(offsets[1], object.connection_state.index);
  writer.writeString(offsets[2], object.device_type_id);
  writer.writeString(offsets[3], object.display_name);
  writer.writeBool(offsets[4], object.favorite);
  writer.writeString(offsets[5], object.id);
  writer.writeString(offsets[6], object.local_id);
  writer.writeString(offsets[7], object.name);
  writer.writeString(offsets[8], object.owner_id);
  writer.writeBool(offsets[9], object.shared);
}

DeviceInstance _deviceInstanceDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = DeviceInstance(
    reader.readString(offsets[5]),
    reader.readString(offsets[6]),
    reader.readString(offsets[7]),
    reader.readObjectList<Attribute>(
      offsets[0],
      AttributeSchema.deserialize,
      allOffsets,
      Attribute(),
    ),
    reader.readString(offsets[2]),
    reader.readBool(offsets[9]),
    reader.readString(offsets[8]),
    reader.readStringOrNull(offsets[3]),
    _DeviceInstanceconnection_stateValueEnumMap[
            reader.readByteOrNull(offsets[1])] ??
        DeviceConnectionStatus.online,
  );
  object.favorite = reader.readBool(offsets[4]);
  object.isarId = id;
  return object;
}

P _deviceInstanceDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readObjectList<Attribute>(
        offset,
        AttributeSchema.deserialize,
        allOffsets,
        Attribute(),
      )) as P;
    case 1:
      return (_DeviceInstanceconnection_stateValueEnumMap[
              reader.readByteOrNull(offset)] ??
          DeviceConnectionStatus.online) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readBool(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _DeviceInstanceconnection_stateEnumValueMap = {
  'online': 0,
  'offline': 1,
  'unknown': 2,
};
const _DeviceInstanceconnection_stateValueEnumMap = {
  0: DeviceConnectionStatus.online,
  1: DeviceConnectionStatus.offline,
  2: DeviceConnectionStatus.unknown,
};

Id _deviceInstanceGetId(DeviceInstance object) {
  return object.isarId;
}

List<IsarLinkBase<dynamic>> _deviceInstanceGetLinks(DeviceInstance object) {
  return [];
}

void _deviceInstanceAttach(
    IsarCollection<dynamic> col, Id id, DeviceInstance object) {
  object.isarId = id;
}

extension DeviceInstanceQueryWhereSort
    on QueryBuilder<DeviceInstance, DeviceInstance, QWhere> {
  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhere> anyIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhere> anyFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'favorite'),
      );
    });
  }
}

extension DeviceInstanceQueryWhere
    on QueryBuilder<DeviceInstance, DeviceInstance, QWhereClause> {
  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause> isarIdEqualTo(
      Id isarId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: isarId,
        upper: isarId,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      isarIdGreaterThan(Id isarId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: isarId, includeLower: include),
      );
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      isarIdLessThan(Id isarId, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: isarId, includeUpper: include),
      );
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause> isarIdBetween(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause> idEqualTo(
      String id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'id',
        value: [id],
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause> idNotEqualTo(
      String id) {
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      local_idEqualTo(String local_id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'local_id',
        value: [local_id],
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      local_idNotEqualTo(String local_id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'local_id',
              lower: [],
              upper: [local_id],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'local_id',
              lower: [local_id],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'local_id',
              lower: [local_id],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'local_id',
              lower: [],
              upper: [local_id],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      display_nameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'display_name',
        value: [null],
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      display_nameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'display_name',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      display_nameEqualTo(String? display_name) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'display_name',
        value: [display_name],
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      display_nameNotEqualTo(String? display_name) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'display_name',
              lower: [],
              upper: [display_name],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'display_name',
              lower: [display_name],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'display_name',
              lower: [display_name],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'display_name',
              lower: [],
              upper: [display_name],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      favoriteEqualTo(bool favorite) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'favorite',
        value: [favorite],
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterWhereClause>
      favoriteNotEqualTo(bool favorite) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'favorite',
              lower: [],
              upper: [favorite],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'favorite',
              lower: [favorite],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'favorite',
              lower: [favorite],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'favorite',
              lower: [],
              upper: [favorite],
              includeUpper: false,
            ));
      }
    });
  }
}

extension DeviceInstanceQueryFilter
    on QueryBuilder<DeviceInstance, DeviceInstance, QFilterCondition> {
  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attributes',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attributes',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attributes',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attributes',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attributes',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attributes',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attributes',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attributes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      connection_stateEqualTo(DeviceConnectionStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'connection_state',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      connection_stateGreaterThan(
    DeviceConnectionStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'connection_state',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      connection_stateLessThan(
    DeviceConnectionStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'connection_state',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      connection_stateBetween(
    DeviceConnectionStatus lower,
    DeviceConnectionStatus upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'connection_state',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_type_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'device_type_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'device_type_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'device_type_id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'device_type_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'device_type_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'device_type_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'device_type_id',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_type_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      device_type_idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'device_type_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'display_name',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'display_name',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'display_name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'display_name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'display_name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'display_name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'display_name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'display_name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'display_name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'display_name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'display_name',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      display_nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'display_name',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      favoriteEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'favorite',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition> idEqualTo(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      idGreaterThan(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      idLessThan(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition> idBetween(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      idStartsWith(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      idEndsWith(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      idContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition> idMatches(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      isarIdEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'local_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'local_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'local_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'local_id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'local_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'local_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'local_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'local_id',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'local_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      local_idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'local_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameEqualTo(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameGreaterThan(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameLessThan(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameBetween(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameStartsWith(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameEndsWith(
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

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'owner_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'owner_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'owner_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'owner_id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'owner_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'owner_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'owner_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'owner_id',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'owner_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      owner_idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'owner_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      sharedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'shared',
        value: value,
      ));
    });
  }
}

extension DeviceInstanceQueryObject
    on QueryBuilder<DeviceInstance, DeviceInstance, QFilterCondition> {
  QueryBuilder<DeviceInstance, DeviceInstance, QAfterFilterCondition>
      attributesElement(FilterQuery<Attribute> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'attributes');
    });
  }
}

extension DeviceInstanceQueryLinks
    on QueryBuilder<DeviceInstance, DeviceInstance, QFilterCondition> {}

extension DeviceInstanceQuerySortBy
    on QueryBuilder<DeviceInstance, DeviceInstance, QSortBy> {
  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByConnection_state() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connection_state', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByConnection_stateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connection_state', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByDevice_type_id() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'device_type_id', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByDevice_type_idDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'device_type_id', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByDisplay_name() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'display_name', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByDisplay_nameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'display_name', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> sortByFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'favorite', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByFavoriteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'favorite', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> sortByLocal_id() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'local_id', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByLocal_idDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'local_id', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> sortByOwner_id() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'owner_id', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortByOwner_idDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'owner_id', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> sortByShared() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'shared', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      sortBySharedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'shared', Sort.desc);
    });
  }
}

extension DeviceInstanceQuerySortThenBy
    on QueryBuilder<DeviceInstance, DeviceInstance, QSortThenBy> {
  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByConnection_state() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connection_state', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByConnection_stateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connection_state', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByDevice_type_id() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'device_type_id', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByDevice_type_idDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'device_type_id', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByDisplay_name() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'display_name', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByDisplay_nameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'display_name', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenByFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'favorite', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByFavoriteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'favorite', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenByIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByIsarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenByLocal_id() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'local_id', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByLocal_idDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'local_id', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenByOwner_id() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'owner_id', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenByOwner_idDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'owner_id', Sort.desc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy> thenByShared() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'shared', Sort.asc);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterSortBy>
      thenBySharedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'shared', Sort.desc);
    });
  }
}

extension DeviceInstanceQueryWhereDistinct
    on QueryBuilder<DeviceInstance, DeviceInstance, QDistinct> {
  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct>
      distinctByConnection_state() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'connection_state');
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct>
      distinctByDevice_type_id({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'device_type_id',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct>
      distinctByDisplay_name({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'display_name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct> distinctByFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'favorite');
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct> distinctById(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'id', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct> distinctByLocal_id(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'local_id', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct> distinctByOwner_id(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'owner_id', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QDistinct> distinctByShared() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'shared');
    });
  }
}

extension DeviceInstanceQueryProperty
    on QueryBuilder<DeviceInstance, DeviceInstance, QQueryProperty> {
  QueryBuilder<DeviceInstance, int, QQueryOperations> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isarId');
    });
  }

  QueryBuilder<DeviceInstance, List<Attribute>?, QQueryOperations>
      attributesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attributes');
    });
  }

  QueryBuilder<DeviceInstance, DeviceConnectionStatus, QQueryOperations>
      connection_stateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'connection_state');
    });
  }

  QueryBuilder<DeviceInstance, String, QQueryOperations>
      device_type_idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'device_type_id');
    });
  }

  QueryBuilder<DeviceInstance, String?, QQueryOperations>
      display_nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'display_name');
    });
  }

  QueryBuilder<DeviceInstance, bool, QQueryOperations> favoriteProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'favorite');
    });
  }

  QueryBuilder<DeviceInstance, String, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<DeviceInstance, String, QQueryOperations> local_idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'local_id');
    });
  }

  QueryBuilder<DeviceInstance, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<DeviceInstance, String, QQueryOperations> owner_idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'owner_id');
    });
  }

  QueryBuilder<DeviceInstance, bool, QQueryOperations> sharedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'shared');
    });
  }
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceInstance _$DeviceInstanceFromJson(Map<String, dynamic> json) =>
    DeviceInstance(
      json['id'] as String,
      json['local_id'] as String,
      json['name'] as String,
      (json['attributes'] as List<dynamic>?)
          ?.map((e) => Attribute.fromJson(e as Map<String, dynamic>))
          .toList(),
      json['device_type_id'] as String,
      json['shared'] as bool,
      json['owner_id'] as String,
      json['display_name'] as String?,
      $enumDecode(_$DeviceConnectionStatusEnumMap, json['connection_state']),
    );

Map<String, dynamic> _$DeviceInstanceToJson(DeviceInstance instance) =>
    <String, dynamic>{
      'id': instance.id,
      'local_id': instance.local_id,
      'name': instance.name,
      'device_type_id': instance.device_type_id,
      'owner_id': instance.owner_id,
      'display_name': instance.display_name,
      'attributes': instance.attributes,
      'shared': instance.shared,
      'connection_state':
          _$DeviceConnectionStatusEnumMap[instance.connection_state]!,
    };

const _$DeviceConnectionStatusEnumMap = {
  DeviceConnectionStatus.online: 'online',
  DeviceConnectionStatus.offline: 'offline',
  DeviceConnectionStatus.unknown: '',
};
