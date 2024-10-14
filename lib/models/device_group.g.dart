// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_group.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetDeviceGroupCollection on Isar {
  IsarCollection<DeviceGroup> get deviceGroups => this.collection();
}

const DeviceGroupSchema = CollectionSchema(
  name: r'DeviceGroup',
  id: -7548998771799459115,
  properties: {
    r'attributes': PropertySchema(
      id: 0,
      name: r'attributes',
      type: IsarType.objectList,
      target: r'Attribute',
    ),
    r'auto_generated_by_device': PropertySchema(
      id: 1,
      name: r'auto_generated_by_device',
      type: IsarType.string,
    ),
    r'criteria': PropertySchema(
      id: 2,
      name: r'criteria',
      type: IsarType.objectList,
      target: r'DeviceGroupCriteria',
    ),
    r'device_ids': PropertySchema(
      id: 3,
      name: r'device_ids',
      type: IsarType.stringList,
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
    r'image': PropertySchema(
      id: 6,
      name: r'image',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 7,
      name: r'name',
      type: IsarType.string,
    )
  },
  estimateSize: _deviceGroupEstimateSize,
  serialize: _deviceGroupSerialize,
  deserialize: _deviceGroupDeserialize,
  deserializeProp: _deviceGroupDeserializeProp,
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
    r'name': IndexSchema(
      id: 879695947855722453,
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
  embeddedSchemas: {
    r'DeviceGroupCriteria': DeviceGroupCriteriaSchema,
    r'Attribute': AttributeSchema
  },
  getId: _deviceGroupGetId,
  getLinks: _deviceGroupGetLinks,
  attach: _deviceGroupAttach,
  version: '3.1.0+1',
);

int _deviceGroupEstimateSize(
  DeviceGroup object,
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
  {
    final value = object.auto_generated_by_device;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.criteria.length * 3;
  {
    final offsets = allOffsets[DeviceGroupCriteria]!;
    for (var i = 0; i < object.criteria.length; i++) {
      final value = object.criteria[i];
      bytesCount +=
          DeviceGroupCriteriaSchema.estimateSize(value, offsets, allOffsets);
    }
  }
  bytesCount += 3 + object.device_ids.length * 3;
  {
    for (var i = 0; i < object.device_ids.length; i++) {
      final value = object.device_ids[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.id.length * 3;
  bytesCount += 3 + object.image.length * 3;
  bytesCount += 3 + object.name.length * 3;
  return bytesCount;
}

void _deviceGroupSerialize(
  DeviceGroup object,
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
  writer.writeString(offsets[1], object.auto_generated_by_device);
  writer.writeObjectList<DeviceGroupCriteria>(
    offsets[2],
    allOffsets,
    DeviceGroupCriteriaSchema.serialize,
    object.criteria,
  );
  writer.writeStringList(offsets[3], object.device_ids);
  writer.writeBool(offsets[4], object.favorite);
  writer.writeString(offsets[5], object.id);
  writer.writeString(offsets[6], object.image);
  writer.writeString(offsets[7], object.name);
}

DeviceGroup _deviceGroupDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = DeviceGroup(
    reader.readString(offsets[5]),
    reader.readString(offsets[7]),
    reader.readObjectList<DeviceGroupCriteria>(
          offsets[2],
          DeviceGroupCriteriaSchema.deserialize,
          allOffsets,
          DeviceGroupCriteria(),
        ) ??
        [],
    reader.readString(offsets[6]),
    reader.readStringList(offsets[3]) ?? [],
    reader.readObjectList<Attribute>(
      offsets[0],
      AttributeSchema.deserialize,
      allOffsets,
      Attribute(),
    ),
  );
  object.auto_generated_by_device = reader.readStringOrNull(offsets[1]);
  object.favorite = reader.readBool(offsets[4]);
  object.isarId = id;
  return object;
}

P _deviceGroupDeserializeProp<P>(
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
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readObjectList<DeviceGroupCriteria>(
            offset,
            DeviceGroupCriteriaSchema.deserialize,
            allOffsets,
            DeviceGroupCriteria(),
          ) ??
          []) as P;
    case 3:
      return (reader.readStringList(offset) ?? []) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _deviceGroupGetId(DeviceGroup object) {
  return object.isarId;
}

List<IsarLinkBase<dynamic>> _deviceGroupGetLinks(DeviceGroup object) {
  return [];
}

void _deviceGroupAttach(
    IsarCollection<dynamic> col, Id id, DeviceGroup object) {
  object.isarId = id;
}

extension DeviceGroupQueryWhereSort
    on QueryBuilder<DeviceGroup, DeviceGroup, QWhere> {
  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhere> anyIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhere> anyFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'favorite'),
      );
    });
  }
}

extension DeviceGroupQueryWhere
    on QueryBuilder<DeviceGroup, DeviceGroup, QWhereClause> {
  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> isarIdEqualTo(
      Id isarId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: isarId,
        upper: isarId,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> isarIdNotEqualTo(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> isarIdGreaterThan(
      Id isarId,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: isarId, includeLower: include),
      );
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> isarIdLessThan(
      Id isarId,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: isarId, includeUpper: include),
      );
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> isarIdBetween(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> idEqualTo(
      String id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'id',
        value: [id],
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> nameEqualTo(
      String name) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'name',
        value: [name],
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> nameNotEqualTo(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> favoriteEqualTo(
      bool favorite) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'favorite',
        value: [favorite],
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterWhereClause> favoriteNotEqualTo(
      bool favorite) {
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

extension DeviceGroupQueryFilter
    on QueryBuilder<DeviceGroup, DeviceGroup, QFilterCondition> {
  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      attributesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'attributes',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      attributesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'attributes',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'auto_generated_by_device',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'auto_generated_by_device',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'auto_generated_by_device',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'auto_generated_by_device',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'auto_generated_by_device',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'auto_generated_by_device',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'auto_generated_by_device',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'auto_generated_by_device',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'auto_generated_by_device',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'auto_generated_by_device',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'auto_generated_by_device',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      auto_generated_by_deviceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'auto_generated_by_device',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      criteriaLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'criteria',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      criteriaIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'criteria',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      criteriaIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'criteria',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      criteriaLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'criteria',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      criteriaLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'criteria',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      criteriaLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'criteria',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      device_idsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'device_ids',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      device_idsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'device_ids',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      device_idsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_ids',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      device_idsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'device_ids',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      device_idsLengthEqualTo(int length) {
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      device_idsIsEmpty() {
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      device_idsIsNotEmpty() {
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      device_idsLengthBetween(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> favoriteEqualTo(
      bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'favorite',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idEqualTo(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idBetween(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idStartsWith(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idEndsWith(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idMatches(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> imageEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'image',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      imageGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'image',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> imageLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'image',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> imageBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'image',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> imageStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'image',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> imageEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'image',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> imageContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'image',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> imageMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'image',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> imageIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'image',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      imageIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'image',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> isarIdEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isarId',
        value: value,
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> isarIdLessThan(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> isarIdBetween(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameEqualTo(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameGreaterThan(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameLessThan(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameBetween(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameStartsWith(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameEndsWith(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameContains(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameMatches(
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

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }
}

extension DeviceGroupQueryObject
    on QueryBuilder<DeviceGroup, DeviceGroup, QFilterCondition> {
  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition>
      attributesElement(FilterQuery<Attribute> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'attributes');
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterFilterCondition> criteriaElement(
      FilterQuery<DeviceGroupCriteria> q) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'criteria');
    });
  }
}

extension DeviceGroupQueryLinks
    on QueryBuilder<DeviceGroup, DeviceGroup, QFilterCondition> {}

extension DeviceGroupQuerySortBy
    on QueryBuilder<DeviceGroup, DeviceGroup, QSortBy> {
  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy>
      sortByAuto_generated_by_device() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'auto_generated_by_device', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy>
      sortByAuto_generated_by_deviceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'auto_generated_by_device', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> sortByFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'favorite', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> sortByFavoriteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'favorite', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> sortByImage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'image', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> sortByImageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'image', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }
}

extension DeviceGroupQuerySortThenBy
    on QueryBuilder<DeviceGroup, DeviceGroup, QSortThenBy> {
  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy>
      thenByAuto_generated_by_device() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'auto_generated_by_device', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy>
      thenByAuto_generated_by_deviceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'auto_generated_by_device', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'favorite', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByFavoriteDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'favorite', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByImage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'image', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByImageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'image', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByIsarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isarId', Sort.desc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }
}

extension DeviceGroupQueryWhereDistinct
    on QueryBuilder<DeviceGroup, DeviceGroup, QDistinct> {
  QueryBuilder<DeviceGroup, DeviceGroup, QDistinct>
      distinctByAuto_generated_by_device({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'auto_generated_by_device',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QDistinct> distinctByDevice_ids() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'device_ids');
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QDistinct> distinctByFavorite() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'favorite');
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QDistinct> distinctById(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'id', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QDistinct> distinctByImage(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'image', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DeviceGroup, DeviceGroup, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }
}

extension DeviceGroupQueryProperty
    on QueryBuilder<DeviceGroup, DeviceGroup, QQueryProperty> {
  QueryBuilder<DeviceGroup, int, QQueryOperations> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isarId');
    });
  }

  QueryBuilder<DeviceGroup, List<Attribute>?, QQueryOperations>
      attributesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attributes');
    });
  }

  QueryBuilder<DeviceGroup, String?, QQueryOperations>
      auto_generated_by_deviceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'auto_generated_by_device');
    });
  }

  QueryBuilder<DeviceGroup, List<DeviceGroupCriteria>, QQueryOperations>
      criteriaProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'criteria');
    });
  }

  QueryBuilder<DeviceGroup, List<String>, QQueryOperations>
      device_idsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'device_ids');
    });
  }

  QueryBuilder<DeviceGroup, bool, QQueryOperations> favoriteProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'favorite');
    });
  }

  QueryBuilder<DeviceGroup, String, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<DeviceGroup, String, QQueryOperations> imageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'image');
    });
  }

  QueryBuilder<DeviceGroup, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }
}

// **************************************************************************
// IsarEmbeddedGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const DeviceGroupCriteriaSchema = Schema(
  name: r'DeviceGroupCriteria',
  id: 7285243210016566965,
  properties: {
    r'aspect_id': PropertySchema(
      id: 0,
      name: r'aspect_id',
      type: IsarType.string,
    ),
    r'device_class_id': PropertySchema(
      id: 1,
      name: r'device_class_id',
      type: IsarType.string,
    ),
    r'function_id': PropertySchema(
      id: 2,
      name: r'function_id',
      type: IsarType.string,
    ),
    r'interaction': PropertySchema(
      id: 3,
      name: r'interaction',
      type: IsarType.string,
    )
  },
  estimateSize: _deviceGroupCriteriaEstimateSize,
  serialize: _deviceGroupCriteriaSerialize,
  deserialize: _deviceGroupCriteriaDeserialize,
  deserializeProp: _deviceGroupCriteriaDeserializeProp,
);

int _deviceGroupCriteriaEstimateSize(
  DeviceGroupCriteria object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.aspect_id.length * 3;
  bytesCount += 3 + object.device_class_id.length * 3;
  bytesCount += 3 + object.function_id.length * 3;
  bytesCount += 3 + object.interaction.length * 3;
  return bytesCount;
}

void _deviceGroupCriteriaSerialize(
  DeviceGroupCriteria object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.aspect_id);
  writer.writeString(offsets[1], object.device_class_id);
  writer.writeString(offsets[2], object.function_id);
  writer.writeString(offsets[3], object.interaction);
}

DeviceGroupCriteria _deviceGroupCriteriaDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = DeviceGroupCriteria();
  object.aspect_id = reader.readString(offsets[0]);
  object.device_class_id = reader.readString(offsets[1]);
  object.function_id = reader.readString(offsets[2]);
  object.interaction = reader.readString(offsets[3]);
  return object;
}

P _deviceGroupCriteriaDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension DeviceGroupCriteriaQueryFilter on QueryBuilder<DeviceGroupCriteria,
    DeviceGroupCriteria, QFilterCondition> {
  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aspect_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'aspect_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'aspect_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'aspect_id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'aspect_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'aspect_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'aspect_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'aspect_id',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aspect_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      aspect_idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'aspect_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_class_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'device_class_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'device_class_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'device_class_id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'device_class_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'device_class_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'device_class_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'device_class_id',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'device_class_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      device_class_idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'device_class_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'function_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'function_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'function_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'function_id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'function_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'function_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'function_id',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'function_id',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'function_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      function_idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'function_id',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'interaction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'interaction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'interaction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'interaction',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'interaction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'interaction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'interaction',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'interaction',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'interaction',
        value: '',
      ));
    });
  }

  QueryBuilder<DeviceGroupCriteria, DeviceGroupCriteria, QAfterFilterCondition>
      interactionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'interaction',
        value: '',
      ));
    });
  }
}

extension DeviceGroupCriteriaQueryObject on QueryBuilder<DeviceGroupCriteria,
    DeviceGroupCriteria, QFilterCondition> {}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceGroup _$DeviceGroupFromJson(Map<String, dynamic> json) => DeviceGroup(
      json['id'] as String,
      json['name'] as String,
      (json['criteria'] as List<dynamic>)
          .map((e) => DeviceGroupCriteria.fromJson(e as Map<String, dynamic>))
          .toList(),
      json['image'] as String,
      (json['device_ids'] as List<dynamic>).map((e) => e as String).toList(),
      (json['attributes'] as List<dynamic>?)
          ?.map((e) => Attribute.fromJson(e as Map<String, dynamic>))
          .toList(),
    )..auto_generated_by_device = json['auto_generated_by_device'] as String?;

Map<String, dynamic> _$DeviceGroupToJson(DeviceGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'image': instance.image,
      'criteria': instance.criteria,
      'device_ids': instance.device_ids,
      'attributes': instance.attributes,
      'auto_generated_by_device': instance.auto_generated_by_device,
    };

DeviceGroupCriteria _$DeviceGroupCriteriaFromJson(Map<String, dynamic> json) =>
    DeviceGroupCriteria()
      ..aspect_id = json['aspect_id'] as String
      ..device_class_id = json['device_class_id'] as String
      ..function_id = json['function_id'] as String
      ..interaction = json['interaction'] as String;

Map<String, dynamic> _$DeviceGroupCriteriaToJson(
        DeviceGroupCriteria instance) =>
    <String, dynamic>{
      'aspect_id': instance.aspect_id,
      'device_class_id': instance.device_class_id,
      'function_id': instance.function_id,
      'interaction': instance.interaction,
    };
