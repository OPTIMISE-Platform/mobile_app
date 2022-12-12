// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'annotations.dart';

// **************************************************************************
// IsarEmbeddedGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters

const AnnotationsSchema = Schema(
  name: r'Annotations',
  id: 3815579495590919680,
  properties: {
    r'connected': PropertySchema(
      id: 0,
      name: r'connected',
      type: IsarType.bool,
    )
  },
  estimateSize: _annotationsEstimateSize,
  serialize: _annotationsSerialize,
  deserialize: _annotationsDeserialize,
  deserializeProp: _annotationsDeserializeProp,
);

int _annotationsEstimateSize(
  Annotations object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  return bytesCount;
}

void _annotationsSerialize(
  Annotations object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.connected);
}

Annotations _annotationsDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Annotations();
  object.connected = reader.readBoolOrNull(offsets[0]);
  return object;
}

P _annotationsDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBoolOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension AnnotationsQueryFilter
    on QueryBuilder<Annotations, Annotations, QFilterCondition> {
  QueryBuilder<Annotations, Annotations, QAfterFilterCondition>
      connectedIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'connected',
      ));
    });
  }

  QueryBuilder<Annotations, Annotations, QAfterFilterCondition>
      connectedIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'connected',
      ));
    });
  }

  QueryBuilder<Annotations, Annotations, QAfterFilterCondition>
      connectedEqualTo(bool? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'connected',
        value: value,
      ));
    });
  }
}

extension AnnotationsQueryObject
    on QueryBuilder<Annotations, Annotations, QFilterCondition> {}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Annotations _$AnnotationsFromJson(Map<String, dynamic> json) =>
    Annotations()..connected = json['connected'] as bool?;

Map<String, dynamic> _$AnnotationsToJson(Annotations instance) =>
    <String, dynamic>{
      'connected': instance.connected,
    };
