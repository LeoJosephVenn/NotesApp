/*
* Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
*
* Licensed under the Apache License, Version 2.0 (the "License").
* You may not use this file except in compliance with the License.
* A copy of the License is located at
*
*  http://aws.amazon.com/apache2.0
*
* or in the "license" file accompanying this file. This file is distributed
* on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
* express or implied. See the License for the specific language governing
* permissions and limitations under the License.
*/

// NOTE: This file is generated and may not follow lint rules defined in your app
// Generated files can be excluded from analysis in analysis_options.yaml
// For more info, see: https://dart.dev/guides/language/analysis-options#excluding-code-from-analysis

// ignore_for_file: public_member_api_docs, annotate_overrides, dead_code, dead_codepublic_member_api_docs, depend_on_referenced_packages, file_names, library_private_types_in_public_api, no_leading_underscores_for_library_prefixes, no_leading_underscores_for_local_identifiers, non_constant_identifier_names, null_check_on_nullable_type_parameter, override_on_non_overriding_member, prefer_adjacent_string_concatenation, prefer_const_constructors, prefer_if_null_operators, prefer_interpolation_to_compose_strings, slash_for_doc_comments, sort_child_properties_last, unnecessary_const, unnecessary_constructor_name, unnecessary_late, unnecessary_new, unnecessary_null_aware_assignments, unnecessary_nullable_for_final_variable_declarations, unnecessary_string_interpolations, use_build_context_synchronously

import 'ModelProvider.dart';
import 'package:amplify_core/amplify_core.dart' as amplify_core;


/** This is an auto generated class representing the Location type in your schema. */
class Location {
  final double? _lat;
  final double? _long;

  double? get lat {
    return _lat;
  }
  
  double? get long {
    return _long;
  }
  
  const Location._internal({lat, long}): _lat = lat, _long = long;
  
  factory Location({double? lat, double? long}) {
    return Location._internal(
      lat: lat,
      long: long);
  }
  
  bool equals(Object other) {
    return this == other;
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Location &&
      _lat == other._lat &&
      _long == other._long;
  }
  
  @override
  int get hashCode => toString().hashCode;
  
  @override
  String toString() {
    var buffer = new StringBuffer();
    
    buffer.write("Location {");
    buffer.write("lat=" + (_lat != null ? _lat!.toString() : "null") + ", ");
    buffer.write("long=" + (_long != null ? _long!.toString() : "null"));
    buffer.write("}");
    
    return buffer.toString();
  }
  
  Location copyWith({double? lat, double? long}) {
    return Location._internal(
      lat: lat ?? this.lat,
      long: long ?? this.long);
  }
  
  Location copyWithModelFieldValues({
    ModelFieldValue<double?>? lat,
    ModelFieldValue<double?>? long
  }) {
    return Location._internal(
      lat: lat == null ? this.lat : lat.value,
      long: long == null ? this.long : long.value
    );
  }
  
  Location.fromJson(Map<String, dynamic> json)  
    : _lat = (json['lat'] as num?)?.toDouble(),
      _long = (json['long'] as num?)?.toDouble();
  
  Map<String, dynamic> toJson() => {
    'lat': _lat, 'long': _long
  };
  
  Map<String, Object?> toMap() => {
    'lat': _lat,
    'long': _long
  };

  static var schema = amplify_core.Model.defineSchema(define: (amplify_core.ModelSchemaDefinition modelSchemaDefinition) {
    modelSchemaDefinition.name = "Location";
    modelSchemaDefinition.pluralName = "Locations";
    
    modelSchemaDefinition.addField(amplify_core.ModelFieldDefinition.customTypeField(
      fieldName: 'lat',
      isRequired: false,
      ofType: amplify_core.ModelFieldType(amplify_core.ModelFieldTypeEnum.double)
    ));
    
    modelSchemaDefinition.addField(amplify_core.ModelFieldDefinition.customTypeField(
      fieldName: 'long',
      isRequired: false,
      ofType: amplify_core.ModelFieldType(amplify_core.ModelFieldTypeEnum.double)
    ));
  });
}